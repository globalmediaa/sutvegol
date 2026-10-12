#!/usr/bin/env bash
# Şut ve Gol backend'ini sunucuda kurar / günceller (Docker Compose + host Nginx).
#
#   bash backend/deploy/deploy.sh                # git pull + build + migration + Nginx
#   bash backend/deploy/deploy.sh --no-pull      # çekmeden, mevcut kodla (GitHub Actions)
#   bash backend/deploy/deploy.sh --skip-nginx   # yalnız Docker tarafı
#   bash backend/deploy/deploy.sh --print-nginx  # üretilecek Nginx dosyasını yazdırır, bir şey değiştirmez
#
# Yalnız "sutvegol" Compose projesine ve kendi Nginx site dosyasına dokunur. Başka
# konteyner/ağ/volume/site değiştirilmez; prune, down -v, volume silme yoktur.
# Üretilen her şey (.env, secrets/, .deploy-backups/, .deploy.lock) backend/ altında durur.
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$BACKEND_DIR/.." && pwd)"
PROJECT=sutvegol
IMAGE=sutvegol-app
ENV_FILE="$BACKEND_DIR/.env"
LOCK_FILE="$BACKEND_DIR/.deploy.lock"
BACKUP_DIR="$BACKEND_DIR/.deploy-backups"
ACME_ROOT=/var/www/letsencrypt
TMP_DIR=""
LOCK_DIR_HELD=0

# Cloudflare https://www.cloudflare.com/ips adresine ulaşılamazsa kullanılır.
CF_FALLBACK="173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18
108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15
104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22 2400:cb00::/32 2606:4700::/32
2803:f800::/32 2405:b500::/32 2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32"

