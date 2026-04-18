#!/usr/bin/env bash
# goodbyedpi-linux-install.sh — bir Turkey varyantını systemd olmadan
# kalıcı bir süreç olarak arka plana alır. Windows'taki service_install_*.cmd
# dosyalarının karşılığıdır ama dağıtımdan bağımsızdır: süreci arka plana
# alır ve bir PID dosyası yazar. Önyüklemede otomatik başlatma size
# bırakılmıştır (cron @reboot, /etc/rc.local vb.).
#
# Kullanım: sudo ./goodbyedpi-linux-install.sh <varyant>
#   <varyant>, turkey_dnsredir* script adlarından biridir (.sh olmadan):
#     turkey_dnsredir        turkey_dnsredir_alt1   turkey_dnsredir_alt2
#     turkey_dnsredir_alt3   turkey_dnsredir_alt4   turkey_dnsredir_alt5
#     turkey_dnsredir_alt6
#
# Çalışan daemon'u durdurmak için: sudo ./goodbyedpi-linux-uninstall.sh

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "root (sudo) olarak çalıştırılmalıdır" >&2
    exit 1
fi

if [ $# -ne 1 ]; then
    echo "kullanım: $0 <varyant>" >&2
    exit 2
fi

VARIANT="$1"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
VARIANT_SH="$SCRIPT_DIR/${VARIANT}.sh"

if [ ! -x "$VARIANT_SH" ]; then
    echo "varyant betiği bulunamadı veya çalıştırılabilir değil: $VARIANT_SH" >&2
    exit 1
fi

PID_FILE="/var/run/goodbyedpi-linux.pid"
LOG_FILE="/var/log/goodbyedpi-linux.log"

# Önceki bir daemon hâlâ çalışıyorsa reddet.
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "daemon zaten çalışıyor (PID $(cat "$PID_FILE"))" >&2
    echo "önce goodbyedpi-linux-uninstall.sh'i çalıştırın" >&2
    exit 1
fi

# Varyant scriptini ayrık olarak çalıştır. setsid yeni bir oturum açar,
# böylece terminal kapansa da daemon asılı kalmaz; nohup stdout/stderr'i
# yeniden yönlendirir.
GBD_INSTALL_MODE=1 setsid nohup "$VARIANT_SH" >>"$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"
sleep 0.5

if ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "daemon başlatılamadı — $LOG_FILE dosyasına bakın" >&2
    rm -f "$PID_FILE"
    exit 1
fi

echo "goodbyedpi-linux arka planda başlatıldı (PID $(cat "$PID_FILE"), günlük $LOG_FILE)"
echo "durdurmak için: sudo $SCRIPT_DIR/goodbyedpi-linux-uninstall.sh"
