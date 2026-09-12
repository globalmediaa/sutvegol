import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sut_ve_gol/game/sut_ve_gol_game.dart';
import 'package:sut_ve_gol/game/sfx.dart';
import 'package:sut_ve_gol/ui/game_over_overlay.dart';
import 'package:sut_ve_gol/ui/pause_overlay.dart';
import 'package:sut_ve_gol/ui/leaderboard_screen.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(440, 956),
    const Size(1032, 1376),
  ]) {
    testWidgets('yayın arayüzü $size taşmaz ve örnek oyuncu göstermez', (
      tester,
    ) async {
      Sfx.skipInit = true;
      SharedPreferences.setMockInitialValues({'best': 420});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final game = SutVeGolGame()..best = 420;
      for (final overlay in [
        PauseOverlay(game: game),
        GameOverOverlay(game: game),
      ]) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: overlay)));
        await tester.pump(const Duration(seconds: 2));
        expect(
          tester.takeException(),
          isNull,
          reason: overlay.runtimeType.toString(),
        );
        expect(find.text('SIRALAMA'), findsNothing);
      }
      await tester.pumpWidget(
        const MaterialApp(home: LeaderboardScreen(myScore: 30)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sıralama'), findsOneWidget);
      expect(find.text('Sıralama yüklenemedi'), findsOneWidget);
      expect(find.text('Kerem'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
