import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sut_ve_gol/game/sfx.dart';
import 'package:sut_ve_gol/game/sut_ve_gol_game.dart';
import 'package:sut_ve_gol/services/api_client.dart';
import 'package:sut_ve_gol/services/auth_service.dart';
import 'package:sut_ve_gol/services/progress_service.dart';
import 'package:sut_ve_gol/ui/game_over_overlay.dart';
import 'package:sut_ve_gol/ui/pause_overlay.dart';

/// Sunucu davranışının (backend/src/progress.php) bellek içi karşılığı.
class FakeRemote implements ProgressRemote {
  int epoch = 0, revision = 0;
  ProgressData data = ProgressData.empty;
  int pushes = 0, fetches = 0, resets = 0;
  int failNext = 0;
  final List<ProgressData> pushed = [];

  void _maybeFail() {
    if (failNext > 0) {
      failNext--;
      throw const ApiException('network', 'Sunucuya ulaşılamadı.');
    }
  }

  ProgressSnapshot get snap => ProgressSnapshot(epoch, revision, data);

  @override
  Future<ProgressSnapshot> fetch() async {
    fetches++;
    _maybeFail();
    return snap;
  }

  @override
  Future<ProgressSnapshot> push(int epoch, ProgressData incoming) async {
    pushes++;
    _maybeFail();
    pushed.add(incoming);
    if (epoch != this.epoch) throw ProgressResetException(snap);
    final merged = ProgressData.merge(data, incoming);
    if (!merged.sameAs(data)) {
      data = merged;
      revision++;
    }
    return snap;
  }

  @override
  Future<ProgressSnapshot> reset() async {
    resets++;
    _maybeFail();
    epoch++;
    revision++;
    data = data.wiped();
    return snap;
  }
}

/// İlk yazımda oturum süresi dolmuş (401) sunucu.
class _UnauthorizedOnce extends FakeRemote {
  bool _done = false;
  @override
  Future<ProgressSnapshot> push(int epoch, ProgressData incoming) {
    if (!_done) {
      _done = true;
      pushes++;
      throw const ApiException('unauthorized', 'Oturum gerekli.', 401);
    }
    return super.push(epoch, incoming);
  }
}

/// Yüklenmemiş oyunda yeniden başlatmayı yalnız sayar.
class _ResetProbe extends SutVeGolGame {
  int restarts = 0;
  @override
  void restartAfterReset() => restarts++;
}

Future<ProgressService> service(
  FakeRemote remote, [
  Map<String, Object> prefs = const {},
]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final s = ProgressService(remote: remote)..now = () => 1000;
  await s.ensureLoaded();
  return s;
}

Map<String, int> dev(
  int runs, [
  int shots = 0,
  int hits = 0,
  int fever = 0,
  int ms = 0,
]) => {
  'runs': runs,
  'shots': shots,
  'hits': hits,
  'feverHits': fever,
  'playMs': ms,
};

