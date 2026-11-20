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
#   --exclude-iface AD     bu çıkış arayüzünden giden trafiğe dokunma
#                          (tekrarlanabilir; iptables '+' joker karakteri
#                          geçerli, ör. wg+). Varsayılan: CloudflareWARP
#   --exclude-mark HEX     bu fwmark'ı taşıyan trafiğe dokunma
#                          (tekrarlanabilir). Varsayılan: 0x100cf — WARP
#                          daemon'unun (warp-svc) kendi soketleri
#   --no-vpn-exclude       varsayılan WARP hariç tutmalarını kapat
#
# Ortam değişkenleri (boşluk ya da virgülle ayrılmış, bayraklara eklenir):
#   GBD_EXCLUDE_IFACES     ör. "wg0 tun+"
#   GBD_EXCLUDE_MARKS      ör. "0xca6c"
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
# VPN / tünel hariç tutmaları (bkz. issue #3). Şifreli bir tünelin içinden
# geçen trafiği ISS'nin DPI'ı zaten göremez; onu bölmek / QUIC'i düşürmek /
# DNS'ini yönlendirmek hiçbir şey kazandırmaz, yalnızca tüneli bozar.
#   CloudflareWARP — Cloudflare WARP'ın tünel arayüzü
#   0x100cf        — warp-svc'nin tüneli ve DoH'u taşıyan kendi soketlerine
#                    koyduğu fwmark (fiziksel arayüzden çıkarlar)
VPN_EXCLUDE=1
DEFAULT_EXCLUDE_IFACES="CloudflareWARP"
DEFAULT_EXCLUDE_MARKS="0x100cf"
EXTRA_IFACES=${GBD_EXCLUDE_IFACES:-}
EXTRA_MARKS=${GBD_EXCLUDE_MARKS:-}

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
        --exclude-iface) EXTRA_IFACES="$EXTRA_IFACES $2"; shift 2 ;;
        --exclude-mark)  EXTRA_MARKS="$EXTRA_MARKS $2"; shift 2 ;;
        --no-vpn-exclude) VPN_EXCLUDE=0; shift ;;
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

# Hariç tutma listelerini doğrula ve tekilleştir.
if [ "$VPN_EXCLUDE" = "1" ]; then
    EXTRA_IFACES="$DEFAULT_EXCLUDE_IFACES $EXTRA_IFACES"
    EXTRA_MARKS="$DEFAULT_EXCLUDE_MARKS $EXTRA_MARKS"
fi
EXCL_IFACES=()
EXCL_MARKS=()
EXCL_DESC=""
_seen=" "
_self_mark=$(printf '0x%x' "$MARK")
for _if in ${EXTRA_IFACES//,/ }; do
    case "$_if" in
        *[!A-Za-z0-9_.+-]*|-*)
            echo "geçersiz arayüz adı: $_if" >&2; exit 2 ;;
    esac
    if [ "${#_if}" -gt 15 ]; then
        echo "geçersiz arayüz adı (15 karakterden uzun): $_if" >&2; exit 2
    fi
    case "$_seen" in *" i:$_if "*) continue ;; esac
    _seen="${_seen}i:$_if "
    EXCL_IFACES+=("$_if")
    EXCL_DESC="$EXCL_DESC $_if"
done
for _mk in ${EXTRA_MARKS//,/ }; do
    case "$_mk" in
        0[xX]*) _hex=${_mk#0[xX]}
                case "$_hex" in ''|*[!0-9a-fA-F]*)
                    echo "geçersiz fwmark: $_mk" >&2; exit 2 ;; esac ;;
        *[!0-9]*) echo "geçersiz fwmark: $_mk" >&2; exit 2 ;;
    esac
    # Sayısal olarak karşılaştır: 0x100CF ile 0x100cf aynı kuraldır.
    _mk=$(printf '0x%x' "$_mk")
    [ "$_mk" = "$_self_mark" ] && continue
    case "$_seen" in *" m:$_mk "*) continue ;; esac
    _seen="${_seen}m:$_mk "
    EXCL_MARKS+=("$_mk")
    EXCL_DESC="$EXCL_DESC mark:$_mk"
done

# Kurallar yerleşik OUTPUT zincirine doğrudan değil, kendi zincirlerimize
# yazılır; OUTPUT'ta yalnızca trafik seçicili atlamalar (jump) durur:
#
#   OUTPUT  -p tcp --dports 80,443 -j GBD_Q<kuyruk>
#   OUTPUT  -p udp --dport 443     -j GBD_Q<kuyruk>      (--quic)
#   GBD_Q<kuyruk>:   -m mark --mark <kendi mark'ımız>  -j RETURN
#                    -o <hariç arayüz>                 -j RETURN   (her biri)
#                    -m mark --mark <hariç mark>       -j RETURN   (her biri)
#                    -j NFQUEUE --queue-num <kuyruk> --queue-bypass
#
# RETURN, paketi OUTPUT'un kalan kurallarına (ufw / firewalld vb.) geri
# verir; yani hariç tutulan trafik başka bir güvenlik duvarını atlamaz.
# Tek kurala sığdırmak mümkün değil: iptables kural başına tek '-o' kabul
# eder, birden çok arayüz hariç tutulamaz.
CHAIN="GBD_Q$QUEUE"
DNS_CHAIN="GBD_DNS$QUEUE"

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

