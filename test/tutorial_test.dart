import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sut_ve_gol/game/geometry.dart';
import 'package:sut_ve_gol/game/sfx.dart';
import 'package:sut_ve_gol/game/sut_ve_gol_game.dart';
import 'package:sut_ve_gol/game/tutorial.dart';
import 'package:sut_ve_gol/main.dart';
import 'package:sut_ve_gol/services/auth_service.dart';
import 'package:sut_ve_gol/ui/pause_overlay.dart';
import 'package:sut_ve_gol/ui/tutorial_overlay.dart';

const _phone = Size(440, 956);

SutVeGolGame _gameOf(WidgetTester tester) => tester
    .widget<GameWidget<SutVeGolGame>>(find.byType(GameWidget<SutVeGolGame>))
    .game!;

void _setView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Gerçek oyun ekranını (GameScreen) kurar; [prefs] null ise önceki
/// testteki kayıtlar korunur (yeni oturum).
Future<SutVeGolGame> _openGame(
  WidgetTester tester, {
  Map<String, Object>? prefs,
  Size size = _phone,
}) async {
  Sfx.skipInit = true;
  if (prefs != null) SharedPreferences.setMockInitialValues(prefs);
  _setView(tester, size);
  late SutVeGolGame game;
  await tester.runAsync(() async {
    await tester.pumpWidget(
      MaterialApp(theme: appTheme(), home: const GameScreen(guest: true)),
    );
    game = _gameOf(tester);
    await game.loaded;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  return game;
}

/// Açılış (~4 s) ve ilk topun gelişi.
Future<void> _untilBallReady(WidgetTester tester, SutVeGolGame game) async {
  for (var i = 0; i < 220 && game.state != GameState.idle; i++) {
    await tester.pump(const Duration(milliseconds: 33));
  }
  expect(game.state, GameState.idle);
  await tester.pump(const Duration(milliseconds: 33));
}

Future<void> _pumpFor(WidgetTester tester, double seconds) async {
  for (var i = 0; i < (seconds / 0.033).ceil(); i++) {
    await tester.pump(const Duration(milliseconds: 33));
  }
}

Offset _ballOnScreen(SutVeGolGame game, Size size) => WorldFrame.of(
  size,
).toScreen(Offset(game.view.ballRest.x, game.view.ballRest.y));

Future<void> _swipeUp(WidgetTester tester, SutVeGolGame game, Size size) async {
  await tester.timedDragFrom(
    _ballOnScreen(game, size),
    Offset(0, -size.height * 0.3),
    const Duration(milliseconds: 160),
  );
  await tester.pump(const Duration(milliseconds: 33));
}

Future<bool?> _doneFlag() async =>
    (await SharedPreferences.getInstance()).getBool(TutorialProgress.doneKey);

void main() {
  group('TutorialProgress', () {
    test('yeni oyuncuya gösterilir, bayrak yazılmaz', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(TutorialProgress.shouldShow(prefs), isTrue);
      expect(prefs.getBool(TutorialProgress.doneKey), isNull);
    });

    test('bitirilen ya da geçilen rehber bir daha gösterilmez', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await TutorialProgress.markDone(prefs);
      expect(TutorialProgress.shouldShow(prefs), isFalse);
    });

    test('rekoru ya da ayarı olan eski oyuncuya gösterilmez', () async {
      for (final old in <Map<String, Object>>[
        {'best': 150},
        {'sound': false},
        {'haptics': true},
      ]) {
        SharedPreferences.setMockInitialValues(old);
        final prefs = await SharedPreferences.getInstance();
        expect(TutorialProgress.shouldShow(prefs), isFalse, reason: '$old');
        expect(prefs.getBool(TutorialProgress.doneKey), isTrue, reason: '$old');
      }
    });

    test('sıfır rekor ilerleme sayılmaz', () async {
      SharedPreferences.setMockInitialValues({'best': 0});
      final prefs = await SharedPreferences.getInstance();
      expect(TutorialProgress.shouldShow(prefs), isTrue);
    });
  });

  test('düello oyunları rehber açmaz', () {
    final duel = SutVeGolGame(mode: GameMode.duel)..firstRunTutorial = true;
    duel.showTutorial();
    expect(duel.tutorialActive, isFalse);
  });

  testWidgets('ilk açılışta rehber oyun ekranında açılır, bilgi adımı şutu yutar', (
    tester,
  ) async {
    final game = await _openGame(tester, prefs: {});
    await tester.pump(const Duration(milliseconds: 33));
    expect(find.byType(TutorialOverlay), findsNothing, reason: 'açılış sürerken');
    await _untilBallReady(tester, game);
    expect(game.tutorialActive, isTrue);
    expect(find.text('Kaydır ve şut çek'), findsOneWidget);
    expect(find.text('1/4'), findsOneWidget);
    for (final lesson in ShotLesson.values) {
      expect(find.text(lesson.label), findsOneWidget);
    }
    await _swipeUp(tester, game, _phone);
    expect(game.kicks, 0);
    expect(game.state, GameState.idle);
    expect(await _doneFlag(), isNull);
  });

  testWidgets('adımlar ilerler, rehber eşliğinde ilk şut rehberi bitirir', (
    tester,
  ) async {
    final game = await _openGame(tester, prefs: {});
    await _untilBallReady(tester, game);

    // Şut dersleri kendiliğinden döner: nişan → falso → güç.
    expect(find.text(ShotLesson.aim.text), findsOneWidget);
    await _pumpFor(tester, ShotLesson.aim.seconds + 0.2);
    expect(find.text(ShotLesson.curve.text), findsOneWidget);
    await tester.tap(find.text('GÜÇ'));
    await _pumpFor(tester, 0.4);
    expect(find.text(ShotLesson.power.text), findsOneWidget);

    await tester.tap(find.text('İLERİ'));
    await _pumpFor(tester, 0.6);
    expect(find.text('Halkayı vur'), findsOneWidget);
    expect(find.text('2/4'), findsOneWidget);

    await tester.tap(find.text('İLERİ'));
    await _pumpFor(tester, 0.6);
    expect(find.text('Üç kalbin var'), findsOneWidget);
    for (final stage in Stage.values) {
      expect(find.text(stage.label), findsOneWidget);
    }

    await tester.tap(find.text('ŞUT ÇEK'));
    await _pumpFor(tester, 0.6);
    expect(find.text('İlk şutunu çek'), findsOneWidget);
    expect(find.text('İLERİ'), findsNothing);
    expect(await _doneFlag(), isNull);

    // Son adımda dokunuş oyuna geçer: gerçek ilk şut.
    await _swipeUp(tester, game, _phone);
    expect(game.kicks, 1);
    expect(game.state, isNot(GameState.idle));
    expect(await _doneFlag(), isTrue);
    await _pumpFor(tester, 0.3);
    expect(find.text('Hazırsın!'), findsOneWidget);
    await _pumpFor(tester, 2.0);
    expect(game.tutorialActive, isFalse);
    expect(find.byType(TutorialOverlay), findsNothing);
  });

  testWidgets('Geç kapatır; bayrak kalıcı, yeni oturumda rehber çıkmaz', (
    tester,
  ) async {
    var game = await _openGame(tester, prefs: {});
    await _untilBallReady(tester, game);
    expect(game.tutorialActive, isTrue);
    await tester.tap(find.text('Geç'));
    await _pumpFor(tester, 0.5);
    expect(game.tutorialActive, isFalse);
    expect(find.byType(TutorialOverlay), findsNothing);
    expect(await _doneFlag(), isTrue);
    // Kapandıktan sonra oyun hemen oynanır.
    await _swipeUp(tester, game, _phone);
    expect(game.kicks, 1);

    // Uygulama yeniden açılmış gibi: aynı kayıtla yeni oyun ekranı.
    await tester.pumpWidget(const SizedBox());
    game = await _openGame(tester);
    await _untilBallReady(tester, game);
    await _pumpFor(tester, 1.0);
    expect(game.tutorialActive, isFalse);
    expect(find.byType(TutorialOverlay), findsNothing);
  });

  testWidgets('rekoru olan eski oyuncu güncellemeden sonra rehberi görmez', (
    tester,
  ) async {
    final game = await _openGame(tester, prefs: {'best': 450});
    await _untilBallReady(tester, game);
    await _pumpFor(tester, 1.0);
    expect(game.tutorialActive, isFalse);
    expect(find.byType(TutorialOverlay), findsNothing);
    expect(await _doneFlag(), isTrue);
  });

  testWidgets('duraklat menüsündeki "Nasıl oynanır" rehberi baştan açar', (
    tester,
  ) async {
    final game = await _openGame(
      tester,
      prefs: {TutorialProgress.doneKey: true},
    );
    await _untilBallReady(tester, game);
    expect(game.tutorialActive, isFalse);
    final frame = WorldFrame.of(_phone);
    await tester.tapAt(frame.toScreen(kPauseRect.center));
    await _pumpFor(tester, 0.5);
    expect(find.byType(PauseOverlay), findsOneWidget);
    await tester.tap(find.text('Nasıl oynanır'));
    await _pumpFor(tester, 0.6);
    expect(find.byType(PauseOverlay), findsNothing);
    expect(game.tutorialActive, isTrue);
    expect(find.text('Kaydır ve şut çek'), findsOneWidget);
    expect(find.text('1/4'), findsOneWidget);
    // Okurken oyun donuk bekler; rehber kapanınca kaldığı yerden sürer.
    expect(game.state, GameState.paused);
    await tester.tap(find.text('Geç'));
    await _pumpFor(tester, 0.5);
    expect(game.tutorialActive, isFalse);
    expect(game.state, GameState.idle);
    await _swipeUp(tester, game, _phone);
    expect(game.kicks, 1);
  });

  testWidgets('giriş akışı aynı: misafir oyuna girince rehber açılır', (
    tester,
  ) async {
    Sfx.skipInit = true;
    SharedPreferences.setMockInitialValues({});
    _setView(tester, _phone);
    AuthService.instance
      ..loading = false
      ..user = null;
    await tester.pumpWidget(
      MaterialApp(theme: appTheme(), home: const AuthGate()),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('MİSAFİR OLARAK OYNA'), findsOneWidget);
    expect(find.byType(TutorialOverlay), findsNothing);
    await tester.tap(find.text('MİSAFİR OLARAK OYNA'));
    late SutVeGolGame game;
    await tester.runAsync(() async {
      await tester.pump();
      game = _gameOf(tester);
      await game.loaded;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await _untilBallReady(tester, game);
    expect(game.tutorialActive, isTrue);
    expect(find.text('Kaydır ve şut çek'), findsOneWidget);
  });

  for (final size in const [Size(320, 568), _phone, Size(1032, 1376)]) {
    testWidgets('rehber adımları $size taşmaz', (tester) async {
      final game = await _openGame(tester, prefs: {}, size: size);
      await _untilBallReady(tester, game);
      expect(game.tutorialActive, isTrue);
      expect(tester.takeException(), isNull, reason: 'şut');
      for (final lesson in [ShotLesson.curve, ShotLesson.power]) {
        await tester.tap(find.text(lesson.label));
        await _pumpFor(tester, 1.0);
        expect(tester.takeException(), isNull, reason: lesson.name);
      }
      for (final button in ['İLERİ', 'İLERİ', 'ŞUT ÇEK']) {
        await tester.tap(find.text(button));
        await _pumpFor(tester, 0.7);
        expect(tester.takeException(), isNull, reason: button);
      }
      expect(find.text('İlk şutunu çek'), findsOneWidget);
      await _swipeUp(tester, game, size);
      await _pumpFor(tester, 0.3);
      expect(find.text('Hazırsın!'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'hazırsın');
      await _pumpFor(tester, 2.0);
      expect(game.tutorialActive, isFalse);
    });
  }
}
