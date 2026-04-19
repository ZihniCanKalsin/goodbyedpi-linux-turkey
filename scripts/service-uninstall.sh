#!/usr/bin/env bash
# service-uninstall.sh — service-install.sh ile kurulan systemd birimini
# durdurur, devre dışı bırakır, siler ve iptables kurallarını temizler.
# Idempotent: birden fazla kez çalıştırılabilir, hata vermez.

set -eu

SERVICE_NAME=goodbyedpi-linux
UNIT_PATH=/etc/systemd/system/${SERVICE_NAME}.service

if [ "$(id -u)" -ne 0 ]; then
    echo "root (sudo) olarak çalıştırılmalıdır" >&2
    exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if command -v systemctl >/dev/null 2>&1; then
    systemctl stop    "${SERVICE_NAME}.service" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true
    rm -f "$UNIT_PATH"
    systemctl daemon-reload 2>/dev/null || true
fi

# Her ihtimale karşı: başka bir yolla başlatılmış artık daemon + kural
# varsa temizle.
"$SCRIPT_DIR/goodbyedpi-linux-uninstall.sh" >/dev/null 2>&1 || true
"$SCRIPT_DIR/iptables-down.sh" --queue 200 >/dev/null 2>&1 || true

echo "goodbyedpi-linux servisi kaldırıldı, iptables kuralları temizlendi."
