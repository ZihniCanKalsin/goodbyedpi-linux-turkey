#include "tcp_mangle.h"
#include "raw_inject.h"
#include "fake_payloads.h"
#include "util.h"

#include <string.h>
#include <arpa/inet.h>
#include <netinet/ip.h>
#include <netinet/ip6.h>
#include <netinet/tcp.h>

static int looks_like_tls_clienthello(const uint8_t *p, size_t n) {
    /* TLS record: 0x16 (Handshake), 0x03 0x01/0x02/0x03/0x04 (TLS version).
     * 6th byte of handshake payload is HandshakeType == 1 (ClientHello). */
    if (n < 6) return 0;
    if (p[0] != 0x16) return 0;
    if (p[1] != 0x03) return 0;
    if (p[5] != 0x01) return 0;
    return 1;
}

static int looks_like_http_request(const uint8_t *p, size_t n) {
    static const char *verbs[] = {
        "GET ", "POST ", "HEAD ", "PUT ", "DELETE ", "OPTIONS ", "PATCH ", "CONNECT "
    };
    for (size_t i = 0; i < sizeof(verbs)/sizeof(verbs[0]); i++) {
        size_t vlen = strlen(verbs[i]);
        if (n >= vlen && memcmp(p, verbs[i], vlen) == 0) return 1;
    }
    return 0;
}

/* Detect whether the packet is the kind we'd act on, independent of whether
 * the act is splitting, decoying, or both. Returns:
 *   0 = not a protocol we care about (NF_ACCEPT verbatim).
 *   1 = TLS ClientHello on 443.
 *   2 = HTTP request on 80.
 * Matches upstream's gating on (port, first-bytes, max_payload_size). */
static int classify_payload(uint16_t dport, const uint8_t *payload, size_t plen) {
    if (plen < 16) return 0;
    if (gbd_cfg.max_payload_size && plen > gbd_cfg.max_payload_size) return 0;
    if (dport == 443 && looks_like_tls_clienthello(payload, plen)) return 1;
    if (dport == 80  && looks_like_http_request(payload, plen))    return 2;
    return 0;
}

static int want_split(int is_https) {
    return is_https ? (gbd_cfg.frag_https > 0) : (gbd_cfg.frag_http > 0);
}

static int effective_decoy_ttl(void) {
    if (gbd_cfg.set_ttl > 0) return gbd_cfg.set_ttl;
    if (gbd_cfg.auto_ttl)    return 4;   /* simplification; upstream probes */
    return 0;
}

/* Mirrors Windows send_fake_request(): up to three independent decoys,
 * one per enabled mode (ttl, checksum, seq). */
static void emit_fake_decoys_v4(const struct iphdr *ip, const struct tcphdr *tcp,
                                int is_https)
{
    if (!gbd_cfg.fake_packet) return;

    const uint8_t *data = is_https ? fake_https_request : fake_http_request;
    size_t         dlen = is_https ? fake_https_request_len : fake_http_request_len;

    int ttl = effective_decoy_ttl();
    if (ttl > 0) {
        raw_inject_tcp4(ip, tcp, data, dlen, ttl, 0, 0);
    }
    if (gbd_cfg.wrong_chksum) {
        raw_inject_tcp4(ip, tcp, data, dlen, 0, 0, 1);
    }
    if (gbd_cfg.wrong_seq) {
        uint32_t bogus_seq = ntohl(tcp->seq) - 10000u;
        raw_inject_tcp4(ip, tcp, data, dlen, 0, bogus_seq, 0);
    }
}

static void emit_fake_decoys_v6(const struct ip6_hdr *ip6, const struct tcphdr *tcp,
                                int is_https)
{
    if (!gbd_cfg.fake_packet) return;

    const uint8_t *data = is_https ? fake_https_request : fake_http_request;
    size_t         dlen = is_https ? fake_https_request_len : fake_http_request_len;

    int hop = effective_decoy_ttl();
    if (hop > 0) {
        raw_inject_tcp6(ip6, tcp, data, dlen, hop, 0, 0);
    }
    if (gbd_cfg.wrong_chksum) {
        raw_inject_tcp6(ip6, tcp, data, dlen, 0, 0, 1);
    }
    if (gbd_cfg.wrong_seq) {
        uint32_t bogus_seq = ntohl(tcp->seq) - 10000u;
        raw_inject_tcp6(ip6, tcp, data, dlen, 0, bogus_seq, 0);
    }
}

