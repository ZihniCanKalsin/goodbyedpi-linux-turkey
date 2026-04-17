#include "dns_redir.h"
#include "checksum.h"
#include "util.h"

#include <string.h>
#include <time.h>
#include <arpa/inet.h>
#include <netinet/ip.h>
#include <netinet/ip6.h>
#include <netinet/udp.h>

/* Tracks an outbound DNS query so we can reverse the server-address rewrite
 * on the reply. Key = (client src ip, client src port, dns txid). */
#define MAP_SIZE 4096
#define MAP_TTL_SEC 30

struct map4 {
    uint8_t  used;
    uint32_t saddr;      /* client */
    uint16_t sport;
    uint16_t txid;
    uint32_t orig_daddr; /* original dns server as seen by client */
    uint16_t orig_dport;
    time_t   expire;
};

struct map6 {
    uint8_t  used;
    uint8_t  saddr[16];
    uint16_t sport;
    uint16_t txid;
    uint8_t  orig_daddr[16];
    uint16_t orig_dport;
    time_t   expire;
};

static struct map4 map4_[MAP_SIZE];
static struct map6 map6_[MAP_SIZE];

static uint32_t hash4(uint32_t a, uint16_t b, uint16_t c) {
    uint32_t x = a ^ ((uint32_t)b << 16) ^ c;
    x ^= x >> 16; x *= 0x7feb352d;
    x ^= x >> 15; x *= 0x846ca68b;
    x ^= x >> 16;
    return x;
}

static uint32_t hash6(const uint8_t *a, uint16_t b, uint16_t c) {
    uint32_t x = 0;
    for (int i = 0; i < 16; i += 4) {
        uint32_t w;
        memcpy(&w, a + i, 4);
        x ^= w;
    }
    x ^= ((uint32_t)b << 16) ^ c;
    x ^= x >> 16; x *= 0x7feb352d;
    x ^= x >> 15; x *= 0x846ca68b;
    x ^= x >> 16;
    return x;
}

static uint16_t read_txid(const uint8_t *udp_payload, size_t plen) {
    if (plen < 2) return 0;
    return ((uint16_t)udp_payload[0] << 8) | udp_payload[1];
}

static void map4_put(uint32_t saddr, uint16_t sport, uint16_t txid,
                     uint32_t orig_daddr, uint16_t orig_dport) {
    uint32_t h = hash4(saddr, sport, txid);
    time_t now = time(NULL);
    for (int i = 0; i < 8; i++) {
        struct map4 *e = &map4_[(h + i) & (MAP_SIZE - 1)];
        if (!e->used || e->expire < now ||
            (e->saddr == saddr && e->sport == sport && e->txid == txid)) {
            e->used = 1;
            e->saddr = saddr; e->sport = sport; e->txid = txid;
            e->orig_daddr = orig_daddr; e->orig_dport = orig_dport;
            e->expire = now + MAP_TTL_SEC;
            return;
        }
    }
}

static int map4_get(uint32_t saddr, uint16_t sport, uint16_t txid,
                    uint32_t *orig_daddr, uint16_t *orig_dport) {
    uint32_t h = hash4(saddr, sport, txid);
    time_t now = time(NULL);
    for (int i = 0; i < 8; i++) {
        struct map4 *e = &map4_[(h + i) & (MAP_SIZE - 1)];
        if (e->used && e->expire >= now &&
            e->saddr == saddr && e->sport == sport && e->txid == txid) {
            *orig_daddr = e->orig_daddr;
            *orig_dport = e->orig_dport;
            return 1;
        }
    }
    return 0;
}

static void map6_put(const uint8_t *saddr, uint16_t sport, uint16_t txid,
                     const uint8_t *orig_daddr, uint16_t orig_dport) {
    uint32_t h = hash6(saddr, sport, txid);
    time_t now = time(NULL);
    for (int i = 0; i < 8; i++) {
        struct map6 *e = &map6_[(h + i) & (MAP_SIZE - 1)];
        if (!e->used || e->expire < now ||
            (memcmp(e->saddr, saddr, 16) == 0 && e->sport == sport && e->txid == txid)) {
            e->used = 1;
            memcpy(e->saddr, saddr, 16);
            e->sport = sport; e->txid = txid;
            memcpy(e->orig_daddr, orig_daddr, 16);
            e->orig_dport = orig_dport;
            e->expire = now + MAP_TTL_SEC;
            return;
        }
    }
}

static int map6_get(const uint8_t *saddr, uint16_t sport, uint16_t txid,
                    uint8_t *orig_daddr, uint16_t *orig_dport) {
    uint32_t h = hash6(saddr, sport, txid);
    time_t now = time(NULL);
    for (int i = 0; i < 8; i++) {
        struct map6 *e = &map6_[(h + i) & (MAP_SIZE - 1)];
        if (e->used && e->expire >= now &&
            memcmp(e->saddr, saddr, 16) == 0 && e->sport == sport && e->txid == txid) {
            memcpy(orig_daddr, e->orig_daddr, 16);
            *orig_dport = e->orig_dport;
            return 1;
        }
    }
    return 0;
}

