# Kick Legend — Flutter/Flame

Videodan birebir kopyalanan "hedefe şut" oyunu (KICK LEGEND). Samet'in kararı: aynı grafikler, aynı mekanik.

## Yapı
- `lib/game/geometry.dart` — sanal çözünürlük 1320x2868 (kaynak video), geniş/yakın görünüm ölçüleri (`kWide`, `kZoom`).
- `lib/game/kick_legend_game.dart` — durum makinesi (splash → idle → flying → resolving), skor/can, kamera geçişi, zamanlayıcı.
- `lib/game/scene.dart` — Background (crossfade), Ball (giriş/uçuş/perspektif), TargetComp, Keeper (raylı manken), RestingBall, NetRipple, ScorePopup.
- `lib/game/hud.dart` — 7-segment tabela + kalpler, InputLayer (swipe = şut, sağ üst = pause), OverlayLayer (pause / game over).
- `lib/game/splash.dart` — açılış: gök akışı, logo alttan yükselir, sahaya pan.
- `assets/images/` — video karelerinden kesilmiş sprite'lar (bg_wide, bg_zoom, splash_bg, logo, ball, target, keeper, heart). Tabela rakam/kalp alanları arka planda boş; runtime'da çiziliyor.

## Mekanik notları
- Şut: bırakma noktası + hız payı = iniş noktası; top 0.28 s'de kaleye küçülerek uçar.
- İsabet: +30, file dalgası, "+30" popup, hedef 0.55 s sonra yeni yerde. Iskalama/kaleci bloğu: 1 kalp.
- Kaleci 30 puandan sonra aktif, 3.2 s periyotla ray üstünde salınır.
- Her şuttan sonra %40 ihtimalle geniş ↔ yakın kamera.
- `--dart-define=AUTOPLAY=true` → oyun kendi kendine oynar (test/ekran görüntüsü için).

## Test
- `flutter test` — swipe → şut widget testi.
- Simülatör: `flutter build ios --simulator --debug` sonra `xcrun simctl install/launch`.
