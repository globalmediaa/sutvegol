#!/usr/bin/env bash
# Google / Sign in with Apple ayarlarını deploy.sh'tan ÖNCE sunucuya yazar. Değerler
# globalmediaa/pazarci-esnaf → .github/workflows/deploy-sutvegol.yml (appleboy/ssh-action
# "envs") ile gelir; elle çalıştırıldığında boştur ve hiçbir şey değişmez.
#
#   SUTVEGOL_GOOGLE_CLIENT_IDS      → backend/.env GOOGLE_CLIENT_IDS (iOS + Web client ID, virgüllü)
#   SUTVEGOL_APPLE_KEY_ID           → backend/.env APPLE_KEY_ID (10 karakter)
#   SUTVEGOL_APPLE_PRIVATE_KEY_B64  → backend/secrets/apple_key.p8 (P-256 .p8 PEM'in tek satır base64'ü)
#
# Kurallar:
#   - Boş ya da tanımsız değişken hiçbir satırı/dosyayı silmez, boşaltmaz.
#   - Geçersiz değer ::warning:: ile atlanır, deploy sürer. Değerler hiçbir zaman yazdırılmaz.
#   - backend/.env yerinde yazılır (izin ve sahiplik korunur; awk ENVIRON, tek tırnak). İlk
#     değişiklikten önce bir kez backend/.env.pre-oauth (600) yedeği alınır. Diğer satırlara
#     dokunulmaz; etkin değer zaten aynıysa dosya hiç yazılmaz.
#   - backend/.env yoksa (ilk kurulum ya da kökte eski düzen) .env adımı atlanır: deploy.sh
#     dosyayı üretir/taşır, değerler bir sonraki deploy'da yazılır.
#   - Anahtar base64 -d + openssl ile PEM P-256 özel anahtar olarak doğrulanır; aynıysa
#     dokunulmaz. deploy.sh'ın beklediği gibi secrets/ 750, apple_key.p8 640 ve ikisinin grubu
#     33 (konteynerdeki www-data; SUTVEGOL_SECRETS_GID ile değişir). Grup sırayla chgrp →
#     sudo -n chgrp → yerel sutvegol-app imajıyla (çekmeden, ağsız) docker run chgrp ile verilir;
#     hiçbiri olmazsa dosya 600 kalır ve elle komut uyarısı çıkar.
#
#   bash backend/deploy/secrets_env.sh
set -eu
umask 077

BACKEND_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$BACKEND_DIR/.." && pwd)"
ENV_FILE="$BACKEND_DIR/.env"
BACKUP="$ENV_FILE.pre-oauth"
SECRETS_DIR="$BACKEND_DIR/secrets"
KEY_FILE="$SECRETS_DIR/apple_key.p8"
GID="${SUTVEGOL_SECRETS_GID:-33}"
IMAGE=sutvegol-app:latest
GOOGLE_RE='^[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$'
KID_RE='^[A-Z0-9]{10}$'
CHANGED=""
SKIPPED=""
TMP=""

cleanup() { if [ -n "$TMP" ]; then rm -f "$TMP"; fi; }
trap cleanup EXIT

warn() { echo "::warning::secrets_env: $*"; }
file_gid()  { stat -c %g "$1" 2>/dev/null || stat -f %g "$1"; }
file_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

# deploy.sh / maintenance.sh ile aynı kilit: çalışan bir deploy .env'yi okurken yazılmasın.
if command -v flock >/dev/null 2>&1; then
  exec 9>"$BACKEND_DIR/.deploy.lock"
  flock -n 9 || { echo "secrets_env: başka bir deploy ya da bakım işi çalışıyor (backend/.deploy.lock)." >&2; exit 1; }
fi

# ---------------------------------------------------------------- backend/.env

# NAME'in .env'deki etkin (son) değeri, tırnaksız. Compose ve deploy.sh de son satırı kullanır.
env_value() {
  SE_NAME="$1" awk -v q="'" '
    BEGIN { n = ENVIRON["SE_NAME"]; v = "" }
    $0 ~ "^[ \t]*(export[ \t]+)?" n "[ \t]*=" {
      v = $0; sub(/^[^=]*=/, "", v); sub(/\r$/, "", v)
      if (v ~ ("^" q ".*" q "$") || v ~ /^".*"$/) v = substr(v, 2, length(v) - 2)
    }
    END { printf "%s", v }' "$ENV_FILE"
}

