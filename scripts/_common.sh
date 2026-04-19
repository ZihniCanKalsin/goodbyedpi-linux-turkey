#!/usr/bin/env bash
# _common.sh — her turkey_*.sh varyantı tarafından kaynaklanır. Daemon
# binary'sinin yerini bulur, doğru iptables kurallarını kurar ve çıkışta
# temizliği bağlar.
#
# Kaynaklamadan önce çağıranlar şunları ayarlamalıdır:
#   GBD_ARGS      — `goodbyedpi-linux` argüman vektörü (binary yolu hariç)
#   UP_ARGS       — `iptables-up.sh` argüman vektörü
#   QUEUE_NUM     — opsiyonel, varsayılan 200

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "root (sudo) olarak çalıştırılmalıdır" >&2
    exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LINUX_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
BIN="$LINUX_DIR/goodbyedpi-linux"

if [ ! -x "$BIN" ]; then
    echo "binary $BIN bulunamadı — önce $LINUX_DIR içinde 'make' çalıştırın" >&2
    exit 1
fi

QUEUE_NUM=${QUEUE_NUM:-200}

if [ "${GBD_INSTALL_MODE:-0}" = "1" ]; then
    # Install mode execs the daemon so the PID observed by the installer is
    # the actual goodbyedpi-linux process rather than a wrapper shell.
    # shellcheck disable=SC2086
    "$SCRIPT_DIR/iptables-up.sh" --queue "$QUEUE_NUM" $UP_ARGS
    echo "goodbyedpi-linux daemon olarak başlatılıyor ($GBD_ARGS)"
    # shellcheck disable=SC2086
    exec "$BIN" --queue-num "$QUEUE_NUM" $GBD_ARGS
fi

# shellcheck disable=SC2317  # çağrılıyor: trap cleanup EXIT
cleanup() {
    "$SCRIPT_DIR/iptables-down.sh" --queue "$QUEUE_NUM" || true
}
# Yalnızca EXIT'i tuzakla — bash EXIT'i her çıkış yolunda (normal +
# SIGINT/TERM, daemon çıkıştan sonra) çalıştırır; INT/TERM eklemek cleanup'ı
# iki kere çalıştırır.
trap cleanup EXIT

# shellcheck disable=SC2086
"$SCRIPT_DIR/iptables-up.sh" --queue "$QUEUE_NUM" $UP_ARGS

echo "goodbyedpi-linux başlatılıyor ($GBD_ARGS) — durdurmak için Ctrl-C"
# Ön planda çalıştır (exec DEĞİL), böylece Ctrl-C'de EXIT tuzağı
# iptables-down.sh'i tetikler.
# shellcheck disable=SC2086
"$BIN" --queue-num "$QUEUE_NUM" $GBD_ARGS
exit $?
