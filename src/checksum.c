#include "checksum.h"
#include <string.h>
#include <arpa/inet.h>

static uint32_t sum16(const void *vdata, size_t length, uint32_t init) {
    const uint8_t *p = vdata;
    uint32_t acc = init;
    while (length >= 2) {
        acc += ((uint32_t)p[0] << 8) | p[1];
        p += 2;
        length -= 2;
    }
    if (length) acc += ((uint32_t)p[0] << 8);
    while (acc >> 16) acc = (acc & 0xFFFF) + (acc >> 16);
    return acc;
}

static uint16_t fold(uint32_t acc) {
    while (acc >> 16) acc = (acc & 0xFFFF) + (acc >> 16);
    return htons((uint16_t)~acc & 0xFFFF);
}

uint16_t ipv4_checksum(const void *vdata, size_t length) {
    return fold(sum16(vdata, length, 0));
}

static uint32_t pseudo4(const struct iphdr *ip, uint8_t proto, uint16_t l4_len) {
    uint32_t acc = 0;
    uint32_t s = ntohl(ip->saddr);
    uint32_t d = ntohl(ip->daddr);
    acc += (s >> 16) & 0xFFFF;
    acc += s & 0xFFFF;
    acc += (d >> 16) & 0xFFFF;
    acc += d & 0xFFFF;
    acc += proto;
    acc += l4_len;
    return acc;
}

uint16_t tcp4_checksum(const struct iphdr *ip, const void *l4, size_t l4_len) {
    uint32_t acc = pseudo4(ip, 6, (uint16_t)l4_len);
    acc = sum16(l4, l4_len, acc);
    return fold(acc);
}

uint16_t udp4_checksum(const struct iphdr *ip, const void *l4, size_t l4_len) {
    uint32_t acc = pseudo4(ip, 17, (uint16_t)l4_len);
    acc = sum16(l4, l4_len, acc);
    uint16_t cs = fold(acc);
    return cs ? cs : 0xFFFF;
}

static uint32_t pseudo6(const struct ip6_hdr *ip6, uint8_t proto, uint32_t l4_len) {
    uint32_t acc = 0;
    const uint8_t *s = (const uint8_t *)&ip6->ip6_src;
    const uint8_t *d = (const uint8_t *)&ip6->ip6_dst;
    for (int i = 0; i < 16; i += 2)
        acc += ((uint32_t)s[i] << 8) | s[i+1];
    for (int i = 0; i < 16; i += 2)
        acc += ((uint32_t)d[i] << 8) | d[i+1];
    acc += (l4_len >> 16) & 0xFFFF;
    acc += l4_len & 0xFFFF;
    acc += proto;
    return acc;
}

uint16_t tcp6_checksum(const struct ip6_hdr *ip6, const void *l4, size_t l4_len) {
    uint32_t acc = pseudo6(ip6, 6, (uint32_t)l4_len);
    acc = sum16(l4, l4_len, acc);
    return fold(acc);
}

uint16_t udp6_checksum(const struct ip6_hdr *ip6, const void *l4, size_t l4_len) {
    uint32_t acc = pseudo6(ip6, 17, (uint32_t)l4_len);
    acc = sum16(l4, l4_len, acc);
    uint16_t cs = fold(acc);
    return cs ? cs : 0xFFFF;
}
