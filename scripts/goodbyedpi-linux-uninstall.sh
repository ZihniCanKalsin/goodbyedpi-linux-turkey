#!/usr/bin/env bash
# goodbyedpi-linux-uninstall.sh — goodbyedpi-linux-install.sh ile
# başlatılan arka plan daemon'unu durdurur ve iptables kurallarını
# kaldırır. Idempotent.

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "root (sudo) olarak çalıştırılmalıdır" >&2
    exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# install.sh ile aynı /run-önce / /var/run-yedek mantığını izle. Ortam
# değişkeni override'ı kabul edilir.
if [ -n "${PID_FILE:-}" ]; then
    :
elif [ -f /run/goodbyedpi-linux.pid ]; then
    PID_FILE=/run/goodbyedpi-linux.pid
elif [ -f /var/run/goodbyedpi-linux.pid ]; then
    PID_FILE=/var/run/goodbyedpi-linux.pid
elif [ -d /run ]; then
    PID_FILE=/run/goodbyedpi-linux.pid
else
    PID_FILE=/var/run/goodbyedpi-linux.pid
fi
QUEUE=200

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null || true)
    # PID dosyasının bozulmuş olmasına karşı koru — aksi halde
    # `kill -TERM -<garbage>` alakasız bir süreç grubunu hedef alabilir.
    case "$PID" in
        ''|*[!0-9]*)
            echo "PID dosyası bozuk veya boş; atlanıyor" >&2
            PID=""
            ;;
    esac
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        # Signal the entire process group (negative PID) so the actual
        # goodbyedpi-linux binary is reached even when the PID file points
        # to the wrapper shell that launched it via setsid.
        kill -TERM -"$PID" 2>/dev/null || kill -TERM "$PID" 2>/dev/null || true
        # Düzgün çıkış için 5 saniyeye kadar bekle, hâlâ varsa SIGKILL uygula.
        for _ in 1 2 3 4 5; do
            kill -0 "$PID" 2>/dev/null || break
            sleep 1
        done
        if kill -0 "$PID" 2>/dev/null; then
            echo "daemon (PID $PID) zamanında çıkmadı; SIGKILL gönderiliyor"
            kill -KILL -"$PID" 2>/dev/null || kill -KILL "$PID" 2>/dev/null || true
        fi
    fi
    # Daemon'un EXIT tuzağı genelde iptables-down'ı çağırır; güvende olmak
    # için tekrar çalıştırıyoruz (idempotent).
    rm -f "$PID_FILE"
fi

"$SCRIPT_DIR/iptables-down.sh" --queue "$QUEUE" || true
echo "goodbyedpi-linux durduruldu ve iptables kuralları temizlendi"
