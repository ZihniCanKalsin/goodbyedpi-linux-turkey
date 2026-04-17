#include "raw_inject.h"
#include "checksum.h"
#include "util.h"

#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <arpa/inet.h>

static int sock4 = -1;
static int sock6 = -1;

int raw_inject_init(void) {
    sock4 = socket(AF_INET, SOCK_RAW, IPPROTO_RAW);
    if (sock4 < 0) {
        LOGE("socket(AF_INET, SOCK_RAW, IPPROTO_RAW) başarısız: %s", strerror(errno));
        return -1;
    }
    int one = 1;
    (void)setsockopt(sock4, IPPROTO_IP, IP_HDRINCL, &one, sizeof one);

    sock6 = socket(AF_INET6, SOCK_RAW, IPPROTO_RAW);
    if (sock6 < 0) {
        LOGI("IPv6 ham soket kullanılamıyor (%s); IPv6 TCP değişimi devre dışı", strerror(errno));
        sock6 = -1;
    } else {
        int hdrincl = 1;
        (void)setsockopt(sock6, IPPROTO_IPV6, IPV6_HDRINCL, &hdrincl, sizeof hdrincl);
    }
    return 0;
}

void raw_inject_close(void) {
    if (sock4 >= 0) close(sock4);
    if (sock6 >= 0) close(sock6);
    sock4 = sock6 = -1;
}

int raw_inject_tcp4(const struct iphdr *tpl_ip,
                    const struct tcphdr *tpl_tcp,
                    const uint8_t *payload, size_t payload_len,
                    int ttl, uint32_t seq_override, int wrong_chksum)
{
    if (sock4 < 0) return -1;

    size_t tcp_len = sizeof(struct tcphdr) + payload_len;
    size_t total   = sizeof(struct iphdr) + tcp_len;
    if (total > 1500) return -1;

    uint8_t buf[1500];
    memset(buf, 0, total);

    struct iphdr *ip = (struct iphdr *)buf;
    struct tcphdr *tcp = (struct tcphdr *)(buf + sizeof(struct iphdr));

    ip->version  = 4;
    ip->ihl      = 5;
    ip->tos      = tpl_ip->tos;
    ip->tot_len  = htons((uint16_t)total);
    ip->id       = 0;
    ip->frag_off = htons(0x4000);
    ip->ttl      = (ttl > 0) ? (uint8_t)ttl : (tpl_ip->ttl ? tpl_ip->ttl : 64);
    ip->protocol = IPPROTO_TCP;
    ip->saddr    = tpl_ip->saddr;
    ip->daddr    = tpl_ip->daddr;
    ip->check    = 0;
    ip->check    = ipv4_checksum(ip, sizeof(struct iphdr));

    tcp->source  = tpl_tcp->source;
    tcp->dest    = tpl_tcp->dest;
    tcp->seq     = seq_override ? htonl(seq_override) : tpl_tcp->seq;
    tcp->ack_seq = tpl_tcp->ack_seq;
    tcp->doff    = 5;
    tcp->fin     = tpl_tcp->fin;
    tcp->syn     = tpl_tcp->syn;
    tcp->rst     = tpl_tcp->rst;
    tcp->psh     = 1;
    tcp->ack     = tpl_tcp->ack;
    tcp->urg     = 0;
    tcp->window  = tpl_tcp->window;
    tcp->urg_ptr = 0;
    tcp->check   = 0;
    if (payload_len) memcpy((uint8_t *)tcp + sizeof(struct tcphdr), payload, payload_len);
    tcp->check   = tcp4_checksum(ip, tcp, tcp_len);
    if (wrong_chksum) tcp->check ^= 0xFFFF;

    struct sockaddr_in dst;
    memset(&dst, 0, sizeof dst);
    dst.sin_family = AF_INET;
    dst.sin_addr.s_addr = ip->daddr;

    ssize_t n = sendto(sock4, buf, total, 0, (struct sockaddr *)&dst, sizeof dst);
    if (n < 0) {
        LOGD("raw_inject_tcp4 sendto başarısız: %s", strerror(errno));
        return -1;
    }
    return 0;
}

int raw_inject_tcp6(const struct ip6_hdr *tpl_ip6,
                    const struct tcphdr *tpl_tcp,
                    const uint8_t *payload, size_t payload_len,
                    int hoplimit, uint32_t seq_override, int wrong_chksum)
{
    if (sock6 < 0) return -1;

    size_t tcp_len = sizeof(struct tcphdr) + payload_len;
    size_t total   = sizeof(struct ip6_hdr) + tcp_len;
    if (total > 1500) return -1;

    uint8_t buf[1500];
    memset(buf, 0, total);

    struct ip6_hdr *ip6 = (struct ip6_hdr *)buf;
    struct tcphdr *tcp  = (struct tcphdr *)(buf + sizeof(struct ip6_hdr));

    ip6->ip6_flow = htonl(6u << 28);
    ip6->ip6_plen = htons((uint16_t)tcp_len);
    ip6->ip6_nxt  = IPPROTO_TCP;
    ip6->ip6_hlim = (hoplimit > 0) ? (uint8_t)hoplimit :
                    (tpl_ip6->ip6_hlim ? tpl_ip6->ip6_hlim : 64);
    ip6->ip6_src  = tpl_ip6->ip6_src;
    ip6->ip6_dst  = tpl_ip6->ip6_dst;

    tcp->source  = tpl_tcp->source;
    tcp->dest    = tpl_tcp->dest;
    tcp->seq     = seq_override ? htonl(seq_override) : tpl_tcp->seq;
    tcp->ack_seq = tpl_tcp->ack_seq;
    tcp->doff    = 5;
    tcp->fin     = tpl_tcp->fin;
    tcp->syn     = tpl_tcp->syn;
    tcp->rst     = tpl_tcp->rst;
    tcp->psh     = 1;
    tcp->ack     = tpl_tcp->ack;
    tcp->urg     = 0;
    tcp->window  = tpl_tcp->window;
    tcp->urg_ptr = 0;
    tcp->check   = 0;
    if (payload_len) memcpy((uint8_t *)tcp + sizeof(struct tcphdr), payload, payload_len);
    tcp->check   = tcp6_checksum(ip6, tcp, tcp_len);
    if (wrong_chksum) tcp->check ^= 0xFFFF;

    struct sockaddr_in6 dst;
    memset(&dst, 0, sizeof dst);
    dst.sin6_family = AF_INET6;
    dst.sin6_addr   = ip6->ip6_dst;

    ssize_t n = sendto(sock6, buf, total, 0, (struct sockaddr *)&dst, sizeof dst);
    if (n < 0) {
        LOGD("raw_inject_tcp6 sendto başarısız: %s", strerror(errno));
        return -1;
    }
    return 0;
}
