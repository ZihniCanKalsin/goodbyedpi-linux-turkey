# goodbyedpi-linux-turkey

[![build](https://img.shields.io/github/actions/workflow/status/ZihniCanKalsin/goodbyedpi-linux-turkey/build.yml?branch=main)](./.github/workflows/build.yml)
[![lisans](https://img.shields.io/badge/lisans-Apache--2.0-blue)](./LICENSE)
[![sürüm](https://img.shields.io/badge/s%C3%BCr%C3%BCm-0.1.0-informational)](./CHANGELOG.md)

[GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI)'ın — Windows üzerinde
çalışan DPI (Derin Paket İnceleme) atlatma aracının — Linux için sıfırdan
yeniden yazılmış uygulaması; Turkey-ISP fork'unun özellik yüzeyini hedefler.
Windows'un **WinDivert** çekirdek sürücüsünün yerine Linux'ta **NFQUEUE +
ham soketler** kullanır ve `-5` / `-9` ön ayarları, TTL hileleri ve şeffaf
DNS yönlendirmesi için eşleşen komut satırı semantiklerine sahiptir.

Bu çalışma satır-satır bir port değildir. Temiz oda (clean-room) yöntemiyle
yapılmış bağımsız bir yeniden uygulamadır; Turkey fork'unun `.cmd`
başlatıcılarının kullandığı komut satırı yüzeyini birebir hedefler; böylece
mevcut kullanıcılar zihinsel modellerini değiştirmeden Windows'tan Linux'a
1:1 geçebilir.

---

## İçindekiler

- [Neden var?](#neden-var)
- [Özellikler](#özellikler)
- [Hızlı başlangıç](#hızlı-başlangıç)
- [Kurulum](#kurulum)
- [Desteklenen dağıtımlar](#desteklenen-dağıtımlar)
- [Kullanım — varyant tablosu](#kullanım--varyant-tablosu)
- [Kalıcı çalıştırma](#kalıcı-çalıştırma)
- [Nasıl çalışır?](#nasıl-çalışır)
- [Bayrak referansı](#bayrak-referansı)
- [Sorun giderme](#sorun-giderme)
- [Üstakıma göre sınırlar ve farklar](#üstakıma-göre-sınırlar-ve-farklar)
- [Geliştirme](#geliştirme)
- [Katkı](#katkı)
- [Lisans ve katkı sahipleri](#lisans-ve-katkı-sahipleri)
- [Yasal uyarı](#yasal-uyarı)

---

## Neden var?

Üstakım GoodbyeDPI ve onun Turkey fork'u yalnızca Windows'ta çalışır;
WinDivert çekirdek sürücüsüne bağımlılar ve Windows ağ yığınını hedef
alırlar. Linux'ta çalışan kullanıcılar için (masaüstü, WSL ana makineleri,
ev yönlendiricisi sanal makineleri, seyahat laptopları) Turkey fork'unun
hazır varyant ön ayarlarını birebir sağlayan bir araç bulunmuyordu.
`goodbyedpi-linux-turkey` bu boşluğu dolduruyor: aynı argv, aynı davranış,
aynı varyant isimleri — Windows Turkey fork'undan 1:1 geçiş için
paketlenmiş hâlde.

## Özellikler

- **NFQUEUE tabanlı paket yakalama.** Çekirdek, eşleşen paketleri
  kullanıcı alanına devreder; daemon onları inceler, değiştirir veya
  yeniden oluşturur.
- **TLS ClientHello bölme**: ayarlanabilir bir bayt konumundan, isteğe
  bağlı olarak ters sırada (ikinci parça birinciden önce gönderilir).
- **HTTP istek bölme**: TCP/80 giden trafikte ayarlanabilir bayt
  konumundan.
- **Sahte tuzak paket enjekte etme**: bilerek yanlış TCP sıra numarası
  ve/veya yanlış TCP sağlama toplamıyla ve düşük TTL / atlama limitiyle;
  böylece tuzak paket, gerçek sunucuya ulaşmadan önce yolda ölür.
- **Şeffaf DNS yönlendirmesi** (IPv4 ve IPv6 üzerinden): giden UDP/53
  sorguları NAT ile özel bir çözümleyiciye (örn. Yandex DNSCrypt
  1253 numaralı portta) yeniden yazılır; cevap yolu yeniden yazımları,
  sorgu başına kısa ömürlü bir hashmap üzerinden tersine çevrilir,
  böylece istemci yığını normal bir cevap görür.
- **QUIC / UDP-443 engelleme**: `-q` ve `-9` altında; böylece tarayıcılar
  fragmantasyon hilelerinin işe yaradığı TCP'ye geri düşer.
- **Turkey fork'unun `.cmd` dosyalarıyla 1:1 eşleşen yedi başlatıcı
  betik.** Windows'tan geçiş, eşleşen `.sh` dosyasını seçmek kadar basit.
- **Çöktüğünde açık bırakır.** iptables kuralları `--queue-bypass` ile
  kurulur; daemon ölürse çekirdek trafiği normal şekilde iletmeye devam
  eder (DPI atlatması kapanır, ama internet hâlâ çalışır).
- **systemd bağımlılığı yok.** Dağıtımdan bağımsız `setsid` + PID-dosya
  arka plan modeli. Otomatik başlatma, kullanıcının tercih ettiği init
  sistemine bırakılmıştır.

## Hızlı başlangıç

Proje dağıtımdan bağımsızdır. Aşağıdaki adımlar
**Debian / Ubuntu / Mint / Pop!_OS / Zorin, Fedora / RHEL / Rocky / Alma,
Arch / Manjaro / Endeavour, openSUSE, Alpine, Void, Gentoo, Solus ve
NixOS** üzerinde aynı şekilde çalışır. Tam liste için aşağıdaki [Desteklenen
dağıtımlar](#desteklenen-dağıtımlar) bölümüne bakın.

### 1. Bağımlılıkları kur ve derle

```sh
git clone https://github.com/ZihniCanKalsin/goodbyedpi-linux-turkey.git
cd goodbyedpi-linux-turkey
sudo scripts/deps-install.sh         # paket yöneticinizi algılar (apt/dnf/pacman/apk/…)
make                                 # ./goodbyedpi-linux üretir (~35 KB)
```

Başarısız olursa önce ortam denetimini çalıştırın — tam olarak neyin
eksik olduğunu ve nasıl kuracağınızı söyler:

```sh
sudo scripts/sanity-check.sh         # her dağıtımda çalışır
```

### 2. Arka plan servisi olarak kur (önerilen)

Tek komut: varyant menüsü açılır, seçtiğiniz varyantı systemd birimi
olarak kurar, hemen başlatır ve **her önyüklemede otomatik çalışır**.
Terminal açmanıza gerek kalmaz.

```sh
sudo scripts/service-install.sh
```

Menü şöyle görünür:

```
Hangi varyant kurulsun?
  1) turkey_dnsredir (ÖNERİLEN, başlangıç)
     TLS ClientHello'yu 2 baytta böl, ters sıra, TTL-5 sahte tuzak, Yandex DNS yönlendirme.
     Çoğu TTNET/Superonline kullanıcısı için en iyi başlangıç.
  2) turkey_dnsredir_alt4
     Ana varyantla aynı ama sabit TTL yerine 'auto-ttl' sezgisi kullanır.
  3) turkey_dnsredir_alt5 (güçlü)
     -9 + Yandex DNS + QUIC engelleme. Chrome HTTP/3 yüzünden engellerse bunu deneyin.
  ... (6 seçenek daha)
```

#### Hangisini seçmeli?

Her ISP / DPI ara kutusu farklı davrandığı için **hangi varyantın size
en iyi uyacağını deneyerek bulmak zorundasınız**. Önerilen sıra:

1. **`turkey_dnsredir` (menüde 1)** — başlangıç. Çoğu kullanıcıda yeter.
2. **`turkey_dnsredir_alt5` (menüde 3)** — Chrome'da sayfa açılmıyorsa.
   Sebep: Chrome önce QUIC (UDP/443) kullanır; alt5 QUIC'i engeller ve
   Chrome TCP'ye geri düşer, bizim ClientHello bölme hilemiz de TCP'de
   çalışır. Ayrıca `-9` ön ayarı daha agresif tuzak paketler üretir.
3. **`turkey_dnsredir_alt4` (menüde 2)** — birincil varyant çalışıyor
   ama bazı siteler hâlâ açılmıyorsa. Auto-TTL sezgisi bazı DPI ara
   kutularına daha iyi uyum sağlar.
4. **`turkey_dnsredir_alt3` (menüde 4)** — yalnız TTL 3 sahte tuzak;
   bölme yok. "Hafif" mod. DPI'nız yalnızca SNI tabanlıysa bu bile
   yetebilir ve daha az yan etki yaratır (ör. bazı siteler bölmeden
   hoşlanmaz).
5. **alt1 / alt2 / alt6** — yalnızca kendi DNS'inizi zaten başka bir
   yolla (DoH, DoT, özel resolver) yapılandırdıysanız. Bu varyantlar
   UDP/53'ü **yeniden yazmaz**, yalnız DPI atlatması yaparlar.

Başka bir varyant denemek için aynı komutu tekrar çalıştırın; eski birim
otomatik olarak değiştirilir.

#### Durum, günlük, kaldırma

```sh
systemctl status goodbyedpi-linux            # durum
journalctl -u goodbyedpi-linux -f            # canlı günlük
sudo scripts/service-uninstall.sh            # tamamen kaldır
```

### 3. Tek seferlik test (servis kurmadan)

Sadece deneyip karar vermek istiyorsanız, varyantı ön planda çalıştırın —
Ctrl-C ile bırakınca iptables kuralları da otomatik temizlenir:

```sh
sudo scripts/turkey_dnsredir.sh              # ya da alt{1..6}.sh
```

### Çalışıyor mu? Hızlı test

```sh
curl -o /dev/null -w '%{http_code}\n' https://discord.com/
```

`301` ya da `200` yazdırıyorsa DPI atlatma çalışıyor. `curl: (35)` /
`Connection reset by peer` alıyorsanız ya servis çalışmıyordur ya da
seçtiğiniz varyant bu ISS'nizin DPI'ına uymuyor — başka bir varyant
deneyin (önce alt5).

## Kurulum

### Bağımlılıklar

**Derleme zamanı:** `libnetfilter_queue` başlıkları, `libmnl` başlıkları,
bir C derleyici, `make`, `pkg-config`.

**Çalışma zamanı:** `iptables` (ve IPv6 için `ip6tables`), çekirdek
modülü `nfnetlink_queue` (her güncel dağıtım çekirdeğinde vardır; yardımcı
script başlangıçta `modprobe` ile yükler) ve **root** (ya da
`CAP_NET_ADMIN` + `CAP_NET_RAW`).

`scripts/deps-install.sh` yardımcı scripti yerel paket yöneticisini
(`apt-get`, `dnf`, `yum`, `pacman`, `zypper`, `apk`, `xbps-install`,
`emerge`) algılayıp doğru paketleri kurar. `make`'den önce çalıştırın —
aksi halde `pkg-config` hataları alırsınız. Dağıtımınız bu listede yoksa
(ör. NixOS) aşağıdakilerin karşılıklarını manuel olarak kurun:

| Paket (Debian/Ubuntu) | Diğer dağıtımlardaki karşılığı                          |
|---|---|
| `libnetfilter-queue-dev` | `libnetfilter_queue-devel` (Fedora/RHEL/SUSE), `libnetfilter_queue` + `-dev` (Arch/Alpine) |
| `libmnl-dev`             | `libmnl-devel` (Fedora/RHEL/SUSE), `libmnl`          |
| `gcc`, `make`, `pkg-config`, `iptables` | her yerde aynı isim |

### Derleme

```sh
make                # ./goodbyedpi-linux üretir (~35 KB)
make clean          # derleme çıktılarını temizler
```

## Desteklenen dağıtımlar

Proje dağıtım-agnostiktir: yalnızca `glibc` veya `musl`, GNU `make`, `cc`,
`pkg-config`, `bash` ve Linux ≥ 3.10 çekirdeği gerekir. `deps-install.sh`
aşağıdaki paket yöneticilerini algılayıp doğru paket adlarını kurar:

| Paket yöneticisi | Kapsadığı dağıtımlar |
|---|---|
| `apt-get` | Debian, Ubuntu, Linux Mint, Pop!_OS, Kali, Raspbian, elementary, Zorin |
| `dnf` / `dnf5` | Fedora, RHEL 8+, Rocky, AlmaLinux, Amazon Linux 2023, OpenMandriva |
| `yum` | CentOS 7, RHEL 7, Oracle Linux 7 |
| `pacman` | Arch, Manjaro, EndeavourOS, Garuda (iptables-nft otomatik tercih edilir) |
| `zypper` | openSUSE Tumbleweed / Leap, SLES |
| `apk` | Alpine (musl; `bash` dahil kurulur) |
| `xbps-install` | Void (glibc ve musl) |
| `emerge` | Gentoo, Funtoo |
| `eopkg` | Solus |
| `swupd` | Clear Linux |
| `slackpkg` | Slackware (libnetfilter_queue SBo'dan gerekir) |
| `nix` / `nix-env` | NixOS / nix (deklaratif öneri yazdırır) |

Dağıtımınız bu listede yoksa veya paket adları farklıysa:

```sh
sudo scripts/sanity-check.sh
```

tam olarak neyin eksik olduğunu ve nasıl kuracağınızı gösterir. Paket
adları dağıtıma özel olsa da **minimum bağımlılık listesi evrenseldir**:

- derleme: `libnetfilter_queue` (+ dev başlıkları), `libmnl` (+ dev
  başlıkları), C derleyicisi, GNU `make`, `pkg-config`, `bash`
- çalışma: `iptables` (ve IPv6 için `ip6tables`), çekirdekte
  `nfnetlink_queue` + `xt_NFQUEUE` (her güncel dağıtım çekirdeğinde
  var), opsiyonel `conntrack` (artık-DNAT UDP girdisi temizliği)

Init sistemi seçimi:

- **systemd olan** herhangi bir dağıtımda `scripts/service-install.sh`
  çalışır ve önyüklemede otomatik başlatma kurar.
- **systemd olmayan** (OpenRC, runit, s6, SysV, Alpine OpenRC)
  kullanıcılar `scripts/goodbyedpi-linux-install.sh <varyant>` ile
  `setsid` arka planına atar; önyüklemede otomatik başlatmayı kendi
  init mekanizmanızla (cron @reboot, rc.local, openrc servis dosyası)
  yaparsınız.

`sanity-check.sh` her iki mekanizmanın da kullanılabilir olup
olmadığını raporlar.

## Kullanım — varyant tablosu

Her betik, varyantın ihtiyaç duyduğu iptables kurallarını kurar, daemon'u
ön planda çalıştırır ve Ctrl-C / çıkışta kuralları kaldırır.

| Windows `.cmd` (Turkey fork) | Buradaki Linux karşılığı | Ne yapar |
|---|---|---|
| `turkey_dnsredir.cmd` | `sudo scripts/turkey_dnsredir.sh` | Birincil varyant. `-5` + TTL 5 + IPv4 ve IPv6 için Yandex (1253) DNS yönlendirmesi. |
| `turkey_dnsredir_alternative_superonline.cmd` | `sudo scripts/turkey_dnsredir_alt1.sh` | Sadece `--set-ttl 3`. DNS'i manuel olarak siz ayarlarsınız. |
| `turkey_dnsredir_alternative2_superonline.cmd` | `sudo scripts/turkey_dnsredir_alt2.sh` | Sadece `-5`. DNS'i manuel olarak siz ayarlarsınız. |
| `turkey_dnsredir_alternative3_superonline.cmd` | `sudo scripts/turkey_dnsredir_alt3.sh` | `--set-ttl 3` + Yandex DNS yönlendirmesi (v4 + v6). |
| `turkey_dnsredir_alternative4_superonline.cmd` | `sudo scripts/turkey_dnsredir_alt4.sh` | `-5` + Yandex DNS yönlendirmesi (v4 + v6). |
| `turkey_dnsredir_alternative5_superonline.cmd` | `sudo scripts/turkey_dnsredir_alt5.sh` | `-9` + Yandex DNS yönlendirmesi (v4 + v6). |
| `turkey_dnsredir_alternative6_superonline.cmd` | `sudo scripts/turkey_dnsredir_alt6.sh` | Sadece `-9`. DNS'i manuel olarak siz ayarlarsınız. |

Adında "DNS yönlendirmesi" geçmeyen varyantlar UDP/53'ü **yeniden
yazmaz** — sistem çözümleyicinizi kendiniz ayarlamanız gerekir (Yandex
`77.88.8.8` veya Cloudflare `1.1.1.1` yaygın tercihlerdir); Windows
README'deki aynı uyarı geçerlidir.

Yandex yerine özel bir DNS sunucusu kullanmak için varyant betiğinin
başını düzenleyin veya daemon'u doğrudan çalıştırın:

```sh
sudo scripts/iptables-up.sh --dns4 --dns4-addr 1.1.1.1 --dns4-port 53 &&
sudo ./goodbyedpi-linux -5 --dns-addr 1.1.1.1 --dns-port 53
```

## Kalıcı çalıştırma

### systemd (önerilen; Hızlı başlangıç'ta anlatıldı)

```sh
sudo scripts/service-install.sh      # etkileşimli menü
sudo scripts/service-uninstall.sh    # kaldır
```

`service-install.sh` seçtiğiniz varyant için
`/etc/systemd/system/goodbyedpi-linux.service` dosyasını üretir,
`daemon-reload` çalıştırır, `enable --now` eder. Her önyüklemede
otomatik başlar.

### systemd olmayan sistemler (OpenRC, runit, Alpine, ...)

Aşağıdaki iki yardımcı uzun süreli bir arka plan daemon'unu `setsid` ile
yönetir — systemd bağımsızdır ama önyüklemede otomatik başlatmayı siz
kurmak zorundasınız:

```sh
sudo scripts/goodbyedpi-linux-install.sh turkey_dnsredir   # ya da başka bir varyant adı
sudo scripts/goodbyedpi-linux-uninstall.sh
```

Kurucu:

- seçilen varyantı `setsid` ile arka plana alır,
- PID'yi `/run/goodbyedpi-linux.pid` (ya da `/var/run/...`) içine yazar,
- günlükleri `/var/log/goodbyedpi-linux.log` sonuna ekler.

Daemon oturumu kapattıktan sonra **çalışmaya devam eder** ama önyüklemede
**otomatik başlamaz**. Otomatik başlatma için, dağıtımınızın kendi
mekanizmasını kullanın — yaygın seçenekler:

```sh
# /etc/rc.local (klasik sysvinit / rc.local destekli sistemler)
/yol/goodbyedpi-linux-turkey/scripts/goodbyedpi-linux-install.sh turkey_dnsredir

# crontab (cron içeren her dağıtım)
@reboot root /yol/goodbyedpi-linux-turkey/scripts/goodbyedpi-linux-install.sh turkey_dnsredir

# ya da isterseniz kendi systemd biriminizi yazın
```

## Nasıl çalışır?

```
                   ┌──────────────────────────────────────────┐
   giden paketler  │  iptables OUTPUT / INPUT                 │
  ─────────────▶  │  -m multiport --dports 80,443 -j NFQUEUE │
                   │  -p udp --dport 53      -j NFQUEUE       │
                   │  -p udp --dport 443     -j NFQUEUE  (-q) │
                   └───────────────┬──────────────────────────┘
                                   │ libnetfilter_queue
                                   ▼
                   ┌──────────────────────────────────────────┐
                   │  goodbyedpi-linux                        │
                   │  ┌────────────────────────────────────┐  │
                   │  │ dağıtıcı (nfq_loop.c)              │  │
                   │  └───┬──────────┬─────────┬───────────┘  │
                   │      │          │         │              │
                   │      ▼          ▼         ▼              │
                   │  tcp_mangle  dns_redir   QUIC düşür      │
                   │  (ClientHello (UDP 53    (UDP 443        │
                   │   + HTTP bölme, DNAT +   NF_DROP)        │
                   │   sahte tuzak, ters                      │
                   │   yön) yazım)                            │
                   └──────────────────────────────────────────┘
                                   │ ham soket (IP_HDRINCL)
                                   ▼
                    kablo üzerine üretilmiş parçalar / tuzaklar
```

### Paket bazlı kararlar

| Yön | Protokol / port | Koşul                                   | İşlem |
|---|---|---|---|
| Giden    | TCP dport 443   | İlk veri segmenti bir TLS ClientHello (`0x16 0x03 … 0x01`) | Orijinali `NF_DROP` yap; (isteğe bağlı) ham enjekte edilen tuzak + orijinal yükün iki parçası, isteğe bağlı olarak ters sırada. |
| Giden    | TCP dport 80    | İlk veri segmenti bir HTTP fiili (`GET `, `POST `, `HEAD `, …) | yukarıdakiyle aynı. |
| Giden    | UDP dport 53    | `--dns-addr` / `--dnsv6-addr` ayarlı | Hedef IP+portu yapılandırılan çözümleyiciye yeniden yaz, IP/UDP sağlama toplamlarını yeniden hesapla, cevap için `(kaynak, txid)` kaydet, `NF_ACCEPT`. |
| Gelen    | Yapılandırılan DNS sunucusundan UDP | `--dns-addr` / `--dnsv6-addr` ayarlı | Kaynak IP+portunu istemcinin sorduğu orijinal hedefe geri yaz, sağlama toplamlarını yeniden hesapla, `NF_ACCEPT`. |
| Giden    | UDP dport 443   | `-q` / `-9` etkin                        | `NF_DROP` (TCP'ye geri düşmeye zorlar). |
| Kuyruktaki diğer her şey | — | —                        | Dokunulmadan `NF_ACCEPT`. |

### Neden `NF_DROP` + ham soketle yeniden enjeksiyon

`NFQUEUE` bir paketi yerinde değiştirip yeniden karar vermenize izin
verir, ama tek girdiden *birden fazla* paket üretemez. Bölünmüş
ClientHello doğası gereği ≥ 2 paket üretir, bu yüzden orijinal düşürülür
ve yerine geçenler `AF_INET`/`AF_INET6 SOCK_RAW` soketinden
`IP_HDRINCL` ile çıkılır; kaynak IP/port/sıra korunur ve TTL ile sağlama
toplamları serbestçe denetlenebilir.

## Bayrak referansı

| Bayrak                    | Etki                                                                 |
|---|---|
| `-5`                      | `-f 2 -e 2 --reverse-frag --fake-packet --auto-ttl --max-payload-size 1200` |
| `-9`                      | `-f 2 -e 2 --reverse-frag --fake-packet --wrong-seq --wrong-chksum -q --max-payload-size 1200` |
| `-f N`                    | HTTP istek bölme konumu (bayt; Turkey fork 2 kullanır)               |
| `-e N`                    | TLS ClientHello bölme konumu (bayt; Turkey fork 2 kullanır)          |
| `--auto-ttl`              | Tuzak paketler için düşük TTL sezgisi                                |
| `--reverse-frag`          | İkinci parçayı birinciden önce gönder                                |
| `--fake-packet`           | Gerçek parçalardan önce sahte ClientHello/HTTP yem enjekte et        |
| `--wrong-seq`             | Sahte tuzağı hatalı TCP sıra numarasıyla enjekte et                  |
| `--wrong-chksum`          | Sahte tuzağı bilerek geçersiz TCP sağlama toplamıyla enjekte et      |
| `--max-payload`           | Windows CLI uyumluluğu için yaşayan eski işaretçi (no-op)            |
| `--set-ttl N`             | Tuzak paketlere uygulanan TTL / atlama limiti (1–255)                |
| `-q`                      | QUIC / UDP-443 düşür (tarayıcıları TCP'ye zorlar)                    |
| `--dns-addr IP`           | UDP/53 yeniden yazım hedef IP'si                                     |
| `--dns-port N`            | UDP/53 yeniden yazım hedef portu (varsayılan 53)                     |
| `--dnsv6-addr IP6`        | IPv6 UDP/53 yeniden yazım hedef adresi                               |
| `--dnsv6-port N`          | IPv6 UDP/53 yeniden yazım hedef portu (varsayılan 53)                |
| `--queue-num N`           | NFQUEUE numarası (varsayılan 200)                                    |
| `-v`                      | Ayrıntılı hata ayıklama günlüğü                                      |
| `-h`                      | Yardım                                                               |

## Sorun giderme

- **`iptables: No chain/target/match by that name`** — çekirdekte
  `xt_NFQUEUE` yok. `sudo modprobe xt_NFQUEUE nfnetlink_queue`
  çalıştırın ya da bu modülleri içeren bir çekirdek derleyin / yükleyin
  (her güncel dağıtım çekirdeği içerir).
- **`firewalld` / `ufw` kurallarımı siliyor** — bu daemonlar iptables'ı
  tek başına yönetir. Ya NFQUEUE kurallarını kendi arayüzleri üzerinden
  kaydedin ya da goodbyedpi-linux'u kullanırken o güvenlik duvarı
  servisini durdurun.
- **Kabloda hiçbir şey değişmiyor** — kuralların kurulu olduğunu
  (`sudo iptables -S OUTPUT | grep NFQUEUE`) ve daemon'un çalıştığını
  (`ps -ef | grep goodbyedpi-linux` ya da kalıcı modda
  `/var/log/goodbyedpi-linux.log` takibi) doğrulayın.
- **IPv6 DNS yönlendirmesi hiç tetiklenmiyor** — birçok sistem DNS'i
  yalnız IPv4 üzerinden yapar. `dig -6 @<yerel-çözümleyici> example.com`
  ile test edin ya da yığın çözümleyicinizde IPv6'yı zorlayın.
- **`socket(SOCK_RAW, IPPROTO_RAW): Operation not permitted`** — daemon
  `CAP_NET_RAW` olmadan başladı. `sudo` ile çalıştırın ya da yetenekleri
  bir kez binary'ye verin:
  `sudo setcap cap_net_admin,cap_net_raw=ep goodbyedpi-linux`.
- **Aynı kuyruk # üzerinde iki örnek** — her kuyruk numarasına yalnız
  bir NFQUEUE okuyucusu bağlanabilir.
  `QUEUE_NUM=201 scripts/turkey_dnsredir.sh` ile üzerine yazın.
- **WSL2** — WSL içinde uygulanan iptables yalnız WSL'in ağ adını
  etkiler, Windows ana makineyi değil. Windows uygulamaları için DPI
  atlatması hâlâ `goodbyedpi.exe` gerektirir. Gerçek Linux dağıtımı
  için native Linux kullanın (masaüstü, sanal makine ya da yönlendirici).

## Üstakıma göre sınırlar ve farklar

- **`--auto-ttl` bir basitleştirmedir.** Üstakım, DPI ara kutusuna olan
  mesafeyi ölçmek için aktif sondalama yapar. Bu port verilmişse
  `--set-ttl`'i kullanır, yoksa tuzak atlama limitini 4 olarak varsayar.
  Ara kutunuz alışılmadık derecede uzaktaysa açıkça `--set-ttl N`
  geçirin.
- **`--max-payload` kabul edilir ama etkisizdir.** NFQUEUE yolu zaten
  yalnız ClientHello / HTTP fiili taşıyan paketlere etki eder, atlanacak
  bir şey kalmaz.
- **Yalnızca Turkey fork alt kümesi.** Üstakımda onlarca ek bayrak
  (`-1`/`-2`/`-3`/`-4`, `-a`, `-r`, `-s`, `-m`, kara/beyaz liste dosyası
  desteği, fake-gen modları, atlama limiti sondalama, …) bulunur ve
  yeniden uygulanmamışlardır. Bu proje kapsamı dışındadırlar; birine
  ihtiyacınız varsa issue açın.
- **WinDivert tarzı tek-binary paket yok.** Linux iptables'ı dışarıdan
  bağlamayı gerektirir. Varyant betikleri bunu sizin için yapar;
  binary'yi doğrudan çağırıyorsanız önce `scripts/iptables-up.sh`,
  bitirince `scripts/iptables-down.sh` çalıştırın.
- **Açıkta arızalanır, kapalıda değil.** iptables kuralları hâlâ
  kuruluyken daemon ölürse `--queue-bypass` bayrağı sayesinde çekirdek
  trafiği normal iletir (DPI atlatması kapanır, ama). Bu Windows'ta
  `.cmd` penceresini kapatma davranışıyla eşleşir: aşmayı kaybedersiniz,
  bağlantınızı değil.

## Geliştirme

Kaynak yerleşimi:

```
goodbyedpi-linux-turkey/
├── Makefile                    # cc + pkg-config libnetfilter_queue libmnl
├── LICENSE                     # Apache-2.0
├── NOTICE                      # üstakım GoodbyeDPI'a atıf
├── README.md                   # bu dosya
├── CHANGELOG.md
├── .gitignore
├── .github/workflows/build.yml # CI: derleme + CLI duman testi + shellcheck
├── src/
│   ├── main.c                  # argüman ayrıştırma, ön ayar açma, sinyal işleme
│   ├── nfq_loop.c/.h           # NFQUEUE tüketicisi + dağıtıcı
│   ├── tcp_mangle.c/.h         # ClientHello / HTTP tespiti + 2-bayt bölme
│   ├── raw_inject.c/.h         # AF_INET{,6} SOCK_RAW ve IP_HDRINCL
│   ├── dns_redir.c/.h          # DNS yeniden yazım + cevap ters-yazım hashmap
│   ├── checksum.c/.h           # IPv4 / IPv6 / TCP / UDP sağlama toplamları
│   ├── fake_payloads.c/.h      # üstakımdan alınan sahte ClientHello/HTTP yem
│   └── util.c/.h               # global yapılandırma + günlük makroları
└── scripts/
    ├── deps-install.sh         # paket yöneticisi algılayıp bağımlılık kurar
    ├── sanity-check.sh         # ortam denetimi: tüm dağıtımlarda çalışır
    ├── iptables-up.sh / iptables-down.sh
    ├── service-install.sh / service-uninstall.sh      # systemd yolu
    ├── goodbyedpi-linux-install.sh / -uninstall.sh    # systemd-siz arka plan
    ├── _common.sh              # varyant betikleri için ortak ön-yüz
    └── turkey_dnsredir{,_alt1..6}.sh
```

Üzerinde çalışmak için `make` yapın ve daemon'u fazladan günlük için
`-v` ile çalıştırın. Küçük bir yerel yeniden üretici için
`.github/workflows/build.yml` içindeki "CLI parse yolu duman testi"
komutları iyi bir başlangıçtır. Hat üstü inceleme için:

```sh
sudo tcpdump -i any -n 'tcp port 443 or tcp port 80 or udp port 53'
```

## Katkı

Issue ve çekme istekleri memnuniyetle karşılanır. Büyük bir PR açmadan
önce kapsamını tartışmak için lütfen issue açın — proje dar kalmayı
tercih eder (Turkey fork bayrak yüzeyi); daha geniş üstakım
GoodbyeDPI'dan gelen özellikler bilerek kapsam dışında olabilir.

Birkaç kural:

- Kod saf C11 olsun; `libnetfilter_queue` ve `libmnl` dışında harici
  bağımlılık olmasın.
- Var olan stile uyun (4 boşluk girinti, `snake_case`, mümkün olduğunca
  `static`, başlık koruması `GBD_*_H`).
- Shell betikleri `shellcheck`'ten temiz geçmeli (CI bunu zorunlu kılar).
- systemd bağımlılığı sokmayın; proje bilerek dağıtımdan bağımsız.

## Lisans ve katkı sahipleri

**Apache-2.0** lisansı altında — [`LICENSE`](./LICENSE) ve
[`NOTICE`](./NOTICE) dosyalarına bakın.

Bu bağımsız bir yeniden uygulamadır; teknik ve komut satırı tasarımının
kredisi şunlara aittir:

- **[GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI)** (ValdikSS) —
  üstakım Windows projesi, Apache-2.0.
- **GoodbyeDPI Turkey fork** — bu projenin hedeflediği bayrak
  kombinasyonlarını tanımlayan `.cmd` varyant kümesi.

Kullanılan Linux çekirdek alt sistemleri: `nfnetlink_queue` /
`xt_NFQUEUE`, ham soketler. Kütüphaneler: `libnetfilter_queue`
(GPL-2.0) ve `libmnl` (LGPL-2.1) — bu proje kütüphane sınırında
onlara bağlanır; yeniden dağıtım koşulları için ilgili kütüphane
lisansına bakın.

## Yasal uyarı

Bu araç paketlerinizin kabloya ne şekilde çıktığını değiştirir. Bu,
bulunduğunuz yasal bölgedeki yasalar, ISS kullanım şartları veya işyeri
ağ politikalarıyla etkileşebilir. Nasıl ve nerede çalıştırdığınızdan
yalnız siz sorumlusunuz. Yalnız sahibi olduğunuz veya kullanma izni
aldığınız ağlarda kullanın. Yazarlar kötüye kullanım için hiçbir
sorumluluk kabul etmez. Eğitim ve araştırma amaçlıdır.
