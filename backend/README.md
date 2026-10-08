# Şut ve Gol — Emre kurulum paketi

Docker uygulama + MySQL; **Nginx sunucuda mevcut**, yeni Nginx container'ı yok. Alan adı `sutvegol.gmgaming.app`; API `/api`, yönetim `/admin`, tanıtım `/`, gizlilik `/privacy`, hesap silme `/account-deletion`. Uygulama yalnız `127.0.0.1:12883` portunda dinler, MySQL dışa açılmaz. Port başka serviste kullanılıyorsa `.env` APP_PORT ve Nginx upstream birlikte değiştirilir.

## İlk kurulum — Emre’ye kopyalanacak blok

DNS A/AAAA kayıtları bu sunucuyu göstermeli. Docker Compose v2, Python 3, OpenSSL, curl ve host Nginx kurulu olmalı. Depoyu çekmek için mevcut GitHub erişimini kullan:

```bash
mkdir -p ~/games
cd ~/games
git clone https://github.com/globalmediaa/sutvegol.git sutvegol
cd sutvegol
git fetch origin
# İlk kurulum master'dan; Hızır prod'u hazırladığında prod'a geç.
git switch master
umask 077
cp deploy/env.example .env
python3 - <<'PY'
from pathlib import Path
import secrets
p=Path('.env')
s=p.read_text()
for name in ['APP_KEY','DB_PASSWORD','DB_ROOT_PASSWORD']:
    s=s.replace(name+'=\n',name+'='+secrets.token_hex(32)+'\n')
p.write_text(s)
p.chmod(0o600)
PY
mkdir -p secrets
chmod 750 secrets
sudo chgrp 33 secrets
# Aşağıdaki OAuth ve admin ayarlarını .env içinde tamamla.
bash update.sh
sudo cp deploy/nginx.conf /etc/nginx/sites-available/sutvegol.gmgaming.app
sudo ln -s /etc/nginx/sites-available/sutvegol.gmgaming.app /etc/nginx/sites-enabled/sutvegol.gmgaming.app
sudo nginx -t && sudo systemctl reload nginx
# Sunucunun mevcut Let's Encrypt/Certbot kurulumu ile SSL:
sudo certbot --nginx -d sutvegol.gmgaming.app
curl -fsS https://sutvegol.gmgaming.app/api/health
# Günlük özel yedek, 30 gün saklama ve eski geçici kayıt temizliği:
(crontab -l 2>/dev/null | sed '\|games/sutvegol/deploy/maintenance.sh|d'; echo '17 3 * * * /bin/bash "$HOME/games/sutvegol/deploy/maintenance.sh" >> "$HOME/games/sutvegol/.deploy-backups/maintenance.log" 2>&1') | crontab -
```

Temiz kurulum MySQL volume'ü ilk açıldığında şemayı oluşturur. Sonraki dağıtımlar private SQL yedeğinden sonra yalnız eklemeli `IF NOT EXISTS` migrasyonlarını uygular. Mevcut volume silinmez. `.env` değerlerini ilk kurulumdan sonra tekrar üretme; parolayı dosyada değiştirmen mevcut MySQL parolasını değiştirmez. Yedekten dönüşte son yedekten sonraki hesap silme taleplerini yeniden uygula.

## Girişler ve yönetim

- **Apple iOS:** Bundle `com.globalmedia.sutVeGol`, team `Y2MWRALQHR`, Sign in with Apple capability açık olmalı. Uygulama kimlik token'ı imza/issuer/audience/expiry ve tek kullanımlık nonce ile doğrulanır. Apple girişinin kendisi `.p8` istemez. Hesap silmede Apple yetkisini geri almak için `.env` `APPLE_KEY_ID`, `APPLE_TEAM_ID` ve bu uygulamaya yetkili özel anahtar `secrets/apple_key.p8` gereklidir. Anahtarı güvenli sunucu kanalıyla yerleştir; WhatsApp/git üzerinden paylaşma. UID www-data okuyabilsin: `chmod 640 secrets/apple_key.p8`, dizin `750`, container'a uygun grup 33 (`sudo chgrp 33 secrets/apple_key.p8`). Dosya read-only mount edilir, imaja alınmaz.
- **Google:** Bu uygulamaya ait iOS ve Web OAuth client ID'lerini `.env` `GOOGLE_CLIENT_IDS` alanına virgülle yaz. İstemci ID'si gizli anahtar değildir; client secret kullanılmaz. iOS ID ve Web ID'yi Hızır’a ilet; Flutter build `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_SERVER_CLIENT_ID` ve `ios/Flutter/Social.xcconfig` ters callback şemasıyla yeniden derlenir. Başka uygulamanın client ID'sini kullanma. Android için paket/SHA-1 ayrıca yapılandırılır.
- **E-posta:** Sunucu sonrası kayıt/giriş aktiftir; mail doğrulama veya parola sıfırlama servisi mevcut kapsamda yoktur.
- **Admin:** E-posta `info@globalmedia.com.tr`. Parolayı terminalde interaktif okuyarak hash üret: `docker compose exec app php -r '$p=rtrim(fgets(STDIN)); echo password_hash($p,PASSWORD_DEFAULT),PHP_EOL;'`. Hash'i `.env` `ADMIN_PASSWORD_HASH` içine **tek tırnakla** yaz (dolar işaretlerini Compose değiştirmesin). Ardından `docker compose up -d app`. Admin yoksa alanı boş bırak, boş hash girişe izin vermez.

