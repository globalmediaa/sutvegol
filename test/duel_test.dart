import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sut_ve_gol/duel/duel_api.dart';
import 'package:sut_ve_gol/duel/duel_controller.dart';
import 'package:sut_ve_gol/duel/duel_protocol.dart';
import 'package:sut_ve_gol/game/shot_record.dart';
import 'package:sut_ve_gol/services/api_client.dart';
import 'package:sut_ve_gol/ui/duel_screen.dart';

ShotRecord shot([int seq = 1]) => ShotRecord.fromJson({
  'v': 1,
  'seq': seq,
  't': seq * 1000,
  'stage': 'street',
  'view': 'wide',
  'target': [660, 1350],
  'chord': [0, -500],
  'dev': 0,
  'tMax': .5,
  'power': .5,
  'keeper': [null, null],
  'path': 'net',
  'hit': true,
  'end': [660, 1350],
  'drop': null,
  'score': seq * 30,
  'lives': 3,
  'streak': seq,
  'fever': false,
  'feverLeft': 0,
  'shots': seq,
  'hits': seq,
  'misses': 0,
  'feverHits': 0,
  'maxStreak': seq,
});
DuelSnapshot snapshot({
  int now = 1000,
  int accepted = 0,
  List<ShotRecord> events = const [],
  bool finished = false,
}) => DuelSnapshot(
  id: 'duel',
  seed: 1,
  nonce: 'mine',
  status: finished ? 'finished' : 'live',
  startsAt: 2000,
  endsAt: 92000,
  serverNow: now,
  acceptedSeq: accepted,
  players: const [
    DuelPlayer(
      id: 'me',
      name: 'Player_Long_Name',
      score: 30,
      lives: 3,
      shots: 1,
      hits: 1,
      finished: false,
      connected: true,
    ),
    DuelPlayer(
      id: 'other',
      name: 'Opponent_Long_Name',
      score: 60,
      lives: 2,
      shots: 3,
      hits: 2,
      finished: false,
      connected: true,
    ),
  ],
  events: events,
  winnerId: finished ? 'me' : null,
);

class FakeApi implements DuelApi {
  DuelSnapshot? next;
  Completer<DuelSnapshot?>? joining;
  bool failSend = false;
  int joins = 0, cancels = 0, polls = 0, finishes = 0, forfeits = 0;
  final sent = <List<ShotRecord>>[];
  @override
  Future<DuelSnapshot?> queue() async {
    joins++;
    return joining != null ? joining!.future : next;
  }

  @override
  Future<void> cancelQueue() async {
    cancels++;
  }

  @override
  Future<DuelSnapshot> poll(String id, int since) async {
    polls++;
    return next!;
  }

  @override
  Future<DuelSnapshot> send(
    String id,
    String nonce,
    List<ShotRecord> events,
    int since,
  ) async {
    sent.add(events);
    if (failSend) throw const ApiException('network', 'retry');
    return next!;
  }

  @override
  Future<DuelSnapshot> finish(String id, String nonce, int since) async {
    finishes++;
    return next!;
  }

  @override
  Future<void> forfeit(String id) async {
    forfeits++;
  }
}

void main() {
  test('protocol rejects unsupported versions and nonfinite vectors', () {
    final j = shot().toJson();
    expect(() => ShotRecord.fromJson({...j, 'v': 2}), throwsFormatException);
    expect(
      () => ShotRecord.fromJson({
        ...j,
        'chord': [double.nan, 0],
      }),
      throwsFormatException,
    );
    expect(ShotRecord.fromJson(j).consistent, true);
  });
  test('server clock, retry, idempotence, ordered relay and finish', () async {
    int now = 100;
    final api = FakeApi()..next = snapshot();
    final c = DuelController(
      userId: 'me',
      api: api,
      now: () => now,
      autoPoll: false,
    );
    final received = <int>[];
    c.onRemoteShot = (s) => received.add(s.seq);
    await c.start();
    expect(c.phase, DuelPhase.countdown);
    expect(c.countdown, 1);
    expect(c.secondsLeft, 90);
    now += 1000;
    c.tick();
    expect(c.phase, DuelPhase.live);
    c.addShot(shot());
    c.addShot(shot());
    expect(c.pendingShots, 1);
    api.failSend = true;
    await c.synchronize();
    expect(c.pendingShots, 1);
    expect(c.connected, false);
    api.failSend = false;
    api.next = snapshot(now: 3000, accepted: 1, events: [shot(), shot(2)]);
    await c.synchronize();
    expect(c.pendingShots, 0);
    expect(received, [1, 2]);
    await c.synchronize();
    expect(received, [1, 2]);
    expect(api.sent.map((e) => e.single.seq), [1, 1]);
    c.endRun();
    api.next = snapshot(now: 95000, accepted: 1, finished: true);
    await c.synchronize();
    expect(c.phase, DuelPhase.finished);
    expect(api.finishes, 1);
    await c.synchronize();
    expect(api.finishes, 1);
    c.dispose();
  });
  test('cancel wins against an in-flight match join', () async {
    final api = FakeApi()..joining = Completer();
    final c = DuelController(userId: 'me', api: api, autoPoll: false);
    final joining = c.start();
    final leaving = c.leave();
    expect(api.cancels, 0);
    api.joining!.complete(snapshot());
    await joining;
    expect(await leaving, true);
    expect(c.snapshot, isNull);
    expect(api.cancels, 1);
    expect(c.phase, DuelPhase.left);
    c.dispose();
  });
  test('suspended/disposed clients stop requests and callbacks', () async {
    final api = FakeApi()..next = snapshot();
    final c = DuelController(userId: 'me', api: api, autoPoll: false);
    await c.start();
    c.suspend();
    await c.synchronize();
    expect(api.polls, 0);
    await c.resume();
    expect(api.polls, 1);
    c.dispose();
    await c.synchronize();
    expect(api.polls, 1);
  });
  for (final size in [
    const Size(320, 568),
    const Size(440, 956),
    const Size(768, 1024),
  ]) {
    for (final phase in ['search', 'countdown', 'live', 'result']) {
      testWidgets('$phase fits $size with large text and reduced motion', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final api = FakeApi()
          ..next = phase == 'search'
              ? null
              : snapshot(
                  now: phase == 'countdown' ? 1000 : 3000,
                  finished: phase == 'result',
                );
        final c = DuelController(userId: 'me', api: api, autoPoll: false);
        addTearDown(c.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(1.5),
                disableAnimations: true,
              ),
              child: DuelScreen(controller: c, renderGames: false),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('ONLINE DÜELLO'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    }
  }
}
