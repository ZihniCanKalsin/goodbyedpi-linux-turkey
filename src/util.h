#ifndef GBD_UTIL_H
#define GBD_UTIL_H

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <netinet/in.h>

extern int gbd_verbose;

#define LOGE(fmt, ...) fprintf(stderr, "[gbd][E] " fmt "\n", ##__VA_ARGS__)
#define LOGI(fmt, ...) fprintf(stderr, "[gbd][I] " fmt "\n", ##__VA_ARGS__)
#define LOGD(fmt, ...) do { if (gbd_verbose) fprintf(stderr, "[gbd][D] " fmt "\n", ##__VA_ARGS__); } while (0)

struct gbd_config {
    int preset5;
    int preset9;
    int frag_http;
    int frag_https;
    int wrong_seq;
    int wrong_chksum;
    int reverse_frag;
    int max_payload;              /* CLI işaretçisi; uyumluluk için korunur */
    uint16_t max_payload_size;    /* TCP yükü bu değerden büyükse bölme; 0 = sınırsız */
    int auto_ttl;
    int set_ttl;
    int block_quic;
    int fake_packet;              /* gerçek bölmeden önce sahte tuzak segment(ler) yayınla */

    int dns4_enabled;
    struct in_addr  dns4_addr;
    uint16_t        dns4_port;

    int dns6_enabled;
    struct in6_addr dns6_addr;
    uint16_t        dns6_port;

    unsigned queue_num;
};

extern struct gbd_config gbd_cfg;

#endif
