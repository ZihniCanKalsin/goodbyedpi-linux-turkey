#!/usr/bin/env bash
# iptables-down.sh — verilen kuyruk numarasına (varsayılan 200) işaret
# eden her NFQUEUE kuralını kaldırır. Tekrar çalıştırılması güvenlidir.
# İlgisiz iptables kurallarına dokunmaz.
#
# Kullanım: sudo ./iptables-down.sh [--queue N]

set -eu

QUEUE=200
while [ $# -gt 0 ]; do
    case "$1" in
        --queue) QUEUE="$2"; shift 2 ;;
        *) echo "bilinmeyen argüman: $1" >&2; exit 2 ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "root (sudo) olarak çalıştırılmalıdır" >&2
    exit 1
fi

wipe_chain() {
    local ipcmd="$1" chain="$2" i=0
    # Çok sayıda kopya kural olursa diye 50 yineleme; pratikte 1–2.
    while [ $i -lt 50 ]; do
        local line
        line=$("$ipcmd" -S "$chain" 2>/dev/null \
               | grep -E -- "--queue-num $QUEUE( |$)" \
               | head -1 || true)
        [ -n "$line" ] || break
        local rule_args=${line#-A "$chain" }
        # shellcheck disable=SC2086
        "$ipcmd" -D "$chain" $rule_args || break
        i=$((i + 1))
    done
}

# Nat DNAT rules emitted by iptables-up.sh for DNS redirection. We recognise
# them by the -j DNAT target on the nat/OUTPUT chain with a UDP dport 53
# match; this is conservative enough that unrelated DNAT rules aren't
# touched.
wipe_dns_dnat() {
    local ipcmd="$1" i=0
    while [ $i -lt 50 ]; do
        local line
        line=$("$ipcmd" -t nat -S OUTPUT 2>/dev/null \
               | grep -E -- '-p udp .*--dport 53 .*-j DNAT' \
               | head -1 || true)
        [ -n "$line" ] || break
        local rule_args=${line#-A OUTPUT }
        # shellcheck disable=SC2086
        "$ipcmd" -t nat -D OUTPUT $rule_args || break
        i=$((i + 1))
    done
}

for c in OUTPUT INPUT; do wipe_chain iptables "$c"; done
wipe_dns_dnat iptables
if command -v ip6tables >/dev/null 2>&1; then
    for c in OUTPUT INPUT; do wipe_chain ip6tables "$c"; done
    wipe_dns_dnat ip6tables
fi

# Drop any residual UDP conntrack entries so a previously-DNATted DNS flow
# doesn't keep steering queries to the alt resolver once we're torn down.
if command -v conntrack >/dev/null 2>&1; then
    conntrack -D -p udp --dport 53 >/dev/null 2>&1 || true
fi

echo "iptables kuralları (kuyruk #$QUEUE + DNS DNAT) kaldırıldı"
