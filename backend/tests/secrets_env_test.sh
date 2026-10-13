#!/usr/bin/env bash
# backend/deploy/secrets_env.sh için yerel test. Yalnız sahte değerler: geçici bir depo
# kopyasında env.example'dan üretilen sahte backend/.env ve openssl ile üretilen sahte P-256
# anahtar kullanılır. Gerçek sudo/docker çağrılmaz (PATH'e sahte komutlar konur), depodaki
# hiçbir dosyaya dokunulmaz.
#
#   bash backend/tests/secrets_env_test.sh
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REAL_CHGRP="$(command -v chgrp)"
REAL_DOCKER="$(command -v docker || true)"
T="$(mktemp -d "${TMPDIR:-/tmp}/secrets-env-test.XXXXXX")"
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT
REPO="$T/repo"
B="$REPO/backend"
S="$B/secrets"
K="$S/apple_key.p8"
LOG="$T/fake.log"
ALL_OUT="$T/all.out"
MYGID="$(id -g)"
PASS=0
FAILS=0

check() {  # check "açıklama" komut...
  local label="$1"; shift
  if "$@"; then PASS=$((PASS + 1)); echo "ok   $label"; else FAILS=$((FAILS + 1)); echo "FAIL $label"; fi
}
eq()       { [ "$1" = "$2" ]; }
same()     { cmp -s "$1" "$2"; }
has()      { grep -qF -- "$2" "$1"; }
lacks()    { ! grep -qF -- "$2" "$1"; }
mode_of()  { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
gid_of()   { stat -c %g "$1" 2>/dev/null || stat -f %g "$1"; }
stamp_of() { stat -c '%i %Y' "$1" 2>/dev/null || stat -f '%i %m' "$1"; }
no_temp()  { [ -z "$(find "$B" -name '.env.??????' -o -name '.apple_key.p8.*' | head -n1)" ]; }
count()    { grep -c -- "$2" "$1"; }
# deploy.sh'taki env_get ile aynı okuma (son satır, tırnaksız).
env_get() {
  local v; v="$(grep -E "^$1=" "$B/.env" | tail -n1 | cut -d= -f2-)"
  case "$v" in \'*\') v="${v#\'}"; v="${v%\'}" ;; \"*\") v="${v#\"}"; v="${v%\"}" ;; esac
  printf '%s' "$v"
}

# run <çıktı> [AD=değer ...]: script'i temiz ortamla çalıştırır, çıkış kodunu RC'ye yazar.
run() {
  local out="$1"; shift
  env -i PATH="$T/bin:$PATH" HOME="$T" FAKE_LOG="$LOG" REAL_CHGRP="$REAL_CHGRP" \
    FAKE_SECRETS="$S" FAKE_GID="${TARGET_GID:-$MYGID}" SUTVEGOL_SECRETS_GID="${TARGET_GID:-$MYGID}" \
    "$@" bash "$B/deploy/secrets_env.sh" > "$out" 2>&1
  RC=$?
  cat "$out" >> "$ALL_OUT"
}

fresh() {  # temiz sahte depo: backend/.env = env.orig (600), secrets/ yok
  rm -rf "$REPO"
  mkdir -p "$B/deploy"
  cp "$ROOT/backend/deploy/secrets_env.sh" "$B/deploy/secrets_env.sh"
  cp "$T/env.orig" "$B/.env"
  chmod 600 "$B/.env"
  "$REAL_CHGRP" -R "$MYGID" "$REPO"   # macOS'te yeni dosya dizinin grubunu alır; birincil gruba sabitle
  : > "$LOG"
}

# ---------------------------------------------------------------- sahte komutlar ve veriler
mkdir -p "$T/bin"
cat > "$T/bin/sudo" <<'EOF'
#!/bin/sh
echo "sudo $*" >> "$FAKE_LOG"
if [ "${FAKE_SUDO:-fail}" = ok ] && [ "$1" = -n ] && [ "$2" = chgrp ]; then shift 2; exec "$REAL_CHGRP" "$@"; fi
exit 1
EOF
cat > "$T/bin/chgrp" <<'EOF'
#!/bin/sh
echo "chgrp $*" >> "$FAKE_LOG"
[ "${FAKE_CHGRP:-real}" = fail ] && exit 1
exec "$REAL_CHGRP" "$@"
EOF
cat > "$T/bin/docker" <<'EOF'
#!/bin/sh
echo "docker $*" >> "$FAKE_LOG"
[ "${FAKE_DOCKER:-none}" = image ] || exit 1
case "$1" in
  image) exit 0 ;;
  run)
    [ "$*" = "run --rm --pull never --network none --user 0:0 -v $FAKE_SECRETS:/s --entrypoint chgrp sutvegol-app:latest $FAKE_GID /s /s/apple_key.p8" ] || exit 2
    exec "$REAL_CHGRP" "$FAKE_GID" "$FAKE_SECRETS" "$FAKE_SECRETS/apple_key.p8" ;;
