#!/usr/bin/env bash
# deps-install.sh — paket yöneticisini algılayıp goodbyedpi-linux'un
# derleme / çalışma bağımlılıklarını kurar. Dağıtımdan bağımsızdır:
# ağırlıklı olarak yaygın paket yöneticisi adlarını dener.
#
# Derleme zamanında gerekli  : libnetfilter_queue dev başlıkları, libmnl
#                              dev başlıkları, C derleyici, make,
#                              pkg-config, bash.
# Çalışma zamanında gerekli  : iptables (ip6tables dahil), çekirdek
#                              nfnetlink_queue modülü (her güncel
#                              çekirdekte vardır).
# Opsiyonel                  : conntrack-tools (iptables-down.sh UDP/53
#                              conntrack girdilerini temizlemek için
#                              kullanır; yoksa sessizce atlanır).
#
# Algılanan paket yöneticilerinden hiçbiri uymuyorsa elle kurun —
# gereken paket adları için dosya sonundaki geniş liste / README.

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "root (sudo) olarak çalıştırılmalıdır" >&2
    exit 1
fi

# apt ve apt-get farklı sarmalayıcılar; apt-get betiklerde daha kararlıdır.
if command -v apt-get >/dev/null 2>&1; then
    # Debian / Ubuntu / Mint / Kali / Pop!_OS / Raspbian / elementary
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y \
        libnetfilter-queue-dev libmnl-dev \
        gcc make pkg-config \
        iptables conntrack \
        bash
elif command -v dnf5 >/dev/null 2>&1; then
    # Fedora 41+ dnf5
    dnf5 install -y \
        libnetfilter_queue-devel libmnl-devel \
        gcc make pkgconf-pkg-config \
        iptables conntrack-tools \
        bash
elif command -v dnf >/dev/null 2>&1; then
    # Fedora / RHEL 8+ / Rocky / AlmaLinux / Amazon Linux 2023 / OpenMandriva
    dnf install -y \
        libnetfilter_queue-devel libmnl-devel \
        gcc make pkgconf-pkg-config \
        iptables conntrack-tools \
        bash
elif command -v yum >/dev/null 2>&1; then
    # CentOS 7 / RHEL 7 / Oracle Linux 7 — eski dnf öncesi
    yum install -y \
        libnetfilter_queue-devel libmnl-devel \
        gcc make pkgconfig \
        iptables conntrack-tools \
        bash
elif command -v pacman >/dev/null 2>&1; then
    # Arch / Manjaro / EndeavourOS / Garuda — modern kurulumlarda iptables-nft
    # varsayılandır, `iptables` ile çakışır. Zaten hangisi kuruluysa onu
    # ellemiyoruz; yoksa nft sürümünü kuruyoruz.
    _have_iptables=0
    pacman -Qi iptables-nft >/dev/null 2>&1 && _have_iptables=1
    pacman -Qi iptables     >/dev/null 2>&1 && _have_iptables=1
    pacman -Syu --noconfirm --needed \
        libnetfilter_queue libmnl \
        gcc make pkgconf \
        bash conntrack-tools
    if [ "$_have_iptables" -eq 0 ]; then
        pacman -S --noconfirm --needed iptables-nft
    fi
elif command -v zypper >/dev/null 2>&1; then
    # openSUSE Tumbleweed / Leap / SLES
    zypper --non-interactive install \
        libnetfilter_queue-devel libmnl-devel \
        gcc make pkg-config \
        iptables conntrack-tools \
        bash
elif command -v apk >/dev/null 2>&1; then
    # Alpine (musl). bash busybox değildir; açıkça isteniyor çünkü tüm
    # scriptler `#!/usr/bin/env bash` kullanır.
    apk add --no-cache \
        libnetfilter_queue-dev libmnl-dev \
        gcc make pkgconf musl-dev linux-headers \
        iptables conntrack-tools \
        bash
elif command -v xbps-install >/dev/null 2>&1; then
    # Void Linux (glibc veya musl)
    xbps-install -Sy \
        libnetfilter_queue-devel libmnl-devel \
        gcc make pkg-config \
        iptables conntrack-tools \
        bash
elif command -v emerge >/dev/null 2>&1; then
    # Gentoo / Funtoo — başlıklar runtime paketlerine gömülüdür.
    emerge --noreplace \
        net-libs/libnetfilter_queue net-libs/libmnl \
        sys-devel/gcc sys-devel/make dev-util/pkgconf \
        net-firewall/iptables net-firewall/conntrack-tools \
        app-shells/bash
elif command -v eopkg >/dev/null 2>&1; then
    # Solus
    eopkg install -y \
        libnetfilter_queue-devel libmnl-devel \
        gcc make pkg-config \
        iptables \
        bash
elif command -v swupd >/dev/null 2>&1; then
    # Clear Linux
    swupd bundle-add -y \
        c-basic devpkg-libnetfilter_queue devpkg-libmnl iptables bash
elif command -v slackpkg >/dev/null 2>&1; then
    # Slackware — slackpkg'nin -current reposundan yalnızca mevcut
    # paketleri kurar; eksik olanlar SBo'dan elle alınmalıdır.
    slackpkg -batch=on -default_answer=y install \
        gcc make pkg-config iptables bash conntrack-tools 2>/dev/null || true
    echo "slackware: libnetfilter_queue ve libmnl varsayılan depoda yoksa" >&2
    echo "slackbuilds.org'dan kurun" >&2
elif command -v nix-env >/dev/null 2>&1 || command -v nix >/dev/null 2>&1; then
    # NixOS / nix on other distros — bu yaklaşım kullanıcı profili için
    # imperative; deklaratif konfigürasyon isteniyorsa configuration.nix
    # içine ekleme tavsiye edilir.
    cat >&2 <<'EOF'
nix tespit edildi. NixOS'ta bu projeyi imperative kurmak yerine,
configuration.nix içine şunu ekleyip 'nixos-rebuild switch' çalıştırın:

    environment.systemPackages = with pkgs; [
        libnetfilter_queue libmnl pkg-config gcc gnumake
        iptables conntrack-tools bash
    ];

Ya da geçici bir shell için:
    nix-shell -p libnetfilter_queue libmnl pkg-config gcc gnumake \
              iptables conntrack-tools
EOF
    exit 1
else
    cat >&2 <<'EOF'
desteklenen bir paket yöneticisi bulunamadı. Manuel olarak şu
paketleri (dağıtımınızdaki karşılıklarıyla) kurun:

  derleme :  libnetfilter_queue geliştirme başlıkları
             libmnl geliştirme başlıkları
             gcc (veya cc), make, pkg-config
             bash

  çalışma :  iptables (+ ip6tables)
             [opsiyonel] conntrack / conntrack-tools

Linux çekirdeğiniz nfnetlink_queue modülünü (NFQUEUE) sunmalıdır —
her güncel dağıtım çekirdeği sunar.

Tanımadığımız paket yöneticiniz varsa
https://github.com/ZihniCanKalsin/goodbyedpi-linux-turkey adresinde issue açın;
deps-install.sh'a eklenebilir.
EOF
    exit 1
fi

echo
echo "bağımlılıklar kuruldu."
echo "sonraki adım: 'make' ile derleyin, ardından:"
echo "  sudo scripts/service-install.sh       # systemd birimi + menü"
echo "veya tek seferlik deneme için:"
echo "  sudo scripts/turkey_dnsredir.sh       # ön planda"
