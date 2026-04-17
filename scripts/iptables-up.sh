#!/usr/bin/env bash
# iptables-up.sh — goodbyedpi-linux için NFQUEUE kurallarını kurar.
# Idempotent: zaten mevcut olan kurallar tekrar eklenmez.
#
# Kullanım: sudo ./iptables-up.sh [seçenekler]
#   --queue N              NFQUEUE numarası (varsayılan: 200)
#   --dns4                 giden UDP/53 kuyruklamasını etkinleştir
#   --dns4-addr IP         daemon'un kullandığı DNS sunucusu IP'si (INPUT ters kuralı için)
#   --dns4-port N          daemon'un kullandığı DNS sunucu portu
#   --dns6                 IPv6 UDP/53 kuyruklamasını etkinleştir
#   --dns6-addr IP6        IPv6 DNS sunucusu
#   --dns6-port N          IPv6 DNS sunucu portu
#   --quic                 UDP/443 (QUIC) kuyruklamasını etkinleştir

set -eu

QUEUE=200
DNS4=0; DNS4_ADDR=""; DNS4_PORT=53
DNS6=0; DNS6_ADDR=""; DNS6_PORT=53
QUIC=0

while [ $# -gt 0 ]; do
    case "$1" in
        --queue)     QUEUE="$2"; shift 2 ;;
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

# En iyi çaba: çekirdek modüllerinin yüklü olduğundan emin ol. Zaten
# çekirdek içinde varsa zararsız.
modprobe nfnetlink_queue 2>/dev/null || true
modprobe xt_NFQUEUE      2>/dev/null || true
modprobe ip6_tables      2>/dev/null || true

add_rule() {
    # $1=ipcmd, geri kalanı=kural argümanları. Aynı kural varsa eklemez.
    local ipcmd="$1"; shift
    if ! "$ipcmd" -C "$@" 2>/dev/null; then
        "$ipcmd" -I "$@"
    fi
}

add_rule iptables OUTPUT -p tcp -m multiport --dports 80,443 \
         -j NFQUEUE --queue-num "$QUEUE" --queue-bypass

if [ "$DNS4" = "1" ]; then
    add_rule iptables OUTPUT -p udp --dport 53 \
             -j NFQUEUE --queue-num "$QUEUE" --queue-bypass
    if [ -n "$DNS4_ADDR" ]; then
        add_rule iptables INPUT -p udp -s "$DNS4_ADDR" --sport "$DNS4_PORT" \
                 -j NFQUEUE --queue-num "$QUEUE" --queue-bypass
    fi
fi

if [ "$QUIC" = "1" ]; then
    add_rule iptables OUTPUT -p udp --dport 443 \
             -j NFQUEUE --queue-num "$QUEUE" --queue-bypass
fi

# IPv6
if command -v ip6tables >/dev/null 2>&1; then
    add_rule ip6tables OUTPUT -p tcp -m multiport --dports 80,443 \
             -j NFQUEUE --queue-num "$QUEUE" --queue-bypass
    if [ "$DNS6" = "1" ]; then
        add_rule ip6tables OUTPUT -p udp --dport 53 \
                 -j NFQUEUE --queue-num "$QUEUE" --queue-bypass
        if [ -n "$DNS6_ADDR" ]; then
            add_rule ip6tables INPUT -p udp -s "$DNS6_ADDR" --sport "$DNS6_PORT" \
                     -j NFQUEUE --queue-num "$QUEUE" --queue-bypass
        fi
    fi
    if [ "$QUIC" = "1" ]; then
        add_rule ip6tables OUTPUT -p udp --dport 443 \
                 -j NFQUEUE --queue-num "$QUEUE" --queue-bypass
    fi
fi

echo "iptables NFQUEUE kuralları kuruldu (kuyruk #$QUEUE)"
