import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sut_ve_gol/duel/duel_api.dart';
import 'package:sut_ve_gol/duel/duel_controller.dart';
import 'package:sut_ve_gol/duel/duel_protocol.dart';
import 'package:sut_ve_gol/game/geometry.dart';
import 'package:sut_ve_gol/game/sfx.dart';
import 'package:sut_ve_gol/game/sut_ve_gol_game.dart';
import 'package:sut_ve_gol/main.dart';
import 'package:sut_ve_gol/services/game_service.dart';
import 'package:sut_ve_gol/ui/duel_screen.dart';
import 'package:sut_ve_gol/ui/game_over_overlay.dart';
import 'package:sut_ve_gol/ui/leaderboard_screen.dart';
import 'package:sut_ve_gol/ui/logo.dart';
import 'package:sut_ve_gol/ui/theme.dart';
import 'package:sut_ve_gol/ui/tutorial_overlay.dart';
import 'package:sut_ve_gol/ui/widgets.dart';

/// Google Play mağaza görselleri (normal test koşusunda atlanır):
///
///   flutter test test/play_store_assets_test.dart --dart-define=EXPORT_PLAY_ASSETS=true
///
/// Çıktı `store/google-play/` altında: `raw/01–08.png` (1080×2400 ham oyun ekranı),
/// `{tr,en-US}/phone/01–08.png` (1080×1920 başlıklı kare, 24-bit), `{tr,en-US}/feature-graphic.png`
/// (1024×500, 24-bit) ve `icon-512.png`. Ham ekranlar önce üretilir; kareler onlardan çizilir.
/// Arayüz yalnız Türkçe olduğu için iki dilde de oyun içi metin Türkçedir, başlıklar çevrilir.
void main() {
  const export = bool.fromEnvironment('EXPORT_PLAY_ASSETS');
  const out = 'store/google-play';
  const phone = Size(360, 800); // 1080×2400, tipik 20:9 Android telefon
  const dpr = 3.0;

  void phoneView(WidgetTester tester, {bool bars = false}) {
    tester.view.physicalSize = phone * dpr;
    tester.view.devicePixelRatio = dpr;
    if (bars) {
      // Durum çubuğu 24 dp, hareket çubuğu 16 dp (kenardan kenara).
      tester.view.padding = const FakeViewPadding(
        top: 24 * dpr,
        bottom: 16 * dpr,
      );
      tester.view.viewPadding = const FakeViewPadding(
        top: 24 * dpr,
        bottom: 16 * dpr,
      );
    }
    addTearDown(tester.view.reset);
  }

  Future<void> frames(WidgetTester tester, double seconds) async {
    for (var i = 0; i < (seconds / 0.016).round(); i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> capture(
    WidgetTester tester,
    GlobalKey key,
    String path, {
    double pixelRatio = dpr,
    bool opaque = false,
  }) => tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = opaque
        ? await _rgbPng(image)
        : (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    image.dispose();
  });

  /// Tek kişilik oyun, verilen sahnede top yerde beklerken.
  Future<SutVeGolGame> pumpGame(
    WidgetTester tester,
    GlobalKey key,
    Stage stage,
  ) async {
    Sfx.skipInit = true;
    SharedPreferences.setMockInitialValues({'tutorial_done': true, 'best': 1});
    await tester.runAsync(_loadFonts);
    final game = SutVeGolGame()..stage = stage;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          home: RepaintBoundary(
            key: key,
            child: GameWidget(
              game: game,
              overlayBuilderMap: {
                kGameOverOverlay: (context, SutVeGolGame g) =>
                    GameOverOverlay(game: g),
              },
            ),
          ),
        ),
      );
      await game.loaded;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    for (var i = 0; i < 400 && game.state != GameState.idle; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect(game.state, GameState.idle);
    return game;
  }

  Offset ballOnScreen(SutVeGolGame game) => WorldFrame.of(
    phone,
  ).toScreen(Offset(game.view.ballRest.x, game.view.ballRest.y));

  group('ham ekranlar', () {
    testWidgets('01 sokak: şut havada', (tester) async {
      phoneView(tester);
      final key = GlobalKey();
      final game = await pumpGame(tester, key, Stage.street);
      game
        ..score = 90
        ..best = 480
        ..streak = 3;
      await tester.timedDragFrom(
        ballOnScreen(game),
        const Offset(-24, -270),
        const Duration(milliseconds: 170),
      );
      await frames(tester, 0.04);
      await capture(tester, key, '$out/raw/01-sokak-sut.png');
    }, skip: !export);

    testWidgets('02 kral modu', (tester) async {
      phoneView(tester);
      final key = GlobalKey();
      final game = await pumpGame(tester, key, Stage.cage);
      game
        ..score = 960
        ..best = 1240
        ..streak = 5;
      for (final k in game.keepers) {
        k.activate();
      }
      game.startFever();
      await frames(tester, 1.4);
      await capture(tester, key, '$out/raw/02-kral-modu.png');
    }, skip: !export);

    testWidgets('03 online düello', (tester) async {
      phoneView(tester, bars: true);
      Sfx.skipInit = true;
      SharedPreferences.setMockInitialValues({'tutorial_done': true});
      await tester.runAsync(_loadFonts);
      final api = _DuelApi(_duelSnapshot());
      final c = DuelController(
        userId: 'me',
        api: api,
        now: () => 41000,
        autoPoll: false,
      );
      final key = GlobalKey();
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(),
            home: RepaintBoundary(
              key: key,
              child: DuelScreen(controller: c),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await frames(tester, 0.4);
      }
      await capture(tester, key, '$out/raw/03-online-duello.png');
      await tester.pumpWidget(const SizedBox());
      await frames(tester, 0.2);
      c.dispose();
    }, skip: !export);

    testWidgets('04 sahil', (tester) async {
      phoneView(tester);
      final key = GlobalKey();
      final game = await pumpGame(tester, key, Stage.beach);
      game
        ..score = 360
        ..best = 720
        ..streak = 2;
      game.keepers.first.activate();
      await frames(tester, 1.6);
      await capture(tester, key, '$out/raw/04-sahil.png');
    }, skip: !export);

    testWidgets('05 stadyum: falsolu şut', (tester) async {
      phoneView(tester);
      final key = GlobalKey();
      final game = await pumpGame(tester, key, Stage.stadium);
      game
        ..score = 1380
        ..best = 2150
        ..lives = 2
        ..streak = 4;
      for (final k in game.keepers) {
        k.activate();
      }
      await frames(tester, 1.2);
      // Sağa kavisli parmak yayı: falso.
      final start = ballOnScreen(game);
      final g = await tester.startGesture(start);
      for (var i = 1; i <= 10; i++) {
        final t = i / 10;
        await g.moveTo(start + Offset(70 * t * (1 - t) * 4 - 20 * t, -280 * t));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await frames(tester, 0.04);
      await capture(tester, key, '$out/raw/05-stadyum-falso.png');
    }, skip: !export);

    testWidgets('06 sıralama', (tester) async {
      phoneView(tester, bars: true);
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(_loadFonts);
      final key = GlobalKey();
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(),
            home: RepaintBoundary(
              key: key,
              child: LeaderboardScreen(
                myScore: 1380,
                loader: (_) async => _leaders,
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await frames(tester, 1.2);
      await capture(tester, key, '$out/raw/06-siralama.png');
    }, skip: !export);

    testWidgets('07 rehber', (tester) async {
      phoneView(tester, bars: true);
      Sfx.skipInit = true;
      SharedPreferences.setMockInitialValues({});
      debugDisableShadows = false;
      try {
        await tester.runAsync(_loadFonts);
        final key = GlobalKey();
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: appTheme(),
              home: RepaintBoundary(
                key: key,
                child: const GameScreen(guest: true),
              ),
            ),
          );
          final game = tester
              .widget<GameWidget<SutVeGolGame>>(
                find.byType(GameWidget<SutVeGolGame>),
              )
              .game!;
          await game.loaded;
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        final game = tester
            .widget<GameWidget<SutVeGolGame>>(
              find.byType(GameWidget<SutVeGolGame>),
            )
            .game!;
        for (var i = 0; i < 400 && !game.tutorialActive; i++) {
          await tester.pump(const Duration(milliseconds: 33));
        }
        expect(game.tutorialActive, isTrue);
        await frames(tester, 0.62);
        await capture(tester, key, '$out/raw/07-rehber.png');
      } finally {
        debugDisableShadows = true;
      }
    }, skip: !export);

    testWidgets('08 oyun sonu', (tester) async {
      phoneView(tester, bars: true);
      final key = GlobalKey();
      final game = await pumpGame(tester, key, Stage.stadium);
      game
        ..score = 1530
        ..best = 1530
        ..lives = 0
        ..runShots = 64
        ..runHits = 51
        ..runMisses = 13
        ..runFeverHits = 12
        ..runMaxStreak = 14
        ..state = GameState.gameOver;
      game.overlays.add(kGameOverOverlay);
      await frames(tester, 2.4);
      await capture(tester, key, '$out/raw/08-oyun-sonu.png');
    }, skip: !export);
  });

  group('mağaza kareleri', () {
    for (final lang in _captions.keys) {
      testWidgets('$lang telefon kareleri', (tester) async {
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.reset);
        await tester.runAsync(_loadFonts);
        final shots = _captions[lang]!;
        for (var i = 0; i < shots.length; i++) {
          final (file, badge, headline) = shots[i];
          final shot = await tester.runAsync(() => _decode('$out/raw/$file'));
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: appTheme(),
              home: RepaintBoundary(
                key: key,
                child: _PhoneFrame(
                  shot: shot!,
                  badge: badge,
                  headline: headline,
                ),
              ),
            ),
          );
          await tester.pump();
          await capture(
            tester,
            key,
            '$out/$lang/phone/${(i + 1).toString().padLeft(2, '0')}.png',
            opaque: true,
          );
        }
      }, skip: !export);

      testWidgets('$lang öne çıkan grafik', (tester) async {
        tester.view.physicalSize = const Size(1024, 500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.runAsync(_loadFonts);
        final scene = await tester.runAsync(
          () => _decode('$out/raw/05-stadyum-falso.png'),
        );
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(),
            home: RepaintBoundary(
              key: key,
              child: _FeatureGraphic(scene: scene!, tagline: _taglines[lang]!),
            ),
          ),
        );
        await tester.pump();
        await capture(
          tester,
          key,
          '$out/$lang/feature-graphic.png',
          pixelRatio: 1,
          opaque: true,
        );
      }, skip: !export);
    }

    test('512 simge', () async {
      final bytes = await File('assets/brand/app-icon.png').readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 512,
        targetHeight: 512,
      );
      final image = (await codec.getNextFrame()).image;
      // Play simgesi 32-bit (alfa kanallı) PNG ister.
      await File(
        '$out/icon-512.png',
      ).writeAsBytes(await _png(image, alpha: true));
    }, skip: !export);
  });
}

