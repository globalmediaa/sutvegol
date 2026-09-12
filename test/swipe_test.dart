import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sut_ve_gol/game/geometry.dart';
import 'package:sut_ve_gol/game/sut_ve_gol_game.dart';
import 'package:sut_ve_gol/game/sfx.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('şut: kare hızı, falso, güç ve çoklu dokunma regresyonları', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Sfx.skipInit = true;
    tester.view.physicalSize = const Size(kWorldW, kWorldH);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final game = SutVeGolGame();
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
      await game.loaded;
      // Görsellerin decode edilmesi gerçek async; kısa bekleme.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    // Splash (~3 s) + top girişi.
    for (var i = 0; i < 175; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect(game.state, GameState.idle);

    // Aynı şut farklı kare hızlarında aynı noktaya gelmeli.
    final chord = Vector2(80, -700);
    game.target.position = Vector2(660, 1350);
    game.kick(chord, 0, 0.5, 0.5);
    for (var i = 0; i < 12; i++) { game.update(1 / 60); }
    final at60 = game.ball.position.clone();
    game.restart();
    for (var i = 0; i < 60; i++) { game.update(1 / 60); }
    game.target.position = Vector2(660, 1350);
    game.kick(chord, 0, 0.5, 0.5);
    for (var i = 0; i < 4; i++) { game.update(1 / 20); }
    expect(game.ball.position.distanceTo(at60), lessThan(0.01));

    // Falso iki yönde de simetrik tepki vermeli.
    game.restart();
    for (var i = 0; i < 60; i++) { game.update(1 / 60); }
    game.target.position = Vector2(660, 1350);
    game.kick(Vector2(0, -700), 80, 0.5, 0.5);
    game.update(0.1);
    final right = game.ball.position.x;
    game.restart();
    for (var i = 0; i < 60; i++) { game.update(1 / 60); }
    game.target.position = Vector2(660, 1350);
    game.kick(Vector2(0, -700), -80, 0.5, 0.5);
    game.update(0.1);
    expect(right, greaterThan(game.ball.position.x));

    game.restart();
    for (var i = 0; i < 60; i++) { game.update(1 / 60); }
    final slowFrom = Offset(game.view.ballRest.x, game.view.ballRest.y);
    await tester.timedDragFrom(slowFrom, const Offset(0, -700), const Duration(milliseconds: 600));
    expect(game.state, GameState.flying);
    final slowDuration = game.ball.flightDur;
    game.restart();
    for (var i = 0; i < 60; i++) { game.update(1 / 60); }
    await tester.timedDragFrom(slowFrom, const Offset(0, -700), const Duration(milliseconds: 120));
    expect(game.ball.flightDur, lessThan(slowDuration));
    game.restart();
    for (var i = 0; i < 60; i++) { game.update(1 / 60); }

    // İkinci parmağın bırakılması aktif şutu bitirmemeli.
    final firstFinger = await tester.startGesture(slowFrom, pointer: 1);
    await firstFinger.moveBy(const Offset(0, -120));
    final secondFinger = await tester.startGesture(slowFrom + const Offset(200, 0), pointer: 2);
    await secondFinger.moveBy(const Offset(100, -150));
    await secondFinger.up();
    expect(game.state, GameState.idle);
    await firstFinger.moveBy(const Offset(0, -350));
    await firstFinger.up();
    expect(game.state, GameState.flying);
    game.restart();
    for (var i = 0; i < 60; i++) { game.update(1 / 60); }

    final cancelled = await tester.startGesture(slowFrom);
    await cancelled.moveBy(const Offset(0, -300));
    await cancelled.cancel();
    expect(game.state, GameState.idle);
    await tester.timedDragFrom(slowFrom, const Offset(0, 300), const Duration(milliseconds: 120));
    expect(game.state, GameState.idle);

    final from = Offset(game.view.ballRest.x, game.view.ballRest.y);
    final to = Offset(game.target.position.x, game.target.position.y);
    await tester.timedDragFrom(from, to - from, const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 33));
    expect(game.state, GameState.flying);

    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect(game.state, isNot(GameState.flying));
    expect(game.score + (3 - game.lives) * 30, greaterThanOrEqualTo(30),
        reason: 'isabet ya da kalp kaybı olmalı');
  });
}
