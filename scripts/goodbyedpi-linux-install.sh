#!/usr/bin/env bash
# goodbyedpi-linux-install.sh — background-daemonize a Turkey variant as a
# persistent process (no systemd). Analog of the Windows service_install_*.cmd
# files, but distro-agnostic: it just backgrounds the process and writes a
# PID file. Autostart on boot is up to you (cron @reboot, /etc/rc.local, etc).
#
# Usage: sudo ./goodbyedpi-linux-install.sh <variant>
#   <variant> is one of the turkey_dnsredir* script names (without .sh):
#     turkey_dnsredir        turkey_dnsredir_alt1   turkey_dnsredir_alt2
#     turkey_dnsredir_alt3   turkey_dnsredir_alt4   turkey_dnsredir_alt5
#     turkey_dnsredir_alt6
#
# To stop the running daemon: sudo ./goodbyedpi-linux-uninstall.sh

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "must be run as root (sudo)" >&2
    exit 1
fi

if [ $# -ne 1 ]; then
    echo "usage: $0 <variant>" >&2
    exit 2
fi

VARIANT="$1"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
VARIANT_SH="$SCRIPT_DIR/${VARIANT}.sh"

if [ ! -x "$VARIANT_SH" ]; then
    echo "variant script not found or not executable: $VARIANT_SH" >&2
    exit 1
fi

PID_FILE="/var/run/goodbyedpi-linux.pid"
LOG_FILE="/var/log/goodbyedpi-linux.log"

# If a previous daemon is still running, refuse.
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "daemon already running (PID $(cat "$PID_FILE"))" >&2
    echo "run goodbyedpi-linux-uninstall.sh first" >&2
    exit 1
fi

# Run variant script detached. setsid creates a new session so terminal
# close won't hang up the daemon; nohup redirects stdout/stderr.
setsid nohup "$VARIANT_SH" >>"$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"
sleep 0.5

if ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "daemon failed to start — see $LOG_FILE" >&2
    rm -f "$PID_FILE"
    exit 1
fi

echo "goodbyedpi-linux started in background (PID $(cat "$PID_FILE"), log $LOG_FILE)"
echo "to stop: sudo $SCRIPT_DIR/goodbyedpi-linux-uninstall.sh"
