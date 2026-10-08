# Şut ve Gol — Flutter/Flame

Hedefe şut oyunu: kaydır → top kaleye uçar → halkaya isabet puan getirir. Skor arttıkça sahne
**Sokak → Sahil → Halı Saha → Stadyum** olarak değişir. Tüm görseller koddan çizilir (telifsiz),
sesler sentezle üretilir; hiçbir görsel/ses dosyası üçüncü taraf kaynaktan alınmaz.

## Yapı
- `lib/main.dart` — MaterialApp (lacivert tema), GameWidget + `gameOver`/`pause` overlay'leri, çıkış akışı (Yükleniyor → oyun baştan).
- `lib/game/geometry.dart` — sanal çözünürlük 1320x2868, `Stage` enum'u (etiket, skor eşiği, vurgu rengi), geniş/yakın görünüm ölçüleri (`kWide`, `kZoom`, tabela/kalp konumları), `kPauseRect`.
- `lib/game/scene_art.dart` — **prosedürel sanat**: sahne × kamera arka planları (`SceneArt.background`), açılış göğü, top görseli (kesik ikosahedron izdüşümü), kalp/hedef/kaleci çizimleri. Arka planlar `ui.Image` olarak üretilip Flame `images` cache'ine `bg_<stage>_<view>` anahtarıyla eklenir.
- `lib/game/sut_ve_gol_game.dart` — durum makinesi, skor/can, seri + Kral Modu, 2 kaleci, direk sekmesi, kamera geçişi, **sahne geçişi** (`_enterStage`: yeni bg üretimi → crossfade → afiş → ambiyans), zamanlayıcı.
- `lib/game/scene.dart` — Background (crossfade), Ball (yuvarlanma / bezier uçuş / düşme), TargetComp (sahne rengine göre halka), Keeper (siyah silüet manken, koddan çizilir), RestingBall, NetRipple, ScorePopup.
- `lib/game/fever.dart` — Kral Modu parıltı katmanı + taçlı "KRAL MODU" levhası, bitiş halkası, `StageBanner` ("YENİ SAHNE").
- `lib/game/hud.dart` — LED tabela rakamları, kalpler, InputLayer (swipe → iniş noktası + falso).
- `lib/game/led.dart` — 7-segment çizim; hem Flame hem Flutter tarafı kullanır.
- `lib/game/splash.dart` — gece göğü + Yükleniyor → logo alev iziyle belirir, köz parçacıkları → sahaya pan.
- `lib/game/sfx.dart` — flame_audio; sahneye göre ambiyans (`amb_<stage>.wav`), Kral Modu döngüsü, efektler.
- `lib/ui/theme.dart` (`FK` paleti: lacivert + turuncu/amber), `logo.dart` (paintLogo/paintCrown — Flame ve Flutter ortak), `widgets.dart` (GlassCard, PillButton (`enabled`), BusyPill, BrandHeader, SocialButton + GoogleMark (koddan çizilen G), SegmentedPill, `gameInput` alan stili, GameBackdrop (bulanık prosedürel sahne zemini, `hud: false`), RoundButton, AvatarCircle (isimden üretilen), ToggleRow, LogoWidget), `auth_screen.dart` (sokak sahnesi önünde cam kart: Apple / Google / e-posta kayıt-giriş, misafir), `username_screen.dart` (sosyal girişten sonra takma ad), `game_over_overlay.dart`, `pause_overlay.dart`, `leaderboard_screen.dart`, `profile_dialog.dart`, `loading_screen.dart`, `led_painter.dart`, `mock_data.dart` (yerel liste + 37 rozet).
- `assets/fonts/` Titillium Web (OFL). `assets/audio/` — `tools/make_audio.py` ile üretilir.