# "a, b\n c" → "a,b,c"; her öğe Google OAuth client ID biçiminde olmalı.
google_ids() {
  local v id rest
  v="$(printf '%s' "$1" | tr -s ' \t\r\n,' ',')"
  v="${v#,}"; v="${v%,}"
  [ -n "$v" ] || return 1
  rest="$v,"
  while [ -n "$rest" ]; do
    id="${rest%%,*}"; rest="${rest#*,}"
    [[ "$id" =~ $GOOGLE_RE ]] || return 1
  done
  printf '%s' "$v"
}

update_env() {
  local google="" kid="" set_google="" set_kid=""
  if [ -n "${SUTVEGOL_GOOGLE_CLIENT_IDS:-}" ]; then
    google="$(google_ids "$SUTVEGOL_GOOGLE_CLIENT_IDS")" \
      || { google=""; warn "SUTVEGOL_GOOGLE_CLIENT_IDS geçersiz (beklenen: 123-abc.apps.googleusercontent.com,…); GOOGLE_CLIENT_IDS değiştirilmedi."; }
  else
    SKIPPED="$SKIPPED SUTVEGOL_GOOGLE_CLIENT_IDS"
  fi
  if [ -n "${SUTVEGOL_APPLE_KEY_ID:-}" ]; then
    kid="$(printf '%s' "$SUTVEGOL_APPLE_KEY_ID" | tr -d ' \t\r\n')"
    [[ "$kid" =~ $KID_RE ]] || { kid=""; warn "SUTVEGOL_APPLE_KEY_ID geçersiz (10 büyük harf/rakam); APPLE_KEY_ID değiştirilmedi."; }
  else
    SKIPPED="$SKIPPED SUTVEGOL_APPLE_KEY_ID"
  fi
  [ -n "$google$kid" ] || return 0
  if [ ! -f "$ENV_FILE" ]; then
    warn "backend/.env yok (ilk kurulum ya da eski düzen); deploy.sh oluşturduktan sonra bir sonraki deploy'da yazılır."
    return 0
  fi

  if [ -n "$google" ] && [ "$(env_value GOOGLE_CLIENT_IDS)" != "$google" ]; then set_google="$google"; fi
  if [ -n "$kid" ] && [ "$(env_value APPLE_KEY_ID)" != "$kid" ]; then set_kid="$kid"; fi
  [ -n "$set_google$set_kid" ] || return 0

  # İlk NAME= satırı değiştirilir (tekrarları silinir), yoksa sona eklenir.
  TMP="$(mktemp "$ENV_FILE.XXXXXX")"
  SE_GOOGLE="$set_google" SE_KID="$set_kid" awk -v q="'" '
    BEGIN {
      n = split("GOOGLE_CLIENT_IDS APPLE_KEY_ID", order, " ")
      if (ENVIRON["SE_GOOGLE"] != "") want["GOOGLE_CLIENT_IDS"] = ENVIRON["SE_GOOGLE"]
      if (ENVIRON["SE_KID"] != "") want["APPLE_KEY_ID"] = ENVIRON["SE_KID"]
    }
    {
      for (k in want) if ($0 ~ "^[ \t]*(export[ \t]+)?" k "[ \t]*=") {
        if (!(k in done)) { print k "=" q want[k] q; done[k] = 1 }
        next
      }
      print
    }
    END { for (i = 1; i <= n; i++) if ((order[i] in want) && !(order[i] in done)) print order[i] "=" q want[order[i]] q }
  ' "$ENV_FILE" > "$TMP"
  if [ ! -e "$BACKUP" ]; then
    cp -p "$ENV_FILE" "$BACKUP"
    chmod 600 "$BACKUP"
  fi
  cat "$TMP" > "$ENV_FILE"   # yerinde yaz: izin ve sahiplik korunur
  rm -f "$TMP"; TMP=""
  if [ -n "$set_google" ]; then CHANGED="$CHANGED GOOGLE_CLIENT_IDS"; fi
  if [ -n "$set_kid" ]; then CHANGED="$CHANGED APPLE_KEY_ID"; fi
}

# ---------------------------------------------------------------- secrets/apple_key.p8

is_p256_pem() {
  grep -q -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' "$1" || return 1
  openssl pkey -in "$1" -passin pass: -noout </dev/null >/dev/null 2>&1 || return 1
  openssl pkey -in "$1" -passin pass: -pubout </dev/null 2>/dev/null \
    | openssl pkey -pubin -noout -text 2>/dev/null | grep -Eq 'prime256v1|P-256'
}

