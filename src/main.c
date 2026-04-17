#include "util.h"
#include "nfq_loop.h"
#include "raw_inject.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <getopt.h>
#include <errno.h>
#include <arpa/inet.h>

static void usage(const char *argv0) {
    fprintf(stderr,
        "GoodbyeDPI (Linux port) — Turkey fork subset\n"
        "Usage: %s [options]\n"
        "\n"
        "Presets (match Windows GoodbyeDPI semantics):\n"
        "  -5                          -f 2 -e 2 --reverse-frag --fake-packet\n"
        "                              --auto-ttl --max-payload-size 1200\n"
        "  -9                          -f 2 -e 2 --reverse-frag --fake-packet\n"
        "                              --wrong-seq --wrong-chksum -q --max-payload-size 1200\n"
        "\n"
        "Individual flags:\n"
        "  -f N                        fragment HTTP request at N bytes\n"
        "  -e N                        fragment HTTPS TLS ClientHello at N bytes\n"
        "  --auto-ttl                  low-hop-limit decoy heuristic (fixed hop 4)\n"
        "  --reverse-frag              send fragments in reverse order\n"
        "  --fake-packet               emit decoy ClientHello/HTTP ahead of real fragments\n"
        "  --wrong-seq                 decoy with bogus TCP sequence\n"
        "  --wrong-chksum              decoy with invalid TCP checksum\n"
        "  --max-payload               legacy no-op marker (compat with Windows CLI)\n"
        "  -q                          block QUIC (UDP/443)\n"
        "  --set-ttl N                 TTL for decoy packets (1..255)\n"
        "  --dns-addr IP               redirect UDP/53 → IP:--dns-port\n"
        "  --dns-port N                (default 53)\n"
        "  --dnsv6-addr IP6            IPv6 DNS redirect target\n"
        "  --dnsv6-port N              (default 53)\n"
        "  --queue-num N               NFQUEUE number (default 200)\n"
        "  -v                          verbose debug logging\n"
        "  -h                          this help\n"
        "\n"
        "Requires root (or CAP_NET_ADMIN + CAP_NET_RAW) and iptables rules\n"
        "queuing matching traffic to this tool (see scripts/iptables-up.sh).\n",
        argv0);
}

/* Mirrors Windows goodbyedpi.c case '5':
 *   do_fragment_http = do_fragment_https = 1
 *   do_reverse_frag = do_native_frag = 1
 *   http_fragment_size = https_fragment_size = 2
 *   do_fake_packet = 1
 *   do_auto_ttl = 1
 *   max_payload_size = 1200
 * (do_native_frag is approximated by our TCP-level split.) */
static void apply_preset_5(void) {
    gbd_cfg.frag_http        = 2;
    gbd_cfg.frag_https       = 2;
    gbd_cfg.reverse_frag     = 1;
    gbd_cfg.fake_packet      = 1;
    gbd_cfg.auto_ttl         = 1;
    gbd_cfg.max_payload      = 1;
    gbd_cfg.max_payload_size = 1200;
}

/* Mirrors Windows goodbyedpi.c case '9' → '8' → '7' fall-through:
 *   fragment at 2 + reverse + native + fake_packet + wrong_chksum + wrong_seq + block_quic
 *   max_payload_size = 1200
 * Notably, upstream does NOT set do_auto_ttl for -9. */
static void apply_preset_9(void) {
    gbd_cfg.frag_http        = 2;
    gbd_cfg.frag_https       = 2;
    gbd_cfg.reverse_frag     = 1;
    gbd_cfg.fake_packet      = 1;
    gbd_cfg.wrong_seq        = 1;
    gbd_cfg.wrong_chksum     = 1;
    gbd_cfg.block_quic       = 1;
    gbd_cfg.max_payload      = 1;
    gbd_cfg.max_payload_size = 1200;
}

static void on_signal(int sig) {
    (void)sig;
    gbd_stop = 1;
}

enum {
    OPT_AUTO_TTL = 1000,
    OPT_REVERSE_FRAG,
    OPT_WRONG_SEQ,
    OPT_WRONG_CHKSUM,
    OPT_MAX_PAYLOAD,
    OPT_SET_TTL,
    OPT_DNS_ADDR,
    OPT_DNS_PORT,
    OPT_DNSV6_ADDR,
    OPT_DNSV6_PORT,
    OPT_QUEUE_NUM,
};