static size_t effective_split_offset(int is_https) {
    size_t off = is_https ? (size_t)gbd_cfg.frag_https : (size_t)gbd_cfg.frag_http;
    return off ? off : 2;
}

int tcp_mangle_ipv4(uint8_t *pkt, size_t pkt_len) {
    if (pkt_len < sizeof(struct iphdr)) return 0;
    struct iphdr *ip = (struct iphdr *)pkt;
    if (ip->protocol != IPPROTO_TCP) return 0;
    size_t iph_len = ip->ihl * 4u;
    if (pkt_len < iph_len + sizeof(struct tcphdr)) return 0;
    struct tcphdr *tcp = (struct tcphdr *)(pkt + iph_len);
    size_t tcph_len = tcp->doff * 4u;
    if (pkt_len < iph_len + tcph_len) return 0;

    uint16_t dport = ntohs(tcp->dest);
    uint8_t *payload = pkt + iph_len + tcph_len;
    size_t   plen    = pkt_len - iph_len - tcph_len;

    int cls = classify_payload(dport, payload, plen);
    if (!cls) return 0;
    int is_https = (cls == 1);

    /* Emit decoys (if configured) regardless of whether we split the real packet.
     * Upstream: `--set-ttl N` / `--wrong-seq` / `--wrong-chksum` alone still
     * sends a decoy on every ClientHello / HTTP verb. */
    emit_fake_decoys_v4(ip, tcp, is_https);

    if (!want_split(is_https)) return 0;  /* decoy-only path: let original pass. */

    size_t first_len = effective_split_offset(is_https);
    if (plen <= first_len) return 0;

    uint32_t base_seq  = ntohl(tcp->seq);
    size_t   second_len = plen - first_len;

    if (gbd_cfg.reverse_frag) {
        raw_inject_tcp4(ip, tcp, payload + first_len, second_len,
                        0, base_seq + first_len, 0);
        raw_inject_tcp4(ip, tcp, payload, first_len,
                        0, base_seq, 0);
    } else {
        raw_inject_tcp4(ip, tcp, payload, first_len,
                        0, base_seq, 0);
        raw_inject_tcp4(ip, tcp, payload + first_len, second_len,
                        0, base_seq + first_len, 0);
    }
    return 1;
}

int tcp_mangle_ipv6(uint8_t *pkt, size_t pkt_len) {
    if (pkt_len < sizeof(struct ip6_hdr)) return 0;
    struct ip6_hdr *ip6 = (struct ip6_hdr *)pkt;
    if (ip6->ip6_nxt != IPPROTO_TCP) return 0;
    size_t iph_len = sizeof(struct ip6_hdr);
    if (pkt_len < iph_len + sizeof(struct tcphdr)) return 0;
    struct tcphdr *tcp = (struct tcphdr *)(pkt + iph_len);
    size_t tcph_len = tcp->doff * 4u;
    if (pkt_len < iph_len + tcph_len) return 0;

    uint16_t dport = ntohs(tcp->dest);
    uint8_t *payload = pkt + iph_len + tcph_len;
    size_t   plen    = pkt_len - iph_len - tcph_len;

    int cls = classify_payload(dport, payload, plen);
    if (!cls) return 0;
    int is_https = (cls == 1);

    emit_fake_decoys_v6(ip6, tcp, is_https);

    if (!want_split(is_https)) return 0;

    size_t first_len = effective_split_offset(is_https);
    if (plen <= first_len) return 0;

    uint32_t base_seq  = ntohl(tcp->seq);
    size_t   second_len = plen - first_len;

    if (gbd_cfg.reverse_frag) {
        raw_inject_tcp6(ip6, tcp, payload + first_len, second_len,
                        0, base_seq + first_len, 0);
        raw_inject_tcp6(ip6, tcp, payload, first_len,
                        0, base_seq, 0);
    } else {
        raw_inject_tcp6(ip6, tcp, payload, first_len,
                        0, base_seq, 0);
        raw_inject_tcp6(ip6, tcp, payload + first_len, second_len,
                        0, base_seq + first_len, 0);
    }
    return 1;
}
