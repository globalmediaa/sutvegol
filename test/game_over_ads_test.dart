import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sut_ve_gol/game/sfx.dart';
import 'package:sut_ve_gol/game/sut_ve_gol_game.dart';
import 'package:sut_ve_gol/main.dart';
import 'package:sut_ve_gol/services/ad_service.dart';
import 'package:sut_ve_gol/ui/continue_overlay.dart';
import 'package:sut_ve_gol/ui/game_over_overlay.dart';
import 'package:sut_ve_gol/ui/logo.dart';
import 'package:sut_ve_gol/ui/widgets.dart';

/// Oyun sonu reklam teklifi: kart ve butonlarla çakışmaz, dokununca yeni
/// koşu Kral Modu'nda başlar. `--dart-define=SHOT_DIR=…` ile ekranlar PNG yazılır.
void main() {
  const shotDir = String.fromEnvironment('SHOT_DIR');

  tearDown(() {
    AdService.instance.debugRewardedReady = null;
    AdService.instance.policy.totalRuns = 0;
  });

  Future<SutVeGolGame> pumpGameOver(
    WidgetTester tester,
    Size size, {
    String overlay = kGameOverOverlay,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Sfx.skipInit = true;
    SharedPreferences.setMockInitialValues({'tutorial_done': true});
    AdService.instance
      ..debugRewardedReady = true
      ..policy.totalRuns = AdPolicyTestRuns.enough;
    final game = SutVeGolGame();
    await tester.runAsync(_loadFonts);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: RepaintBoundary(
            key: const Key('shot'),
            child: GameWidget(
              game: game,
              overlayBuilderMap: {
                kGameOverOverlay: (_, SutVeGolGame g) =>
                    GameOverOverlay(game: g, onDuel: () {}),
                kContinueOverlay: (_, SutVeGolGame g) =>
                    ContinueOverlay(game: g),
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
    game
      ..score = 840
      ..best = 1200
      ..lives = 0
      ..state = GameState.gameOver;
    game.overlays.add(overlay);
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return game;
  }

  for (final size in const [
    Size(320, 568),
    Size(360, 800),
    Size(393, 852),
    Size(1032, 1376),
  ]) {
    testWidgets('Kral Modu teklifi $size kart ve butonlarla çakışmaz', (
      tester,
    ) async {
      await pumpGameOver(tester, size);
      final offer = tester.getRect(find.byKey(const Key('fever-start-offer')));
      final card = tester.getRect(find.byType(GlassCard));
      final replay = tester.getRect(
        find.widgetWithText(PillButton, 'TEKRAR OYNA'),
      );
      expect(offer.top, greaterThanOrEqualTo(card.bottom), reason: 'kart');
      expect(offer.bottom, lessThanOrEqualTo(replay.top), reason: 'buton');
      expect(offer.left, greaterThanOrEqualTo(0));
      expect(offer.right, lessThanOrEqualTo(size.width));
      if (shotDir.isNotEmpty) {
        await tester.runAsync(() async {
          final boundary =
              tester.renderObject(find.byKey(const Key('shot')))
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$shotDir/gameover-${size.width.toInt()}x${size.height.toInt()}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
      }
    });
  }

  for (final size in const [Size(320, 568), Size(393, 852)]) {
    testWidgets('BİR ŞANS DAHA perdesi $size taşmaz', (tester) async {
      await pumpGameOver(tester, size, overlay: kContinueOverlay);
      final watch = tester.getRect(find.byKey(const Key('continue-watch')));
      expect(watch.right, lessThanOrEqualTo(size.width));
      expect(watch.bottom, lessThanOrEqualTo(size.height));
      if (shotDir.isNotEmpty) {
        await tester.runAsync(() async {
          final boundary =
              tester.renderObject(find.byKey(const Key('shot')))
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$shotDir/continue-${size.width.toInt()}x${size.height.toInt()}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
      }
    });
  }

  testWidgets('teklif yoksa (reklam hazır değil) buton görünmez', (
    tester,
  ) async {
    await pumpGameOver(tester, const Size(393, 852));
    AdService.instance.debugRewardedReady = false;
    AdService.instance.notifyListeners();
    await tester.pump();
    expect(find.byKey(const Key('fever-start-offer')), findsNothing);
  });

  testWidgets('teklife dokununca yeni koşu Kral Modu ile başlar', (
    tester,
  ) async {
    final game = await pumpGameOver(tester, const Size(393, 852));
    await tester.tap(find.byKey(const Key('fever-start-offer')));
    await tester.pump();
    expect(game.overlays.isActive(kGameOverOverlay), isFalse);
    for (var i = 0; i < 300 && game.state != GameState.idle; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect(game.fever, isTrue);
    expect(game.score, 0);
  });
}

/// Gerçek yazı tipi: taşma ölçümü test yer tutucu fontuyla yanıltıcı olur.
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

/// Teklifin açıldığı koşu sayısı (yeni oyuncu eşiğinin üstü).
abstract final class AdPolicyTestRuns {
  static const enough = 5;
}
