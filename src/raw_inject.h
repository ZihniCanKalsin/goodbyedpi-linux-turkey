#ifndef GBD_RAW_INJECT_H
#define GBD_RAW_INJECT_H

#include <stdint.h>
#include <stddef.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/ip6.h>
#include <netinet/tcp.h>

int  raw_inject_init(void);
void raw_inject_close(void);

/* Inject a TCP segment built from the given IPv4 template (src/dst/ports/flags
 * from tpl_ip/tpl_tcp), carrying the given payload, with options:
 *  - ttl:          IP TTL to set (<=0 means copy from template)
 *  - seq_override: TCP seq to use (0 = use tpl_tcp->seq)
 *  - wrong_chksum: if non-zero, produce a deliberately invalid L4 checksum
 */
int raw_inject_tcp4(const struct iphdr *tpl_ip,
                    const struct tcphdr *tpl_tcp,
                    const uint8_t *payload, size_t payload_len,
                    int ttl, uint32_t seq_override, int wrong_chksum);

int raw_inject_tcp6(const struct ip6_hdr *tpl_ip6,
                    const struct tcphdr *tpl_tcp,
                    const uint8_t *payload, size_t payload_len,
                    int hoplimit, uint32_t seq_override, int wrong_chksum);

#endif
