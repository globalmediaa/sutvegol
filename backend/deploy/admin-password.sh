#!/usr/bin/env bash
# Admin paneli parolasını ayarlar / değiştirir.
#
#   bash backend/deploy/admin-password.sh
#
# Hash çalışan sutvegol-app konteynerindeki PHP ile üretilir, backend/.env'ye tek tırnakla
# yazılır (Compose '$' işaretlerini değiştirmesin), uygulama yeniden başlatılır ve parolanın
# konteynerdeki hash ile eşleştiği doğrulanır.
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$BACKEND_DIR/.env"

die() { printf '[hata] %s\n' "$*" >&2; exit 1; }
dc() { docker compose -p sutvegol -f "$BACKEND_DIR/compose.yaml" --env-file "$ENV_FILE" "$@"; }
env_get() { grep -E "^$1=" "$ENV_FILE" | tail -n1 | cut -d= -f2- | sed -e "s/^['\"]//" -e "s/['\"]\$//" || true; }
# compose exec -T bazı sürümlerde stdin iletmiyor; docker exec -i her zaman iletir.
app_exec() {
  local cid; cid="$(dc ps -q app 2>/dev/null || true)"
  [[ -n "$cid" ]] || return 1
  docker exec -i "$cid" "$@"
}

[[ -f "$ENV_FILE" ]] || die "backend/.env yok; önce bash backend/deploy/deploy.sh çalıştır."
app_exec true </dev/null 2>/dev/null || die "sutvegol-app çalışmıyor; önce bash backend/deploy/deploy.sh çalıştır."

read -rsp 'Yeni admin parolası: ' P; echo
read -rsp 'Tekrar: ' P2; echo
[[ -n "$P" ]] || die "Parola boş olamaz."
[[ "$P" == "$P2" ]] || die "Parolalar aynı değil; hiçbir şey değişmedi."
unset P2

hash="$(printf '%s' "$P" | app_exec php -r '$p = stream_get_contents(STDIN); if ($p === "") exit(3); echo password_hash($p, PASSWORD_DEFAULT);')" \
  || die "Hash üretilemedi (parola konteynere ulaşmadı); hiçbir şey değişmedi."
[[ "$hash" == \$2y\$* ]] || die "Beklenmeyen hash çıktısı; hiçbir şey değişmedi."

(
  umask 077
  H="$hash" awk -v q="'" '
    /^ADMIN_PASSWORD_HASH=/ { print "ADMIN_PASSWORD_HASH=" q ENVIRON["H"] q; f = 1; next }
    { print }
    END { if (!f) print "ADMIN_PASSWORD_HASH=" q ENVIRON["H"] q }' "$ENV_FILE" > "$ENV_FILE.tmp"
)
cat "$ENV_FILE.tmp" > "$ENV_FILE"   # dosyanın 600 iznini korur
rm -f "$ENV_FILE.tmp"

echo "Uygulama yeni parolayla yeniden başlatılıyor..."
dc up -d app >/dev/null 2>&1 || die "docker compose up başarısız: docker compose -p sutvegol logs --tail=50 app"

ok=0
for _ in $(seq 1 20); do
  if printf '%s' "$P" | app_exec php -r 'exit(password_verify(stream_get_contents(STDIN), (string) getenv("ADMIN_PASSWORD_HASH")) ? 0 : 1);' 2>/dev/null; then
    ok=1; break
  fi
  sleep 1
done
unset P
[[ "$ok" == 1 ]] || die "Konteynerdeki hash bu parolayla eşleşmiyor (docker compose -p sutvegol exec app printenv ADMIN_PASSWORD_HASH)."

email="$(app_exec printenv ADMIN_EMAIL </dev/null || true)"
echo
echo "Tamam, parola doğrulandı."
domain="$(env_get DOMAIN)"
echo "  Adres:   https://${domain:-sutvegol.gmgaming.app}/admin/"
echo "  E-posta: $email   (birebir aynı yaz; değiştirmek için backend/.env ADMIN_EMAIL, sonra bu script)"
echo "  Not: 5 dakikada 8'den fazla hatalı deneme geçici olarak engellenir."