esac
exit 1
EOF
chmod +x "$T/bin/sudo" "$T/bin/chgrp" "$T/bin/docker"

openssl ecparam -genkey -name prime256v1 2>/dev/null | openssl pkcs8 -topk8 -nocrypt -out "$T/p256.pem"
openssl ecparam -genkey -name prime256v1 2>/dev/null | openssl pkcs8 -topk8 -nocrypt -out "$T/p256-2.pem"
openssl ecparam -genkey -name secp384r1 2>/dev/null | openssl pkcs8 -topk8 -nocrypt -out "$T/p384.pem"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$T/rsa.pem" 2>/dev/null
openssl pkey -in "$T/p256.pem" -outform DER -out "$T/p256.der"
b64() { base64 < "$1" | tr -d '\n'; }
KEY_B64="$(b64 "$T/p256.pem")"
KEY2_B64="$(b64 "$T/p256-2.pem")"
G_RAW=$' 111-aaa.apps.googleusercontent.com ,\n222-bbb.apps.googleusercontent.com, '
G="111-aaa.apps.googleusercontent.com,222-bbb.apps.googleusercontent.com"
G2="333-ccc.apps.googleusercontent.com"
KID="ABCDE12345"

awk '
  /^APP_KEY=$/          { print "APP_KEY=" sprintf("%064d", 1); next }
  /^DB_PASSWORD=$/      { print "DB_PASSWORD=" sprintf("%064d", 2); next }
  /^DB_ROOT_PASSWORD=$/ { print "DB_ROOT_PASSWORD=" sprintf("%064d", 3); next }
  /^ADMIN_PASSWORD_HASH=$/ { print "ADMIN_PASSWORD_HASH=\047$2y$12$sahtesahtesahtesahtesOuQhash.fake/value01234567\047"; next }
  { print }' "$ROOT/backend/deploy/env.example" > "$T/env.orig"
expected_env() {  # beklenen .env: yalnız iki boş satır değişir
  awk -v g="$1" -v k="$2" -v q="'" '
    $0 == "GOOGLE_CLIENT_IDS=" && g != "" { print "GOOGLE_CLIENT_IDS=" q g q; next }
    $0 == "APPLE_KEY_ID=" && k != ""      { print "APPLE_KEY_ID=" q k q; next }
    { print }' "$T/env.orig"
}
SECRETS=(SUTVEGOL_GOOGLE_CLIENT_IDS="$G_RAW" SUTVEGOL_APPLE_KEY_ID="$KID" SUTVEGOL_APPLE_PRIVATE_KEY_B64="$KEY_B64")
: > "$ALL_OUT"

