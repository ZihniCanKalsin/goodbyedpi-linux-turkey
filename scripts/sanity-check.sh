#!/usr/bin/env bash
# sanity-check.sh — dağıtımdan bağımsız bir ortam denetimi. 'make' veya
# 'service-install.sh' çalıştırmadan ÖNCE her şeyin yerli yerinde olduğunu
# doğrular ve eksik parçayı nasıl kuracağınızı söyler.
#
# Kullanım:  ./scripts/sanity-check.sh
#            sudo ./scripts/sanity-check.sh       # çekirdek modül / iptables
#                                                 # kontrolleri için
#
# Root olmadan çağırabilirsiniz; bazı kontroller atlanır ama çoğunluk
# yine sağlanır. Başarısız olan her kontrol için NE YAPILMALI satırı
# basılır; amacımız kullanıcıyı "kopuk derleme" kara deliğinden kurtarmak.

set -u

FAIL=0
WARN=0
SKIP=0

red()   { printf '\033[31m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
yellow(){ printf '\033[33m%s\033[0m' "$*"; }

ok()    { echo "  [$(green OK)]    $*"; }
bad()   { echo "  [$(red FAIL)]  $*"; FAIL=$((FAIL + 1)); }
warn()  { echo "  [$(yellow WARN)]  $*"; WARN=$((WARN + 1)); }
skip()  { echo "  [SKIP]  $*"; SKIP=$((SKIP + 1)); }

hint()  { echo "          $*"; }

section() { echo; echo "== $* =="; }

# -----------------------------------------------------------------------------
section "işletim sistemi"
# -----------------------------------------------------------------------------

if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-?}"
    OS_NAME="${PRETTY_NAME:-$OS_ID}"
    ok "algılanan: $OS_NAME ($OS_ID)"
else
    warn "/etc/os-release okunamadı; dağıtım bilinmiyor"
    OS_ID=unknown
fi

KERNEL=$(uname -r 2>/dev/null || echo ?)
ok "çekirdek: $KERNEL"
case "$(uname -s)" in
    Linux) ok "Linux çekirdeği doğrulandı" ;;
    *)     bad "Bu araç yalnızca Linux'ta çalışır ($(uname -s) tespit edildi)" ;;
esac

# -----------------------------------------------------------------------------
section "gerekli komutlar"
# -----------------------------------------------------------------------------

need() {
    local bin="$1"; local hint_text="$2"
    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin: $(command -v "$bin")"
    else
        bad "$bin bulunamadı"
        hint "NASIL: $hint_text"
    fi
}

optional() {
    local bin="$1"; local why="$2"
    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin (opsiyonel): $(command -v "$bin")"
    else
        warn "$bin yok — $why"
    fi
}

need bash      "her dağıtımda paket adı 'bash'"
need cc        "gcc ya da clang kurun (paket adı: gcc, clang, build-essential)"
need make      "GNU make; paket adı: make (bazı minimal imajlarda 'build-essential')"
need pkg-config "paket adı: pkg-config / pkgconf / pkgconf-pkg-config"
need iptables  "paket adı: iptables veya iptables-nft (modern Arch/Fedora)"
optional ip6tables "IPv6 kuralları olmadan çalışır, ama IPv6 DNS redir yapılamaz"
optional conntrack "iptables-down.sh artık-DNAT UDP girdilerini bu araçla temizler; yoksa sessizce atlanır"
optional setsid    "goodbyedpi-linux-install.sh (systemd-siz arka plan) bunu kullanır"
optional systemctl "service-install.sh systemd birimini kurar; yoksa manuel init mekanizmanızı kullanın"

# -----------------------------------------------------------------------------
section "derleme kütüphaneleri (pkg-config)"
# -----------------------------------------------------------------------------

if command -v pkg-config >/dev/null 2>&1; then
    for lib in libnetfilter_queue libmnl; do
        if pkg-config --exists "$lib"; then
            ok "$lib: $(pkg-config --modversion "$lib")"
        else
            bad "$lib pkg-config tarafından bulunamadı"
            hint "NASIL: 'sudo ./scripts/deps-install.sh' (Debian ailesi için $lib-dev,"
            hint "      Fedora ailesi için ${lib}-devel)"
        fi
    done
else
    skip "pkg-config yok — kütüphane kontrolü atlandı"
fi

# -----------------------------------------------------------------------------
section "Linux çekirdek netfilter desteği"
# -----------------------------------------------------------------------------

# /proc/net/netfilter/nfnetlink_queue varsa modül YÜKLÜ demektir.
# modprobe hiç gerekmeden çekirdeğe built-in olabilir.
if [ -e /proc/net/netfilter/nfnetlink_queue ]; then
    ok "nfnetlink_queue çekirdeğe yüklü"
elif [ -e /sys/module/nfnetlink_queue ]; then
    ok "nfnetlink_queue çekirdek modülü aktif"