Future<void> _loadFonts() async {
  final titillium = FontLoader('TitilliumWeb')
    ..addFont(rootBundle.load('assets/fonts/TitilliumWeb-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/TitilliumWeb-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/TitilliumWeb-Bold.ttf'));
  await titillium.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  await loadBrandIdentity();
}

Future<ui.Image> _decode(String path) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  return (await codec.getNextFrame()).image;
}

/// (ham dosya, rozet, başlık) — oyun içi iddialar mekaniğe birebir uyar.
const _captions = {
  'tr': [
    (
      '01-sokak-sut.png',
      'KAYDIR, ŞUT ÇEK',
      'Parmağınla nişan al, falso ver, golü at!',
    ),
    (
      '02-kral-modu.png',
      'KRAL MODU',
      'Üst üste 5 isabet: 10 saniye çift puan!',
    ),
    (
      '03-online-duello.png',
      'ONLINE DÜELLO',
      '90 saniye, gerçek rakip, tek kazanan.',
    ),
    (
      '04-sahil.png',
      '4 FARKLI SAHA',
      'Sokaktan sahile, halı sahadan stadyuma.',
    ),
    (
      '05-stadyum-falso.png',
      'KALECİLERİ GEÇ',
      'İki kaleci, dar açılar: falsoyla köşeyi bul.',
    ),
    ('06-siralama.png', 'SIRALAMA', 'Haftalık listede zirveye oyna.'),
    ('07-rehber.png', 'KOLAY ÖĞREN', 'Nişan, falso ve güç adım adım.'),
    ('08-oyun-sonu.png', 'REKORUNU KIR', 'Her oyun yeni bir rekor şansı.'),
  ],
  'en-US': [
    (
      '01-sokak-sut.png',
      'SWIPE TO SHOOT',
      'Aim with your finger, add curve, score!',
    ),
    (
      '02-kral-modu.png',
      'KING MODE',
      '5 hits in a row: double points for 10 seconds!',
    ),
    (
      '03-online-duello.png',
      'ONLINE DUELS',
      '90 seconds. A real rival. One winner.',
    ),
    (
      '04-sahil.png',
      '4 PITCHES',
      'From the street to the beach, the cage and the stadium.',
    ),
    (
      '05-stadyum-falso.png',
      'BEAT THE KEEPERS',
      'Two keepers, tight angles: bend it into the corner.',
    ),
    ('06-siralama.png', 'LEADERBOARD', 'Climb to the top of the weekly chart.'),
    ('07-rehber.png', 'EASY TO LEARN', 'Aim, curve and power, step by step.'),
    (
      '08-oyun-sonu.png',
      'BREAK YOUR RECORD',
      'Every run is a new shot at your best.',
    ),
  ],
};

