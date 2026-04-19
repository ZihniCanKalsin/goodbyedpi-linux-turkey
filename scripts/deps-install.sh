#!/usr/bin/env bash
# deps-install.sh — paket yöneticisini algılayıp goodbyedpi-linux'un derleme
# / çalışma bağımlılıklarını kuran opsiyonel yardımcı.
#
# Derleme zamanında gerekli  : libnetfilter_queue dev başlıkları, libmnl dev
#                              başlıkları, bir C derleyici, make, pkg-config.
# Çalışma zamanında gerekli  : iptables (ve ip6tables), çekirdek
#                              nfnetlink_queue.
#
# Algılanan paket yöneticilerinden hiçbiri sizinkine uymuyorsa manuel kurun:
#     libnetfilter_queue-dev (veya -devel), libmnl-dev (veya -devel),
#     gcc (veya cc), make, pkg-config, iptables.

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "root (sudo) olarak çalıştırılmalıdır" >&2
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
elif command -v xbps-install >/dev/null 2>&1; then
    # Void Linux
    xbps-install -Sy \
        libnetfilter_queue-devel libmnl-devel gcc make pkg-config iptables
elif command -v emerge >/dev/null 2>&1; then
    # Gentoo — başlıklar runtime paketlerine gömülüdür.
    emerge --noreplace \
        net-libs/libnetfilter_queue net-libs/libmnl \
        sys-devel/gcc sys-devel/make dev-util/pkgconf \
        net-firewall/iptables
else
    echo "desteklenen bir paket yöneticisi bulunamadı." >&2
    echo "bağımlılıkları manuel kurun:" >&2
    echo "  - libnetfilter_queue geliştirme başlıkları" >&2
    echo "  - libmnl geliştirme başlıkları" >&2
    echo "  - gcc (veya cc), make, pkg-config" >&2
    echo "  - iptables (ip6tables dahil)" >&2
    echo "NixOS kullanıcıları: nix-shell -p libnetfilter_queue libmnl gcc gnumake pkg-config iptables" >&2
    exit 1
fi

echo "bağımlılıklar kuruldu"