group_ok() { [ "$(file_gid "$SECRETS_DIR")" = "$GID" ] && [ "$(file_gid "$KEY_FILE")" = "$GID" ]; }

set_group() {
  group_ok && return 0
  chgrp "$GID" "$SECRETS_DIR" "$KEY_FILE" 2>/dev/null && group_ok && return 0
  sudo -n chgrp "$GID" "$SECRETS_DIR" "$KEY_FILE" </dev/null >/dev/null 2>&1 && group_ok && return 0
  # Deploy kullanıcısı zaten docker grubunda (deploy.sh şartı): yerel imaj, çekme yok, ağ yok.
  docker image inspect "$IMAGE" >/dev/null 2>&1 \
    && docker run --rm --pull never --network none --user 0:0 -v "$SECRETS_DIR:/s" \
      --entrypoint chgrp "$IMAGE" "$GID" /s /s/apple_key.p8 </dev/null >/dev/null 2>&1 \
    && group_ok
}

update_key() {
  local b64 gid_before mode_before
  if [ -z "${SUTVEGOL_APPLE_PRIVATE_KEY_B64:-}" ]; then
    SKIPPED="$SKIPPED SUTVEGOL_APPLE_PRIVATE_KEY_B64"
    return 0
  fi
  if [ -d "$REPO_DIR/secrets" ] && [ ! -e "$SECRETS_DIR" ]; then
    warn "kökte eski secrets/ var; deploy.sh backend/ altına taşıdıktan sonra anahtar bir sonraki deploy'da yazılır."
    return 0
  fi
  mkdir -p "$SECRETS_DIR"
  [ "$(file_mode "$SECRETS_DIR")" = 750 ] || chmod 750 "$SECRETS_DIR" 2>/dev/null \
    || warn "backend/secrets izni 750 yapılamadı."
  TMP="$(mktemp "$SECRETS_DIR/.apple_key.p8.XXXXXX")" \
    || { TMP=""; warn "backend/secrets yazılamıyor; apple_key.p8 değiştirilmedi."; return 0; }
  b64="$(printf '%s' "$SUTVEGOL_APPLE_PRIVATE_KEY_B64" | tr -d ' \t\r\n')"
  if ! { printf '%s' "$b64" | base64 -d > "$TMP" 2>/dev/null && is_p256_pem "$TMP"; }; then
    b64=""; rm -f "$TMP"; TMP=""
    warn "SUTVEGOL_APPLE_PRIVATE_KEY_B64 PEM biçiminde P-256 özel anahtar değil; apple_key.p8 değiştirilmedi."
    return 0
  fi
  b64=""
  if [ -f "$KEY_FILE" ] && cmp -s "$TMP" "$KEY_FILE"; then
    rm -f "$TMP"
  else
    mv -f "$TMP" "$KEY_FILE"   # 600; grup verilince 640
    CHANGED="$CHANGED apple_key.p8"
  fi
  TMP=""

  gid_before="$(file_gid "$KEY_FILE")"; mode_before="$(file_mode "$KEY_FILE")"
  if set_group; then
    [ "$(file_mode "$KEY_FILE")" = 640 ] || chmod 640 "$KEY_FILE" 2>/dev/null \
      || warn "apple_key.p8 izni 640 yapılamadı."
  else
    [ "$(file_mode "$KEY_FILE")" = 600 ] || chmod 600 "$KEY_FILE" 2>/dev/null || true
    warn "apple_key.p8 grubu $GID yapılamadı, konteyner (www-data) okuyamaz. Sunucuda: sudo chgrp $GID backend/secrets backend/secrets/apple_key.p8 && chmod 640 backend/secrets/apple_key.p8"
  fi
  case "$CHANGED" in
    *apple_key.p8*) ;;
    *) if [ "$(file_gid "$KEY_FILE")" != "$gid_before" ] || [ "$(file_mode "$KEY_FILE")" != "$mode_before" ]; then
         CHANGED="$CHANGED apple_key.p8(izin)"
       fi ;;
  esac
}

update_env
update_key
if [ -n "$SKIPPED" ]; then echo "secrets_env: boş, dokunulmadı:$SKIPPED"; fi
if [ -n "$CHANGED" ]; then echo "secrets_env: güncellendi:$CHANGED"; else echo "secrets_env: değişiklik yok"; fi
