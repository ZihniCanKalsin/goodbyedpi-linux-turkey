#!/usr/bin/env bash
# deps-install.sh — optional helper that detects the package manager and
# installs the build/runtime dependencies for goodbyedpi-linux.
#
# Required at build time : libnetfilter_queue dev headers, libmnl dev headers,
#                          a C compiler, make, pkg-config.
# Required at run time   : iptables (and ip6tables), kernel nfnetlink_queue.
#
# If none of the detected package managers match yours, install manually:
#     libnetfilter_queue-dev (or -devel), libmnl-dev (or -devel),
#     gcc (or cc), make, pkg-config, iptables.

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "must be run as root (sudo)" >&2
    exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y \
        libnetfilter-queue-dev libmnl-dev gcc make pkg-config iptables
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y \
        libnetfilter_queue-devel libmnl-devel gcc make pkgconfig iptables
elif command -v yum >/dev/null 2>&1; then
    yum install -y \
        libnetfilter_queue-devel libmnl-devel gcc make pkgconfig iptables
elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm \
        libnetfilter_queue libmnl gcc make pkgconf iptables
elif command -v zypper >/dev/null 2>&1; then
    zypper install -y \
        libnetfilter_queue-devel libmnl-devel gcc make pkg-config iptables
elif command -v apk >/dev/null 2>&1; then
    apk add libnetfilter_queue-dev libmnl-dev gcc make pkgconf iptables musl-dev linux-headers
else
    echo "no supported package manager detected; install deps manually" >&2
    exit 1
fi

echo "dependencies installed"