# ---------------------------------------------------------------- 1) ilk çalıştırma
echo "== ilk çalıştırma"
fresh
run "$T/o1" "${SECRETS[@]}"
expected_env "$G" "$KID" > "$T/env.expected"
check "çıkış 0" eq "$RC" 0
check ".env yalnız GOOGLE_CLIENT_IDS ve APPLE_KEY_ID satırlarıyla değişti" same "$B/.env" "$T/env.expected"
check "Google listesi boşluk/satır sonundan arındırıldı (deploy.sh env_get)" eq "$(env_get GOOGLE_CLIENT_IDS)" "$G"
check "APPLE_KEY_ID yazıldı (deploy.sh env_get)" eq "$(env_get APPLE_KEY_ID)" "$KID"
check ".env izni 600 kaldı" eq "$(mode_of "$B/.env")" 600
check ".env.pre-oauth özgün dosya" same "$B/.env.pre-oauth" "$T/env.orig"
check ".env.pre-oauth izni 600" eq "$(mode_of "$B/.env.pre-oauth")" 600
check "anahtar backend/secrets/apple_key.p8 yolunda, birebir aynı" same "$K" "$T/p256.pem"
check "openssl anahtarı okuyor" openssl pkey -in "$K" -noout
check "apple_key.p8 izni 640" eq "$(mode_of "$K")" 640
check "apple_key.p8 grubu hedef gid" eq "$(gid_of "$K")" "$MYGID"
check "secrets/ izni 750" eq "$(mode_of "$S")" 750
check "secrets/ grubu hedef gid" eq "$(gid_of "$S")" "$MYGID"
check "geçici dosya kalmadı" no_temp
check "rapor: güncellenenler" has "$T/o1" "güncellendi: GOOGLE_CLIENT_IDS APPLE_KEY_ID apple_key.p8"
check "chgrp/sudo/docker gerekmedi" eq "$(wc -l < "$LOG" | tr -d ' ')" 0

# ---------------------------------------------------------------- 2) idempotent
echo "== ikinci çalıştırma (aynı değerler)"
cp "$B/.env" "$T/env.after1"
STAMP_ENV="$(stamp_of "$B/.env")"; STAMP_KEY="$(stamp_of "$K")"
run "$T/o2" "${SECRETS[@]}"
check "çıkış 0" eq "$RC" 0
check "değişiklik yok raporu" has "$T/o2" "değişiklik yok"
check ".env aynı" same "$B/.env" "$T/env.after1"
check ".env hiç yazılmadı (inode/mtime)" eq "$(stamp_of "$B/.env")" "$STAMP_ENV"
check "anahtar hiç yazılmadı (inode/mtime)" eq "$(stamp_of "$K")" "$STAMP_KEY"
check "izinler yerinde" eq "$(mode_of "$K") $(mode_of "$S")" "640 750"

# ---------------------------------------------------------------- 3) boş / tanımsız secret
echo "== boş ve tanımsız secret'lar"
run "$T/o3" SUTVEGOL_GOOGLE_CLIENT_IDS= SUTVEGOL_APPLE_KEY_ID= SUTVEGOL_APPLE_PRIVATE_KEY_B64=
check "boş: çıkış 0" eq "$RC" 0
check "boş: .env aynı" same "$B/.env" "$T/env.after1"
check "boş: anahtar aynı" same "$K" "$T/p256.pem"
check "boş: rapor" has "$T/o3" "boş, dokunulmadı: SUTVEGOL_GOOGLE_CLIENT_IDS SUTVEGOL_APPLE_KEY_ID SUTVEGOL_APPLE_PRIVATE_KEY_B64"
run "$T/o3b"
check "tanımsız: çıkış 0, .env ve anahtar aynı" eq "$RC $(cmp -s "$B/.env" "$T/env.after1" && cmp -s "$K" "$T/p256.pem" && echo same)" "0 same"

# ---------------------------------------------------------------- 4) geçersiz değerler
echo "== geçersiz değerler atlanır"
BAD_DESC=("Google tırnak içeriyor" "Google ters şema (com.googleusercontent.apps…)" "Google listesinde \$(id)"
  "Key ID küçük harf" "Key ID kısa" "anahtar değil (düz metin base64)" "base64 değil" "RSA anahtar"
  "P-384 anahtar" "PEM değil (DER P-256)")