const _taglines = {
  'tr': 'Kaydır, şut çek, rekoru kır!',
  'en-US': 'Swipe, shoot, break the record!',
};

/// Örnek sıralama (mağaza görseli; gerçek kullanıcı değildir).
const _leaders = [
  LeaderboardEntry(id: 'u1', username: 'FalsoKral', score: 4260, games: 212),
  LeaderboardEntry(id: 'u2', username: 'golcu_ece', score: 3870, games: 168),
  LeaderboardEntry(id: 'u3', username: 'TopcuAli', score: 3510, games: 143),
  LeaderboardEntry(id: 'u4', username: 'deniz_10', score: 3120, games: 97),
  LeaderboardEntry(id: 'u5', username: 'Rovesata', score: 2890, games: 120),
  LeaderboardEntry(id: 'u6', username: 'kaleci34', score: 2655, games: 76),
  LeaderboardEntry(id: 'u7', username: 'Kaptan_7', score: 2400, games: 88),
  LeaderboardEntry(id: 'u8', username: 'uzaktan9', score: 2190, games: 64),
  LeaderboardEntry(id: 'u9', username: 'mert_gol', score: 1980, games: 51),
  LeaderboardEntry(id: 'u10', username: 'SahilGol', score: 1720, games: 45),
];

/// 52 saniye kala, başa baş canlı düello (örnek oyuncular).
DuelSnapshot _duelSnapshot() => const DuelSnapshot(
  id: 'duel',
  seed: 7,
  nonce: 'mine',
  status: 'live',
  startsAt: 2000,
  endsAt: 92000,
  serverNow: 41000,
  acceptedSeq: 0,
  players: [
    DuelPlayer(
      id: 'me',
      name: 'Kaptan_7',
      score: 270,
      shots: 11,
      hits: 9,
      combo: 3,
      maxStreak: 4,
      finished: false,
      connected: true,
      rating: 1580,
    ),
    DuelPlayer(
      id: 'rival',
      name: 'FalsoKral',
      score: 240,
      shots: 10,
      hits: 8,
      combo: 2,
      maxStreak: 5,
      finished: false,
      connected: true,
      rating: 1612,
    ),
  ],
  events: <ShotRecord>[],
  kind: 'live',
);

