# Değişiklik Günlüğü

Bu projedeki önemli değişiklikler burada belgelenir.
Biçim [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)'u takip eder
ve proje [Anlamsal Sürümleme](https://semver.org/spec/v2.0.0.html)'ye uyar.

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