BAD_ENV=("SUTVEGOL_GOOGLE_CLIENT_IDS=111-aaa.apps.googleusercontent.com'x"
  "SUTVEGOL_GOOGLE_CLIENT_IDS=com.googleusercontent.apps.111-aaa"
  "SUTVEGOL_GOOGLE_CLIENT_IDS=111-aaa.apps.googleusercontent.com,\$(id)"
  "SUTVEGOL_APPLE_KEY_ID=abcde12345"
  "SUTVEGOL_APPLE_KEY_ID=ABC123"
  "SUTVEGOL_APPLE_PRIVATE_KEY_B64=$(printf 'not a key' | base64)"
  "SUTVEGOL_APPLE_PRIVATE_KEY_B64=%%%%"
  "SUTVEGOL_APPLE_PRIVATE_KEY_B64=$(b64 "$T/rsa.pem")"
  "SUTVEGOL_APPLE_PRIVATE_KEY_B64=$(b64 "$T/p384.pem")"
  "SUTVEGOL_APPLE_PRIVATE_KEY_B64=$(b64 "$T/p256.der")")
i=0
while [ "$i" -lt "${#BAD_ENV[@]}" ]; do
  run "$T/o4" "${BAD_ENV[$i]}"
  ok=0
  [ "$RC" = 0 ] && grep -q '::warning::' "$T/o4" && cmp -s "$B/.env" "$T/env.after1" && cmp -s "$K" "$T/p256.pem" \
    && [ "$(mode_of "$K")" = 640 ] && no_temp && ok=1
  check "${BAD_DESC[$i]} → uyarı, çıkış 0, hiçbir dosya değişmedi" eq "$ok" 1
  i=$((i + 1))
done

# ---------------------------------------------------------------- 5) değer değişimi, yedek korunur
echo "== değer değişimi"
run "$T/o5" SUTVEGOL_GOOGLE_CLIENT_IDS="$G2" SUTVEGOL_APPLE_PRIVATE_KEY_B64="$KEY2_B64"
check "çıkış 0" eq "$RC" 0
check "GOOGLE_CLIENT_IDS yeni değer" eq "$(env_get GOOGLE_CLIENT_IDS)" "$G2"
check "APPLE_KEY_ID korunuyor" eq "$(env_get APPLE_KEY_ID)" "$KID"
check "GOOGLE_CLIENT_IDS tek satır" eq "$(count "$B/.env" '^GOOGLE_CLIENT_IDS=')" 1
check ".env.pre-oauth ilk hali olarak kaldı" same "$B/.env.pre-oauth" "$T/env.orig"
check "yeni anahtar yazıldı, 640" eq "$(cmp -s "$K" "$T/p256-2.pem" && echo same) $(mode_of "$K")" "same 640"
check "rapor" has "$T/o5" "güncellendi: GOOGLE_CLIENT_IDS apple_key.p8"

# ---------------------------------------------------------------- 6) tekrar eden / eksik satırlar
echo "== tekrar eden ve eksik satırlar"
fresh
printf 'APP_KEY=x\nGOOGLE_CLIENT_IDS=eski1\nexport APPLE_KEY_ID=OLDOLDOLD1\nGOOGLE_CLIENT_IDS=eski2\nZ=son\n' > "$B/.env"
run "$T/o6" SUTVEGOL_GOOGLE_CLIENT_IDS="$G2" SUTVEGOL_APPLE_KEY_ID="$KID"
printf "APP_KEY=x\nGOOGLE_CLIENT_IDS='%s'\nAPPLE_KEY_ID='%s'\nZ=son\n" "$G2" "$KID" > "$T/env6.expected"
check "ilk satır değişti, tekrar silindi, export düzeldi" same "$B/.env" "$T/env6.expected"
printf 'APP_KEY=x\n# yorum\n' > "$B/.env"
run "$T/o6b" SUTVEGOL_GOOGLE_CLIENT_IDS="$G2" SUTVEGOL_APPLE_KEY_ID="$KID"
printf "APP_KEY=x\n# yorum\nGOOGLE_CLIENT_IDS='%s'\nAPPLE_KEY_ID='%s'\n" "$G2" "$KID" > "$T/env6b.expected"
check "eksik satırlar sona eklendi" same "$B/.env" "$T/env6b.expected"
cp "$T/env.orig" "$B/.env"; chmod 640 "$B/.env"
run "$T/o6c" SUTVEGOL_APPLE_KEY_ID="$KID"
check ".env izni (640) korundu" eq "$(mode_of "$B/.env")" 640

