#ifndef GBD_TCP_MANGLE_H
#define GBD_TCP_MANGLE_H

#include <stdint.h>
#include <stddef.h>

/* Returns 1 if the caller should NF_DROP the original packet (it's been
 * handled via fragmented re-injection); 0 if NF_ACCEPT (no match / noop). */
int tcp_mangle_ipv4(uint8_t *pkt, size_t pkt_len);
int tcp_mangle_ipv6(uint8_t *pkt, size_t pkt_len);

#endif
