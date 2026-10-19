import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sut_ve_gol/game/geometry.dart';
import 'package:sut_ve_gol/game/sfx.dart';
import 'package:sut_ve_gol/game/sut_ve_gol_game.dart';
import 'package:sut_ve_gol/ui/continue_overlay.dart';

/// "1 hak daha": son kalpte koşu bitmeden teklif açılır; skor ancak koşu
/// gerçekten bitince gönderilir. Testte reklam SDK'sı yok: "izle" reklam
/// açılamamış gibi davranır ve hak yine verilir.
void main() {
  late SutVeGolGame game;
  late List<GameRunSummary> finished;

  Future<void> pumpFor(WidgetTester tester, int frames) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
  }

  Future<void> idle(WidgetTester tester) async {
    for (var i = 0; i < 300 && game.state != GameState.idle; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect(game.state, GameState.idle);
  }

  Future<void> boot(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    Sfx.skipInit = true;
    tester.view.physicalSize = const Size(kWorldW, kWorldH);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    finished = [];
    game = SutVeGolGame()
      ..onRunFinished = finished.add
      ..canContinue = () => !game.continuedThisRun && game.score > 0;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameWidget(
            game: game,
            overlayBuilderMap: {
              kContinueOverlay: (_, SutVeGolGame g) => ContinueOverlay(game: g),
              kGameOverOverlay: (_, SutVeGolGame g) =>
                  const SizedBox(key: Key('game-over')),
            },
          ),
        ),
      );
      await game.loaded;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await idle(tester);
  }

  /// Son kalbi kaleden çok uzağa atılan şutla kaybeder.
  Future<void> loseLastHeart(WidgetTester tester) async {
    game.lives = 1;
    final v = game.view;
    final rGoal = kBallDiameter / 2 * v.ballGoalScale;
    final trackEndY = v.groundY - rGoal;
    final chord =
        Vector2(
          v.goalCenterX + 1100 - game.ball.position.x,
          trackEndY - game.ball.position.y,
        ) *
        0.4;
    game.kick(chord, 0, 0.5, 0.4);
    for (var i = 0; i < 120 && game.state != GameState.gameOver; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect(game.state, GameState.gameOver);
  }

  testWidgets('teklif reddedilince oyun biter ve koşu bir kez gönderilir', (
    tester,
  ) async {
    await boot(tester);
    game.score = 90;
    await loseLastHeart(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // perde açılışı
    expect(game.awaitingContinue, isTrue);
    expect(game.overlays.isActive(kContinueOverlay), isTrue);
    expect(finished, isEmpty, reason: 'teklif açıkken skor gönderilmez');

    await tester.tap(find.byKey(const Key('continue-decline')));
    await tester.pump();
    expect(game.awaitingContinue, isFalse);
    expect(game.overlays.isActive(kContinueOverlay), isFalse);
    expect(game.overlays.isActive(kGameOverOverlay), isTrue);
    expect(finished, hasLength(1));
    expect(finished.single.score, 90);
  });

  testWidgets('süre dolunca teklif kendiliğinden kapanır', (tester) async {
    await boot(tester);
    game.score = 30;
    await loseLastHeart(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // perde açılışı
    expect(game.awaitingContinue, isTrue);
    await tester.pump(
      ContinueOverlay.window + const Duration(milliseconds: 100),
    );
    await tester.pump();
    expect(game.overlays.isActive(kGameOverOverlay), isTrue);
    expect(finished, hasLength(1));
  });

  testWidgets('devam: 1 kalple aynı skordan sürer, ikinci kez teklif yok', (
    tester,
  ) async {
    await boot(tester);
    game.score = 120;
    await loseLastHeart(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // perde açılışı
    await tester.tap(find.byKey(const Key('continue-watch')));
    await tester.pump();
    await tester.pump();
    expect(game.continuedThisRun, isTrue);
    expect(game.lives, 1);
    expect(game.score, 120);
    expect(finished, isEmpty);
    await idle(tester);

    await loseLastHeart(tester);
    await pumpFor(tester, 2);
    expect(game.awaitingContinue, isFalse);
    expect(game.overlays.isActive(kGameOverOverlay), isTrue);
    expect(finished, hasLength(1));
    expect(finished.single.score, 120);

    // Yeni koşuda hak yeniden doğar.
    game.restart();
    expect(game.continuedThisRun, isFalse);
  });

  testWidgets('Kral Moduyla başla: yeni koşunun ilk topunda Kral Modu açılır', (
    tester,
  ) async {
    await boot(tester);
    expect(game.fever, isFalse);
    game.restart(feverStart: true);
    expect(game.fever, isFalse);
    await idle(tester);
    expect(game.fever, isTrue);
  });
}
