# Kick Legend — Flutter/Flame

Videodan birebir kopyalanan "hedefe şut" oyunu (KICK LEGEND) + etrafındaki arayüzler. Samet'in kararı: aynı grafikler, aynı mekanik, aynı menüler.

## Yapı
- `lib/main.dart` — MaterialApp, GameWidget + `gameOver` overlay'i, çıkış akışı (kırmızı Loading → oyun baştan).
- `lib/game/geometry.dart` — sanal çözünürlük 1320x2868 (kaynak video), geniş/yakın görünüm ölçüleri (`kWide`, `kZoom`).
- `lib/game/kick_legend_game.dart` — durum makinesi, skor/can, seri + FEVER, 2 kaleci, direk sekmesi, kamera geçişi, zamanlayıcı.
- `lib/game/scene.dart` — Background, Ball (soldan yuvarlanma / bezier eğrili uçuş / düşme), TargetComp, Keeper, RestingBall, NetRipple, ScorePopup.
- `lib/game/fever.dart` — FEVER parıltı katmanı (bokeh, yıldız, altın yazı) ve bitiş halkası.
- `lib/game/hud.dart` — tabela (led.dart ile), kalpler, InputLayer (swipe → iniş noktası + parmağın ilk yönü = falso).
- `lib/game/led.dart` — 7-segment çizim; hem Flame hem Flutter tarafı kullanır.
- `lib/game/splash.dart` — gök + Loading spinner → logo alttan yükselir → sahaya pan.
- `lib/ui/` — game_over_overlay (kart, sayaçlı skor, sıra rozeti, tekrar), pause_overlay (ses/titreşim toggle, çıkış+yeniden başlat, Play), leaderboard_screen (sekmeler, sabit logo+You, podyum, liste), profile_dialog (saha/karatahta kartı, beğeni, 5'li rozet carousel'i), loading_screen (kırmızı), mock_data (yerel liste + 37 rozet), theme.
- `assets/images/` — videodan kesilmiş sprite'lar; `assets/fonts/` Titillium Web.

## Mekanik notları
- Şut: nişan = kaydırma yönü (top kale çizgisine kadar o doğrultuda), yükseklik = güç (hız 0.55 + uzunluk 0.45). Falso: çıkışta yanal bileşen 1.9× abartılır, bezier ile inişe geri büker (videoda dx/dy oranı sona doğru dikleşiyor). Uçuş 0.67 s, gerçek 3D: yer izi (gölge) ekranda 1-(1-z)^1.4 ile ilerler, boyut zamanla doğrusal 1→0.2, dünya yüksekliği = 4·380·z(1−z) + hEnd·z (top-birimi px; 1000 px ≈ 1 m). Top merkezi = yer − r − h·ölçek; gölge yerde, yükseldikçe küçülüp soluklaşır.
- Kale sonrası: top fileden aşağı düşer (0.32 s, sekme), kalenin dibinde kalır; 0.5 s sonra hedef küçülerek yok olur + "+30" + skor. Auta giden top görüş dışına uçar.
- İsabet +30 (fever'da +60), file dalgası, popup. Iskalama/kaleci = 1 kalp, seri sıfırlanır. Direk/üst direk: top düşer, yerde hedefe denk gelirse sayılır.
- 5 ardışık isabet → FEVER 10 s (altın top, parıltı, FEVER yazısı); iskalama veya süre → patlama halkası.
- Kaleci 1: 30 puan; kaleci 2: 420 puan. Genlik kale genişliği + 110 px, periyot skorla kısalır.
- Her şuttan sonra %40 geniş ↔ yakın kamera.
- Leaderboard verisi yerel (`mock_data.dart`); sunucu bağlanınca `lbEntries` değiştirilecek.

## Geliştirme bayrakları
- `--dart-define=AUTOPLAY=true` → oyun kendi kendine oynar.
- `--dart-define=UI_PREVIEW=leaderboard|profile` → ekranı doğrudan açar.
- `--dart-define=FEVER_TEST=true` → ilk toptan itibaren fever.

## Ses
- `lib/game/sfx.dart` (flame_audio). Klipler `assets/audio/` — 17:18 videosunun ses kanalından kesildi (kick, hit, miss, roll, fever start/hit/end, gameover, count_end, splash). Ses ayarı pause menüsünden; arka plan müziği yok (videoda ayrıştırılamadı).

## Test / dağıtım
- `flutter test` — swipe → şut widget testi.
- Simülatör: `flutter build ios --simulator --debug` → `xcrun simctl install/launch`.
- Telefon: `flutter run -d 00008140-001059EA14D8801C --release` (Team Y2MWRALQHR).
