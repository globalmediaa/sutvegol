import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sut_ve_gol/duel/duel_api.dart';
import 'package:sut_ve_gol/duel/duel_controller.dart';
import 'package:sut_ve_gol/duel/duel_protocol.dart';
import 'package:sut_ve_gol/game/shot_record.dart';
import 'package:sut_ve_gol/services/api_client.dart';
import 'package:sut_ve_gol/ui/duel_screen.dart';

Map<String, dynamic> shotJson(int seq, {int? t, bool timeout = false}) => {
  'v': 2,
  'seq': seq,
  't': t ?? seq * 1000,
  'stage': 'street',
  'view': 'wide',
  'target': [660, 1350],
  'chord': [0, -500],
  'dev': 0,
  'tMax': .5,
  'power': .5,
  'keeper': [null, null],
  'path': timeout ? 'timeout' : 'net',
  'hit': !timeout,
  'end': [660, 1350],
  'drop': null,
  'score': timeout ? 0 : 30,
  'streak': timeout ? 0 : 1,
  'fever': false,
  'feverLeft': 0,
  'shots': seq,
  'hits': timeout ? seq - 1 : seq,
  'misses': timeout ? 1 : 0,
  'feverHits': 0,
  'maxStreak': 1,
  'mult': timeout ? 0 : 1,
};
ShotRecord shot([int seq = 1, int? t]) =>
    ShotRecord.fromJson(shotJson(seq, t: t));
const me = DuelPlayer(
  id: 'me',
  name: 'Player_Long_Name',
  score: 30,
  shots: 1,
  hits: 1,
  finished: false,
  connected: true,
  rating: 1500,
  calibrating: true,
);
const other = DuelPlayer(
  id: 'other',
  name: 'Opponent_Long_Name',
  score: 60,
  shots: 3,
  hits: 2,
  combo: 2,
  maxStreak: 2,
  finished: false,
  connected: true,
);
const ghostPlayer = DuelPlayer(
  id: 'ghost',
  name: 'kayitli_oyuncu',
  score: 0,
  shots: 0,
  hits: 0,
  finished: false,
  connected: true,
  ghost: true,
);
DuelSnapshot snapshot({
  int now = 1000,
  int accepted = 0,
  List<ShotRecord> events = const [],
  bool finished = false,
  bool ghost = false,
  List<ShotRecord>? ghostEvents,
  DuelRematch? rematch,
  String id = 'duel',
}) => DuelSnapshot(
  id: id,
  seed: 1,
  nonce: 'mine',
  status: finished ? 'finished' : 'live',
  startsAt: 2000,
  endsAt: 92000,
  serverNow: now,
  acceptedSeq: accepted,
  players: [me, ghost ? ghostPlayer : other],
  events: events,
  kind: ghost ? 'ghost' : 'live',
  ghostSource: ghost ? 'recorded' : null,
  ghostEvents: ghostEvents,
  winnerId: finished ? 'me' : null,
  xp: finished ? 41 : null,
  ratingBefore: finished && !ghost ? 1500 : null,
  ratingAfter: finished && !ghost ? 1562 : null,
  ratingCounted: finished && !ghost,
  rematch: rematch,
);

class FakeApi implements DuelApi {
  DuelSnapshot? next;
  Completer<DuelSnapshot?>? joining;
  bool failSend = false;
  int joins = 0, cancels = 0, polls = 0, finishes = 0, forfeits = 0;
  int rematches = 0;
  DuelSnapshot? rematchNext;
  final ghostRequests = <bool>[];
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
  Future<DuelSnapshot> poll(
    String id,
    int since, {
    bool withGhost = false,
  }) async {
    polls++;
    ghostRequests.add(withGhost);
    return next!;
  }