if [[ -t 1 ]]; then B=$'\033[1m' BLUE=$'\033[1;34m' YEL=$'\033[1;33m' RED=$'\033[1;31m' GRN=$'\033[1;32m' R=$'\033[0m'
else B="" BLUE="" YEL="" RED="" GRN="" R=""; fi
step() { printf '\n%s==> %s%s\n' "$BLUE" "$*" "$R"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%s[uyarı]%s %s\n' "$YEL" "$R" "$*" >&2; }
die()  { printf '%s[hata]%s %s\n' "$RED" "$R" "$*" >&2; exit 1; }

cleanup() {
  [[ -n "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
  [[ "$LOCK_DIR_HELD" == 1 ]] && rmdir "$LOCK_FILE.d" 2>/dev/null
  return 0
}

dc() { docker compose -p "$PROJECT" -f "$BACKEND_DIR/compose.yaml" --env-file "$ENV_FILE" "$@"; }
# compose exec -T bazı sürümlerde stdin iletmiyor (migration sessizce boş gider); docker exec -i her zaman iletir.
db_exec() { local cid; cid="$(dc ps -q db 2>/dev/null || true)"; [[ -n "$cid" ]] || return 1; docker exec -i "$cid" "$@"; }
db_sql() { db_exec sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" exec mysql -h127.0.0.1 -u"$MYSQL_USER" "$MYSQL_DATABASE" "$@"' sh "$@"; }

# .env içindeki KEY değerini (tırnaksız) döndürür; yoksa $2.
env_get() {
  local v=""
  [[ -f "$ENV_FILE" ]] && v="$(grep -E "^$1=" "$ENV_FILE" | tail -n1 | cut -d= -f2-)" || true
  v="${v%$'\r'}"
  if [[ "$v" =~ ^\'(.*)\'$ || "$v" =~ ^\"(.*)\"$ ]]; then v="${BASH_REMATCH[1]}"; fi
  printf '%s' "${v:-${2:-}}"
}

acquire_lock() {
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    flock -n 9 || die "Başka bir deploy ya da bakım işi çalışıyor ($LOCK_FILE)."
  else
    mkdir "$LOCK_FILE.d" 2>/dev/null || die "Başka bir deploy çalışıyor (kilit: $LOCK_FILE.d)."
    LOCK_DIR_HELD=1
  fi
}

release_lock() {
  if [[ "$LOCK_DIR_HELD" == 1 ]]; then rmdir "$LOCK_FILE.d" 2>/dev/null || true; LOCK_DIR_HELD=0
  else exec 9>&-; fi
}

# ---------------------------------------------------------------- adımlar

git_pull() {
  step "Kod güncelleniyor"
  if ! git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then info "Git deposu değil, atlandı."; return; fi
  local branch before
  branch="$(git -C "$REPO_DIR" symbolic-ref --short -q HEAD)" || die "Depo bir dalda değil (detached HEAD). 'git switch master' ya da 'git switch prod' yap."
  if ! git -C "$REPO_DIR" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then warn "'$branch' dalının upstream'i yok, pull atlandı."; return; fi
  [[ -z "$(git -C "$REPO_DIR" status --porcelain --untracked-files=no)" ]] \
    || die "Sunucudaki depoda commit edilmemiş değişiklik var; deploy durduruldu. ('git status' ile bak.)"
  before="$(git -C "$REPO_DIR" rev-parse HEAD)"
  git -C "$REPO_DIR" pull --ff-only --quiet || die "git pull --ff-only başarısız (sunucuda ayrışmış commit olabilir)."
  if [[ "$(git -C "$REPO_DIR" rev-parse HEAD)" != "$before" ]]; then
    info "Yeni kod: $(git -C "$REPO_DIR" log --oneline -1)"
    release_lock; cleanup
    # Script'in kendisi de değişmiş olabilir: yeni sürümüyle baştan çalıştır.
    exec bash "$BACKEND_DIR/deploy/deploy.sh" --no-pull "$@"
  fi
  info "Zaten güncel: $(git -C "$REPO_DIR" log --oneline -1) ($branch)"
}

preflight() {
  step "Ön kontroller"
  command -v docker >/dev/null || die "Docker kurulu değil."
  docker compose version >/dev/null 2>&1 || die "Docker Compose v2 gerekli ('docker compose' komutu)."
  docker info >/dev/null 2>&1 \
    || die "Docker'a erişilemiyor. Kullanıcıyı docker grubuna ekle: sudo usermod -aG docker $USER (sonra yeniden bağlan)."
  local c
  for c in curl openssl gzip awk; do command -v "$c" >/dev/null || die "'$c' kurulu değil."; done
  info "$(docker compose version | head -n1)"
}

migrate_old_layout() {
  # Eski düzende .env, secrets/ ve yedekler depo kökündeydi.
  if [[ -f "$REPO_DIR/.env" && ! -f "$ENV_FILE" ]]; then mv "$REPO_DIR/.env" "$ENV_FILE"; info "Kökteki .env → backend/.env taşındı."; fi
  if [[ -d "$REPO_DIR/secrets" && ! -e "$BACKEND_DIR/secrets" ]]; then mv "$REPO_DIR/secrets" "$BACKEND_DIR/secrets"; info "Kökteki secrets/ → backend/secrets/ taşındı."; fi
  if [[ -d "$REPO_DIR/.deploy-backups" && ! -e "$BACKUP_DIR" ]]; then mv "$REPO_DIR/.deploy-backups" "$BACKUP_DIR"; info "Kökteki yedekler → backend/.deploy-backups/ taşındı."; fi
  return 0
}

ensure_env() {
  step "Ortam dosyası (backend/.env)"
  if [[ -f "$ENV_FILE" ]]; then
    local k
    for k in APP_KEY DB_PASSWORD DB_ROOT_PASSWORD; do [[ -n "$(env_get "$k")" ]] || die "backend/.env içinde $k boş."; done
    info "Mevcut .env kullanılıyor."
    return
  fi
  if docker volume inspect "${PROJECT}_db_data" >/dev/null 2>&1; then
    die "backend/.env yok ama ${PROJECT}_db_data volume'ü var. Yeni parola üretmek mevcut veritabanına erişimi keser; eski .env'yi geri koy."
  fi
  (
    umask 077
    awk -v a="$(openssl rand -hex 32)" -v b="$(openssl rand -hex 32)" -v c="$(openssl rand -hex 32)" '
      /^APP_KEY=$/          { print "APP_KEY=" a; next }
      /^DB_PASSWORD=$/      { print "DB_PASSWORD=" b; next }
      /^DB_ROOT_PASSWORD=$/ { print "DB_ROOT_PASSWORD=" c; next }
      { print }' "$BACKEND_DIR/deploy/env.example" > "$ENV_FILE"
  )
  info "İlk kurulum: rastgele APP_KEY ve veritabanı parolalarıyla oluşturuldu (chmod 600)."
  info "Bu dosyayı sakla; ilk kurulumdan sonra bu üç değeri değiştirme."
}

ensure_files() {
  mkdir -p "$BACKEND_DIR/secrets" "$BACKUP_DIR"
  chmod 750 "$BACKEND_DIR/secrets"
  chmod 700 "$BACKUP_DIR"
  # MySQL konteyneri ilk açılışta bu dosyaları kendi kullanıcısıyla okur (umask 077'li sunucular için).
  chmod a+r "$BACKEND_DIR"/database/*.sql "$BACKEND_DIR"/database/migrations/*.sql
  local key="$BACKEND_DIR/secrets/apple_key.p8" gid
  if [[ -f "$key" ]]; then
    # Konteynerdeki www-data (gid 33) okuyabilmeli.
    gid="$(stat -c %g "$BACKEND_DIR/secrets" 2>/dev/null || stat -f %g "$BACKEND_DIR/secrets")"
    if [[ "$gid" != 33 ]] && ! { sudo -n chgrp 33 "$BACKEND_DIR/secrets" "$key" 2>/dev/null && chmod 640 "$key"; }; then
      warn "secrets/apple_key.p8 www-data tarafından okunamayabilir: sudo chgrp 33 backend/secrets backend/secrets/apple_key.p8 && chmod 640 backend/secrets/apple_key.p8"
    fi
  fi
}

check_port() {
  local port="$1" cid=""
  cid="$(dc ps -q app 2>/dev/null || true)"
  if [[ -n "$cid" ]] && docker port "$cid" 80/tcp 2>/dev/null | grep -q ":$port\$"; then return; fi
  local busy=""
  if command -v ss >/dev/null 2>&1; then busy="$(ss -Hltn "sport = :$port" 2>/dev/null || true)"
  elif command -v lsof >/dev/null 2>&1; then busy="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"; fi
  [[ -z "$busy" ]] || die "127.0.0.1:$port başka bir servis tarafından kullanılıyor. backend/.env içinde APP_PORT'u boş bir porta çevir (Nginx otomatik güncellenir)."
}

deploy_docker() {
  local port="$1" attempt
  step "İmaj derleniyor ($IMAGE)"
  check_port "$port"
  if docker image inspect "$IMAGE:latest" >/dev/null 2>&1; then docker tag "$IMAGE:latest" "$IMAGE:previous"; fi
  DOCKER_BUILDKIT=1 dc build app

  step "Veritabanı"
  dc up -d db
  for attempt in $(seq 1 90); do
    # TCP ile bağlan: ilk kurulumdaki geçici (soket-only) MySQL sunucusu şema bitmeden sayılmasın.
    if db_sql -e 'SELECT 1' </dev/null >/dev/null 2>&1; then break; fi
    [[ "$attempt" == 90 ]] && die "Veritabanı 3 dakikada hazır olmadı: docker compose -p $PROJECT logs --tail=100 db"
    sleep 2
  done
  info "MySQL hazır."

  local backup
  backup="$BACKUP_DIR/db-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
  (umask 077; db_exec sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysqldump --single-transaction --no-tablespaces -u"$MYSQL_USER" "$MYSQL_DATABASE"' </dev/null | gzip > "$backup") \
    || die "Veritabanı yedeği alınamadı; migration ve güncelleme yapılmadı."
  info "Yedek: backend/${backup#"$BACKEND_DIR"/} ($(du -h "$backup" | cut -f1))"

  # Migration'lar yalnız eklemeli (IF NOT EXISTS); her deploy'da güvenle yeniden uygulanır.
  local m
  for m in "$BACKEND_DIR"/database/migrations/*.sql; do
    [[ -f "$m" ]] || continue
    db_sql < "$m" || die "Migration başarısız: ${m#"$BACKEND_DIR"/} (yedek: ${backup#"$BACKEND_DIR"/})"
    info "Migration: ${m##*/}"
  done

  step "Uygulama başlatılıyor (127.0.0.1:$port)"
  dc up -d app
  if ! wait_healthy "$port"; then
    if docker image inspect "$IMAGE:previous" >/dev/null 2>&1; then
      warn "Yeni sürüm sağlık kontrolünü geçemedi; önceki imaja dönülüyor."
      dc logs --tail=40 app >&2 || true
      docker tag "$IMAGE:previous" "$IMAGE:latest"
      dc up -d app
      wait_healthy "$port" && die "Önceki sürüm geri yüklendi ve çalışıyor; yeni sürüm hatalı."
    fi
    dc logs --tail=60 app >&2 || true
    die "Sağlık kontrolü başarısız: http://127.0.0.1:$port/api/health"
  fi
  info "Sağlık kontrolü geçti: http://127.0.0.1:$port/api/health"
  # Yalnız bu projenin etiketli, artık kullanılmayan eski imajları.
  docker image prune -f --filter "label=com.globalmedia.project=$PROJECT" >/dev/null 2>&1 || true
}

wait_healthy() {
  local attempt
  for attempt in $(seq 1 30); do
    curl -fsS --max-time 5 "http://127.0.0.1:$1/api/health" >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

ensure_cron() {
  [[ "$(uname -s)" == Linux ]] || return 0
  if ! command -v crontab >/dev/null 2>&1; then warn "crontab yok; günlük yedek/temizlik kurulmadı."; return 0; fi
  local marker="# sutvegol-maintenance"
  local line="17 3 * * * /bin/bash '$BACKEND_DIR/deploy/maintenance.sh' >> '$BACKUP_DIR/maintenance.log' 2>&1 $marker"
  local current; current="$(crontab -l 2>/dev/null || true)"
  if grep -qxF "$line" <<<"$current"; then return 0; fi
  # Yalnız bu projenin satırları değişir (eski düzenin kök yolu dahil).
  { grep -vF "$marker" <<<"$current" | grep -vF 'games/sutvegol/deploy/maintenance.sh' || true; echo "$line"; } | crontab -
  info "Cron: her gece 03:17 yedek + temizlik (backend/deploy/maintenance.sh)."
}

# ---------------------------------------------------------------- nginx

cloudflare_ranges() {
  local fetched
  fetched="$( { curl -fsS --max-time 10 https://www.cloudflare.com/ips-v4; echo; curl -fsS --max-time 10 https://www.cloudflare.com/ips-v6; echo; } 2>/dev/null \
    | grep -E '^[0-9a-fA-F:.]+/[0-9]{1,3}$' || true)"
  if [[ "$(grep -c . <<<"$fetched")" -ge 10 ]]; then printf '%s\n' "$fetched"; else tr ' ' '\n' <<<"$CF_FALLBACK" | grep .; fi
}

# SSL_CERT/SSL_KEY değişkenlerini doldurur (yoksa boş bırakır).
find_cert() {
  local domain="$1" c k
  SSL_CERT="$(env_get SSL_CERT)" SSL_KEY="$(env_get SSL_KEY)"
  if [[ -n "$SSL_CERT$SSL_KEY" ]]; then
    $SUDO test -r "$SSL_CERT" && $SUDO test -r "$SSL_KEY" || die "backend/.env SSL_CERT/SSL_KEY dosyaları bulunamadı: $SSL_CERT / $SSL_KEY"
    return
  fi
  for c in "/etc/letsencrypt/live/$domain/fullchain.pem:/etc/letsencrypt/live/$domain/privkey.pem" \
           "/etc/ssl/cloudflare/$domain.pem:/etc/ssl/cloudflare/$domain.key"; do
    k="${c#*:}" c="${c%%:*}"
    if $SUDO test -r "$c" && $SUDO test -r "$k"; then SSL_CERT="$c" SSL_KEY="$k"; return; fi
  done
}

render_nginx() {
  local domain="$1" port="$2" cert="$3" key="$4" realip="$5" ipv6="$6"
  local l80="    listen 80;" l443="    listen 443 ssl;" real="" r
  if [[ "$ipv6" == 1 ]]; then l80+=$'\n    listen [::]:80;'; l443+=$'\n    listen [::]:443 ssl;'; fi
  if [[ "$realip" == 1 ]]; then
    # Cloudflare arkasında gerçek oyuncu IP'si (API hız sınırı IP başına çalışır).
    while read -r r; do real+="    set_real_ip_from $r;"$'\n'; done < <(cloudflare_ranges)
    real+="    real_ip_header CF-Connecting-IP;"$'\n'
  fi
  # Let's Encrypt webroot doğrulaması iki portta da çalışır (Cloudflare "Always Use HTTPS" açık olsa bile).
  local acme="    location ^~ /.well-known/acme-challenge/ { root $ACME_ROOT; default_type text/plain; }"
  local body
  body="$(cat <<EOF
    client_max_body_size 256k;
${real}
${acme}
    location ~ /(?:\.env|\.git|composer\.(?:json|lock)) { deny all; }
    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 30s;
        add_header X-Content-Type-Options nosniff always;
        add_header Referrer-Policy strict-origin-when-cross-origin always;
    }
EOF
)"
  echo "# Şut ve Gol API — backend/deploy/deploy.sh üretir. Elle değişiklik bir sonraki deploy'da ezilir;"
  echo "# ayar için backend/.env (DOMAIN, APP_PORT, SSL_CERT, SSL_KEY) kullan."
  if [[ -n "$cert" ]]; then
    printf 'server {\n%s\n    server_name %s;\n%s\n    location / { return 301 https://$host$request_uri; }\n}\n\n' "$l80" "$domain" "$acme"
    printf 'server {\n%s\n    server_name %s;\n    ssl_certificate %s;\n    ssl_certificate_key %s;\n%s\n}\n' "$l443" "$domain" "$cert" "$key" "$body"
  else
    printf 'server {\n%s\n    server_name %s;\n%s\n}\n' "$l80" "$domain" "$body"
  fi
}

# 443'ü Nginx dışında bir süreç (ör. host'ta çalışan Caddy) tutuyorsa SSL bloğu eklenmez.
check_443_owner() {
  command -v ss >/dev/null 2>&1 || return 0
  local l; l="$($SUDO ss -Hltnp 'sport = :443' 2>/dev/null || true)"
  [[ -z "$l" ]] || grep -q '"nginx"' <<<"$l" \
    || die "443 portunu Nginx dışında bir süreç dinliyor; Nginx'e 443 eklenemedi, hiçbir şeye dokunulmadı:"$'\n'"$l"
}

# $1 dosyasını kendi site yolumuza yazar; nginx -t geçmezse eski haline döner.
install_nginx_conf() {
  local new="$1"
  if $SUDO test -f "$NGINX_AVAIL" && $SUDO cmp -s "$new" "$NGINX_AVAIL" && { [[ -z "$NGINX_ENABLED" ]] || $SUDO test -L "$NGINX_ENABLED"; }; then
    info "Yapılandırma değişmedi: $NGINX_AVAIL"
    return 0
  fi
  $SUDO "$NGINX_BIN" -t >/dev/null 2>&1 || die "Nginx'in mevcut yapılandırması zaten hatalı ('sudo nginx -t'); hiçbir şeye dokunulmadı."

  # Aynı alan adını tanımlayan başka bir site varsa dokunma, kullanıcıya bırak.
  local re="server_name[^;]*[[:space:]]${DOMAIN_RE}([[:space:];]|$)" f others=""
  while read -r f; do
    [[ -z "$f" ]] && continue
    [[ "$($SUDO readlink -f "$f")" == "$($SUDO readlink -f "$NGINX_AVAIL" 2>/dev/null || echo "$NGINX_AVAIL")" ]] && continue
    others+=" $f"
  done < <($SUDO grep -RlsE "$re" /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null || true)
  [[ -z "$others" ]] || die "Alan adı başka Nginx dosyasında da tanımlı:$others — o dosyayı kaldır/devre dışı bırak, sonra tekrar çalıştır."

  local old="" had_link=0
  if $SUDO test -f "$NGINX_AVAIL"; then old="$TMP_DIR/nginx.old"; $SUDO cat "$NGINX_AVAIL" > "$old"; fi
  if [[ -n "$NGINX_ENABLED" ]] && $SUDO test -L "$NGINX_ENABLED"; then had_link=1; fi
  $SUDO install -m 644 "$new" "$NGINX_AVAIL"
  [[ -z "$NGINX_ENABLED" ]] || $SUDO ln -sfn "$NGINX_AVAIL" "$NGINX_ENABLED"
  if ! $SUDO "$NGINX_BIN" -t >"$TMP_DIR/nginx-t.log" 2>&1; then
    if [[ -n "$old" ]]; then $SUDO install -m 644 "$old" "$NGINX_AVAIL"; else $SUDO rm -f "$NGINX_AVAIL"; fi
    [[ -n "$NGINX_ENABLED" && "$had_link" == 0 ]] && $SUDO rm -f "$NGINX_ENABLED"
    cat "$TMP_DIR/nginx-t.log" >&2
    die "Yeni Nginx yapılandırması geçersiz; eski hali geri yüklendi, Nginx yeniden yüklenmedi."
  fi
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nginx; then $SUDO systemctl reload nginx
  else $SUDO "$NGINX_BIN" -s reload; fi
  info "Yazıldı ve yeniden yüklendi: $NGINX_AVAIL"
}

# Let's Encrypt sertifikası alır (webroot; certbot Nginx dosyalarına dokunmaz). Başarısızsa 1 döner.
issue_cert() {
  local domain="$1" email token got="" attempt
  if ! command -v certbot >/dev/null 2>&1; then
    warn "certbot kurulu değil (sudo apt install certbot); SSL alınamadı."
    return 1
  fi
  email="$(env_get ADMIN_EMAIL info@globalmedia.com.tr)"
  token="sutvegol-check-$(openssl rand -hex 6)"
  $SUDO mkdir -p "$ACME_ROOT/.well-known/acme-challenge"
  echo "$token" | $SUDO tee "$ACME_ROOT/.well-known/acme-challenge/$token" >/dev/null
  $SUDO chmod 644 "$ACME_ROOT/.well-known/acme-challenge/$token"
  # Let's Encrypt'in izleyeceği yolu önce kendimiz dene: sınırlı deneme hakkını boşa harcamayalım.
  # Nginx reload asenkron: yeni yapılandırma devreye girene kadar birkaç kez dene.
  for attempt in 1 2 3 4 5 6; do
    got="$(curl -fsSL --max-time 15 "http://$domain/.well-known/acme-challenge/$token" 2>/dev/null || true)"
    [[ "$got" == "$token" ]] && break
    sleep 2
  done
  $SUDO rm -f "$ACME_ROOT/.well-known/acme-challenge/$token"
  if [[ "$got" != "$token" ]]; then
    warn "http://$domain/.well-known/acme-challenge/ dışarıdan bu sunucuya ulaşmıyor; Let's Encrypt denenmedi."
    warn "Cloudflare DNS kaydının bu sunucuyu gösterdiğini kontrol et; 'Always Use HTTPS' açıksa ilk kurulum için geçici kapat."
    return 1
  fi
  info "Let's Encrypt sertifikası alınıyor ($email)..."
  $SUDO certbot certonly --webroot -w "$ACME_ROOT" -d "$domain" --cert-name "$domain" \
    --non-interactive --agree-tos -m "$email" --no-eff-email --keep-until-expiring \
    --deploy-hook "systemctl reload nginx" || { warn "certbot başarısız (ayrıntı: /var/log/letsencrypt/letsencrypt.log)."; return 1; }
}

nginx_setup() {
  local domain="$1" port="$2" print_only="${3:-0}"
  [[ "$print_only" == 1 ]] || step "Nginx ($domain)"

  if [[ "$(id -u)" -eq 0 ]]; then SUDO=""
  elif sudo -n true 2>/dev/null; then SUDO="sudo"
  elif [[ -t 0 && "$print_only" != 1 ]]; then SUDO="sudo"; sudo -v || die "sudo yetkisi alınamadı."
  elif [[ "$print_only" == 1 ]]; then SUDO=""
  else warn "Parolasız sudo yok; Nginx adımı atlandı (sunucuda elle: bash backend/deploy/deploy.sh --no-pull)."; return 0
  fi

  NGINX_BIN="$(command -v nginx 2>/dev/null || echo /usr/sbin/nginx)"
  DOMAIN_RE="${domain//./\\.}"
  local realip=0 ipv6=0
  if [[ -x "$NGINX_BIN" ]] && "$NGINX_BIN" -V 2>&1 | grep -q 'http_realip_module'; then realip=1; fi
  [[ -f /proc/net/if_inet6 ]] && ipv6=1
  [[ "$print_only" == 1 && ! -x "$NGINX_BIN" ]] && realip=1

  SSL_CERT="" SSL_KEY=""
  find_cert "$domain"
  local new="$TMP_DIR/nginx.conf"
  if [[ "$print_only" == 1 ]]; then
    render_nginx "$domain" "$port" "$SSL_CERT" "$SSL_KEY" "$realip" "$ipv6"
    return 0
  fi

  [[ -x "$NGINX_BIN" ]] || die "Nginx bulunamadı."
  [[ "$realip" == 1 ]] || warn "Nginx'te realip modülü yok: oyuncu IP'leri Cloudflare IP'si görünecek (hız sınırı paylaşılır)."
  if [[ -d /etc/nginx/sites-enabled ]] && grep -qs 'sites-enabled' /etc/nginx/nginx.conf; then
    NGINX_AVAIL="/etc/nginx/sites-available/$domain" NGINX_ENABLED="/etc/nginx/sites-enabled/$domain"
  else
    NGINX_AVAIL="/etc/nginx/conf.d/$domain.conf" NGINX_ENABLED=""
  fi

  if [[ -z "$SSL_CERT" ]]; then
    # Önce HTTP + doğrulama yolu, sonra sertifika.
    check_443_owner
    render_nginx "$domain" "$port" "" "" "$realip" "$ipv6" > "$new"
    install_nginx_conf "$new"
    if issue_cert "$domain"; then find_cert "$domain"; fi
  fi
  if [[ -n "$SSL_CERT" ]]; then check_443_owner; fi
  render_nginx "$domain" "$port" "$SSL_CERT" "$SSL_KEY" "$realip" "$ipv6" > "$new"
  install_nginx_conf "$new"

  local url="http://127.0.0.1/api/health" opts=(-H "Host: $domain") ok=0 attempt
  if [[ -n "$SSL_CERT" ]]; then
    info "SSL: $SSL_CERT"
    url="https://$domain/api/health" opts=(-k --resolve "$domain:443:127.0.0.1")
  else
    warn "SSL sertifikası yok; yalnız 80 portu açık (Cloudflare Full/strict modunda 526 verir). Yukarıdaki uyarıyı düzeltip tekrar çalıştır."
  fi
  for attempt in 1 2 3 4 5; do
    if curl -fsS --max-time 10 "${opts[@]}" "$url" >/dev/null 2>&1; then ok=1; break; fi
    sleep 2
  done
  if [[ "$ok" == 1 ]]; then info "Nginx → uygulama çalışıyor (${url%%/api*})."; else warn "$url sunucu içinden yanıt vermedi."; fi
}

# ---------------------------------------------------------------- ana akış

main() {
  local pull=1 nginx=1 print_nginx=0 arg
  for arg in "$@"; do
    case "$arg" in
      --no-pull) pull=0 ;;
      --skip-nginx) nginx=0 ;;
      --print-nginx) print_nginx=1 ;;
      -h|--help) sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) die "Bilinmeyen seçenek: $arg (bkz. --help)" ;;
    esac
  done
  TMP_DIR="$(mktemp -d)"
  trap cleanup EXIT
  cd "$BACKEND_DIR"

  if [[ "$print_nginx" == 1 ]]; then
    nginx_setup "$(env_get DOMAIN sutvegol.gmgaming.app)" "$(env_get APP_PORT 12883)" 1
    return
  fi

  printf '%sŞut ve Gol backend deploy%s — %s\n' "$B" "$R" "$BACKEND_DIR"
  acquire_lock
  if [[ "$pull" == 1 ]]; then git_pull "$@"; fi
  preflight
  migrate_old_layout
  ensure_env
  ensure_files

  local domain port
  domain="$(env_get DOMAIN sutvegol.gmgaming.app)"
  port="$(env_get APP_PORT 12883)"
  [[ "$port" =~ ^[0-9]+$ ]] || die "APP_PORT geçersiz: $port"

  deploy_docker "$port"
  ensure_cron
  if [[ "$nginx" == 1 ]]; then nginx_setup "$domain" "$port"; fi

  step "Tamamlandı"
  printf '    %sAPI:%s https://%s/api/health\n' "$GRN" "$R" "$domain"
  info "Konteynerler: $(docker ps --filter "label=com.docker.compose.project=$PROJECT" --format '{{.Names}} ({{.Status}})' | paste -sd ',' - | sed 's/,/, /g')"
  info "Loglar:  docker compose -p $PROJECT logs -f app"
  [[ -n "$(env_get ADMIN_PASSWORD_HASH)" ]] || info "Admin paneli kapalı: ADMIN_PASSWORD_HASH boş (backend/README.md → Admin)."
  [[ -n "$(env_get GOOGLE_CLIENT_IDS)" ]] || info "Google girişi kapalı: GOOGLE_CLIENT_IDS boş."
}

main "$@"
