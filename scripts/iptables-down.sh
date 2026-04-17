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

for c in OUTPUT INPUT; do wipe_chain iptables "$c"; done
if command -v ip6tables >/dev/null 2>&1; then
    for c in OUTPUT INPUT; do wipe_chain ip6tables "$c"; done
fi

echo "iptables NFQUEUE kuralları (kuyruk #$QUEUE) kaldırıldı"