  @override
  Future<DuelSnapshot> rematch(String id) async {
    rematches++;
    return rematchNext ?? next!;
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
  test(
    'protocol v2: rejects v1 records, nonfinite vectors; timeout record',
    () {
      final j = shot().toJson();
      expect(j['v'], 2);
      expect(j.containsKey('lives'), false);
      expect(() => ShotRecord.fromJson({...j, 'v': 1}), throwsFormatException);
      expect(
        () => ShotRecord.fromJson({...j, 'mult': 4}),
        throwsFormatException,
      );
      final timeout = ShotRecord.fromJson(shotJson(2, timeout: true));
      expect(timeout.isTimeout, true);
      expect(timeout.consistent, true);
      expect(
        ShotRecord.fromJson({
          ...shotJson(2, timeout: true),
          'hit': true,
        }).consistent,
        false,
      );
      expect(
        () => ShotRecord.fromJson({
          ...j,
          'chord': [double.nan, 0],
        }),
        throwsFormatException,
      );
      expect(ShotRecord.fromJson(j).consistent, true);
    },
  );
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
  test('ghost playback emits by t order exactly once', () {
    final g = GhostPlayback([shot(3, 4100), shot(1, 900), shot(2, 2500)]);
    expect(g.events.map((e) => e.t), [900, 2500, 4100]);
    expect(g.due(0), isEmpty);
    expect(g.due(2500).map((e) => e.seq), [1, 2]);
    expect(g.due(2500), isEmpty);
    expect(g.latest!.seq, 2);
    final view = g.apply(ghostPlayer);
    expect((view.shots, view.ghost, view.name), (2, true, 'kayitli_oyuncu'));
    expect(g.due(90000).map((e) => e.seq), [3]);
    expect(g.done, true);
  });

  test('snapshot: one human + ghost is valid, mixed kinds are rejected', () {
    Map<String, dynamic> resp(
      String kind,
      List<Map<String, dynamic>> players,
    ) => {
      'serverNowMs': 1000,
      'duel': {
        'id': 'd',
        'version': 2,
        'kind': kind,
        'seed': 1,
        'nonce': 'n',
        'status': 'countdown',
        'startsAtMs': 2000,
        'endsAtMs': 92000,
        'shotClockMs': 5000,
        'myAcceptedSeq': 0,
        'events': [],
        'players': players,
        'ghost': kind == 'ghost'
            ? {
                'source': 'recorded',
                'eventCount': 2,
                'events': [shotJson(1, t: 1200), shotJson(2, t: 2800)],
              }
            : null,
        'result': null,
        'rematch': null,
      },
    };
    final human = {
      'id': 'me',
      'username': 'ben',
      'score': 0,
      'shots': 0,
      'hits': 0,
      'combo': 0,
      'maxStreak': 0,
      'finished': false,
      'connected': true,
      'ghost': false,
      'rating': 1500,
      'calibrating': true,
    };
    final g = {...human, 'id': 'ghost', 'username': 'ayse', 'ghost': true};
    final s = DuelSnapshot.fromResponse(resp('ghost', [human, g]));
    expect(s.isGhost, true);
    expect(s.opponentKind, OpponentKind.recorded);
    expect(s.ghostEvents!.map((e) => e.t), [1200, 2800]);
    expect(s.opponent('me').ghost, true);
    expect(
      () => DuelSnapshot.fromResponse(resp('live', [human, g])),
      throwsFormatException,
    );
    expect(
      () => DuelSnapshot.fromResponse(
        resp('ghost', [
          human,
          {...human, 'id': 'x'},
        ]),
      ),
      throwsFormatException,
    );
  });

  test(
    'controller plays a ghost by match time and stops asking for it',
    () async {
      int now = 100;
      final api = FakeApi()
        ..next = snapshot(
          now: 2000,
          ghost: true,
          ghostEvents: [shot(1, 1500), shot(2, 3200)],
        );
      final c = DuelController(
        userId: 'me',
        api: api,
        now: () => now,
        autoPoll: false,
      );
      final played = <int>[];
      c.onRemoteShot = (e) => played.add(e.seq);
      await c.start();
      expect(c.ghost, isNotNull);
      expect(c.phase, DuelPhase.live);
      c.advanceGhost(); // maç saati 0
      expect(played, isEmpty);
      expect(c.opponentView!.score, 0);
      now += 1600;
      c.advanceGhost();
      expect(played, [1]);
      expect(c.opponentView!.score, 30);
      now += 5000;
      c.tick();
      expect(played, [1, 2]);
      await c.synchronize();
      expect(api.ghostRequests.last, false);
      c.dispose();
    },
  );

  test(
    'rematch: open for 10 s, request once, follow the new duel id',
    () async {
      int now = 100;
      final r = const DuelRematch(expiresAt: 105000, mine: false, theirs: true);
      final api = FakeApi()
        ..next = snapshot(now: 95000, finished: true, rematch: r);
      final c = DuelController(
        userId: 'me',
        api: api,
        now: () => now,
        autoPoll: false,
      );
      await c.start();
      expect(c.phase, DuelPhase.finished);
      expect(c.rematchOpen, true);
      expect(c.rematchSecondsLeft, 10);
      api.rematchNext = snapshot(
        now: 96000,
        finished: true,
        rematch: const DuelRematch(
          expiresAt: 105000,
          mine: true,
          theirs: true,
          duelId: 'next',
        ),
      );
      await c.requestRematch();
      expect(api.rematches, 1);
      expect(c.snapshot!.rematch!.duelId, 'next');
      expect(c.rematchOpen, false);
      await c.requestRematch();
      expect(api.rematches, 1);
      c.dispose();
      // Ghost maçında rövanş yok.
      final g = DuelController(
        userId: 'me',
        api: FakeApi()
          ..next = snapshot(now: 95000, finished: true, ghost: true),
        autoPoll: false,
      );
      await g.start();
      expect(g.rematchOpen, false);
      g.dispose();
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(440, 956),
    const Size(768, 1024),
  ]) {
    for (final phase in [
      'search',
      'countdown',
      'live',
      'result',
      'ghost',
      'ghost-result',
      'rematch',
    ]) {
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
                  now: phase == 'countdown' || phase == 'ghost' ? 1000 : 3000,
                  finished: phase.contains('result') || phase == 'rematch',
                  ghost: phase.startsWith('ghost'),
                  ghostEvents: phase.startsWith('ghost')
                      ? [shot(1, 1500)]
                      : null,
                  rematch: phase == 'rematch'
                      ? const DuelRematch(
                          expiresAt: 13000,
                          mine: false,
                          theirs: true,
                        )
                      : null,
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
