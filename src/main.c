#include "util.h"
#include "nfq_loop.h"
#include "raw_inject.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <getopt.h>
#include <errno.h>
#include <limits.h>
#include <arpa/inet.h>

static long parse_long(const char *s, long lo, long hi, const char *opt) {
    char *end;
    errno = 0;
    long v = strtol(s, &end, 10);
    if (errno || *end || end == s || v < lo || v > hi) {
        LOGE("%s: geçersiz değer '%s' (beklenen %ld..%ld)", opt, s, lo, hi);
        exit(2);
    }
    return v;
}

static void usage(const char *argv0) {
    fprintf(stderr,
        "GoodbyeDPI (Linux port'u) — Turkey fork alt kümesi\n"
        "Kullanım: %s [seçenekler]\n"
        "\n"
        "Ön ayarlar (Windows GoodbyeDPI semantikleriyle eşleşir):\n"
        "  -5                          -f 2 -e 2 --reverse-frag --fake-packet\n"
        "                              --auto-ttl --max-payload-size 1200\n"
        "  -9                          -f 2 -e 2 --reverse-frag --fake-packet\n"
        "                              --wrong-seq --wrong-chksum -q --max-payload-size 1200\n"
        "\n"
        "Tek tek bayraklar:\n"
        "  -f N                        HTTP isteğini N baytta böl\n"
        "  -e N                        HTTPS TLS ClientHello'yu N baytta böl\n"
        "  --auto-ttl                  tuzak paket için düşük atlama limiti sezgisi (sabit 4)\n"
        "  --reverse-frag              parçaları ters sırada gönder\n"
        "  --fake-packet               gerçek parçalardan önce sahte ClientHello/HTTP yem üret\n"
        "  --wrong-seq                 hatalı TCP sıra numarasıyla tuzak\n"
        "  --wrong-chksum              geçersiz TCP sağlama toplamıyla tuzak\n"
        "  --max-payload               eski no-op işaretçi (Windows CLI uyumluluğu için)\n"
        "  -q                          QUIC'i (UDP/443) engelle\n"
        "  --set-ttl N                 tuzak paketlerin TTL'si (1..255)\n"
        "  --dns-addr IP               UDP/53'ü IP:--dns-port'a yönlendir\n"
        "  --dns-port N                (varsayılan 53)\n"
        "  --dnsv6-addr IP6            IPv6 DNS yönlendirme hedefi\n"
        "  --dnsv6-port N              (varsayılan 53)\n"
        "  --queue-num N               NFQUEUE numarası (varsayılan 200)\n"
        "  -v                          ayrıntılı hata ayıklama günlüğü\n"
        "  -h                          bu yardım\n"
        "\n"
        "root (ya da CAP_NET_ADMIN + CAP_NET_RAW) ve eşleşen trafiği bu araca\n"
        "kuyruklayan iptables kuralları gerektirir (bkz. scripts/iptables-up.sh).\n",
        argv0);
}

/* Windows goodbyedpi.c '5' durumunu yansıtır:
 *   do_fragment_http = do_fragment_https = 1
 *   do_reverse_frag = do_native_frag = 1
 *   http_fragment_size = https_fragment_size = 2
 *   do_fake_packet = 1
 *   do_auto_ttl = 1
 *   max_payload_size = 1200
 * (do_native_frag burada TCP seviyesi bölme ile yaklaştırılır.) */
static void apply_preset_5(void) {
    gbd_cfg.frag_http        = 2;
    gbd_cfg.frag_https       = 2;
    gbd_cfg.reverse_frag     = 1;
    gbd_cfg.fake_packet      = 1;
    gbd_cfg.auto_ttl         = 1;
    gbd_cfg.max_payload      = 1;
    gbd_cfg.max_payload_size = 1200;
}

/* Windows goodbyedpi.c '9' → '8' → '7' fall-through'unu yansıtır:
 *   2 baytta böl + reverse + native + fake_packet + wrong_chksum + wrong_seq + block_quic
 *   max_payload_size = 1200
 * Dikkat: üstakım -9 için do_auto_ttl'yi AYARLAMAZ. */
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
    OPT_FAKE_PACKET,
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
        {"fake-packet",   no_argument,       NULL, OPT_FAKE_PACKET},
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
        case 'f': gbd_cfg.frag_http  = (int)parse_long(optarg, 1, 65535, "-f"); break;
        case 'e': gbd_cfg.frag_https = (int)parse_long(optarg, 1, 65535, "-e"); break;
        case 'q': gbd_cfg.block_quic = 1; break;
        case 'v': gbd_verbose = 1; break;
        case OPT_AUTO_TTL:
            /* üstakım: --auto-ttl do_fake_packet=1 anlamına gelir */
            gbd_cfg.auto_ttl = 1;
            gbd_cfg.fake_packet = 1;
            break;
        case OPT_REVERSE_FRAG: gbd_cfg.reverse_frag = 1; break;
        case OPT_FAKE_PACKET: gbd_cfg.fake_packet = 1; break;
        case OPT_WRONG_SEQ:
            /* üstakım: --wrong-seq do_fake_packet=1 anlamına gelir */
            gbd_cfg.wrong_seq = 1;
            gbd_cfg.fake_packet = 1;
            break;
        case OPT_WRONG_CHKSUM:
            /* üstakım: --wrong-chksum do_fake_packet=1 anlamına gelir */
            gbd_cfg.wrong_chksum = 1;
            gbd_cfg.fake_packet = 1;
            break;
        case OPT_MAX_PAYLOAD:  gbd_cfg.max_payload = 1; break;
        case OPT_SET_TTL:
            gbd_cfg.set_ttl = (int)parse_long(optarg, 1, 255, "--set-ttl");
            /* üstakım: --set-ttl N do_fake_packet=1 anlamına gelir */
            gbd_cfg.fake_packet = 1;
            break;
        case OPT_DNS_ADDR:
            if (inet_pton(AF_INET, optarg, &gbd_cfg.dns4_addr) != 1) {
                LOGE("--dns-addr: geçersiz IPv4 adresi '%s'", optarg);
                return 2;
            }
            gbd_cfg.dns4_enabled = 1;
            break;
        case OPT_DNS_PORT:
            gbd_cfg.dns4_port = (uint16_t)parse_long(optarg, 1, 65535, "--dns-port");
            break;
        case OPT_DNSV6_ADDR:
            if (inet_pton(AF_INET6, optarg, &gbd_cfg.dns6_addr) != 1) {
                LOGE("--dnsv6-addr: geçersiz IPv6 adresi '%s'", optarg);
                return 2;
            }
            gbd_cfg.dns6_enabled = 1;
            break;
        case OPT_DNSV6_PORT:
            gbd_cfg.dns6_port = (uint16_t)parse_long(optarg, 1, 65535, "--dnsv6-port");
            break;
        case OPT_QUEUE_NUM:
            gbd_cfg.queue_num = (unsigned)parse_long(optarg, 0, 65535, "--queue-num");
            break;
        case 'h':
            usage(argv[0]);
            return 0;
        default:
            usage(argv[0]);
            return 2;
        }
    }

    LOGI("yapılandırma: f=%d e=%d auto_ttl=%d reverse=%d fake=%d wrong_seq=%d wrong_chk=%d "
         "quic=%d set_ttl=%d max_payload=%u dns4=%d dns6=%d kuyruk=%u",
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
        LOGE("raw_inject_init başarısız — CAP_NET_RAW / root gerekli");
        return 1;
    }

    int rc = nfq_loop_run();
    raw_inject_close();
    return rc < 0 ? 1 : 0;
}