int main(int argc, char **argv) {
    memset(&gbd_cfg, 0, sizeof gbd_cfg);
    gbd_cfg.queue_num = 200;
    gbd_cfg.dns4_port = 53;
    gbd_cfg.dns6_port = 53;

    static const struct option long_opts[] = {
        {"auto-ttl",      no_argument,       NULL, OPT_AUTO_TTL},
        {"reverse-frag",  no_argument,       NULL, OPT_REVERSE_FRAG},
        {"wrong-seq",     no_argument,       NULL, OPT_WRONG_SEQ},
        {"wrong-chksum",  no_argument,       NULL, OPT_WRONG_CHKSUM},
        {"max-payload",   no_argument,       NULL, OPT_MAX_PAYLOAD},
        {"set-ttl",       required_argument, NULL, OPT_SET_TTL},
        {"dns-addr",      required_argument, NULL, OPT_DNS_ADDR},
        {"dns-port",      required_argument, NULL, OPT_DNS_PORT},
        {"dnsv6-addr",    required_argument, NULL, OPT_DNSV6_ADDR},
        {"dnsv6-port",    required_argument, NULL, OPT_DNSV6_PORT},
        {"queue-num",     required_argument, NULL, OPT_QUEUE_NUM},
        {"help",          no_argument,       NULL, 'h'},
        {0,0,0,0}
    };

    int c;
    while ((c = getopt_long(argc, argv, "59f:e:qvh", long_opts, NULL)) != -1) {
        switch (c) {
        case '5': gbd_cfg.preset5 = 1; apply_preset_5(); break;
        case '9': gbd_cfg.preset9 = 1; apply_preset_9(); break;
        case 'f': gbd_cfg.frag_http  = atoi(optarg); break;
        case 'e': gbd_cfg.frag_https = atoi(optarg); break;
        case 'q': gbd_cfg.block_quic = 1; break;
        case 'v': gbd_verbose = 1; break;
        case OPT_AUTO_TTL:
            /* upstream: --auto-ttl implies do_fake_packet=1 */
            gbd_cfg.auto_ttl = 1;
            gbd_cfg.fake_packet = 1;
            break;
        case OPT_REVERSE_FRAG: gbd_cfg.reverse_frag = 1; break;
        case OPT_WRONG_SEQ:
            /* upstream: --wrong-seq implies do_fake_packet=1 */
            gbd_cfg.wrong_seq = 1;
            gbd_cfg.fake_packet = 1;
            break;
        case OPT_WRONG_CHKSUM:
            /* upstream: --wrong-chksum implies do_fake_packet=1 */
            gbd_cfg.wrong_chksum = 1;
            gbd_cfg.fake_packet = 1;
            break;
        case OPT_MAX_PAYLOAD:  gbd_cfg.max_payload = 1; break;
        case OPT_SET_TTL:
            gbd_cfg.set_ttl = atoi(optarg);
            if (gbd_cfg.set_ttl < 1 || gbd_cfg.set_ttl > 255) {
                LOGE("--set-ttl must be 1..255");
                return 2;
            }
            /* upstream: --set-ttl N implies do_fake_packet=1 */
            gbd_cfg.fake_packet = 1;
            break;
        case OPT_DNS_ADDR:
            if (inet_pton(AF_INET, optarg, &gbd_cfg.dns4_addr) != 1) {
                LOGE("--dns-addr: invalid IPv4 address '%s'", optarg);
                return 2;
            }
            gbd_cfg.dns4_enabled = 1;
            break;
        case OPT_DNS_PORT:
            gbd_cfg.dns4_port = (uint16_t)atoi(optarg);
            break;
        case OPT_DNSV6_ADDR:
            if (inet_pton(AF_INET6, optarg, &gbd_cfg.dns6_addr) != 1) {
                LOGE("--dnsv6-addr: invalid IPv6 address '%s'", optarg);
                return 2;
            }
            gbd_cfg.dns6_enabled = 1;
            break;
        case OPT_DNSV6_PORT:
            gbd_cfg.dns6_port = (uint16_t)atoi(optarg);
            break;
        case OPT_QUEUE_NUM:
            gbd_cfg.queue_num = (unsigned)atoi(optarg);
            break;
        case 'h':
            usage(argv[0]);
            return 0;
        default:
            usage(argv[0]);
            return 2;
        }
    }

    LOGI("config: f=%d e=%d auto_ttl=%d reverse=%d fake=%d wrong_seq=%d wrong_chk=%d "
         "quic=%d set_ttl=%d max_payload=%u dns4=%d dns6=%d queue=%u",
         gbd_cfg.frag_http, gbd_cfg.frag_https, gbd_cfg.auto_ttl,
         gbd_cfg.reverse_frag, gbd_cfg.fake_packet,
         gbd_cfg.wrong_seq, gbd_cfg.wrong_chksum,
         gbd_cfg.block_quic, gbd_cfg.set_ttl,
         (unsigned)gbd_cfg.max_payload_size,
         gbd_cfg.dns4_enabled, gbd_cfg.dns6_enabled, gbd_cfg.queue_num);

    struct sigaction sa = { .sa_handler = on_signal };
    sigemptyset(&sa.sa_mask);
    sigaction(SIGINT,  &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    signal(SIGPIPE, SIG_IGN);

    if (raw_inject_init() < 0) {
        LOGE("raw_inject_init failed — need CAP_NET_RAW / root");
        return 1;
    }

    int rc = nfq_loop_run();
    raw_inject_close();
    return rc < 0 ? 1 : 0;
}
