import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sut_ve_gol/duel/duel_api.dart';
import 'package:sut_ve_gol/duel/duel_controller.dart';
import 'package:sut_ve_gol/duel/duel_protocol.dart';
import 'package:sut_ve_gol/game/shot_record.dart';
import 'package:sut_ve_gol/services/auth_service.dart';
import 'package:sut_ve_gol/services/game_service.dart';
import 'package:sut_ve_gol/services/moderation_service.dart';
import 'package:sut_ve_gol/ui/account_screen.dart';
import 'package:sut_ve_gol/ui/auth_screen.dart';
import 'package:sut_ve_gol/ui/duel_screen.dart';
import 'package:sut_ve_gol/ui/leaderboard_screen.dart';
import 'package:sut_ve_gol/ui/moderation_ui.dart';
import 'package:sut_ve_gol/ui/username_screen.dart';

/// Sunucusuz şikâyet/engel uçları: çağrıları kaydeder.
class FakeModeration implements ModerationRemote {
  final reports = <Map<String, Object?>>[];
  final blocked = <String>[];
  final unblocked = <String>[];
  List<BlockedPlayer> list = const [];

  @override
  Future<void> report({
    required String targetId,
    required ReportReason reason,
    required ReportContext context,
    String? duelId,
    String? note,
  }) async {
    reports.add({
      'target': targetId,
      'reason': reason.name,
      'context': context.name,
      'duel': duelId,
      'note': note,
    });
  }

  @override
  Future<void> block(String userId) async => blocked.add(userId);

  @override
  Future<void> unblock(String userId) async {
    unblocked.add(userId);
    list = list.where((b) => b.id != userId).toList();
  }

  @override
  Future<List<BlockedPlayer>> blocks() async => list;
}

class FakeDuelApi implements DuelApi {
  FakeDuelApi(this.next);
  DuelSnapshot next;
  @override
  Future<DuelSnapshot?> queue() async => next;
  @override
  Future<void> cancelQueue() async {}
  @override
  Future<DuelSnapshot> poll(
    String id,
    int since, {
    bool withGhost = false,
  }) async => next;
  @override
  Future<DuelSnapshot> send(
    String id,
    String nonce,
    List<ShotRecord> events,
    int since,
  ) async => next;
  @override
  Future<DuelSnapshot> finish(String id, String nonce, int since) async => next;
  @override
  Future<void> forfeit(String id) async {}
  @override
  Future<DuelSnapshot> rematch(String id) async => next;
}

const kOther = 'B2B2B2B2B2B2B2B2B2B2B2B2B2';
const kOwner = 'C3C3C3C3C3C3C3C3C3C3C3C3C3';
const kMe = 'A1A1A1A1A1A1A1A1A1A1A1A1A1';

const me = DuelPlayer(
  id: kMe,
  name: 'ben_oyuncu',
  score: 30,
  shots: 1,
  hits: 1,
  finished: false,
  connected: true,
);

DuelSnapshot duel({
  bool finished = false,
  String kind = 'live',
  String? ghostSource,
  String? ownerId,
}) {
  final ghost = kind == 'ghost';
  return DuelSnapshot(
    id: 'd' * 32,
    seed: 1,
    nonce: 'mine',
    status: finished ? 'finished' : 'live',
    startsAt: 2000,
    endsAt: 92000,
    serverNow: finished ? 95000 : 3000,
    acceptedSeq: 0,
    players: [
      me,
      DuelPlayer(
        id: ghost ? 'ghost' : kOther,
        name: ghost && ghostSource == 'cpu' ? 'CPU' : 'rakip_oyuncu',
        score: 60,
        shots: 2,
        hits: 2,
        finished: false,
        connected: true,
        ghost: ghost,
        ownerId: ownerId,
      ),
    ],
    events: const [],
    kind: kind,
    ghostSource: ghostSource,
    winnerId: finished ? kMe : null,
    xp: finished ? 20 : null,
  );
}