class _DuelApi implements DuelApi {
  _DuelApi(this.snapshot);
  final DuelSnapshot snapshot;
  @override
  Future<DuelSnapshot?> queue() async => snapshot;
  @override
  Future<void> cancelQueue() async {}
  @override
  Future<DuelSnapshot> poll(
    String id,
    int since, {
    bool withGhost = false,
  }) async => snapshot;
  @override
  Future<DuelSnapshot> rematch(String id) async => snapshot;
  @override
  Future<DuelSnapshot> send(
    String id,
    String nonce,
    List<ShotRecord> events,
    int since,
  ) async => snapshot;
  @override
  Future<DuelSnapshot> finish(String id, String nonce, int since) async =>
      snapshot;
  @override
  Future<void> forfeit(String id) async {}
}

/// 1080×1920 mağaza karesi: rozet + başlık, altta telefon ekranı kartı.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({
    required this.shot,
    required this.badge,
    required this.headline,
  });
  final ui.Image shot;
  final String badge;
  final String headline;

  @override
  Widget build(BuildContext context) {
    const cardH = 468.0;
    final cardW = cardH * shot.width / shot.height;
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF13214A), FK.navy, Color(0xFF070B18)],
            stops: [0, .55, 1],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: -80,
              right: -80,
              bottom: -170,
              height: 340,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      FK.orange.withValues(alpha: .38),
                      FK.orange.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 30,
              left: 20,
              right: 20,
              child: Column(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: FK.fire,
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 3, 14, 4),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          fontFamily: FK.font,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 1.6,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    headline,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(
                      fontFamily: FK.font,
                      fontWeight: FontWeight.w700,
                      fontSize: 23,
                      height: 1.15,
                      color: FK.text,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 26,
              left: (360 - cardW) / 2,
              width: cardW,
              height: cardH,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFF2A3760), width: 4),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xAA000000),
                      blurRadius: 30,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: RawImage(image: shot, fit: BoxFit.cover),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 1024×500 öne çıkan grafik: solda logo + slogan, sağda stadyum sahnesi.
