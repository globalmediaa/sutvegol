# Şut ve Gol — Backend kurulumu

Docker (PHP/Apache uygulama + MySQL) host Nginx'in arkasında, Cloudflare proxy'si önünde çalışır. Alan adı `sutvegol.gmgaming.app`; API `/api`, yönetim `/admin`, tanıtım `/` (kaynak: depo kökündeki `docs/`, GitHub Pages ile ortak), gizlilik `/privacy`, hesap silme `/account-deletion`.

Sunucuya ait her şey `backend/` altındadır: `compose.yaml`, `Dockerfile`, `deploy/` (deploy.sh, maintenance.sh, apache/php ayarları) ve sunucuda üretilen `.env`, `secrets/`, `.deploy-backups/`. Oyun klasörlerine dokunulmaz.

**Diğer konteynerler etkilenmez:** Compose projesi sabit `sutvegol` adlıdır (`sutvegol-app-1`, `sutvegol-db-1`, `sutvegol_default` ağı, `sutvegol_db_data` volume'ü). Uygulama yalnız `127.0.0.1:12883` portunda dinler, MySQL dışa açılmaz, bellek limitlidir. Script prune / `down -v` / volume silme çalıştırmaz; yalnız kendi Nginx site dosyasını yazar ve önce `nginx -t` ile doğrular, hata olursa eski haline döner.

## Sunucuda bir kerelik hazırlık

1. **Gereksinimler:** Docker + Compose v2 (`docker compose version`), git, curl, openssl. Deploy kullanıcısı `docker` grubunda olmalı (`sudo usermod -aG docker $USER`, sonra yeniden bağlan). Nginx adımı için sudo gerekir.
2. **Cloudflare SSL modu:** `sutvegol.gmgaming.app` için **Full (strict)**. Zone'daki diğer siteler farklı modda çalışıyorsa zone ayarını değiştirme; Rules → Configuration Rules ile yalnız bu hostname için SSL = Full (strict) kuralı ekle. (Flexible modda Nginx'in 80→443 yönlendirmesi sonsuz döngü yapar.)
3. **SSL sertifikası otomatik:** deploy.sh sertifika bulamazsa certbot ile Let's Encrypt sertifikası alır (`certbot certonly --webroot -w /var/www/letsencrypt`, e-posta `ADMIN_EMAIL`). certbot Nginx dosyalarına dokunmaz; yenileme mevcut certbot timer'ı ile olur, sonrasında Nginx reload edilir. Önce doğrulama yolunu Cloudflare üzerinden kendisi dener; ulaşmıyorsa Let's Encrypt'i hiç denemez. Cloudflare "Always Use HTTPS" açıksa ilk sertifika için geçici kapat. 443 portunu Nginx dışında bir süreç (ör. host'ta Caddy) tutuyorsa hiçbir şeye dokunmadan durur. Elle sertifika kullanmak istersen `backend/.env` içine `SSL_CERT=` / `SSL_KEY=` yaz (ör. Cloudflare Origin Certificate).
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

Olağan yol GitHub Actions'tır (aşağıda, Canlıya dağıtım). Sunucuda elle:

```bash
cd ~/games/sutvegol && bash backend/deploy/deploy.sh
```

Sırasıyla: kilit → `git pull --ff-only` → imaj derleme → MySQL hazır → SQL yedeği (`backend/.deploy-backups/`) → eklemeli migration'lar → uygulama yeniden başlatma → `/api/health`. Yeni sürüm sağlık kontrolünü geçemezse önceki imaja otomatik döner. Seçenekler: `--no-pull`, `--skip-nginx`, `--print-nginx` (yalnız üretilecek Nginx dosyasını gösterir).

Yedekten dönüşte son yedekten sonraki hesap silme taleplerini yeniden uygula.

## Girişler ve yönetim

- **Apple iOS:** Bundle `com.globalmedia.sutVeGol`, team `Y2MWRALQHR`, Sign in with Apple capability açık olmalı. Uygulama kimlik token'ı imza/issuer/audience/expiry ve tek kullanımlık nonce ile doğrulanır. Apple girişinin kendisi `.p8` istemez. Hesap silmede Apple yetkisini geri almak için `backend/.env` `APPLE_KEY_ID`, `APPLE_TEAM_ID` ve bu uygulamaya yetkili özel anahtar `backend/secrets/apple_key.p8` gereklidir. Anahtarı güvenli sunucu kanalıyla yerleştir; WhatsApp/git üzerinden paylaşma. Konteynerdeki www-data okuyabilsin: `sudo chgrp 33 backend/secrets backend/secrets/apple_key.p8 && chmod 640 backend/secrets/apple_key.p8` (deploy.sh parolasız sudo varsa bunu kendisi yapar). Dosya read-only mount edilir, imaja alınmaz. Otomatik yol: `SUTVEGOL_APPLE_KEY_ID` + `SUTVEGOL_APPLE_PRIVATE_KEY_B64` secret'ları (aşağıda, Canlıya dağıtım).
- **Google:** Bu uygulamaya ait iOS ve Web OAuth client ID'lerini `backend/.env` `GOOGLE_CLIENT_IDS` alanına virgülle yaz. Otomatik yol: `SUTVEGOL_GOOGLE_CLIENT_IDS` secret'ı (aşağıda). İstemci ID'si gizli anahtar değildir; client secret kullanılmaz. iOS ID ve Web ID'yi Hızır’a ilet; Flutter build `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_SERVER_CLIENT_ID` ve `ios/Flutter/Social.xcconfig` ters callback şemasıyla yeniden derlenir. Başka uygulamanın client ID'sini kullanma. Android için paket/SHA-1 ayrıca yapılandırılır.
- **E-posta:** Sunucu sonrası kayıt/giriş aktiftir; mail doğrulama veya parola sıfırlama servisi mevcut kapsamda yoktur.
- **Admin:** E-posta `info@globalmedia.com.tr`. Parolayı ayarlamak/değiştirmek için `bash backend/deploy/admin-password.sh`: parolayı iki kez sorar, hash'i konteynerdeki PHP ile üretip `backend/.env` `ADMIN_PASSWORD_HASH` alanına tek tırnakla yazar, uygulamayı yeniden başlatır ve eşleştiğini doğrular. Admin yoksa alanı boş bırak, boş hash girişe izin vermez.

## Oyuncu güvenliği (build 13, App Store 1.2)

Kullanıcı adları rakiplere, kayıtlı rakip koşusunda ve sıralamada görünür; kural tek yerde: `backend/src/moderation.php`.

- **Filtre:** kayıt, `PUT /v1/me/username` (sosyal girişte ad seçimi) ve `GET /v1/username/check` aynı kuralı kullanır (`username_issue`). TR+EN küfür/hakaret/cinsel/nefret listesi + taklit (admin, moderator, apple, google, sutvegol, destek, resmi…). Küçük harf, Türkçe harf katlama, leet (0→o 1→i/l 3→e 4→a 5→s 7→t, @→a $→s), alt çizgi/rakam ayıklanmış ve uç rakamsız biçimler denenir; kısa kelimeler yalnız bütün parça olarak eşleşir (ışık, sikke, seksen, nazım, badminton geçer). Ret: 422 `username_not_allowed` + Türkçe mesaj; check yanıtı `allowed:false`, `code`, `message` (eski istemci `available:false` görür). Yöneticinin yasakladığı adlar (`name_bans`: tam + normal biçim) da reddedilir. Filtreye takılan eski adlar başkalarına `Oyuncu#XXXX` görünür.
- **Şikâyet:** `POST /v1/report` (oturum) `{target_user_id, reason: username|cheating|other, context: duel|ghost|leaderboard, duel_id?, note?}`; not ≤ 200 karakter. Kendini şikâyet 422, hedef silinmişse 410 `player_gone`, aynı kişi → aynı hedef tek kayıt (tekrar günceller; reddedilmiş şikâyet aynı ad + sebeple yeniden açılmaz), kişi başı 24 saatte 20 yeni şikâyet (429 `report_limit`). `duel_id` verilirse şikâyet eden o maçta olmalı, hedef rakip ya da kayıtlı koşunun sahibi (`ownerId`) olmalı. Aynı (mevcut) ada 3 farklı kişiden açık `username` şikâyeti → yönetici karar verene kadar başkalarına `Oyuncu#XXXX` (sıralama, düello rakibi, ghost).
- **Engelleme:** `POST /v1/blocks {user_id}`, `DELETE /v1/blocks/{user_id}`, `GET /v1/blocks` (en çok 500). Canlı kuyruk, rövanş ve kayıtlı rakip havuzu iki yönlü engeli dikkate alır; sıralama ve düello yanıtında engellenen engelleyene `Engellenen oyuncu` (`blocked: true`). `DELETE /v1/me` şikâyet/engel kayıtlarını siler, `name_bans` kişiden ayrılır; 3 şikâyetle gizlenmiş ad kişisiz yasak listesine girer.
- **Yönetici (`/admin`, CSRF korumalı):** açık şikâyetler hedef başına (sebep, kişi sayısı, bağlam, zaman, notlar; 24 saati geçen kırmızı). Eylemler: Reddet, Yeniden adlandır (eski ad `name_bans`'a, kullanıcı `oyuncu_NNNN`), Askıya al (giriş 403 `account_suspended`, oturumlar düşer, kuyruk/ghost/sıralama dışı), Askıyı kaldır.
- **Kullanım koşulları:** kayıt ve ad seçimi `termsVersion` gönderir; `users.terms_version` / `terms_accepted_at` saklanır, `/v1/me` `termsVersion` döner. Metin: `docs/terms.html` (GitHub Pages ve `/terms`).
- **Migration:** `database/migrations/20261013_moderation.sql` (`user_reports`, `user_blocks`, `name_bans`, users'a iki NULL sütun; idempotent, yalnız eklemeli, `utf8mb4_unicode_ci`), compose initdb 05. Testler: `php backend/tests/moderation_unit_test.php [--table]` (filtre yanlış pozitif/negatif tablosu), `SV_PHP=… python3 backend/tests/moderation_test.py` (canlıdaki gibi `utf8mb4_0900_ai_ci` varsayılanlı yeni test DB + ikinci `php -S` ile yönetim paneli).

## Canlıya dağıtım: Halk deposundan workflow_dispatch (13 Ekim 2026)

Bu depoda Hetzner secret'ları yok. Deploy, aynı sunucuya zaten bağlanan `globalmediaa/pazarci-esnaf` deposundaki `.github/workflows/deploy-sutvegol.yml` ile elle tetiklenir: yalnız `workflow_dispatch`, input `ref` (bu deponun dalı, varsayılan `prod`). Oradaki `HETZNER_HOST`, `HETZNER_USER`, `HETZNER_SSH_KEY` kullanılır; `HETZNER_FINGERPRINT` orada da yok, host anahtarı Halk'ın kendi deploy'undaki gibi doğrulanmaz. Halk Pazarı'na dokunulmaz.

```bash
git push origin master:prod   # prod'u master'dan normal push ile güncelle (force yok)
gh workflow run deploy-sutvegol.yml -R globalmediaa/pazarci-esnaf -f ref=prod
gh run list -R globalmediaa/pazarci-esnaf -w deploy-sutvegol.yml -L 1
```

Akış: runner `ref`'in bu depoda dal olarak var olduğunu doğrular → SSH ile `cd ~/games/sutvegol` → izlenen dosyalarda yerel değişiklik varsa durur → yalnız o dalı `git fetch` eder → yerel dal yoksa `origin/<ref>`'ten açar → `git switch` → `git pull --ff-only` (sunucuda ayrışmış commit varsa durur; force/reset yok) → `bash backend/deploy/secrets_env.sh` → secret değişkenlerini `unset` → `bash backend/deploy/deploy.sh --no-pull`. Sonuç Telegram'a (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_IDS` varsa) "sutvegol" başlığıyla gider. Nginx adımı yalnız parolasız sudo varsa çalışır, yoksa atlanır. Prod'da master'da olmayan commit varsa force push yapılmaz; önce korunarak birleştirilir.

Giriş ayarları pazarci-esnaf Actions secret'larındadır; değerleri mesaja, dosyaya ya da loga yazma (`gh secret set` değeri stdin'den okur):

| Secret | Sunucudaki hedef |
|---|---|
| `SUTVEGOL_GOOGLE_CLIENT_IDS` | `backend/.env` `GOOGLE_CLIENT_IDS`: bu uygulamanın iOS + Web client ID'leri, virgüllü |
| `SUTVEGOL_APPLE_KEY_ID` | `backend/.env` `APPLE_KEY_ID`: 10 karakterlik Key ID |
| `SUTVEGOL_APPLE_PRIVATE_KEY_B64` | `backend/secrets/apple_key.p8`: P-256 `.p8` dosyasının tek satır base64'ü |

```bash
base64 < AuthKey_XXXXXXXXXX.p8 | tr -d '\n' | gh secret set SUTVEGOL_APPLE_PRIVATE_KEY_B64 -R globalmediaa/pazarci-esnaf
gh secret set SUTVEGOL_APPLE_KEY_ID -R globalmediaa/pazarci-esnaf        # değeri sorar
gh secret set SUTVEGOL_GOOGLE_CLIENT_IDS -R globalmediaa/pazarci-esnaf   # ios-id,web-id
```

`secrets_env.sh` kuralları: boş ya da tanımsız secret hiçbir satırı/dosyayı silmez; geçersiz değer (Google ID biçimi, Key ID, P-256 olmayan ya da PEM olmayan anahtar) `::warning::` ile atlanır ve deploy sürer; değerler yazdırılmaz. `.env` yerinde yazılır (izin ve sahiplik korunur), etkin değer zaten aynıysa dosyaya dokunulmaz, ilk değişiklikten önce bir kez `backend/.env.pre-oauth` (600) yedeği alınır. Anahtar aynıysa yeniden yazılmaz; deploy.sh'ın beklediği gibi `secrets/` 750, `apple_key.p8` 640 ve ikisinin grubu 33 (konteynerdeki www-data). Grup sırasıyla `chgrp` → `sudo -n chgrp` → yerel `sutvegol-app` imajıyla çekmeden ve ağsız `docker run … chgrp` ile verilir (deploy kullanıcısı zaten docker grubunda); hiçbiri olmazsa dosya 600 kalır ve elle komut uyarısı çıkar. `backend/.env` yoksa (ilk kurulum) .env adımı atlanır, değerler bir sonraki deploy'da yazılır. Yerel test (sahte .env + sahte P-256 anahtar, gerçek sudo/docker çağrılmaz): `bash backend/tests/secrets_env_test.sh`.

### Bu depodaki `.github/workflows/deploy.yml` neden çalışmıyor

Rokas düzeninde **prod push** ile tetiklenir ve `HETZNER_HOST`, `HETZNER_USER`, `HETZNER_SSH_KEY`, `HETZNER_FINGERPRINT` secret'larını **bu depoda** bekler. Bu secret'lar burada tanımlı değil (organization secret'ı da açılmadı); bu yüzden her prod push'unda çalışır ama SSH adımında "missing server host" hatasıyla düşer. Sunucuya dokunmaz, yalnız kırmızı bir run bırakır. Secret'lar ileride bu depoya eklenirse diye silinmedi; eklenirse iki workflow aynı prod'u deploy eder (sunucudaki `.deploy.lock` aynı anda çalışmayı engeller), o zaman birini kapat. Kırmızı run istenmezse: `gh workflow disable deploy.yml -R globalmediaa/sutvegol`.

## Düello / test / sınırlar

Düello v2 (protokol `duelVersion` 2): 90 saniye ortak kronometre, **can yok** (ıskalama yalnız combo'yu sıfırlar), şut başına 5 sn şut saati (dolarsa otomatik ıskalama), gol 30 × combo (x1→x3; Kral Modu x2), gerçek oyuncu kuyruğu (15 sn sonra kayıtlı rakip / CPU), 6 saniyelik başlama payı. Rakip üstte, oyuncu altta. Şut akışı 700 ms sorgu ile, hata halinde 2/4/8 saniye geri çekilerek aktarılır; sıradan çıkış rakibe galibiyet verir. Ağ hatasında kuyruk sınırlı tutulur, tekrar olaylar idempotent, skor ve sonuç sunucuda kaydedilir. Süre sunucudan belirlenir; arka plana almak süreyi durdurmaz. Tek kişilik sıralama ayrı tutulur.

Fizik şut atan cihazda hesaplanır; sunucu şema, sıra, skor/combo matematiği, zaman ve maç nonce'u doğrular. Her şut vuruş (`t`) ve sonuçlanma (`rt`) anını taşır: Kral Modu `rt` ile işler, şut saati önceki `rt`'den ölçülür (sahne geçişinde +4 sn), `t` maç saatinin en çok 12 sn gerisinde olabilir, n. şut t ≥ (n−1)×1,5 sn. Reddedilen şuttan önceki şutlar kalıcı olur; 422 gövdesi `seq` ve `acceptedSeq`, snapshot `me` durumu taşır, istemci reddedileni düşürüp yeniden hizalanır. Rating için iki tarafın da en az bir şutu gerekir. Bu sürümde tam sunucu fizik doğrulaması veya ödüllü rekabet yoktur.

Doğrulama: `flutter analyze`, `flutter test`; gerçek PHP/MySQL testleri `SV_PHP=/path/to/php8.4 python3 backend/tests/duel_test.py`. Her backend testi yeni `sutvegol_test_*` veritabanı oluşturur; mevcut DB drop edilmez. Docker testi ayrı `sutvegol_verify` proje adıyla yapılır. Canlıya çıkmadan iki TestFlight hesabıyla aynı anda eşleşme, arka plana alma, çıkış, şut saati ıskası, 90 saniye sonuç ve hesap silme kontrol edilmeli. Telefon pil/ısı ölçümü yalnız fiziksel cihazda doğrulanabilir.

8 Ekim 2026 doğrulaması: 23 Flutter testi + lint, 4 PHP/MySQL senaryosu ve aynı 4 senaryo Docker Apache/MySQL üzerinde geçti. Nginx sözdizimi resmî Nginx imajında geçti; 320 px web görünümünde yatay taşma yok. Alan adı henüz DNS’te çözülmüyor. Apple Developer Sign in with Apple yetkisi Samet’in onayıyla açıldı ve mevcut Şut ve Gol App Store dağıtım profili aynı sertifikayla yenilendi; imza entitlements kontrolü geçti. Google client ID’ler ve organization Actions secret erişimi kurulumdan sonra tamamlanacak.

TestFlight teslimi: 1.0.0(9) Transporter 8 Ekim 2026 17:57 TR ile gönderildi; Apple processing tamamlandı, Testciler dahili grubu (8 testçi) ve Türkçe test notu kaydedildi. Online özelliklerin fiziksel iki telefon testi Emre’nin HTTPS API kurulumundan sonra yapılacak; App Review gönderilmedi.
