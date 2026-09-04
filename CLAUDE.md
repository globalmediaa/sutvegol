# Frikik Kral (Free Kick King) — Flutter/Flame

Hedefe şut oyunu: kaydır → top kaleye uçar → halkaya isabet puan getirir. Skor arttıkça sahne
**Sokak → Halı Saha → Stadyum** olarak değişir. Tüm görseller koddan çizilir (telifsiz),
sesler sentezle üretilir; hiçbir görsel/ses dosyası üçüncü taraf kaynaktan alınmaz.

## Yapı
- `lib/main.dart` — MaterialApp (lacivert tema), GameWidget + `gameOver`/`pause` overlay'leri, çıkış akışı (Yükleniyor → oyun baştan).
- `lib/game/geometry.dart` — sanal çözünürlük 1320x2868, `Stage` enum'u (etiket, skor eşiği, vurgu rengi), geniş/yakın görünüm ölçüleri (`kWide`, `kZoom`, tabela/kalp konumları), `kPauseRect`.
- `lib/game/scene_art.dart` — **prosedürel sanat**: sahne × kamera arka planları (`SceneArt.background`), açılış göğü, top görseli (kesik ikosahedron izdüşümü), kalp/hedef/kaleci çizimleri. Arka planlar `ui.Image` olarak üretilip Flame `images` cache'ine `bg_<stage>_<view>` anahtarıyla eklenir.
- `lib/game/frikik_kral_game.dart` — durum makinesi, skor/can, seri + Kral Modu, 2 kaleci, direk sekmesi, kamera geçişi, **sahne geçişi** (`_enterStage`: yeni bg üretimi → crossfade → afiş → ambiyans), zamanlayıcı.
- `lib/game/scene.dart` — Background (crossfade), Ball (yuvarlanma / bezier uçuş / düşme), TargetComp (sahne rengine göre halka), Keeper (manken), RestingBall, NetRipple, ScorePopup.
- `lib/game/fever.dart` — Kral Modu parıltı katmanı + taçlı "KRAL MODU" levhası, bitiş halkası, `StageBanner` ("YENİ SAHNE").
- `lib/game/hud.dart` — LED tabela rakamları, kalpler, InputLayer (swipe → iniş noktası + falso).
- `lib/game/led.dart` — 7-segment çizim; hem Flame hem Flutter tarafı kullanır.
- `lib/game/splash.dart` — gece göğü + Yükleniyor → logo alev iziyle belirir, köz parçacıkları → sahaya pan.
- `lib/game/sfx.dart` — flame_audio; sahneye göre ambiyans (`amb_<stage>.wav`), Kral Modu döngüsü, efektler.
- `lib/ui/theme.dart` (`FK` paleti: lacivert + turuncu/amber), `logo.dart` (paintLogo/paintCrown — Flame ve Flutter ortak), `widgets.dart` (GlassCard, PillButton, RoundButton, AvatarCircle (isimden üretilen), ToggleRow, LogoWidget), `game_over_overlay.dart`, `pause_overlay.dart`, `leaderboard_screen.dart`, `profile_dialog.dart`, `loading_screen.dart`, `led_painter.dart`, `mock_data.dart` (yerel liste + 37 rozet).
- `assets/fonts/` Titillium Web (OFL). `assets/audio/` — `tools/make_audio.py` ile üretilir.

## Mekanik notları
- Şut: nişan = kaydırma yönü, yükseklik = güç (hız 0.75 + uzunluk 0.25). Falso: parmak yayının kirişten sapması bezier ile topun yer izine ölçeklenir. Uçuş 0.58 s, gerçek 3D: gölge yerde ilerler, boyut doğrusal küçülür, yükseklik parabol + hedef yüksekliği.
- Kale sonrası: top fileden aşağı düşer, kale dibinde kalır; 0.5 s sonra hedef küçülerek yok olur + "+30" + skor. Auta giden top görüş dışına uçar.
- İsabet +30 (Kral Modu'nda +60). Iskalama/kaleci = 1 kalp, seri sıfırlanır. Direk/üst direk: top düşer, yerde hedefe denk gelirse sayılır.
- 5 ardışık isabet → **Kral Modu** 10 s (altın top, parıltı, taçlı levha); iskalama veya süre → patlama halkası.
- Kaleci 1: 30 puan; kaleci 2: 420 puan. Genlik kale genişliği + 110 px, periyot skorla kısalır.
- **Sahneler:** Sokak 0+, Halı Saha 300+, Stadyum 900+ (`Stage.minScore`). Geçiş bir sonraki topta: geniş kamera, crossfade, "YENİ SAHNE" afişi, fanfar, ambiyans değişimi. Yeniden başlatmada sokağa dönülür.
- Her şuttan sonra %40 geniş ↔ yakın kamera (aynı sahnenin diğer görünümü).
- Leaderboard verisi yerel (`mock_data.dart`); sunucu bağlanınca `lbEntries` değiştirilecek. Avatarlar isimden üretilir (fotoğraf yok).

## Geliştirme bayrakları
- `--dart-define=AUTOPLAY=true` → oyun kendi kendine oynar.
- `--dart-define=UI_PREVIEW=leaderboard|profile` → ekranı doğrudan açar.
- `--dart-define=FEVER_TEST=true` → ilk toptan itibaren Kral Modu.
- `--dart-define=STAGE=cage|stadium` → o sahneden başlar.

## Ses
- Tümü sentez: `python3 tools/make_audio.py` → `assets/audio/` (22.05 kHz mono). Vuruş, isabet çanı, iskalama, yuvarlanma, Kral Modu başla/isabet/bitiş + alev döngüsü, oyun bitti, sayaç, açılış, sahne fanfarı, 3 ambiyans (sokak trafiği / gece halı saha / tribün).

## Kimlik
- Uygulama adı: **Frikik Kral**. Paket `frikik_kral`, iOS bundle `com.globalmedia.frikikKral`, Android `com.globalmedia.frikik_kral`. İkonlar: lacivert zemin, taç + top (PIL ile üretildi).
- Klasör adı hâlâ `kick-legend` (yerel yol; istenirse ayrıca taşınır).

## Test / dağıtım
- `flutter test` — swipe → şut widget testi.
- Simülatör: `flutter build ios --simulator --debug` → `xcrun simctl install/launch`.
- Telefon: `flutter run -d 00008140-001059EA14D8801C --release` (Team Y2MWRALQHR).
