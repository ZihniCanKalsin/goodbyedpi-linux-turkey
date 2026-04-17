#include "nfq_loop.h"
#include "tcp_mangle.h"
#include "dns_redir.h"
#include "util.h"

#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <poll.h>
#include <arpa/inet.h>
#include <netinet/ip.h>
#include <netinet/ip6.h>
#include <netinet/udp.h>
#include <linux/netfilter.h>
#include <libnetfilter_queue/libnetfilter_queue.h>

volatile int gbd_stop = 0;

/* Heuristic direction: if dst-port or src-port matches known server ports,
 * treat it as outbound/inbound. NFQUEUE hook is OUTPUT (always outbound for
 * the local socket) or INPUT (inbound reply); we distinguish by the nfmark
 * or the in/out ifindex. Simpler: outbound vs inbound is encoded by which
 * iptables chain queued it — we attach two queues in that case. For this
 * implementation we use a single queue and infer from port semantics. */

static int handle_ipv4(uint8_t *data, size_t len, int *verdict,
                       uint8_t **out_buf, size_t *out_len) {
    struct iphdr *ip = (struct iphdr *)data;
    size_t iph_len = ip->ihl * 4u;
    if (len < iph_len) { *verdict = NF_ACCEPT; return 0; }

    if (ip->protocol == IPPROTO_UDP && len >= iph_len + sizeof(struct udphdr)) {
        struct udphdr *udp = (struct udphdr *)(data + iph_len);
        uint16_t dport = ntohs(udp->dest);
        uint16_t sport = ntohs(udp->source);

        if (gbd_cfg.block_quic && dport == 443) {
            *verdict = NF_DROP;
            return 0;
        }
        if (dport == 53 && gbd_cfg.dns4_enabled) {
            if (dns_redir_out_ipv4(data, len)) {
                *verdict = NF_ACCEPT; *out_buf = data; *out_len = len; return 1;
            }
        }
        if (sport == gbd_cfg.dns4_port && gbd_cfg.dns4_enabled &&
            ip->saddr == gbd_cfg.dns4_addr.s_addr) {
            if (dns_redir_in_ipv4(data, len)) {
                *verdict = NF_ACCEPT; *out_buf = data; *out_len = len; return 1;
            }
        }
        *verdict = NF_ACCEPT;
        return 0;
    }

    if (ip->protocol == IPPROTO_TCP) {
        if (tcp_mangle_ipv4(data, len)) {
            *verdict = NF_DROP;
            return 0;
        }
    }
    *verdict = NF_ACCEPT;
    return 0;
}

static int handle_ipv6(uint8_t *data, size_t len, int *verdict,
                       uint8_t **out_buf, size_t *out_len) {
    struct ip6_hdr *ip6 = (struct ip6_hdr *)data;
    size_t iph_len = sizeof(struct ip6_hdr);
    if (len < iph_len) { *verdict = NF_ACCEPT; return 0; }

    if (ip6->ip6_nxt == IPPROTO_UDP && len >= iph_len + sizeof(struct udphdr)) {
        struct udphdr *udp = (struct udphdr *)(data + iph_len);
        uint16_t dport = ntohs(udp->dest);
        uint16_t sport = ntohs(udp->source);

        if (gbd_cfg.block_quic && dport == 443) {
            *verdict = NF_DROP;
            return 0;
        }
        if (dport == 53 && gbd_cfg.dns6_enabled) {
            if (dns_redir_out_ipv6(data, len)) {
                *verdict = NF_ACCEPT; *out_buf = data; *out_len = len; return 1;
            }
        }
        if (sport == gbd_cfg.dns6_port && gbd_cfg.dns6_enabled &&
            memcmp(&ip6->ip6_src, &gbd_cfg.dns6_addr, 16) == 0) {
            if (dns_redir_in_ipv6(data, len)) {
                *verdict = NF_ACCEPT; *out_buf = data; *out_len = len; return 1;
            }
        }
        *verdict = NF_ACCEPT;
        return 0;
    }

    if (ip6->ip6_nxt == IPPROTO_TCP) {
        if (tcp_mangle_ipv6(data, len)) {
            *verdict = NF_DROP;
            return 0;
        }
    }
    *verdict = NF_ACCEPT;
    return 0;
}

static int cb(struct nfq_q_handle *qh, struct nfgenmsg *nfmsg,
              struct nfq_data *nfa, void *cbdata) {
    (void)nfmsg; (void)cbdata;
    struct nfqnl_msg_packet_hdr *ph = nfq_get_msg_packet_hdr(nfa);
    if (!ph) return -1;
    uint32_t id = ntohl(ph->packet_id);

    uint8_t *data = NULL;
    int len = nfq_get_payload(nfa, (unsigned char **)&data);
    if (len < 0 || data == NULL) {
        return nfq_set_verdict(qh, id, NF_ACCEPT, 0, NULL);
    }

    int verdict = NF_ACCEPT;
    uint8_t *out_buf = NULL;
    size_t   out_len = 0;
    int modified = 0;

    if ((data[0] >> 4) == 4) {
        modified = handle_ipv4(data, (size_t)len, &verdict, &out_buf, &out_len);
    } else if ((data[0] >> 4) == 6) {
        modified = handle_ipv6(data, (size_t)len, &verdict, &out_buf, &out_len);
    }

    if (modified) {
        return nfq_set_verdict(qh, id, verdict, (uint32_t)out_len, out_buf);
    }
    return nfq_set_verdict(qh, id, verdict, 0, NULL);
}

int nfq_loop_run(void) {
    struct nfq_handle *h = nfq_open();
    if (!h) { LOGE("nfq_open failed: %s", strerror(errno)); return -1; }

    /* These unbind/bind calls are no-ops on modern kernels but harmless. */
    nfq_unbind_pf(h, AF_INET);
    nfq_bind_pf(h, AF_INET);
    nfq_bind_pf(h, AF_INET6);

    struct nfq_q_handle *qh = nfq_create_queue(h, gbd_cfg.queue_num, &cb, NULL);
    if (!qh) {
        LOGE("nfq_create_queue(%u) failed: %s", gbd_cfg.queue_num, strerror(errno));
        nfq_close(h);
        return -1;
    }
    if (nfq_set_mode(qh, NFQNL_COPY_PACKET, 0xFFFF) < 0) {
        LOGE("nfq_set_mode failed");
        nfq_destroy_queue(qh);
        nfq_close(h);
        return -1;
    }
    nfq_set_queue_maxlen(qh, 4096);

    int fd = nfq_fd(h);
    LOGI("listening on NFQUEUE #%u", gbd_cfg.queue_num);

    char buf[65536] __attribute__((aligned(8)));
    while (!gbd_stop) {
        struct pollfd pfd = { .fd = fd, .events = POLLIN };
        int pr = poll(&pfd, 1, 500);
        if (pr < 0) {
            if (errno == EINTR) continue;
            LOGE("poll: %s", strerror(errno));
            break;
        }
        if (pr == 0) continue;
        ssize_t n = recv(fd, buf, sizeof buf, 0);
        if (n < 0) {
            if (errno == EINTR) continue;
            if (errno == ENOBUFS) { LOGD("ENOBUFS, dropping"); continue; }
            LOGE("recv: %s", strerror(errno));
            break;
        }
        nfq_handle_packet(h, buf, (int)n);
    }

    LOGI("shutting down NFQ loop");
    nfq_destroy_queue(qh);
    nfq_close(h);
    return 0;
}
