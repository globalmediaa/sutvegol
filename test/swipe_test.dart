import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frikik_kral/game/geometry.dart';
import 'package:frikik_kral/game/frikik_kral_game.dart';
import 'package:frikik_kral/game/sfx.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('kaydırma jesti şut üretir', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Sfx.skipInit = true;
    tester.view.physicalSize = const Size(kWorldW, kWorldH);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final game = FrikikKralGame();
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
