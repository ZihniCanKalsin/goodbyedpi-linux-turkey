#!/usr/bin/env bash
# _common.sh — sourced by every turkey_*.sh variant. Locates the daemon
# binary, installs the correct iptables rules, wires cleanup on exit.
#
# Before sourcing, callers must set:
#   GBD_ARGS      — the `goodbyedpi-linux` argv (excluding the binary path)
#   UP_ARGS       — the `iptables-up.sh` argv
#   QUEUE_NUM     — optional, defaults to 200

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "must be run as root (sudo)" >&2
    exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LINUX_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
BIN="$LINUX_DIR/goodbyedpi-linux"

if [ ! -x "$BIN" ]; then
    echo "binary $BIN not found — run 'make' in $LINUX_DIR first" >&2
    exit 1
fi

QUEUE_NUM=${QUEUE_NUM:-200}

cleanup() {
    "$SCRIPT_DIR/iptables-down.sh" --queue "$QUEUE_NUM" || true
}
# Only trap EXIT — bash runs EXIT on any exit path (normal + SIGINT/TERM
# after the daemon exits), so adding INT/TERM here would double-fire cleanup.
trap cleanup EXIT

# shellcheck disable=SC2086
"$SCRIPT_DIR/iptables-up.sh" --queue "$QUEUE_NUM" $UP_ARGS

echo "starting goodbyedpi-linux ($GBD_ARGS) — Ctrl-C to stop"
# Run in foreground (NOT exec) so the EXIT trap fires iptables-down.sh on Ctrl-C.
# shellcheck disable=SC2086
"$BIN" --queue-num "$QUEUE_NUM" $GBD_ARGS
exit $?
