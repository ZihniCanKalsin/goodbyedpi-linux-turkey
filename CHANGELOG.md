# Değişiklik Günlüğü

Bu projedeki önemli değişiklikler burada belgelenir.
Biçim [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)'u takip eder
ve proje [Anlamsal Sürümleme](https://semver.org/spec/v2.0.0.html)'ye uyar.

## [Yayımlanmadı]

### Eklenenler
- `scripts/service-install.sh` — etkileşimli menüyle bir varyant
  seçtirir, `/etc/systemd/system/goodbyedpi-linux.service` üretir,
  `enable --now` eder. Daemon önyüklemede otomatik başlar ve kullanıcı
  her seferinde terminal açmak zorunda kalmaz. Menü her varyantın ne
  yaptığını kısaca açıklar ve nereden başlanmasını önerir.
- `scripts/service-uninstall.sh` — yukarıdakinin karşılığı; servisi
  durdurur, birimi siler, iptables kurallarını temizler.
- `scripts/sanity-check.sh` — dağıtım-agnostik ortam denetimi.
  `/etc/os-release` ile dağıtımı ve çekirdeği raporlar; bash / gcc /
  make / pkg-config / iptables / ip6tables / conntrack / setsid /
  systemctl varlığını kontrol eder; `pkg-config --exists` ile
  `libnetfilter_queue` ve `libmnl` başlıklarını doğrular; NFQUEUE
  çekirdek modülünü ve `xt_NFQUEUE` iptables hedefini canlı test
  eder (root ile çalıştırıldığında); ipucu satırlarıyla her eksik
  parça için tam olarak ne kurulacağını söyler.

### Dağıtım-agnostik hâle getirme
- `scripts/deps-install.sh` artık 12 paket yöneticisini algılar:
  önceki 8'e ek olarak `dnf5` (Fedora 41+), `eopkg` (Solus), `swupd`
  (Clear Linux), `slackpkg` (Slackware) ve `nix`/`nix-env` (NixOS;
  deklaratif kullanım için öneri basar). Alpine üzerinde `bash`
  paketi açıkça eklenir (scriptler bash gerektirir). Arch'ta
  `iptables-nft` zaten kuruluysa `iptables` ile çakışmayı önlemek için
  atlanır.
- `iptables-up.sh` IPv4 NAT/DNAT eklenmesi başarısız olursa (nadir:
  `iptable_nat` çekirdek modülü eksik) sert hata vermek yerine uyarı
  yazıp devam ediyor; DPI atlatma rolleri korunur, kullanıcı DNS'i
  elle yönetir.
- README'de yeni **Desteklenen dağıtımlar** bölümü ve minimum
  bağımlılık tablosu; quickstart tek bir `deps-install + make`
  blokuyla başlar ve bir şey yanlış giderse `sanity-check` adımına
  yönlendirir.
- `tcp_mangle.c`: TLS ClientHello / HTTP isteği sınıflandırmasında artık
  `max_payload_size` kapısı uygulanmıyor. Üstakımda bu kapı yalnızca
  WinDivert filtresinde bir performans kısayoludur ve gerçek TLS/HTTP
  başlığı olan paketler boyuttan bağımsız olarak geçer. Chrome'un
  post-quantum `key_share` taşıyan ~1500 bayt ClientHello'su 1200 eşiğini
  aşıp atlanıyordu; artık atlanmıyor, Chrome ile SNI-engelli sitelere
  (örn. `discord.com`) erişim çalışıyor.

### Düzeltilenler
- **DNS yönlendirmesi artık gerçekten çalışıyor.** 0.1.0'da UDP/53 kuralı
  NFQUEUE üzerinden yeniden yazma yapıyordu; ancak çekirdek rota aramasını
  paket netfilter kancasına girmeden önce yaptığı için, `127.0.0.53`
  (systemd-resolved sapı) hedefli bir sorgunun hedefini Yandex'e çevirmek
  paketi yine loopback arabiriminden çıkarmaya çalışıyor ve düşürüyordu —
  Türkiye ISS testinde gerçek dünyada `curl https://discord.com/`
  `Could not resolve host` ile başarısız olurdu. Yönlendirme artık
  `iptables -t nat OUTPUT … -j DNAT` üzerinden yapılıyor (pre-routing;
  conntrack cevap yolunu tersine çevirir) ve `127.0.0.0/8` / `::1/128`
  hedefleri hariç tutuluyor ki yerel sap çalışmaya devam etsin. SNI-engelli
  etki alanları (ör. `discord.com`), `sudo scripts/turkey_dnsredir.sh`
  çalıştırıldığında artık düz `curl` / tarayıcıdan ulaşılabilir durumda.
- `scripts/iptables-up.sh` içindeki `add_rule` artık `-t TABLE` önekini
  komut fiilinden önce koruyor; iptables 1.8+ yalnızca o sırayı kabul
  ediyor.
- `scripts/iptables-down.sh` NAT/OUTPUT üzerindeki DNS DNAT kurallarını
  ve artık-DNAT'lı UDP conntrack girdilerini de temizliyor.

## [0.1.0] - 2026-04-17

### Eklenenler
- İlk sürüm.
  [GoodbyeDPI Turkey fork](https://github.com/ValdikSS/GoodbyeDPI)'unun
  özellik yüzeyinin Linux üzerinde sıfırdan C ile yeniden uygulanması;
  WinDivert yerine NFQUEUE + ham soketler kullanır.
- `-5` ve `-9` ön ayarları, üstakım bayrak açılımlarıyla eşleşir.
- `-f`, `-e`, `--auto-ttl`, `--reverse-frag`, `--wrong-seq`,
  `--wrong-chksum`, `--max-payload`, `--set-ttl`, `-q` için tek tek bayrak
  desteği.
- Giden TLS ClientHello ve HTTP isteklerinin ayarlanabilir bir bayt
  konumundan, isteğe bağlı olarak ters sırada bölünmesi.
- Yanlış TCP sıra numarası ve/veya yanlış sağlama toplamıyla ve
  çağıranın seçtiği düşük TTL / atlama limitiyle sahte tuzak TCP segmenti
  enjeksiyonu.
- IPv4 (`--dns-addr`/`--dns-port`) ve IPv6 (`--dnsv6-addr`/`--dnsv6-port`)
  üzerinden şeffaf DNS yönlendirmesi; cevap yolundaki ters-yazım sabit
  boyutlu `(kaynak, txid)` hashmap'i üzerinden yapılır.
- `-q` ve `-9` altında QUIC / UDP-443 engelleme.
- Windows Turkey fork'unun `.cmd` dosyalarıyla 1:1 eşleşen yedi
  başlatıcı script (`scripts/turkey_dnsredir*.sh`).
- `setsid` ve PID dosyası üzerinden daemon hâline getiren, dağıtımdan
  bağımsız arka plan kurulum / kaldırma yardımcıları (systemd bağımlılığı
  yok).
- `--queue-bypass` ile bir çökmenin açıkta arızalanmasını sağlayan
  idempotent `scripts/iptables-up.sh` / `iptables-down.sh`.
- `apt-get`, `dnf`, `yum`, `pacman`, `zypper` ve `apk` algılayan
  `scripts/deps-install.sh`.

### Bilinen sınırlar
- `--auto-ttl` bir sezgidir (`--set-ttl` verilmemişse sabit atlama
  limiti 4); üstakım DPI ara kutusuna olan mesafeyi ölçmek için aktif
  ağ sondalaması yapar.
- `--max-payload` bir no-op düğmedir. NFQUEUE yolu zaten ClientHello /
  HTTP fiili tespitine dayandığından atlanacak bir şey yoktur.
- Gerçek bir Türkiye ISS DPI ara kutusu karşısında uçtan uca
  doğrulanmadı. Paket seviyesindeki davranış yerel bir duman testinde
  doğrulandı (NFQ bağlama, ön ayar açma, temiz kural sökme); gerçek
  dünya etkisinin ağ üzerinde doğrulanması gerekir.
