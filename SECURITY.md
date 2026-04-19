# Güvenlik

## Güvenlik açıklarını bildirme

`goodbyedpi-linux-turkey` ağ paketlerini kullanıcı alanında manipüle
eden `root` (veya `CAP_NET_ADMIN + CAP_NET_RAW`) yetkili bir daemon
çalıştırır. Bu yüzden standart uygulama güvenlik açıklarından farklı
olarak uzaktan kötü amaçlı bir TCP/DNS paketi ile tetiklenebilecek
**çekirdek yakın** hatalar yüksek önceliklidir.

Sorumlu açıklama için:

- **Kamuya açık** genel hatalar / iyileştirmeler →
  [GitHub Issues](https://github.com/OWNER/goodbyedpi-linux-turkey/issues).
- **Doğrudan güvenlik raporları** →
  [GitHub güvenlik açığı raporu](https://github.com/OWNER/goodbyedpi-linux-turkey/security/advisories/new)
  (özel repo öncesi koordineli açıklama imkânı sağlar).

Lütfen herkese açık issue açmadan önce aşağıdaki türleri doğrudan
özelden bildirin:

- Uzaktaki bir sunucudan gönderilen paketle daemon'u çöktürmek /
  uzaktan kod çalıştırmak.
- Raw soket enjeksiyonunda başka bir kullanıcının trafiğine müdahale
  etmeyi mümkün kılan bir mantık hatası.
- DNS yeniden-yönlendirme tablosunda zehirleme veya kaçış.

## Desteklenen sürümler

Yayımlanan en son `main` sürümü desteklenir. Eski etiket sürümleri için
güvenlik yamaları yapılmaz; güncel kalmak tavsiye edilir.

## Kapsam dışı

- Sistem yöneticisinin DPI atlatma amacıyla kasıtlı olarak iptables
  kurallarını gevşettiği durumlar (ör. VPN ara yüzündeki kuralların
  bozulması) — bu aracın *varlık sebebi* bu gevşetmedir.
- Windows / WinDivert üstakımındaki hatalar — üstakıma (ValdikSS /
  cagritaskn fork'u) bildirin.
- **Kötüye kullanım**: bu aracın sahibi olmadığınız ağlarda DPI
  atlatmak için kullanılması, yasal meseledir ve güvenlik hatası
  değildir. Bkz. README'deki Yasal uyarı bölümü.
