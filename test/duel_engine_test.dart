import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sut_ve_gol/game/geometry.dart';
import 'package:sut_ve_gol/game/sfx.dart';
import 'package:sut_ve_gol/game/sut_ve_gol_game.dart';

void main() {
  testWidgets(
    'two independent fields relay real shots without changing solo records',
    (tester) async {
      SharedPreferences.setMockInitialValues({'best': 900, 'sound': false});
      Sfx.skipInit = true;
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final mine = SutVeGolGame(mode: GameMode.duel, seed: 123),
          replica = SutVeGolGame(mode: GameMode.replica, seed: 123);
      final records = <ShotRecord>[];
      mine.onShotResolved = records.add;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Column(
              children: [
                Expanded(child: GameWidget(game: replica)),
                Expanded(child: GameWidget(game: mine)),
              ],
            ),
          ),
        );
        await Future.wait([mine.loaded, replica.loaded]);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      mine.startRun();
      replica.startRun();
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(mine.state, GameState.idle);
      expect(replica.state, GameState.idle);
      expect(identical(mine.images, replica.images), false);
      expect(
        mine.images.fromCache(kWide.bgKey(Stage.street)).height,
        kDuelBand.height.toInt(),
      );
      mine.kick(mine.target.position - mine.view.ballRest, 0, .5, .5);
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(records.length, 1);
      expect(records.single.consistent, true);
      final encoded = ShotRecord.fromJson(records.single.toJson());
      replica.applyRemoteShot(encoded);
      replica.applyRemoteShot(encoded);
      for (var i = 0; i < 180; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(replica.score, mine.score);
      expect(replica.lives, mine.lives);
      expect(replica.runShots, mine.runShots);
      expect(replica.runHits, mine.runHits);
      expect((await SharedPreferences.getInstance()).getInt('best'), 900);
      mine.finishRun();
      replica.finishRun();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(mine.images.keys, isEmpty);
      expect(replica.images.keys, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