class _FeatureGraphic extends StatelessWidget {
  const _FeatureGraphic({required this.scene, required this.tagline});
  final ui.Image scene;
  final String tagline;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: FK.navy),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 620,
          child: RawImage(
            image: scene,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -.1),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [FK.navy, FK.navy, Color(0x000B1226)],
              stops: [0, .42, .78],
            ),
          ),
        ),
        Positioned(
          left: 64,
          top: 0,
          bottom: 0,
          width: 470,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LogoWidget(width: 420, subtitle: false),
              const SizedBox(height: 18),
              Text(
                tagline,
                style: const TextStyle(
                  fontFamily: FK.font,
                  fontWeight: FontWeight.w700,
                  fontSize: 34,
                  height: 1.1,
                  color: FK.text,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
});

int _crc32(List<int> a, List<int> b) {
  var c = 0xFFFFFFFF;
  for (final part in [a, b]) {
    for (final byte in part) {
      c = _crcTable[(c ^ byte) & 0xFF] ^ (c >>> 8);
    }
  }
  return c ^ 0xFFFFFFFF;
}

/// Play ekran görüntüsü ve öne çıkan grafik alfa kanalı kabul etmez: 24-bit RGB PNG.
Future<Uint8List> _rgbPng(ui.Image image) => _png(image, alpha: false);

/// [alpha]: 32-bit RGBA, değilse 24-bit RGB PNG.
Future<Uint8List> _png(ui.Image image, {required bool alpha}) async {
  final rgba = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  final w = image.width, h = image.height;
  final ch = alpha ? 4 : 3;
  final raw = Uint8List(h * (1 + w * ch));
  var o = 0;
  for (var y = 0; y < h; y++) {
    raw[o++] = 0;
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      for (var c = 0; c < ch; c++) {
        raw[o++] = rgba[i + c];
      }
    }
  }
  Uint8List u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);
  final png = BytesBuilder()..add(const [137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> data) {
    final t = ascii.encode(type);
    png
      ..add(u32(data.length))
      ..add(t)
      ..add(data)
      ..add(u32(_crc32(t, data)));
  }

  chunk('IHDR', [...u32(w), ...u32(h), 8, alpha ? 6 : 2, 0, 0, 0]);
  chunk('IDAT', ZLibEncoder(level: 9).convert(raw));
  chunk('IEND', const []);
  return png.takeBytes();
}
