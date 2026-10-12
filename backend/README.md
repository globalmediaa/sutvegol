# Şut ve Gol — Backend kurulumu

Docker (PHP/Apache uygulama + MySQL) host Nginx'in arkasında, Cloudflare proxy'si önünde çalışır. Alan adı `sutvegol.gmgaming.app`; API `/api`, yönetim `/admin`, tanıtım `/` (kaynak: depo kökündeki `docs/`, GitHub Pages ile ortak), gizlilik `/privacy`, hesap silme `/account-deletion`.

Sunucuya ait her şey `backend/` altındadır: `compose.yaml`, `Dockerfile`, `deploy/` (deploy.sh, maintenance.sh, apache/php ayarları) ve sunucuda üretilen `.env`, `secrets/`, `.deploy-backups/`. Oyun klasörlerine dokunulmaz.

**Diğer konteynerler etkilenmez:** Compose projesi sabit `sutvegol` adlıdır (`sutvegol-app-1`, `sutvegol-db-1`, `sutvegol_default` ağı, `sutvegol_db_data` volume'ü). Uygulama yalnız `127.0.0.1:12883` portunda dinler, MySQL dışa açılmaz, bellek limitlidir. Script prune / `down -v` / volume silme çalıştırmaz; yalnız kendi Nginx site dosyasını yazar ve önce `nginx -t` ile doğrular, hata olursa eski haline döner.

## Sunucuda bir kerelik hazırlık

1. **Gereksinimler:** Docker + Compose v2 (`docker compose version`), git, curl, openssl. Deploy kullanıcısı `docker` grubunda olmalı (`sudo usermod -aG docker $USER`, sonra yeniden bağlan). Nginx adımı için sudo gerekir.
2. **Cloudflare SSL modu:** `sutvegol.gmgaming.app` için **Full (strict)**. Zone'daki diğer siteler farklı modda çalışıyorsa zone ayarını değiştirme; Rules → Configuration Rules ile yalnız bu hostname için SSL = Full (strict) kuralı ekle. (Flexible modda Nginx'in 80→443 yönlendirmesi sonsuz döngü yapar.)
3. **Origin sertifikası:** Cloudflare → SSL/TLS → Origin Server → Create Certificate (hostname `sutvegol.gmgaming.app`, PEM). Sunucuya yerleştir:
   ```bash
   sudo mkdir -p /etc/ssl/cloudflare
   sudo nano /etc/ssl/cloudflare/sutvegol.gmgaming.app.pem   # Origin Certificate
   sudo nano /etc/ssl/cloudflare/sutvegol.gmgaming.app.key   # Private Key
   sudo chmod 600 /etc/ssl/cloudflare/sutvegol.gmgaming.app.key
   ```
   Sunucuda zaten `*.gmgaming.app` sertifikası varsa onu kullanmak için ilk deploy'dan sonra `backend/.env` içine `SSL_CERT=` / `SSL_KEY=` yollarını yaz. `/etc/letsencrypt/live/sutvegol.gmgaming.app/` varsa o da otomatik bulunur.
4. **Port:** 12883 doluysa ilk deploy'dan sonra `backend/.env` içinde `APP_PORT`'u değiştir; Nginx otomatik güncellenir. Güvenlik duvarında yeni port açmaya gerek yok (yalnız 80/443).

## İlk kurulum

Sunucuya yalnız `backend/` ve `docs/` çekilir (oyun kodu inmez):

```bash
mkdir -p ~/games && cd ~/games
git clone --filter=blob:none --sparse git@github.com:globalmediaa/sutvegol.git sutvegol
cd sutvegol
git sparse-checkout set backend docs
bash backend/deploy/deploy.sh
curl -fsS https://sutvegol.gmgaming.app/api/health
```

İlk çalıştırma `backend/.env` dosyasını rastgele `APP_KEY` ve veritabanı parolalarıyla üretir (chmod 600). **Bu üç değeri sonradan değiştirme**; MySQL volume'ü ilk parolayla oluşur. Script ayrıca kullanıcının crontab'ına her gece 03:17 yedek + temizlik satırı ekler (`deploy/maintenance.sh`, yedekler 28 gün).

## Güncelleme

```bash
cd ~/games/sutvegol && bash backend/deploy/deploy.sh
```

Sırasıyla: kilit → `git pull --ff-only` → imaj derleme → MySQL hazır → SQL yedeği (`backend/.deploy-backups/`) → eklemeli migration'lar → uygulama yeniden başlatma → `/api/health`. Yeni sürüm sağlık kontrolünü geçemezse önceki imaja otomatik döner. Seçenekler: `--no-pull`, `--skip-nginx`, `--print-nginx` (yalnız üretilecek Nginx dosyasını gösterir).

Yedekten dönüşte son yedekten sonraki hesap silme taleplerini yeniden uygula.

## Girişler ve yönetim

- **Apple iOS:** Bundle `com.globalmedia.sutVeGol`, team `Y2MWRALQHR`, Sign in with Apple capability açık olmalı. Uygulama kimlik token'ı imza/issuer/audience/expiry ve tek kullanımlık nonce ile doğrulanır. Apple girişinin kendisi `.p8` istemez. Hesap silmede Apple yetkisini geri almak için `backend/.env` `APPLE_KEY_ID`, `APPLE_TEAM_ID` ve bu uygulamaya yetkili özel anahtar `backend/secrets/apple_key.p8` gereklidir. Anahtarı güvenli sunucu kanalıyla yerleştir; WhatsApp/git üzerinden paylaşma. Konteynerdeki www-data okuyabilsin: `sudo chgrp 33 backend/secrets backend/secrets/apple_key.p8 && chmod 640 backend/secrets/apple_key.p8` (deploy.sh parolasız sudo varsa bunu kendisi yapar). Dosya read-only mount edilir, imaja alınmaz.
- **Google:** Bu uygulamaya ait iOS ve Web OAuth client ID'lerini `backend/.env` `GOOGLE_CLIENT_IDS` alanına virgülle yaz. İstemci ID'si gizli anahtar değildir; client secret kullanılmaz. iOS ID ve Web ID'yi Hızır’a ilet; Flutter build `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_SERVER_CLIENT_ID` ve `ios/Flutter/Social.xcconfig` ters callback şemasıyla yeniden derlenir. Başka uygulamanın client ID'sini kullanma. Android için paket/SHA-1 ayrıca yapılandırılır.
- **E-posta:** Sunucu sonrası kayıt/giriş aktiftir; mail doğrulama veya parola sıfırlama servisi mevcut kapsamda yoktur.
- **Admin:** E-posta `info@globalmedia.com.tr`. Parolayı terminalde interaktif okuyarak hash üret: `cd ~/games/sutvegol/backend && docker compose -p sutvegol exec app php -r '$p=rtrim(fgets(STDIN)); echo password_hash($p,PASSWORD_DEFAULT),PHP_EOL;'`. Hash'i `backend/.env` `ADMIN_PASSWORD_HASH` içine **tek tırnakla** yaz (dolar işaretlerini Compose değiştirmesin). Ardından `bash backend/deploy/deploy.sh`. Admin yoksa alanı boş bırak, boş hash girişe izin vermez.

## Rokas ile aynı GitHub Actions akışı

`.github/workflows/deploy.yml`, **prod push** üzerine Hetzner'a SSH ile bağlanır, `~/games/sutvegol` altında ff-only pull + `backend/deploy/deploy.sh --no-pull` çalıştırır. Nginx adımı yalnız parolasız sudo varsa çalışır, yoksa atlanır. Aynı Hetzner/Rokas secret düzeni:

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
