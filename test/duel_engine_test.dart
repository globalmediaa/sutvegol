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

  testWidgets('shot clock auto-miss and combo multipliers in duel mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'sound': false});
    Sfx.skipInit = true;
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mine = SutVeGolGame(mode: GameMode.duel, seed: 7),
        replica = SutVeGolGame(mode: GameMode.replica, seed: 7);
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
    expect(mine.shotClockVisible, true);
    expect(replica.shotClockVisible, false);
    // 5 sn hiç şut yok → otomatik ıskalama kaydı; top yerinde, saat yeniden.
    for (var i = 0; i < 270; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(records.length, 1);
    final timeout = records.single;
    expect(timeout.path, ShotPath.timeout);
    expect(
      (timeout.hit, timeout.mult, timeout.streak, timeout.misses),
      (false, 0, 0, 1),
    );
    expect(timeout.t, greaterThanOrEqualTo(5000));
    expect(timeout.rt, timeout.t);
    expect(timeout.consistent, true);
    expect(mine.state, GameState.idle);
    expect(mine.lives, 3); // can yok
    expect(mine.shotClock, greaterThan(4));
    replica.applyRemoteShot(ShotRecord.fromJson(timeout.toJson()));
    await tester.pump(const Duration(milliseconds: 20));
    expect(
      (replica.runMisses, replica.lives, replica.lastAppliedSeq),
      (1, 3, 1),
    );

    // Hedefe tam nişan: her kayıt combo kuralına uyar (gol: 30 × min(3, seri),
    // Kral Modu'nda x2; ıskalama: 0 ve seri sıfır).
    for (var shot = 0; shot < 4; shot++) {
      final g = mine.view;
      final trackEndY = g.groundY - kBallDiameter / 2 * g.ballGoalScale;
      final t = mine.target.position;
      mine.kick(
        Vector2(t.x - mine.ball.position.x, trackEndY - mine.ball.position.y),
        0,
        .5,
        ((trackEndY - t.y) / (g.goalHeight * 1.15)).clamp(0.0, 1.0),
      );
      for (var i = 0; i < 160; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (records.length == shot + 2 && mine.state == GameState.idle) break;
      }
    }
    expect(records.length, 5);
    expect(records[1].hit, true); // kaleci yokken tam nişan gol
    for (var i = 1; i < records.length; i++) {
      final prev = records[i - 1], r = records[i];
      final expected = !r.hit
          ? 0
          : (prev.fever ? 2 : (prev.streak + 1).clamp(1, 3));
      expect(r.mult, expected, reason: 'kayıt ${r.seq}');
      expect(r.score - prev.score, 30 * r.mult);
      expect(r.streak, r.hit ? prev.streak + 1 : 0);
      // Sunucu sözleşmesi: sonuç vuruştan sonra, şut saati önceki sonuçtan ölçülür.
      expect(r.rt, inInclusiveRange(r.t, r.t + 5000), reason: 'kayıt ${r.seq}');
      expect(r.t, greaterThanOrEqualTo(prev.rt));
      expect(r.t - prev.rt, lessThanOrEqualTo(10000));
    }
    mine.finishRun();
    replica.finishRun();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('match clock resync and server realign keep the contract', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'sound': false});
    Sfx.skipInit = true;
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mine = SutVeGolGame(mode: GameMode.duel, seed: 11);
    final records = <ShotRecord>[];
    mine.onShotResolved = records.add;
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: GameWidget(game: mine)));
      await mine.loaded;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    // Yoklama gecikmesi: maç 1,2 sn önce başlamıştı; koşu saati oradan başlar.
    mine.startRun(lateMs: 1200);
    expect(mine.runElapsedMs, inInclusiveRange(1200, 1210));
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(mine.state, GameState.idle);
    // Küçük sapma kaydırılmaz.
    expect(mine.syncMatchClock(mine.runElapsedMs + 1000), 0);
    // 20 sn arka plan: oyun saati durdu, maç sürdü. Saat ileri alınır ve şut
    // saati hemen dolar (sunucu: 12 sn'den eski t yok, boşluk sonrası tek timeout).
    final before = mine.runElapsedMs;
    expect(mine.syncMatchClock(before + 20000), 20000);
    await tester.pump(const Duration(milliseconds: 20));
    expect(records.length, 1);
    final gap = records.single;
    expect((gap.path, gap.seq, gap.rt), (ShotPath.timeout, 1, gap.t));
    expect(gap.t, greaterThanOrEqualTo(before + 20000));
    expect(mine.lastEventRt, gap.rt);

    // Sunucu bir şutu reddetti: sayaçlar sunucunun durumuna döner. Kral Modu
    // sunucuda rt=now-9000'de başladı → yerelde 1 sn kaldı.
    final now = mine.runElapsedMs;
    mine.realignFromServer(
      score: 270,
      shots: 5,
      hits: 5,
      misses: 0,
      streak: 5,
      maxStreak: 5,
      feverHits: 0,
      fever: true,
      feverT: now - 9000,
      lastRt: now - 500,
      lastStage: 'street',
    );
    expect(
      (mine.score, mine.runShots, mine.streak, mine.fever),
      (270, 5, 5, true),
    );
    expect(mine.feverTime, closeTo(1.0, 0.05));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(
      (mine.fever, mine.streak),
      (false, 0),
    ); // süre sonuçlanma saatinde doldu
    for (var i = 0; i < 300 && records.length < 2; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(records.length, 2);
    final next = records.last;
    expect(
      (next.seq, next.shots, next.hits, next.misses, next.score, next.streak),
      (6, 6, 5, 1, 270, 0),
    );
    expect(next.t - (now - 500), greaterThanOrEqualTo(4700));
    expect(next.consistent, true);
    mine.finishRun();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