void main() {
  // PHP testindeki (backend/tests/progress_unit_test.php) örneklerin aynısı.
  final a = ProgressData.fromJson({
    'best': 420,
    'maxStreak': 7,
    'tutorialDone': true,
    'devices': {'devA1234': dev(5, 40, 20, 2, 90000)},
    'settings': {'sound': false, 'haptics': true, 'at': 1000},
  });
  final b = ProgressData.fromJson({
    'best': 300,
    'maxStreak': 9,
    'devices': {
      'devA1234': dev(3, 50, 10, 4, 1000),
      'devB5678': dev(2, 10, 5, 0, 5000),
    },
    'settings': {'sound': true, 'haptics': false, 'at': 2000},
  });
  final c = ProgressData.fromJson({
    'best': 900,
    'devices': {'devC9999': dev(1, 3, 3, 0, 700)},
  });

  group('birleştirme ("ileride olan kazanır")', () {
    test('alan kuralları', () {
      final m = ProgressData.merge(a, b);
      expect(m.best, 420);
      expect(m.maxStreak, 9);
      expect(m.devices['devA1234'], dev(5, 50, 20, 4, 90000));
      expect(m.totals, dev(7, 60, 25, 4, 95000));
      expect(m.settings!.sound, isTrue);
      expect(m.settings!.at, 2000);
      expect(m.tutorialDone, isTrue);
    });

    test('değişmeli, birleşmeli, idempotent', () {
      final m = ProgressData.merge(a, b);
      expect(m.sameAs(ProgressData.merge(b, a)), isTrue);
      expect(
        ProgressData.merge(
          ProgressData.merge(a, b),
          c,
        ).sameAs(ProgressData.merge(a, ProgressData.merge(b, c))),
        isTrue,
      );
      expect(ProgressData.merge(m, m).sameAs(m), isTrue);
      expect(ProgressData.merge(m, b).sameAs(m), isTrue);
    });

    test(
      'eşit zaman damgasında ayar deterministik; ayarı olmayan kaybeder',
      () {
        final s1 = ProgressData.fromJson({
          'settings': {'sound': true, 'haptics': false, 'at': 5},
        });
        final s2 = ProgressData.fromJson({
          'settings': {'sound': false, 'haptics': true, 'at': 5},
        });
        expect(
          ProgressData.merge(s1, s2).sameAs(ProgressData.merge(s2, s1)),
          isTrue,
        );
        expect(
          ProgressData.merge(ProgressData.empty, s2).settings!.haptics,
          isTrue,
        );
      },
    );

    test('normalizasyon sunucuyla aynı', () {
      final n = ProgressData.fromJson({
        'best': -5,
        'maxStreak': '12',
        'tutorialDone': 'yes',
        'devices': {
          'kısa': {'runs': 1},
          'ok_device_1': {'runs': 'x', 'shots': 1e20},
          'bad<>id!!': {},
        },
        'settings': {'sound': 'on', 'haptics': true},
      });
      expect(n.best, 0);
      expect(n.maxStreak, 12);
      expect(n.tutorialDone, isFalse);
      expect(n.devices.keys, ['ok_device_1']);
      expect(n.devices['ok_device_1']!['shots'], 1000000000000);
      expect(n.settings, isNull);
      final many = {
        for (var i = 0; i < 60; i++)
          'device${i.toString().padLeft(3, '0')}': {'runs': i},
      };
      final capped = ProgressData.fromJson({'devices': many});
      expect(capped.devices.length, 48);
      expect(capped.devices.containsKey('device059'), isTrue);
      expect(capped.devices.containsKey('device000'), isFalse);
      expect(
        ProgressData.empty.toJson().toString(),
        '{v: 1, best: 0, maxStreak: 0, tutorialDone: false, devices: {}, settings: null}',
      );
    });

    test('sıfırlama tercihleri korur', () {
      final w = ProgressData.merge(a, b).wiped();
      expect(w.best, 0);
      expect(w.devices, isEmpty);
      expect(w.settings!.at, 2000);
      expect(w.tutorialDone, isTrue);
    });
  });

  group('servis', () {
    testWidgets('yeni kurulum: girişte buluttan sorusuz geri yükleme', (
      tester,
    ) async {
      final remote = FakeRemote()
        ..epoch = 2
        ..revision = 9
        ..data = ProgressData.merge(a, b);
      final s = await service(remote);
      await s.attach('U1');
      expect(s.best, 420);
      expect(s.sound, isTrue);
      expect(s.haptics, isFalse);
      expect(s.totals['runs'], 7);
      expect((s.epoch, s.revision, s.owner, s.dirty), (2, 9, 'U1', false));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('best'), 420);
      expect(prefs.getBool('tutorial_done'), isTrue);
      await tester.pump(const Duration(seconds: 15));
      expect(remote.pushes, 0, reason: 'bulutla aynı veri geri yazılmaz');
    });

    testWidgets('2 sn debounce, en geç 10 sn', (tester) async {
      final remote = FakeRemote();
      final s = await service(remote);
      await s.attach('U1');
      s.recordBest(30);
      await tester.pump(const Duration(milliseconds: 1500));
      s.recordBest(60);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(remote.pushes, 0, reason: 'son değişiklikten 2 sn geçmedi');
      await tester.pump(const Duration(milliseconds: 600));
      expect(remote.pushes, 1);
      expect(remote.data.best, 60);
      expect(s.dirty, isFalse);
      // Sürekli değişiklik: debounce hiç dolmasa da 10 sn'de yazılır.
      for (var i = 1; i <= 9; i++) {
        s.recordBest(60 + i * 30);
        await tester.pump(const Duration(seconds: 1));
      }
      expect(remote.pushes, 1);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(remote.pushes, 2);
      s.debugDetach();
    });

    testWidgets('arka plana geçişte hemen gönderir', (tester) async {
      final remote = FakeRemote();
      final s = await service(remote);
      await s.attach('U1');
      s.setSound(false);
      s.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      expect(remote.pushes, 1);
      expect(remote.data.settings!.sound, isFalse);
    });

    testWidgets('çevrimdışı: kalıcı kuyruk ve üstel geri deneme', (
      tester,
    ) async {
      final remote = FakeRemote();
      final s = await service(remote);
      await s.attach('U1');
      remote.failNext = 3;
      s.recordRun(
        score: 90,
        shots: 5,
        hits: 3,
        feverHits: 0,
        maxStreak: 3,
        durationMs: 9000,
      );
      await tester.pump(const Duration(seconds: 2)); // 1. deneme başarısız
      expect((remote.pushes, s.failures, s.dirty), (1, 1, true));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(ProgressService.kDirty), isTrue);
      await tester.pump(const Duration(seconds: 2)); // +2 s
      expect(remote.pushes, 2);
      await tester.pump(const Duration(seconds: 3));
      expect(remote.pushes, 2, reason: 'ikinci bekleme 4 sn');
      await tester.pump(const Duration(seconds: 1)); // +4 s
      expect(remote.pushes, 3);
      await tester.pump(const Duration(seconds: 8)); // +8 s → başarılı
      expect(remote.pushes, 4);
      expect((s.failures, s.dirty), (0, false));
      expect(remote.data.best, 90);
      expect(remote.data.totals['runs'], 1);
    });

    testWidgets('oturum düşünce durur, yeniden girişte sürer', (tester) async {
      final remote = _UnauthorizedOnce();
      final s = await service(remote);
      await s.attach('U1');
      s.recordBest(120);
      await tester.pump(const Duration(seconds: 2));
      expect((remote.pushes, s.dirty), (1, true));
      await tester.pump(const Duration(minutes: 6));
      expect(remote.pushes, 1, reason: '401 sonrası boşuna deneme yok');
      await s.attach('U1');
      await tester.pump(const Duration(seconds: 2));
      expect((remote.data.best, s.dirty), (120, false));
    });

    testWidgets('yeniden açılışta kirli kayıt gönderilir', (tester) async {
      final remote = FakeRemote();
      final s = await service(remote, {
        ProgressService.kData: '{"best":510,"devices":{}}',
        ProgressService.kDirty: true,
        ProgressService.kOwner: 'U1',
        'best': 510,
      });
      await s.attach('U1');
      await tester.pump(const Duration(seconds: 2));
      expect(remote.data.best, 510);
      expect(s.dirty, isFalse);
    });

    testWidgets('misafir ilerlemesi girişte hesaba birleşir', (tester) async {
      final remote = FakeRemote()..data = c;
      final s = await service(remote, {'best': 1200, 'sound': false});
      expect(s.best, 1200);
      expect(s.sound, isFalse);
      await s.attach('U1');
      expect(s.best, 1200);
      expect(s.totals['runs'], 1, reason: 'buluttaki diğer cihaz sayacı geldi');
      await tester.pump(const Duration(seconds: 2));
      expect(remote.data.best, 1200);
      expect(remote.data.settings!.sound, isFalse);
    });

    testWidgets('başka hesabın yerel ilerlemesi yeni hesaba karışmaz', (
      tester,
    ) async {
      final remote = FakeRemote()..data = c;
      final s = await service(remote, {
        ProgressService.kData:
            '{"best":2000,"devices":{"oldDevice1":{"runs":9}}}',
        ProgressService.kOwner: 'U1',
      });
      await s.attach('U2');
      expect(s.best, 900);
      expect(s.data.devices.containsKey('oldDevice1'), isFalse);
      await tester.pump(const Duration(seconds: 15));
      expect(remote.data.best, 900);
    });

    testWidgets('Sil ve baştan başla: bulut sıfırlanır, epoch artar', (
      tester,
    ) async {
      final remote = FakeRemote();
      final phone = await service(remote);
      await phone.attach('U1');
      phone.recordRun(
        score: 600,
        shots: 20,
        hits: 12,
        feverHits: 2,
        maxStreak: 6,
        durationMs: 60000,
      );
      phone.setHaptics(false);
      await phone.flush();
      expect(remote.data.best, 600);

      await phone.resetAll();
      expect(remote.resets, 1);
      expect((phone.best, phone.totals['runs'], phone.haptics), (0, 0, false));
      expect(phone.epoch, 1);

      expect(remote.data.best, 0);
      expect(remote.data.settings!.haptics, isFalse, reason: 'tercih korunur');
      // Diğer cihazın eski epoch'lu yazımı reddedilir (yayılım: sonraki test).
      await expectLater(
        remote.push(0, ProgressData.fromJson({'best': 600})),
        throwsA(isA<ProgressResetException>()),
      );
      phone.debugDetach();
    });

    testWidgets('eski epoch ile yazım reddedilince yerel silinir', (
      tester,
    ) async {
      final remote = FakeRemote()..epoch = 3;
      final s = await service(remote, {
        ProgressService.kData:
            '{"best":700,"devices":{"tabletAAA1":{"runs":4}}}',
        ProgressService.kOwner: 'U1',
        ProgressService.kEpoch: 2,
        ProgressService.kDirty: true,
      });
      // Çekme başarısız olsa da yazım 409 alır ve sıfırlamayı benimser.
      remote.failNext = 1;
      await s.attach('U1');
      await tester.pump(const Duration(seconds: 2));
      expect((s.best, s.epoch), (0, 3));
      expect(remote.data.best, 0);
      s.debugDetach();
    });

    testWidgets('çevrimdışı sıfırlama: hata, yerel ilerleme korunur', (
      tester,
    ) async {
      final remote = FakeRemote();
      final s = await service(remote, {'best': 300});
      await s.attach('U1');
      remote.failNext = 1;
      await expectLater(s.resetAll(), throwsA(isA<ApiException>()));
      expect(s.best, 300);
      s.debugDetach();
    });

    testWidgets('misafir sıfırlaması yalnız yerel', (tester) async {
      final remote = FakeRemote();
      final s = await service(remote, {'best': 300, 'haptics': false});
      await s.resetAll();
      expect((s.best, s.haptics, remote.resets), (0, false, 0));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('best'), 0);
    });

    testWidgets('hesap silme yereli de temizler', (tester) async {
      final remote = FakeRemote()..data = c;
      final s = await service(remote);
      await s.attach('U1');
      await s.forgetAccount();
      expect((s.best, s.owner, s.epoch, s.signedIn), (0, null, 0, false));
      await tester.pump(const Duration(seconds: 15));
      expect(remote.pushes, 0);
    });
  });

  testWidgets('duraklat menüsü: iki onaylı Sil ve baştan başla', (
    tester,
  ) async {
    Sfx.skipInit = true;
    SharedPreferences.setMockInitialValues({'best': 450});
    final old = ProgressService.instance;
    final remote = FakeRemote();
    ProgressService.instance = ProgressService(remote: remote);
    addTearDown(() => ProgressService.instance = old);
    await ProgressService.instance.ensureLoaded();
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = _ResetProbe()..best = 450;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PauseOverlay(game: game, guest: true)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Sil ve baştan başla'), findsOneWidget);
    expect(find.textContaining('yalnız bu cihazda'), findsOneWidget);
    await tester.ensureVisible(find.text('Sil ve baştan başla'));
    await tester.tap(find.text('Sil ve baştan başla'));
    await tester.pumpAndSettle();
    expect(find.text('Sil ve baştan başla?'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(ProgressService.instance.best, 450, reason: 'ilk onayda vazgeçildi');
    await tester.tap(find.text('Sil ve baştan başla'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    expect(find.text('Emin misin?'), findsOneWidget);
    expect(
      ProgressService.instance.best,
      450,
      reason: 'ikinci onay bekleniyor',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sil ve baştan başla'));
    await tester.pump();
    await tester.pump();
    expect(ProgressService.instance.best, 0);
    expect(remote.resets, 0, reason: 'misafir: yalnız yerel');
    expect(game.restarts, 1, reason: 'yarım koşu atılıp baştan başlar');
    expect(find.text('İlerleme silindi. Baştan başlıyorsun.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  for (final google in [false, true]) {
    testWidgets(
      'misafire ilk oyun sonunda bir kez kayıt önerisi (Google ${google ? 'var' : 'yok'})',
      (tester) async {
        Sfx.skipInit = true;
        debugGoogleAvailable = google;
        addTearDown(() => debugGoogleAvailable = null);
        SharedPreferences.setMockInitialValues({});
        final old = ProgressService.instance;
        ProgressService.instance = ProgressService(remote: FakeRemote());
        addTearDown(() => ProgressService.instance = old);
        await ProgressService.instance.ensureLoaded();
        tester.view.physicalSize = const Size(440, 956);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final game = SutVeGolGame();
        Future<void> show({required bool guest}) async {
          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              home: Scaffold(
                body: GameOverOverlay(game: game, guest: guest),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 2000));
          await tester.pump(const Duration(milliseconds: 600));
        }

        await show(guest: false);
        expect(
          find.text('İlerlemeni kaydet'),
          findsNothing,
          reason: 'girişli oyuncuya öneri yok',
        );
        await show(guest: true);
        expect(find.text('İlerlemeni kaydet'), findsOneWidget);
        expect(find.text('Apple ile kaydet'), findsOneWidget);
        expect(
          find.text('Google ile kaydet'),
          google ? findsOneWidget : findsNothing,
          reason: 'Google kimliği yoksa düğme gizli',
        );
        expect(ProgressService.instance.saveOfferSeen, isTrue);
        await tester.tap(find.text('Şimdi değil'));
        await tester.pumpAndSettle();
        expect(find.text('İlerlemeni kaydet'), findsNothing);
        // Atlandıktan sonra sonraki oyunlarda tekrar sorulmaz.
        await show(guest: true);
        expect(find.text('İlerlemeni kaydet'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
      },
    );
  }
}
