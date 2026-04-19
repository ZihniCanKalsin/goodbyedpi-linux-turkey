#!/usr/bin/env bash
# service-install.sh — kullanıcı dostu kurulum: bir varyant seçtirir,
# `goodbyedpi-linux.service` systemd birimini yazar, etkinleştirir ve
# başlatır. Böylece daemon her önyüklemede otomatik çalışır; kullanıcı
# her seferinde terminal açmak zorunda kalmaz.
#
# Kullanım (etkileşimli):    sudo ./service-install.sh
# Kullanım (doğrudan):       sudo ./service-install.sh turkey_dnsredir_alt5
#
# Kaldırmak için:             sudo ./service-uninstall.sh

set -eu

SERVICE_NAME=goodbyedpi-linux
UNIT_PATH=/etc/systemd/system/${SERVICE_NAME}.service

if [ "$(id -u)" -ne 0 ]; then
    echo "root (sudo) olarak çalıştırılmalıdır" >&2
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
    cat >&2 <<'EOF'
systemctl bulunamadı. Bu yardımcı script systemd kullanır; eğer sistemde
systemd yoksa (örn. OpenRC, runit, alpine) onun yerine el-kitabındaki
manuel yöntemi kullanın: 'scripts/goodbyedpi-linux-install.sh <varyant>'
plus dağıtımınızın önyüklemede koşturma mekanizması (cron @reboot,
rc.local vb.).
EOF
    exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
BIN="$REPO_DIR/goodbyedpi-linux"

if [ ! -x "$BIN" ]; then
    echo "derleme çıktısı bulunamadı: $BIN" >&2
    echo "önce '$REPO_DIR' içinde 'make' çalıştırın" >&2
    exit 1
fi

# Varyantların kısa açıklamaları — menü ve README ile eşleşir.
# Format: "slug|başlık|tanım"
VARIANTS=(
    "turkey_dnsredir|turkey_dnsredir (ÖNERİLEN, başlangıç)|TLS ClientHello'yu 2 baytta böl, ters sıra, TTL-5 sahte tuzak, Yandex DNS yönlendirme. Çoğu TTNET/Superonline kullanıcısı için en iyi başlangıç."
    "turkey_dnsredir_alt4|turkey_dnsredir_alt4|Ana varyantla aynı ama sabit TTL yerine 'auto-ttl' sezgisi kullanır. Birincil varyantta sorun yaşarsanız deneyin."
    "turkey_dnsredir_alt5|turkey_dnsredir_alt5 (güçlü)|-9 ön ayarı (yanlış-sıra + yanlış-sağlama + bölme) + Yandex DNS + QUIC engelleme. Chrome'da HTTP/3 yüzünden sorun yaşıyorsanız ya da daha inatçı bir DPI varsa bunu deneyin."
    "turkey_dnsredir_alt3|turkey_dnsredir_alt3|Yalnız TTL 3 sahte tuzak + Yandex DNS. Bölme yok; yalnızca hafif müdahale yeterliyse kullanın."
    "turkey_dnsredir_alt1|turkey_dnsredir_alt1|Yalnız TTL 3 sahte tuzak, DNS yönlendirmesi yok. Kendi DNS'inizi ayarladıysanız (DoH, DoT) ve sadece DPI atlatması gerekiyorsa."
    "turkey_dnsredir_alt2|turkey_dnsredir_alt2|-5 ön ayarı, DNS yönlendirmesi yok. alt1 gibi ama tam TLS bölme."
    "turkey_dnsredir_alt6|turkey_dnsredir_alt6|-9 + QUIC engelleme, DNS yönlendirmesi yok. Kendi DNS'iniz var ve en güçlü DPI atlatmasını istiyorsanız."
)

