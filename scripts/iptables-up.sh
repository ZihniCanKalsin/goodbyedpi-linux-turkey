#!/usr/bin/env bash
# iptables-up.sh — goodbyedpi-linux için NFQUEUE kurallarını kurar.
# Idempotent: zaten mevcut olan kurallar tekrar eklenmez.
#
# Kullanım: sudo ./iptables-up.sh [seçenekler]
#   --queue N              NFQUEUE numarası (varsayılan: 200)
#   --mark HEX             daemon'un kendi enjekte ettiği paketleri taşıyan
#                          fwmark; bu kural setinden hariç tutulur
#                          (varsayılan: 0xCEE1, src/util.h GBD_FWMARK ile eşleşmeli)
#   --dns4                 giden UDP/53 kuyruklamasını etkinleştir
#   --dns4-addr IP         daemon'un kullandığı DNS sunucusu IP'si (INPUT ters kuralı için)
#   --dns4-port N          daemon'un kullandığı DNS sunucu portu
#   --dns6                 IPv6 UDP/53 kuyruklamasını etkinleştir
#   --dns6-addr IP6        IPv6 DNS sunucusu
#   --dns6-port N          IPv6 DNS sunucu portu
#   --quic                 UDP/443 (QUIC) kuyruklamasını etkinleştir
#
# Önemli: --mark hariç tutması, daemon'un raw soketle gönderdiği sahte
# tuzakların ve TCP parçalarının kendi kuyruğuna geri düşmesini engeller.
# Bu olmadan kuyruk dolar (ENOBUFS), yasal trafik düşer ve ana makinede
# internet kopar.

set -eu

QUEUE=200
MARK=0xCEE1
DNS4=0; DNS4_ADDR=""; DNS4_PORT=53
DNS6=0; DNS6_ADDR=""; DNS6_PORT=53
QUIC=0

while [ $# -gt 0 ]; do
    case "$1" in
        --queue)     QUEUE="$2"; shift 2 ;;
        --mark)      MARK="$2"; shift 2 ;;
        --dns4)      DNS4=1; shift ;;
        --dns4-addr) DNS4_ADDR="$2"; shift 2 ;;
        --dns4-port) DNS4_PORT="$2"; shift 2 ;;
        --dns6)      DNS6=1; shift ;;
        --dns6-addr) DNS6_ADDR="$2"; shift 2 ;;
        --dns6-port) DNS6_PORT="$2"; shift 2 ;;
        --quic)      QUIC=1; shift ;;
        *) echo "bilinmeyen argüman: $1" >&2; exit 2 ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "root (sudo) olarak çalıştırılmalıdır" >&2
    exit 1
fi

# iptables kurulu mu? Modern bazı dağıtımlarda yalnızca 'nft' olabilir;
# o durumda iptables-nft shim'inin de yüklü olması gerekir.
if ! command -v iptables >/dev/null 2>&1; then
    echo "iptables bulunamadı — paketi kurun (iptables veya iptables-nft)" >&2
    exit 1
fi

# En iyi çaba: çekirdek modüllerinin yüklü olduğundan emin ol. Zaten
# çekirdek içinde varsa zararsız; embedded/minimal sistemlerde modprobe
# bulunmayabilir — bu durumda sessizce atlanır.
if command -v modprobe >/dev/null 2>&1; then
    modprobe nfnetlink_queue 2>/dev/null || true
    modprobe xt_NFQUEUE      2>/dev/null || true
    modprobe ip6_tables      2>/dev/null || true
fi

# NFQUEUE hedefi gerçekten kullanılabilir mi? Geçici bir RETURN zinciri
# oluşturup içine NFQUEUE eklemeye çalışırız; başarısız olursa çekirdekte
# xt_NFQUEUE yok demektir.
_nfq_probe_chain="gbd_nfq_probe_$$"
if ! iptables -N "$_nfq_probe_chain" 2>/dev/null; then
    # zaten varsa (önceki başarısız çalıştırma) temizle
    iptables -F "$_nfq_probe_chain" 2>/dev/null || true
    iptables -X "$_nfq_probe_chain" 2>/dev/null || true
    # Tekrar denemek istiyoruz ama 'set -e' altında bir hata bizi devirmesin:
    # eğer hâlâ yaratamıyorsak, aşağıdaki -A çağrısı temiz bir hata verecek.
    iptables -N "$_nfq_probe_chain" 2>/dev/null || true
fi
if ! iptables -A "$_nfq_probe_chain" -j NFQUEUE --queue-num "$QUEUE" --queue-bypass 2>/dev/null; then
    iptables -X "$_nfq_probe_chain" 2>/dev/null || true
    echo "çekirdek NFQUEUE hedefini desteklemiyor (xt_NFQUEUE yüklü değil)" >&2
    echo "çekirdek modülünü yükleyin veya NFQUEUE destekli bir çekirdek çalıştırın" >&2
    exit 1