# ---------------------------------------------------------------- 7) .env yok / eski düzen
echo "== ilk kurulum ve eski düzen"
fresh
rm -f "$B/.env"
run "$T/o7" "${SECRETS[@]}"
check ".env yok: çıkış 0 ve uyarı" eq "$RC $(grep -c '::warning::.*backend/.env yok' "$T/o7")" "0 1"
check ".env yok: .env oluşturulmadı" test ! -e "$B/.env"
check ".env yok: anahtar yine yazıldı (640)" eq "$(cmp -s "$K" "$T/p256.pem" && echo same) $(mode_of "$K")" "same 640"
fresh
mkdir "$REPO/secrets"
run "$T/o7b" "${SECRETS[@]}"
check "kökte eski secrets/: backend/secrets oluşturulmadı" test ! -e "$S"
check "kökte eski secrets/: uyarı, .env yine güncellendi" eq "$(grep -c '::warning::.*eski secrets' "$T/o7b") $(env_get APPLE_KEY_ID)" "1 $KID"

# ---------------------------------------------------------------- 8) grup: sudo ve docker yedekleri
SECOND_GID=""
for g in $(id -G); do [ "$g" != "$MYGID" ] && { SECOND_GID="$g"; break; }; done
if [ -n "$SECOND_GID" ]; then
  echo "== grup sudo -n ile (hedef gid $SECOND_GID)"
  fresh
  TARGET_GID="$SECOND_GID"
  run "$T/o8" "${SECRETS[@]}" FAKE_CHGRP=fail FAKE_SUDO=ok
  check "sudo -n chgrp kullanıldı, docker yok" eq "$(grep -c '^sudo -n chgrp' "$LOG") $(grep -c '^docker' "$LOG")" "1 0"
  check "anahtar 640 + hedef grup, secrets/ hedef grup" eq "$(mode_of "$K") $(gid_of "$K") $(gid_of "$S")" "640 $SECOND_GID $SECOND_GID"
  echo "== grup docker ile (sudo yok)"
  fresh
  run "$T/o8b" "${SECRETS[@]}" FAKE_CHGRP=fail FAKE_SUDO=fail FAKE_DOCKER=image
  check "docker run (--pull never --network none, yerel imaj) kullanıldı" has "$LOG" "docker run --rm --pull never --network none --user 0:0 -v $S:/s --entrypoint chgrp sutvegol-app:latest $SECOND_GID /s /s/apple_key.p8"
  check "anahtar 640 + hedef grup, secrets/ hedef grup" eq "$(mode_of "$K") $(gid_of "$K") $(gid_of "$S")" "640 $SECOND_GID $SECOND_GID"
  check "uyarı yok" lacks "$T/o8b" "::warning::"
  echo "== izin düzeltme raporu (içerik aynı, grup yanlış)"
  "$REAL_CHGRP" "$MYGID" "$S" "$K"; chmod 600 "$K"
  run "$T/o8c" "${SECRETS[@]}"
  check "yalnız izin düzeltildi" eq "$(grep -c 'güncellendi: apple_key.p8(izin)' "$T/o8c") $(mode_of "$K") $(gid_of "$K")" "1 640 $SECOND_GID"
  TARGET_GID=""