## Rokas ile aynı GitHub Actions akışı

`.github/workflows/deploy.yml`, **prod push** üzerine Hetzner'a SSH ile bağlanır, `~/games/sutvegol` altında ff-only pull + `update.sh` çalıştırır. Aynı Hetzner/Rokas secret düzeni:

- `HETZNER_HOST`, `HETZNER_USER`, `HETZNER_SSH_KEY`
- `HETZNER_FINGERPRINT`: sunucunun doğrulanmış SSH host fingerprint'i

Bu değerler şu an Şut ve Gol deposunda bulunmuyor. Mevcut organization secret'ları bu repoya açılmalı veya repo Settings → Secrets and variables → Actions'a eklenmeli. Değerleri mesaj/git dosyasına koyma. Mevcut Rokas deploy kullanıcısı aynı yetkili alıcıdır; yeni sunucu hesabı gerekli değildir.

İlk prod dağıtımından önce sunucuda `git switch prod` çalıştırılır. Samet'in akışı master'dan prod'u normal push ile günceller. Prod'da master'da olmayan commit varsa otomasyon force push yapmaz; önce korunarak birleştirilir. Bu depoda kurulum bitmeden prod tetiklenmez.

## Düello / test / sınırlar

90 saniye, 3 can, gerçek oyuncu kuyruğu, 6 saniyelik başlama payı. Rakip üstte, oyuncu altta. Şut akışı 700 ms sorgu ile, hata halinde 2/4/8 saniye geri çekilerek aktarılır; sıradan çıkış rakibe galibiyet verir. Ağ hatasında kuyruk sınırlı tutulur, tekrar olaylar idempotent, skor ve sonuç sunucuda kaydedilir. Süre sunucudan belirlenir; arka plana almak süreyi durdurmaz. Tek kişilik sıralama ayrı tutulur.

Fizik şut atan cihazda hesaplanır; sunucu şema, sıra, skor/can matematiği, zaman ve maç nonce'u doğrular. Bu sürümde tam sunucu fizik doğrulaması veya ödüllü rekabet yoktur.

Doğrulama: `flutter analyze`, `flutter test`; gerçek PHP/MySQL testleri `SV_PHP=/path/to/php8.4 python3 backend/tests/duel_test.py`. Her backend testi yeni `sutvegol_test_*` veritabanı oluşturur; mevcut DB drop edilmez. Docker testi ayrı `sutvegol_verify` proje adıyla yapılır. Canlıya çıkmadan iki TestFlight hesabıyla aynı anda eşleşme, arka plana alma, çıkış, 3 can, 90 saniye sonuç ve hesap silme kontrol edilmeli. Telefon pil/ısı ölçümü yalnız fiziksel cihazda doğrulanabilir.

8 Ekim 2026 doğrulaması: 23 Flutter testi + lint, 4 PHP/MySQL senaryosu ve aynı 4 senaryo Docker Apache/MySQL üzerinde geçti. Nginx sözdizimi resmî Nginx imajında geçti; 320 px web görünümünde yatay taşma yok. Alan adı henüz DNS’te çözülmüyor. Apple Developer Sign in with Apple yetkisi Samet’in onayıyla açıldı ve mevcut Şut ve Gol App Store dağıtım profili aynı sertifikayla yenilendi; imza entitlements kontrolü geçti. Google client ID’ler ve organization Actions secret erişimi kurulumdan sonra tamamlanacak.

TestFlight teslimi: 1.0.0(9) Transporter 8 Ekim 2026 17:57 TR ile gönderildi; Apple processing tamamlandı, Testciler dahili grubu (8 testçi) ve Türkçe test notu kaydedildi. Online özelliklerin fiziksel iki telefon testi Emre’nin HTTPS API kurulumundan sonra yapılacak; App Review gönderilmedi.
