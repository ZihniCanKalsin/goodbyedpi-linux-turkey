#ifndef GBD_DNS_REDIR_H
#define GBD_DNS_REDIR_H

#include <stdint.h>
#include <stddef.h>

/* Each function returns 1 if the packet buffer was mutated in place (caller
 * must NF_ACCEPT with the modified payload), 0 if no change (NF_ACCEPT as-is). */
int dns_redir_out_ipv4(uint8_t *pkt, size_t pkt_len);
int dns_redir_in_ipv4 (uint8_t *pkt, size_t pkt_len);
int dns_redir_out_ipv6(uint8_t *pkt, size_t pkt_len);
int dns_redir_in_ipv6 (uint8_t *pkt, size_t pkt_len);

#endif