else
  echo "skip sudo/docker grup testleri (kullanıcının ikinci grubu yok)"
fi
NOT_MINE=""
for g in 0 1 2 3 4 5 7 9 13 26 27 65534; do
  case " $(id -G) " in *" $g "*) ;; *) NOT_MINE="$g"; break ;; esac
done
if [ "$(id -u)" != 0 ] && [ -n "$NOT_MINE" ]; then
  echo "== grup verilemiyor (hedef gid $NOT_MINE, sudo/docker yok)"
  fresh
  TARGET_GID="$NOT_MINE"
  run "$T/o9" "${SECRETS[@]}"
  check "çıkış 0, elle komut uyarısı" eq "$RC $(grep -c "::warning::.*sudo chgrp $NOT_MINE backend/secrets" "$T/o9")" "0 1"
  check "anahtar yazıldı ama 600 kaldı (grup okuyamaz)" eq "$(cmp -s "$K" "$T/p256.pem" && echo same) $(mode_of "$K")" "same 600"
  check ".env yine güncellendi" eq "$(env_get APPLE_KEY_ID)" "$KID"
  TARGET_GID=""
else
  echo "skip grup verilemiyor testi (root ya da uygun gid yok)"
fi

# ---------------------------------------------------------------- 9) docker compose gerçekten okuyor mu
fresh
run "$T/o10" "${SECRETS[@]}"
cp "$ROOT/backend/compose.yaml" "$B/compose.yaml"
if [ -n "$REAL_DOCKER" ] && "$REAL_DOCKER" compose version >/dev/null 2>&1 \
  && "$REAL_DOCKER" compose -p sutvegol_secrets_test -f "$B/compose.yaml" --env-file "$B/.env" config --format json > "$T/compose.json" 2>"$T/compose.err"; then
  echo "== docker compose config (gerçek compose.yaml)"
  # "config" çıktısı düz "$" işaretini "$$" yazar; konteynere "$" gider.
  app_env() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["services"]["app"]["environment"].get(sys.argv[2], "").replace("$$", "$"))' "$T/compose.json" "$1"; }
  check "compose: GOOGLE_CLIENT_IDS konteynere aynen gidiyor" eq "$(app_env GOOGLE_CLIENT_IDS)" "$G"
  check "compose: APPLE_KEY_ID konteynere aynen gidiyor" eq "$(app_env APPLE_KEY_ID)" "$KID"
  check "compose: APPLE_KEY_FILE /run/secrets/apple_key.p8" eq "$(app_env APPLE_KEY_FILE)" "/run/secrets/apple_key.p8"
  check "compose: ADMIN_PASSWORD_HASH bozulmadı" eq "$(app_env ADMIN_PASSWORD_HASH)" '$2y$12$sahtesahtesahtesahtesOuQhash.fake/value01234567'
  check "compose: secrets/ → /run/secrets (ro)" python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))["services"]["app"]["volumes"]; sys.exit(0 if any(x["source"]==sys.argv[2] and x["target"]=="/run/secrets" and x.get("read_only") for x in v) else 1)' "$T/compose.json" "$S"
else
  echo "skip docker compose config (docker CLI yok ya da config çalışmadı)"
fi

# ---------------------------------------------------------------- 10) çıktıda sır yok
echo "== çıktı"
{ printf '%s\n' "$KEY_B64" "$KEY2_B64" "PRIVATE KEY" "$KID" "111-aaa" "333-ccc"
  for v in "${BAD_ENV[@]}"; do printf '%s\n' "${v#*=}"; done; } | grep -v '^%%%%$' > "$T/needles"
check "çıktıda hiçbir anahtar/base64/ID değeri yok (geçersizler dahil)" eq "$(grep -cF -f "$T/needles" "$ALL_OUT")" 0

echo "$((PASS + FAILS)) kontrol, $FAILS hata"
[ "$FAILS" = 0 ]