int dns_redir_out_ipv4(uint8_t *pkt, size_t pkt_len) {
    if (!gbd_cfg.dns4_enabled) return 0;
    if (pkt_len < sizeof(struct iphdr)) return 0;
    struct iphdr *ip = (struct iphdr *)pkt;
    if (ip->protocol != IPPROTO_UDP) return 0;
    size_t iph_len = ip->ihl * 4u;
    if (pkt_len < iph_len + sizeof(struct udphdr)) return 0;
    struct udphdr *udp = (struct udphdr *)(pkt + iph_len);
    if (ntohs(udp->dest) != 53) return 0;

    size_t udp_len = pkt_len - iph_len;
    if (udp_len < sizeof(struct udphdr)) return 0;
    uint8_t *payload = (uint8_t *)udp + sizeof(struct udphdr);
    size_t plen = udp_len - sizeof(struct udphdr);
    uint16_t txid = read_txid(payload, plen);

    map4_put(ip->saddr, udp->source, txid, ip->daddr, udp->dest);

    ip->daddr = gbd_cfg.dns4_addr.s_addr;
    udp->dest = htons(gbd_cfg.dns4_port);
    ip->check = 0;
    ip->check = ipv4_checksum(ip, iph_len);
    udp->check = 0;
    udp->check = udp4_checksum(ip, udp, udp_len);
    return 1;
}

int dns_redir_in_ipv4(uint8_t *pkt, size_t pkt_len) {
    if (!gbd_cfg.dns4_enabled) return 0;
    if (pkt_len < sizeof(struct iphdr)) return 0;
    struct iphdr *ip = (struct iphdr *)pkt;
    if (ip->protocol != IPPROTO_UDP) return 0;
    size_t iph_len = ip->ihl * 4u;
    if (pkt_len < iph_len + sizeof(struct udphdr)) return 0;
    struct udphdr *udp = (struct udphdr *)(pkt + iph_len);
    if (ip->saddr != gbd_cfg.dns4_addr.s_addr) return 0;
    if (ntohs(udp->source) != gbd_cfg.dns4_port) return 0;

    size_t udp_len = pkt_len - iph_len;
    uint8_t *payload = (uint8_t *)udp + sizeof(struct udphdr);
    size_t plen = udp_len - sizeof(struct udphdr);
    uint16_t txid = read_txid(payload, plen);

    uint32_t orig_daddr; uint16_t orig_dport;
    if (!map4_get(ip->daddr, udp->dest, txid, &orig_daddr, &orig_dport))
        return 0;

    ip->saddr = orig_daddr;
    udp->source = orig_dport;
    ip->check = 0;
    ip->check = ipv4_checksum(ip, iph_len);
    udp->check = 0;
    udp->check = udp4_checksum(ip, udp, udp_len);
    return 1;
}

int dns_redir_out_ipv6(uint8_t *pkt, size_t pkt_len) {
    if (!gbd_cfg.dns6_enabled) return 0;
    if (pkt_len < sizeof(struct ip6_hdr)) return 0;
    struct ip6_hdr *ip6 = (struct ip6_hdr *)pkt;
    if (ip6->ip6_nxt != IPPROTO_UDP) return 0;
    size_t iph_len = sizeof(struct ip6_hdr);
    if (pkt_len < iph_len + sizeof(struct udphdr)) return 0;
    struct udphdr *udp = (struct udphdr *)(pkt + iph_len);
    if (ntohs(udp->dest) != 53) return 0;

    size_t udp_len = pkt_len - iph_len;
    uint8_t *payload = (uint8_t *)udp + sizeof(struct udphdr);
    size_t plen = udp_len - sizeof(struct udphdr);
    uint16_t txid = read_txid(payload, plen);

    map6_put((uint8_t *)&ip6->ip6_src, udp->source, txid,
             (uint8_t *)&ip6->ip6_dst, udp->dest);

    memcpy(&ip6->ip6_dst, &gbd_cfg.dns6_addr, 16);
    udp->dest = htons(gbd_cfg.dns6_port);
    udp->check = 0;
    udp->check = udp6_checksum(ip6, udp, udp_len);
    return 1;
}

int dns_redir_in_ipv6(uint8_t *pkt, size_t pkt_len) {
    if (!gbd_cfg.dns6_enabled) return 0;
    if (pkt_len < sizeof(struct ip6_hdr)) return 0;
    struct ip6_hdr *ip6 = (struct ip6_hdr *)pkt;
    if (ip6->ip6_nxt != IPPROTO_UDP) return 0;
    size_t iph_len = sizeof(struct ip6_hdr);
    if (pkt_len < iph_len + sizeof(struct udphdr)) return 0;
    struct udphdr *udp = (struct udphdr *)(pkt + iph_len);
    if (memcmp(&ip6->ip6_src, &gbd_cfg.dns6_addr, 16) != 0) return 0;
    if (ntohs(udp->source) != gbd_cfg.dns6_port) return 0;

    size_t udp_len = pkt_len - iph_len;
    uint8_t *payload = (uint8_t *)udp + sizeof(struct udphdr);
    size_t plen = udp_len - sizeof(struct udphdr);
    uint16_t txid = read_txid(payload, plen);

    uint8_t orig_daddr[16]; uint16_t orig_dport;
    if (!map6_get((uint8_t *)&ip6->ip6_dst, udp->dest, txid,
                  orig_daddr, &orig_dport))
        return 0;

    memcpy(&ip6->ip6_src, orig_daddr, 16);
    udp->source = orig_dport;
    udp->check = 0;
    udp->check = udp6_checksum(ip6, udp, udp_len);
    return 1;
}
