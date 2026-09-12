# Şut ve Gol backend

PHP 8.1+, MySQL 8/MariaDB 10.5+ ve Composer gerekir. Web kökü `public/`, yönetim paneli kökü `admin/` olmalıdır; `.env` ve `vendor` web kökünün dışında tutulur.

1. `composer install --no-dev --classmap-authoritative`
2. `database/schema.sql` dosyasını boş veritabanına uygula.
3. `.env.example` dosyasını `.env` olarak kopyala; `APP_KEY` için `openssl rand -hex 32`, yönetici parolası için `php -r "echo password_hash('PAROLA', PASSWORD_DEFAULT);"` kullan.
4. Mobil derlemede `--dart-define=API_BASE_URL=https://api.domain.tld` ver.
5. Apple Developer’da Sign in with Apple yeteneğini `com.globalmedia.sutVeGol` için aç. Google Cloud’da iOS ve Android OAuth istemcileri oluşturup istemci kimliklerini `.env` içindeki `GOOGLE_CLIENT_IDS` alanına ekle.

Sağlık kontrolü: `GET /health`. Yönetim paneli ayrı bir HTTPS alanından `backend/admin/` dizinine yönlendirilir.