## Mekanik notları
- Şut: nişan = kaydırma yönü, yükseklik = güç (hız 0.75 + uzunluk 0.25). İniş noktası hedefe 200 px içindeyse mesafeyle orantılı (maks %50) hedefe çekilir (nişan yardımı). Falso: parmak yayının kirişten sapması bezier ile topun yer izine ölçeklenir. Uçuş 0.5 s, gerçek 3D: gölge yerde ilerler, boyut doğrusal küçülür, yükseklik parabol + hedef yüksekliği.
- Kale sonrası: top fileden aşağı düşer, kale dibinde kalır; 0.5 s sonra hedef küçülerek yok olur + "+30" + skor. Auta giden top görüş dışına uçar.
- İsabet +30 (Kral Modu'nda +60). Iskalama/kaleci = 1 kalp, seri sıfırlanır. Direk/üst direk: top düşer, yerde hedefe denk gelirse sayılır.
- 5 ardışık isabet → **Kral Modu** 10 s (altın top, parıltı, taçlı levha); iskalama veya süre → patlama halkası.
- Kaleci 1: 30 puan; kaleci 2: 420 puan. Genlik kale genişliği + 110 px, periyot skorla kısalır.
- **Sahneler:** Sokak 0+, Sahil 300+, Halı Saha 700+, Stadyum 1200+ (`Stage.minScore`). Geçiş bir sonraki topta: geniş kamera, crossfade, "YENİ SAHNE" afişi, fanfar, ambiyans değişimi. Yeniden başlatmada sokağa dönülür.
- Her şuttan sonra %40 geniş ↔ yakın kamera (aynı sahnenin diğer görünümü).
- Leaderboard verisi yerel (`mock_data.dart`); sunucu bağlanınca `lbEntries` değiştirilecek. Avatarlar isimden üretilir (fotoğraf yok).

## Geliştirme bayrakları
- `--dart-define=API_BASE_URL=https://api.alan.tld` → canlı sunucu (varsayılan example.com = yapılandırılmamış).
- `--dart-define=GOOGLE_IOS_CLIENT_ID=…apps.googleusercontent.com` → iOS Google girişi (boşsa buton "yapılandırılmamış" hatası verir, çökmez). `--dart-define=GOOGLE_SERVER_CLIENT_ID=…` → Web istemcisi; Android'de idToken için şart. iOS geri dönüş şeması `ios/Flutter/Social.xcconfig` içindeki `GOOGLE_REVERSED_CLIENT_ID` (com.googleusercontent.apps.…). Sign in with Apple entitlement'ı `Runner.entitlements` içinde.
- `--dart-define=AUTOPLAY=true` → oyun kendi kendine oynar.
- `--dart-define=UI_PREVIEW=leaderboard|profile` → ekranı doğrudan açar.
- `--dart-define=FEVER_TEST=true` → ilk toptan itibaren Kral Modu.
- `--dart-define=STAGE=beach|cage|stadium` → o sahneden başlar.

## Ses
- Tümü sentez: `python3 tools/make_audio.py` → `assets/audio/` (22.05 kHz mono). Vuruş, isabet çanı, iskalama, yuvarlanma, Kral Modu başla/isabet/bitiş + alev döngüsü, oyun bitti, sayaç, açılış, sahne fanfarı, 4 ambiyans (sokak trafiği / sahil dalgası + martı / gece halı saha / tribün).

## Kimlik
- Uygulama adı: **Şut ve Gol**. Paket `sut_ve_gol`, iOS bundle `com.globalmedia.sutVeGol`, Android `com.globalmedia.sut_ve_gol`. İkonlar: lacivert zemin, taç + top (PIL ile üretildi).
- Klasör adı hâlâ `kick-legend` (yerel yol; istenirse ayrıca taşınır).

## Test / dağıtım
- `flutter test` — swipe → şut widget testi.
- Simülatör: Xcode 27'de `flutter build ios --simulator` iki mimaride `lipo -verify_arch` hatası verir; tek mimari derle: `cd ios && xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphonesimulator -destination 'id=<UDID>' -derivedDataPath ../build/ios-sim ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build` → `xcrun simctl install booted build/ios-sim/Build/Products/Debug-iphonesimulator/Runner.app` → `xcrun simctl launch booted com.globalmedia.sutVeGol`.
- Telefon: `flutter run -d 00008140-001059EA14D8801C --release` (Team Y2MWRALQHR).

## Mağaza görselleri
- `python3 tools/make_store_artwork.py` → `store/appstore/` içine App Store ürün sayfası başlığı (21:9, 3840×1646) ve arama sonucu (3:2, 3840×2560) görsellerini PNG+JPG, alfasız üretir. Kaynak `tools/store_artwork/index.html` (headless Chrome ile çizilir; logo, docs/assets sahne görüntüleri, Titillium).

## 8 Ekim 2026 — Düello ve dağıtım güncellemesi
- Asıl kaynak `/Users/sametocak/Desktop/frikik-kral`; GitHub `globalmediaa/sutvegol`. Marka taç değil, S/top/kale logo sistemi; eski açıklamalara göre logoyu değiştirme.
- `lib/duel/`, `lib/ui/duel_screen.dart`: gerçek sunucu eşleşmesi, 90 s iki alan, 6 s countdown, sıralı/idempotent şut aktarımı. Fizik şut atan cihazda; sunucu skor/can/süre/sıra kontrolü. Solo leaderboard ayrı.
- API varsayılan `https://sutvegol.gmgaming.app/api`. Google iOS/Web ID ve ters şema dış yapılandırmadır; boşken etkin olduğunu iddia etme.
- Docker/host Nginx/GitHub Actions ve Emre kurulum bloğu `backend/README.md`. `.env`, `secrets/`, private yedekler git/imaj dışında. Mevcut Docker volume silinmez; migration eklemeli.
- 23 Flutter testi, 4 gerçek PHP/MySQL senaryosu ve lint geçti; fiziksel iPhone pil/ısı ölçümü henüz yok. Apple Sign in with Apple yetkisi Samet’in onayıyla açıldı; mevcut App Store profili aynı sertifikayla yenilendi. Build 9 (1.0.0) IPA imzalandı, Apple giriş entitlement ve strict codesign geçti. Transporter 8 Ekim 17:57 TR teslimi ve Apple processing tamamlandı. TestFlight a253df51-b109-428a-b35b-dfb4e6506382, mevcut Testciler/Internal8 ve Türkçe What to Test Saved doğrulandı; App Review yok. Canlı DNS/API, Google client ID ve Actions secrets kurulumunu Emre tamamlayacak.