fi
iptables -F "$_nfq_probe_chain" 2>/dev/null || true
iptables -X "$_nfq_probe_chain" 2>/dev/null || true

add_rule() {
    # $1=ipcmd, ardından isteğe bağlı olarak `-t TABLE`, geri kalanı kural.
    # iptables -C / -I komut fiilinden ÖNCE gelen -t tablosunu kabul eder,
    # sonra gelen kabul etmez; o yüzden tablo bayrağını ayırıp yeniden
    # dizmek gerekir.
    local ipcmd="$1"; shift
    local table_args=()
    if [ "${1:-}" = "-t" ]; then
        table_args=("$1" "$2")
        shift 2
    fi
    if ! "$ipcmd" "${table_args[@]}" -C "$@" 2>/dev/null; then
        "$ipcmd" "${table_args[@]}" -I "$@"
    fi
}

add_rule iptables OUTPUT -p tcp -m multiport --dports 80,443 \
         -m mark ! --mark "$MARK" \
         -j NFQUEUE --queue-num "$QUEUE" --queue-bypass

# DNS redirection is implemented as NAT DNAT, not NFQUEUE. Reason: an
# NFQUEUE rewrite of a locally-generated UDP/53 packet happens AFTER the
# kernel's route lookup, so a query to 127.0.0.53 (systemd-resolved stub)
# rewritten to a public resolver still tries to leave via the loopback
# interface and is dropped. NAT DNAT runs in nat/OUTPUT, before routing,
# and conntrack un-DNATs the reply automatically — no daemon-side UDP
# handling needed.
if [ "$DNS4" = "1" ] && [ -n "$DNS4_ADDR" ]; then
    # Redirect only queries that leave the host. Queries directed at the
    # local stub resolver (typically systemd-resolved on 127.0.0.53) must
    # still reach it — the stub is our *source* of upstream queries, not
    # a destination to override. Without this exclusion, the stub never
    # receives its clients' packets and every libc resolver call times
    # out even though the DNAT path itself works.
    #
    # On kernels lacking iptable_nat (some ultra-minimal builds), the
    # DNAT target isn't available. We soft-fail so the rest of the
    # DPI-evasion rules still install — without DNS redirection the
    # user must configure their resolver manually.
    if ! add_rule iptables -t nat OUTPUT -p udp --dport 53 \
             \! -d 127.0.0.0/8 \
             -m mark ! --mark "$MARK" \
             -j DNAT --to-destination "$DNS4_ADDR:$DNS4_PORT"; then
        echo "warn: iptables nat/DNAT kullanılamıyor (iptable_nat çekirdek modülü eksik);" >&2
        echo "      IPv4 DNS yönlendirmesi devre dışı — resolv.conf'u manuel yönlendirin" >&2
    fi
fi

if [ "$QUIC" = "1" ]; then
    add_rule iptables OUTPUT -p udp --dport 443 \
             -m mark ! --mark "$MARK" \
             -j NFQUEUE --queue-num "$QUEUE" --queue-bypass
fi

# IPv6
if command -v ip6tables >/dev/null 2>&1; then
    add_rule ip6tables OUTPUT -p tcp -m multiport --dports 80,443 \
             -m mark ! --mark "$MARK" \
             -j NFQUEUE --queue-num "$QUEUE" --queue-bypass
    if [ "$DNS6" = "1" ] && [ -n "$DNS6_ADDR" ]; then
        # ip6tables NAT (ip6table_nat / nf_nat_ipv6) required; present on
        # modern distro kernels. If missing, the add_rule call fails and
        # IPv6 DNS redirect is simply skipped. Excludes ::1 for the same
        # reason the IPv4 rule excludes 127.0.0.0/8 — don't DNAT queries
        # aimed at a local stub resolver.
        add_rule ip6tables -t nat OUTPUT -p udp --dport 53 \
                 \! -d ::1/128 \
                 -m mark ! --mark "$MARK" \
                 -j DNAT --to-destination "[$DNS6_ADDR]:$DNS6_PORT" \
            || echo "warn: ip6tables nat DNAT unavailable; IPv6 DNS redir skipped" >&2
    fi
    if [ "$QUIC" = "1" ]; then
        add_rule ip6tables OUTPUT -p udp --dport 443 \
                 -m mark ! --mark "$MARK" \
                 -j NFQUEUE --queue-num "$QUEUE" --queue-bypass
    fi
fi

echo "iptables NFQUEUE kuralları kuruldu (kuyruk #$QUEUE, mark $MARK hariç)"