else
    # Yüklenebilir mi?
    if command -v modprobe >/dev/null 2>&1; then
        if modprobe -n -q nfnetlink_queue 2>/dev/null; then
            if [ "$(id -u)" -eq 0 ]; then
                if modprobe nfnetlink_queue 2>/dev/null; then
                    ok "nfnetlink_queue modülü başarıyla yüklendi"
                else
                    warn "modprobe nfnetlink_queue başarısız — modül çekirdekte var ama yüklenemiyor"
                fi
            else
                warn "nfnetlink_queue henüz yüklü değil (modprobe için root gerekir); servis başlatılınca otomatik yüklenir"
            fi
        else
            bad "nfnetlink_queue modülü çekirdekte yok"
            hint "NASIL: netfilter destekli bir çekirdek gerekir. Özel / minimal çekirdek"
            hint "      kullanıyorsanız CONFIG_NETFILTER_NETLINK_QUEUE=y/m ile yeniden derleyin"
            hint "      veya stock dağıtım çekirdeğine geçin."
        fi
    else
        skip "modprobe yok; nfnetlink_queue kontrolü yapılamadı"
    fi
fi

if [ "$(id -u)" -eq 0 ]; then
    if iptables -L -n >/dev/null 2>&1; then
        # Hangi backend? (nf_tables vs legacy)
        VER=$(iptables --version 2>/dev/null | head -1 || echo "")
        ok "iptables çalışıyor — $VER"
    else
        bad "iptables çalıştırılabilir ama -L başarısız — çekirdeğinizde filter tablosu kanca eksik olabilir"
    fi

    # NFQUEUE hedefi gerçekten kullanılabilir mi? (xt_NFQUEUE modülü)
    _probe=gbd_probe_$$
    if iptables -N "$_probe" 2>/dev/null; then
        if iptables -A "$_probe" -j NFQUEUE --queue-num 65535 --queue-bypass 2>/dev/null; then
            ok "xt_NFQUEUE iptables hedefi kullanılabilir"
            iptables -F "$_probe" 2>/dev/null || true
        else
            bad "NFQUEUE hedefi iptables tarafından reddedildi (xt_NFQUEUE eksik)"
            hint "NASIL: modprobe xt_NFQUEUE; ya da netfilter modüllerini derleyin"
        fi
        iptables -X "$_probe" 2>/dev/null || true
    else
        warn "iptables -N ile test zinciri açılamadı (başka bir proje bizimle aynı adla çakışıyor olabilir)"
    fi

    # ip6tables NAT desteği — IPv6 DNS redir için
    if command -v ip6tables >/dev/null 2>&1; then
        if ip6tables -t nat -L -n >/dev/null 2>&1; then
            ok "ip6tables nat tablosu erişilebilir (IPv6 DNS redir çalışır)"
        else
            warn "ip6tables var ama nat tablosu erişilemiyor — IPv6 DNS yönlendirmesi atlanır"
            hint "NASIL: 'modprobe ip6table_nat' ya da IPv6 DNS yönlendirmesinden vazgeçin"
        fi
    fi
else
    skip "iptables / NFQUEUE canlı kontrolleri atlandı (root gerekir; 'sudo $0' ile yeniden çalıştırın)"
fi

# -----------------------------------------------------------------------------
section "derlenmiş ikili"
# -----------------------------------------------------------------------------

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BIN="$SCRIPT_DIR/../goodbyedpi-linux"
if [ -x "$BIN" ]; then
    # Dosya boyutunu dağıtım-bağımsız okuruz: GNU stat, BSD stat ve busybox
    # stat bayrakları uyuşmaz; numfmt da yalnız GNU coreutils'te bulunur.
    # wc -c her yerde vardır, IEC biçimini bash aritmetiğiyle üretiriz.
    _sz=$(wc -c < "$BIN" 2>/dev/null | tr -d ' ')
    if [ -n "${_sz:-}" ] && [ "$_sz" -gt 0 ] 2>/dev/null; then
        if   [ "$_sz" -ge 1073741824 ]; then _pretty="$((_sz / 1073741824))G"
        elif [ "$_sz" -ge 1048576 ];    then _pretty="$((_sz / 1048576))M"
        elif [ "$_sz" -ge 1024 ];       then _pretty="$((_sz / 1024))K"
        else                                 _pretty="${_sz}B"
        fi
        ok "goodbyedpi-linux derlenmiş: $_pretty"
    else
        ok "goodbyedpi-linux derlenmiş"
    fi
else
    warn "goodbyedpi-linux henüz derlenmemiş — 'make' çalıştırın"
fi

# -----------------------------------------------------------------------------
section "özet"
# -----------------------------------------------------------------------------

if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
    echo "  her şey yolunda. $(green 'hazırsınız.')"
elif [ "$FAIL" -eq 0 ]; then
    echo "  $WARN uyarı, 0 hata. proje büyük ihtimalle çalışır; uyarılara göre karar verin."
else
    echo "  $(red "$FAIL hata"), $WARN uyarı. yukarıdaki NASIL satırlarını uygulayın."
    exit 1
fi
