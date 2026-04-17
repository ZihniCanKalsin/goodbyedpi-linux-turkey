#!/usr/bin/env bash
# goodbyedpi-linux-uninstall.sh — stop the background daemon started by
# goodbyedpi-linux-install.sh and remove iptables rules. Idempotent.

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "must be run as root (sudo)" >&2
    exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PID_FILE="/var/run/goodbyedpi-linux.pid"
QUEUE=200

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        kill -TERM "$PID" || true
        # Wait up to 5s for graceful exit, then SIGKILL if still around.
        for _ in 1 2 3 4 5; do
            kill -0 "$PID" 2>/dev/null || break
            sleep 1
        done
        if kill -0 "$PID" 2>/dev/null; then
            echo "daemon (PID $PID) did not exit in time; SIGKILLing"
            kill -KILL "$PID" || true
        fi
    fi
    # The daemon's EXIT trap usually runs iptables-down already; do it again
    # to be safe (idempotent).
    rm -f "$PID_FILE"
fi

"$SCRIPT_DIR/iptables-down.sh" --queue "$QUEUE" || true
echo "goodbyedpi-linux stopped and iptables rules cleaned"