print_menu() {
    echo
    echo "Hangi varyant kurulsun?"
    echo "============================================================"
    local i=1
    for v in "${VARIANTS[@]}"; do
        local title=${v#*|}; title=${title%%|*}
        local desc=${v##*|}
        printf "  %d) %s\n     %s\n\n" "$i" "$title" "$desc"
        i=$((i + 1))
    done
    echo "  q) vazgeç"
    echo "============================================================"
    echo "Hangisini denemeli? ÖNERİ: 1'den başlayın. İşe yaramazsa sırasıyla"
    echo "3 (alt5), 2 (alt4), 4 (alt3) deneyin. Chrome HTTP/3 kullandığı için"
    echo "tarayıcıdan açılmayan siteler alt5'te (QUIC engelleme ile) çoğu"
    echo "zaman açılır."
    echo
}

resolve_variant() {
    # $1 ya bir sayı (menü seçimi) ya da slug adı.
    local sel="$1"
    if [[ "$sel" =~ ^[0-9]+$ ]]; then
        local idx=$((sel - 1))
        if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#VARIANTS[@]}" ]; then
            echo ""; return
        fi
        echo "${VARIANTS[$idx]%%|*}"
        return
    fi
    for v in "${VARIANTS[@]}"; do
        local slug=${v%%|*}
        if [ "$slug" = "$sel" ]; then echo "$slug"; return; fi
    done
    echo ""
}

CHOICE="${1:-}"
if [ -z "$CHOICE" ]; then
    print_menu
    read -r -p "Seçim [1]: " CHOICE
    CHOICE="${CHOICE:-1}"
fi

if [ "$CHOICE" = "q" ] || [ "$CHOICE" = "Q" ]; then
    echo "vazgeçildi"
    exit 0
fi

VARIANT=$(resolve_variant "$CHOICE")
if [ -z "$VARIANT" ]; then
    echo "geçersiz seçim: '$CHOICE'" >&2
    exit 2
fi

VARIANT_SH="$SCRIPT_DIR/${VARIANT}.sh"
if [ ! -x "$VARIANT_SH" ]; then
    echo "varyant betiği bulunamadı: $VARIANT_SH" >&2
    exit 1
fi

IPTABLES_DOWN="$SCRIPT_DIR/iptables-down.sh"

# Daha önce bu isimle bir birim varsa devre dışı bırak — böylece eski
# varyant değiştirildiğinde artık referansı kalmaz. Hata verse de sürdür.
if systemctl list-unit-files "${SERVICE_NAME}.service" --no-legend 2>/dev/null | grep -q .; then
    systemctl stop    "${SERVICE_NAME}.service" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true
fi
# Daha önce elle başlatılmış (install.sh) bir daemon kalmışsa onu da kapat.
"$SCRIPT_DIR/goodbyedpi-linux-uninstall.sh" >/dev/null 2>&1 || true

cat > "$UNIT_PATH" <<EOF
[Unit]
Description=goodbyedpi-linux (Turkey fork DPI bypass) - $VARIANT
Documentation=https://github.com/OWNER/goodbyedpi-linux-turkey
After=network-online.target nss-lookup.target
Wants=network-online.target
# Sonsuz yeniden başlatma önleme: 60 saniyede 5 arıza üst üste geldiyse
# servisi 'failed' bırak; iptables chain'ini sürekli yeniden yazmaktan
# kaçınırız.
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=exec
# Varyant betiği bu bayrakla doğrudan exec() eder; bkz. scripts/_common.sh.
Environment=GBD_INSTALL_MODE=1
ExecStart=/usr/bin/env bash $VARIANT_SH
# Daemon 'exec' ile başlatıldığı için onun EXIT tuzağı yok; systemd süreci
# sonlandırdığında iptables kurallarını bu satır temizler.
ExecStopPost=/usr/bin/env bash $IPTABLES_DOWN --queue 200
Restart=on-failure
RestartSec=3
# Tam root gerekir: NFQUEUE (CAP_NET_ADMIN) + raw soket (CAP_NET_RAW) +
# /home ya da özel dizinlerdeki repo yolunu traverse etmek için
# DAC_READ_SEARCH gibi geleneksel root yetkileri. CapabilityBoundingSet
# ayarlamıyoruz çünkü onu NET_ADMIN+NET_RAW ile sınırlamak, kullanıcının
# ev dizini 0750 olduğunda (modern Ubuntu/Zorin varsayılanı) systemd'nin
# script'i okumasını bile engelliyor (exit 126). Tüm tool zaten
# privileged; yüzeyi daraltmak koruma sağlamak yerine servisi patlatıyor.
NoNewPrivileges=false

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "$UNIT_PATH"

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service" >/dev/null
systemctl start  "${SERVICE_NAME}.service"

sleep 1
if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    cat <<EOF

================================================================
  KURULDU: $VARIANT
================================================================
  Aktif ve önyüklemede otomatik başlıyor.

VARYANTI DEĞİŞTİRMEK için aynı komutu yeniden çalıştırın:
    sudo $0
  (menü yeniden açılır, seçtiğiniz yeni varyant eskisini değiştirir;
   yeniden başlatma gerekmez.)

DURDURMAK / BAŞLATMAK (geçici):
    sudo systemctl stop  $SERVICE_NAME
    sudo systemctl start $SERVICE_NAME

TAMAMEN KALDIRMAK:
    sudo $SCRIPT_DIR/service-uninstall.sh

İZLEMEK:
    systemctl status $SERVICE_NAME          # durum
    journalctl -u $SERVICE_NAME -f           # canlı günlük

HIZLI TEST:
    curl -o /dev/null -w '%{http_code}\\n' https://discord.com/
================================================================
EOF
else
    echo
    echo "servis başlatılamadı. journal çıktısı:"
    journalctl -u "$SERVICE_NAME" --no-pager -n 30 || true
    exit 1
fi
