#ifndef GBD_CHECKSUM_H
#define GBD_CHECKSUM_H

#include <stdint.h>
#include <stddef.h>
#include <netinet/ip.h>
#include <netinet/ip6.h>

uint16_t ipv4_checksum(const void *vdata, size_t length);

uint16_t tcp4_checksum(const struct iphdr *ip,
                       const void *tcp_hdr_and_payload, size_t l4_len);
uint16_t udp4_checksum(const struct iphdr *ip,
                       const void *udp_hdr_and_payload, size_t l4_len);

uint16_t tcp6_checksum(const struct ip6_hdr *ip6,
                       const void *tcp_hdr_and_payload, size_t l4_len);
uint16_t udp6_checksum(const struct ip6_hdr *ip6,
                       const void *udp_hdr_and_payload, size_t l4_len);

#endif
