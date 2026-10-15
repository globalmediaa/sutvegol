#!/usr/bin/env bash
# Google Play için imzalı App Bundle üretir → build/play/sut-ve-gol-<sürüm>-<kod>.aab
#
#   bash tools/build_android.sh
#
# Yükleme anahtarı depo dışındadır: ~/.android/sutvegol-release/credentials.properties
# (keystore, alias, store_password, key_password; yol SUTVEGOL_ANDROID_CREDENTIALS ile
# değiştirilebilir). Aynı dosyaya Google Cloud'daki Web istemci kimliği eklenirse Android'de
# "Google ile devam et" açılır; yoksa düğme hiç gösterilmez:
#   google_server_client_id=846087551741-….apps.googleusercontent.com
# Sürüm pubspec.yaml'dan gelir (1.0.0+13 → versionName 1.0.0, versionCode 13); Play'e her
# yüklemede kod artmalı.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRED="${SUTVEGOL_ANDROID_CREDENTIALS:-$HOME/.android/sutvegol-release/credentials.properties}"
export SUTVEGOL_ANDROID_CREDENTIALS="$CRED"

die() { printf '[hata] %s\n' "$*" >&2; exit 1; }
prop() { grep -E "^$1=" "$CRED" | tail -n1 | cut -d= -f2- || true; }

[[ -f "$CRED" ]] || die "Yükleme anahtarı bilgisi yok: $CRED"
keystore="$(prop keystore)" alias="$(prop alias)"
[[ -f "$keystore" ]] || die "Keystore bulunamadı: $keystore"
keytool="$(command -v keytool || echo /opt/homebrew/opt/openjdk@17/bin/keytool)"
[[ -x "$keytool" ]] || die "keytool bulunamadı (JDK 17 gerekli)."

version="$(grep -E '^version:' "$ROOT/pubspec.yaml" | awk '{print $2}')"
name="${version%%+*}" code="${version##*+}"
[[ "$name" != "$code" ]] || die "pubspec.yaml version '<ad>+<kod>' biçiminde olmalı."

defines=()
google="$(prop google_server_client_id)"
if [[ -n "$google" ]]; then
  [[ "$google" == *.apps.googleusercontent.com ]] || die "google_server_client_id geçersiz: $google"
  defines+=("--dart-define=GOOGLE_SERVER_CLIENT_ID=$google")
fi

cd "$ROOT"
echo "==> Şut ve Gol $name ($code) — Google girişi: $([[ -n "$google" ]] && echo açık || echo kapalı)"
flutter build appbundle --release ${defines[@]+"${defines[@]}"}

aab="$ROOT/build/app/outputs/bundle/release/app-release.aab"
[[ -f "$aab" ]] || die "AAB üretilmedi: $aab"

# İmza yükleme anahtarına mı ait? (Debug anahtarıyla imzalı paket Play'de reddedilir.)
want="$("$keytool" -list -v -keystore "$keystore" -alias "$alias" -storepass "$(prop store_password)" 2>/dev/null \
  | awk '/SHA256:/{print $2; exit}')"
got="$("$keytool" -printcert -jarfile "$aab" 2>/dev/null | awk '/SHA256:/{print $2; exit}')"
[[ -n "$want" && "$got" == "$want" ]] || die "AAB yükleme anahtarıyla imzalanmamış (beklenen $want, bulunan ${got:-yok})."

out="$ROOT/build/play/sut-ve-gol-$name-$code.aab"
mkdir -p "$(dirname "$out")"
cp "$aab" "$out"
sha1="$("$keytool" -list -v -keystore "$keystore" -alias "$alias" -storepass "$(prop store_password)" 2>/dev/null \
  | awk '/SHA1:/{print $2; exit}')"

echo
echo "Hazır: ${out#"$ROOT"/} ($(du -h "$out" | cut -f1))"
echo "  Paket com.globalmedia.sut_ve_gol · sürüm $name · kod $code"
echo "  İmza: yükleme anahtarı ($alias) SHA-256 $got"
echo "  Google OAuth Android istemcisi için yükleme anahtarı SHA-1: $sha1"
echo "  (Play'den dağıtılan sürüm için Play Console → Uygulama bütünlüğü'ndeki uygulama imzalama SHA-1'i de eklenmeli.)"