# $1=ipcmd $2=tablo $3=zincir — zinciri oluşturur (varsa boşaltır) ve
# hariç tutma RETURN'lerini yazar. Her çalıştırmada baştan kurulduğu için
# idempotenttir ve hariç tutma listesi değişince eski girdiler kalmaz.
init_chain() {
    local ipcmd="$1" table="$2" chain="$3" x
    "$ipcmd" -t "$table" -N "$chain" 2>/dev/null \
        || "$ipcmd" -t "$table" -F "$chain" 2>/dev/null || return 1
    "$ipcmd" -t "$table" -A "$chain" -m mark --mark "$MARK" -j RETURN || return 1
    for x in ${EXCL_IFACES[@]+"${EXCL_IFACES[@]}"}; do
        "$ipcmd" -t "$table" -A "$chain" -o "$x" -j RETURN || return 1
    done
    for x in ${EXCL_MARKS[@]+"${EXCL_MARKS[@]}"}; do
        "$ipcmd" -t "$table" -A "$chain" -m mark --mark "$x" -j RETURN || return 1
    done
}

# $1=ipcmd — TCP/80,443 (ve --quic ile UDP/443) için NFQUEUE zinciri.
install_queue() {
    local ipcmd="$1"
    init_chain "$ipcmd" filter "$CHAIN" || return 1
    "$ipcmd" -A "$CHAIN" -j NFQUEUE --queue-num "$QUEUE" --queue-bypass || return 1
    add_rule "$ipcmd" OUTPUT -p tcp -m multiport --dports 80,443 -j "$CHAIN" || return 1
    if [ "$QUIC" = "1" ]; then
        add_rule "$ipcmd" OUTPUT -p udp --dport 443 -j "$CHAIN" || return 1
    fi
}

# $1=ipcmd $2=dokunulmayacak yerel hedef (stub çözümleyici) $3=DNAT hedefi
#
# DNS redirection is implemented as NAT DNAT, not NFQUEUE. Reason: an
# NFQUEUE rewrite of a locally-generated UDP/53 packet happens AFTER the
# kernel's route lookup, so a query to 127.0.0.53 (systemd-resolved stub)
# rewritten to a public resolver still tries to leave via the loopback
# interface and is dropped. NAT DNAT runs in nat/OUTPUT, before routing,
# and conntrack un-DNATs the reply automatically — no daemon-side UDP
# handling needed.
#
# Redirect only queries that leave the host. Queries directed at the
# local stub resolver (typically systemd-resolved on 127.0.0.53) must
# still reach it — the stub is our *source* of upstream queries, not
# a destination to override. Without this exclusion, the stub never
# receives its clients' packets and every libc resolver call times
# out even though the DNAT path itself works.
install_dns() {
    local ipcmd="$1" local_dst="$2" to="$3"
    init_chain "$ipcmd" nat "$DNS_CHAIN" || return 1
    "$ipcmd" -t nat -A "$DNS_CHAIN" -p udp -j DNAT --to-destination "$to" \
        2>/dev/null || return 1
    add_rule "$ipcmd" -t nat OUTPUT -p udp --dport 53 \! -d "$local_dst" \
             -j "$DNS_CHAIN" 2>/dev/null || return 1
}

install_queue iptables

if [ "$DNS4" = "1" ] && [ -n "$DNS4_ADDR" ]; then
    # On kernels lacking iptable_nat (some ultra-minimal builds), the
    # DNAT target isn't available. We soft-fail so the rest of the
    # DPI-evasion rules still install — without DNS redirection the
    # user must configure their resolver manually.
    if ! install_dns iptables 127.0.0.0/8 "$DNS4_ADDR:$DNS4_PORT"; then
        echo "warn: iptables nat/DNAT kullanılamıyor (iptable_nat çekirdek modülü eksik);" >&2
        echo "      IPv4 DNS yönlendirmesi devre dışı — resolv.conf'u manuel yönlendirin" >&2
    fi
fi

# IPv6
if command -v ip6tables >/dev/null 2>&1; then
    install_queue ip6tables
    if [ "$DNS6" = "1" ] && [ -n "$DNS6_ADDR" ]; then
        # ip6tables NAT (ip6table_nat / nf_nat_ipv6) required; present on
        # modern distro kernels. If missing, IPv6 DNS redirect is simply
        # skipped. Excludes ::1 for the same reason the IPv4 rule excludes
        # 127.0.0.0/8 — don't DNAT queries aimed at a local stub resolver.
        install_dns ip6tables ::1/128 "[$DNS6_ADDR]:$DNS6_PORT" \
            || echo "warn: ip6tables nat DNAT unavailable; IPv6 DNS redir skipped" >&2
    fi
fi

echo "iptables NFQUEUE kuralları kuruldu (kuyruk #$QUEUE, mark $MARK hariç)"
if [ -n "$EXCL_DESC" ]; then
    echo "dokunulmayan VPN trafiği:$EXCL_DESC"
fi
