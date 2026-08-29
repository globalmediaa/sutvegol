# Kick Legend — Flutter/Flame

Videodan birebir kopyalanan "hedefe şut" oyunu (KICK LEGEND) + etrafındaki arayüzler. Samet'in kararı: aynı grafikler, aynı mekanik, aynı menüler.

## Yapı
- `lib/main.dart` — MaterialApp, GameWidget + `gameOver` overlay'i, çıkış akışı (kırmızı Loading → oyun baştan).
- `lib/game/geometry.dart` — sanal çözünürlük 1320x2868 (kaynak video), geniş/yakın görünüm ölçüleri (`kWide`, `kZoom`).
- `lib/game/kick_legend_game.dart` — durum makinesi, skor/can, seri + FEVER, 2 kaleci, direk sekmesi, kamera geçişi, zamanlayıcı.
- `lib/game/scene.dart` — Background, Ball (soldan yuvarlanma / bezier eğrili uçuş / düşme), TargetComp, Keeper, RestingBall, NetRipple, ScorePopup.
- `lib/game/fever.dart` — FEVER parıltı katmanı (bokeh, yıldız, altın yazı) ve bitiş halkası.
- `lib/game/hud.dart` — tabela (led.dart ile), kalpler, InputLayer (swipe → iniş noktası + falso), pause perdesi.
- `lib/game/led.dart` — 7-segment çizim; hem Flame hem Flutter tarafı kullanır.
- `lib/game/splash.dart` — gök + Loading spinner → logo alttan yükselir → sahaya pan.
- `lib/ui/` — game_over_overlay (kart, sayaçlı skor, sıra rozeti, tekrar), leaderboard_screen (sekmeler, podyum, liste), profile_dialog (saha kartı, rozetler), loading_screen (kırmızı), mock_data (yerel örnek liste), theme.
- `assets/images/` — videodan kesilmiş sprite'lar; `assets/fonts/` Titillium Web.

## Mekanik notları
- Şut: bırakma noktası + hız payı = iniş; parmak yolunun düz çizgiden sapması → yanal bezier eğrisi (falso). Uçuş 0.36 s.
- İsabet +30 (fever'da +60), file dalgası, popup. Iskalama/kaleci = 1 kalp, seri sıfırlanır. Direk/üst direk: top düşer, yerde hedefe denk gelirse sayılır.
- 5 ardışık isabet → FEVER 10 s (altın top, parıltı, FEVER yazısı); iskalama veya süre → patlama halkası.
- Kaleci 1: 30 puan; kaleci 2: 420 puan. Genlik kale genişliği + 110 px, periyot skorla kısalır.
- Her şuttan sonra %40 geniş ↔ yakın kamera.
- Leaderboard verisi yerel (`mock_data.dart`); sunucu bağlanınca `lbEntries` değiştirilecek.

## Geliştirme bayrakları
- `--dart-define=AUTOPLAY=true` → oyun kendi kendine oynar.
- `--dart-define=UI_PREVIEW=leaderboard|profile` → ekranı doğrudan açar.

## Test / dağıtım
- `flutter test` — swipe → şut widget testi.
- Simülatör: `flutter build ios --simulator --debug` → `xcrun simctl install/launch`.
- Telefon: `flutter run -d 00008140-001059EA14D8801C --release` (Team Y2MWRALQHR).