Future<void> pumpDuel(WidgetTester tester, DuelSnapshot s) async {
  final c = DuelController(userId: kMe, api: FakeDuelApi(s), autoPoll: false);
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: DuelScreen(controller: c, renderGames: false),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  late FakeModeration fake;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fake = FakeModeration();
    ModerationService.instance
      ..remote = fake
      ..reset();
    AuthService.instance
      ..loading = false
      ..error = null
      ..user = const AppUser(id: kMe, username: 'ben_oyuncu');
  });

  tearDown(() {
    debugUsernameCheck = null;
    AuthService.instance.user = null;
    ModerationService.instance
      ..remote = ApiModerationRemote()
      ..reset();
  });

  group('protokol', () {
    test('engel / ghost sahibi / kullanıcı adı kontrolü ayrıştırılır', () {
      final p = DuelPlayer.fromJson({
        'id': 'ghost',
        'username': 'Engellenen oyuncu',
        'score': 0,
        'shots': 0,
        'hits': 0,
        'finished': false,
        'connected': true,
        'ghost': true,
        'ownerId': kOwner,
        'blocked': true,
      });
      expect((p.ownerId, p.blocked), (kOwner, true));
      final copy = p.copyWith(score: 90);
      expect((copy.ownerId, copy.blocked, copy.score), (kOwner, true, 90));
      final e = LeaderboardEntry.fromJson({
        'id': kOther,
        'username': 'Oyuncu#B2B2',
        'score': 120,
        'games': '3',
        'blocked': false,
      });
      expect((e.username, e.score, e.games, e.blocked), (
        'Oyuncu#B2B2',
        120,
        3,
        false,
      ));
      final c = UsernameCheck.fromJson({
        'valid': true,
        'allowed': false,
        'available': false,
        'code': 'username_not_allowed',
        'message': 'Bu kullanıcı adı uygun değil.',
      });
      expect((c.allowed, c.message), (false, 'Bu kullanıcı adı uygun değil.'));
      // Eski sunucu `allowed` göndermez: yalnız `available` belirler.
      expect(
        UsernameCheck.fromJson({'valid': true, 'available': true}).allowed,
        true,
      );
      expect(
        AppUser.fromJson({'id': kMe, 'termsVersion': 1}).termsVersion,
        kTermsVersion,
      );
    });

    test('sunucu istek biçimi: /v1/report, /v1/blocks', () async {
      final calls = <http.Request>[];
      final client = MockClient((r) async {
        calls.add(r);
        final body = r.url.path.endsWith('/v1/blocks') && r.method == 'GET'
            ? {
                'ok': true,
                'blocks': [
                  {
                    'id': kOther,
                    'name': 'rakip',
                    'blockedAt': '2026-10-13T10:00:00+00:00',
                  },
                ],
              }
            : {'ok': true};
        return http.Response(jsonEncode(body), 200);
      });
      await http.runWithClient(() async {
        final remote = ApiModerationRemote();
        await remote.report(
          targetId: kOther,
          reason: ReportReason.username,
          context: ReportContext.ghost,
          duelId: 'd' * 32,
          note: '  kaba ad  ',
        );
        await remote.report(
          targetId: kOther,
          reason: ReportReason.cheating,
          context: ReportContext.leaderboard,
          note: '   ',
        );
        await remote.block(kOther);
        await remote.unblock(kOther);
        final list = await remote.blocks();
        expect((list.single.id, list.single.name), (kOther, 'rakip'));
        expect(list.single.blockedAt, isNotNull);
      }, () => client);
      expect(calls.map((c) => '${c.method} ${c.url.path}').toList(), [
        'POST /api/v1/report',
        'POST /api/v1/report',
        'POST /api/v1/blocks',
        'DELETE /api/v1/blocks/$kOther',
        'GET /api/v1/blocks',
      ]);
      expect(jsonDecode(calls[0].body), {
        'target_user_id': kOther,
        'reason': 'username',
        'context': 'ghost',
        'duel_id': 'd' * 32,
        'note': 'kaba ad',
      });
      // Boş not ve duel_id gönderilmez.
      expect(jsonDecode(calls[1].body), {
        'target_user_id': kOther,
        'reason': 'cheating',
        'context': 'leaderboard',
      });
      expect(jsonDecode(calls[2].body), {'user_id': kOther});
    });
  });

  group('kullanıcı adı ve kullanım koşulları', () {
    testWidgets(
      'ad seçimi: uygunsuz ad mesajı, onaysız devam yok, onayla açılır',
      (tester) async {
        debugUsernameCheck = (v) async => v.startsWith('admin')
            ? const UsernameCheck(
                valid: true,
                allowed: false,
                available: false,
                message: 'Bu kullanıcı adı uygun değil.',
              )
            : const UsernameCheck(valid: true, allowed: true, available: true);
        AuthService.instance.user = const AppUser(id: kMe);
        await tester.pumpWidget(const MaterialApp(home: UsernameScreen()));
        await tester.pump(const Duration(seconds: 2));
        await tester.enterText(find.byType(TextField), 'admin_tr');
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Bu kullanıcı adı uygun değil.'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'gol_kral');
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Bu kullanıcı adı kullanılabilir'), findsOneWidget);
        // Koşullar metni sıfır toleransı açıkça söyler; işaretlenmeden düğme kapalı.
        expect(find.textContaining('sıfır tolerans', findRichText: true), findsOneWidget);
        expect(find.textContaining('Kullanım Koşulları', findRichText: true), findsOneWidget);
        final submit = find.ancestor(
          of: find.text('SAHAYA ÇIK'),
          matching: find.byType(GestureDetector),
        );
        expect(tester.widget<GestureDetector>(submit.first).onTap, isNull);
        await tester.tap(find.byKey(const Key('terms-consent')));
        await tester.pump();
        expect(tester.widget<GestureDetector>(submit.first).onTap, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('e-posta kaydı: onay kutusu yalnız kayıtta, onaysız hesap açılmaz', (
      tester,
    ) async {
      debugUsernameCheck = (v) async =>
          const UsernameCheck(valid: true, allowed: true, available: true);
      AuthService.instance.user = null;
      await tester.pumpWidget(MaterialApp(home: AuthScreen(onGuest: () {})));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const Key('terms-consent')), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'gol_kral');
      await tester.pump(const Duration(milliseconds: 500));
      final submit = find.ancestor(
        of: find.text('HESABINI OLUŞTUR'),
        matching: find.byType(GestureDetector),
      );
      expect(tester.widget<GestureDetector>(submit.first).onTap, isNull);
      await tester.ensureVisible(find.byKey(const Key('terms-consent')));
      await tester.tap(find.byKey(const Key('terms-consent')));
      await tester.pump();
      expect(tester.widget<GestureDetector>(submit.first).onTap, isNotNull);
      // Giriş modunda kutu yok (mevcut hesap).
      await tester.ensureVisible(find.text('Giriş yap'));
      await tester.tap(find.text('Giriş yap'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('terms-consent')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uygunsuz ad sunucu tarafından reddedilince mesaj alanda kalır', (
      tester,
    ) async {
      debugUsernameCheck = (v) async =>
          const UsernameCheck(valid: true, allowed: true, available: true);
      expect(
        usernameFeedback(
          const UsernameCheck(valid: true, allowed: false, available: false),
        ).text,
        kUsernameNotAllowed,
      );
      expect(
        usernameFeedback(
          const UsernameCheck(valid: true, allowed: true, available: false),
        ).text,
        'Bu kullanıcı adı alınmış. Başka bir tane dene.',
      );
      expect(usernameFeedback(null).ok, isNull);
    });
  });

  group('sıralama', () {
    final entries = [
      const LeaderboardEntry(
        id: kMe,
        username: 'ben_oyuncu',
        score: 300,
        games: 4,
      ),
      const LeaderboardEntry(
        id: kOther,
        username: 'rakip_oyuncu',
        score: 120,
        games: 2,
      ),
    ];

    Future<int> pumpBoard(WidgetTester tester) async {
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LeaderboardScreen(
            myScore: 0,
            loader: (_) async {
              loads++;
              return entries;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return loads;
    }

    testWidgets('⋯ → Şikâyet et: sebep seçimi, not, gönderim', (tester) async {
      await pumpBoard(tester);
      expect(find.byKey(const Key('lb-actions-$kMe')), findsNothing);
      await tester.tap(find.byKey(const Key('lb-actions-$kOther')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player-report')));
      await tester.pumpAndSettle();
      expect(find.text('Oyuncuyu şikâyet et'), findsOneWidget);
      final send = find.byKey(const Key('report-send'));
      expect(tester.widget<GestureDetector>(
        find.descendant(of: send, matching: find.byType(GestureDetector)).first,
      ).onTap, isNull); // sebep seçilmeden gönderilemez
      await tester.tap(find.byKey(const Key('reason-username')));
      await tester.enterText(find.byKey(const Key('report-note')), 'Kaba ad');
      await tester.pump();
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(fake.reports.single, {
        'target': kOther,
        'reason': 'username',
        'context': 'leaderboard',
        'duel': null,
        'note': 'Kaba ad',
      });
      expect(find.textContaining('24 saat içinde'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('⋯ → Engelle onaylı; sıralama yenilenir', (tester) async {
      final before = await pumpBoard(tester);
      await tester.tap(find.byKey(const Key('lb-actions-$kOther')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player-block')));
      await tester.pumpAndSettle();
      expect(find.textContaining('engellensin mi?'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(fake.blocked, isEmpty);
      await tester.tap(find.byKey(const Key('lb-actions-$kOther')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player-block')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-block')));
      await tester.pumpAndSettle();
      expect(fake.blocked, [kOther]);
      expect(ModerationService.instance.isBlocked(kOther), true);
      expect(find.text('Oyuncu engellendi.'), findsOneWidget);
      expect(before, 1);
      // Engel sonrası liste sunucudan yeniden istenir (ad "Engellenen oyuncu" gelir).
      await tester.tap(find.byKey(const Key('lb-actions-$kOther')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-unblock')), findsOneWidget);
    });

    testWidgets('misafir: şikâyet için giriş ya da e-posta yolu', (tester) async {
      AuthService.instance.user = null;
      await pumpBoard(tester);
      // Misafirde "kendi satırı" yoktur: iki satırda da ⋯ var.
      await tester.tap(find.byKey(const Key('lb-actions-$kOther')));
      await tester.pumpAndSettle();
      expect(find.text('Giriş yapman gerekiyor'), findsOneWidget);
      expect(find.text('E-POSTA İLE BİLDİR'), findsOneWidget);
      final mail = reportMailUri(
        const PlayerRef(id: kOther, name: 'rakip_oyuncu'),
      );
      expect(mail.scheme, 'mailto');
      expect(mail.path, kSupportEmail);
      expect(Uri.decodeComponent(mail.query), contains(kOther));
      expect(fake.reports, isEmpty);
    });

    for (final size in [const Size(320, 568), const Size(440, 956)]) {
      testWidgets('sıralama satırı ⋯ ile $size taşmaz', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpBoard(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('düello', () {
    testWidgets('canlı rakip: ⋯ → Engelle, ad hemen "Engellenen oyuncu"', (
      tester,
    ) async {
      await pumpDuel(tester, duel());
      expect(find.text('rakip_oyuncu'), findsOneWidget);
      await tester.tap(find.byKey(const Key('duel-opponent-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player-block')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-block')));
      await tester.pumpAndSettle();
      expect(fake.blocked, [kOther]);
      expect(find.text('rakip_oyuncu'), findsNothing);
      expect(find.text(kBlockedLabel), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('kayıtlı rakip: şikâyet sahibine ve ghost bağlamıyla gider', (
      tester,
    ) async {
      await pumpDuel(
        tester,
        duel(kind: 'ghost', ghostSource: 'recorded', ownerId: kOwner),
      );
      await tester.tap(find.byKey(const Key('duel-opponent-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player-report')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reason-cheating')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('report-send')));
      await tester.pumpAndSettle();
      expect(fake.reports.single, {
        'target': kOwner,
        'reason': 'cheating',
        'context': 'ghost',
        'duel': 'd' * 32,
        'note': '',
      });
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('CPU koşusunda şikâyet edilecek oyuncu yok', (tester) async {
      await pumpDuel(tester, duel(kind: 'ghost', ghostSource: 'cpu'));
      expect(find.byKey(const Key('duel-opponent-actions')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    for (final size in [const Size(320, 568), const Size(440, 956)]) {
      testWidgets('sonuç ekranında rakip ⋯ var ve $size taşmaz', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpDuel(tester, duel(finished: true));
        expect(find.byKey(const Key('duel-result-actions')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('duel-result-actions')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('player-report')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  group('Hesabım > Engellenen oyuncular', () {
    testWidgets('liste, engeli kaldır, boş durum', (tester) async {
      fake.list = [
        const BlockedPlayer(id: kOther, name: 'rakip_oyuncu'),
        const BlockedPlayer(id: kOwner, name: 'Oyuncu#C3C3'),
      ];
      await tester.pumpWidget(const MaterialApp(home: AccountScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-blocked')));
      await tester.pumpAndSettle();
      expect(find.text('@rakip_oyuncu'), findsOneWidget);
      expect(find.text('Oyuncu#C3C3'), findsOneWidget); // gizli ad yeniden açılmaz
      await tester.tap(find.byKey(const Key('unblock-$kOther')));
      await tester.pumpAndSettle();
      expect(fake.unblocked, [kOther]);
      expect(find.text('@rakip_oyuncu'), findsNothing);
      expect(ModerationService.instance.isBlocked(kOther, server: true), false);
      await tester.tap(find.byKey(const Key('unblock-$kOwner')));
      await tester.pumpAndSettle();
      expect(find.text('Engellediğin oyuncu yok'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
