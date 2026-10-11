import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sut_ve_gol/game/sfx.dart';
import 'package:sut_ve_gol/game/sut_ve_gol_game.dart';
import 'package:sut_ve_gol/main.dart';
import 'package:sut_ve_gol/ui/logo.dart';
import 'package:sut_ve_gol/ui/tutorial_overlay.dart';

/// İlk açılış rehberinin adım adım telefon görüntüleri (normal test koşusunda
/// atlanır):
/// flutter test test/tutorial_screens_test.dart \
///   --dart-define=EXPORT_TUTORIAL_SHOTS=true \
///   --dart-define=TUTORIAL_SHOTS_DIR=/mutlak/klasor
void main() {
  const export = bool.fromEnvironment('EXPORT_TUTORIAL_SHOTS');
  const dir = String.fromEnvironment(
    'TUTORIAL_SHOTS_DIR',
    defaultValue: 'build/tutorial',
  );

  const devices = [
    // ad, mantıksal boyut, piksel oranı, güvenli alan (üst, alt)
    ('iphone-6.9', Size(440, 956), 3.0, 62.0, 34.0),
    ('iphone-6.1', Size(393, 852), 3.0, 59.0, 34.0),
    ('iphone-se', Size(375, 667), 2.0, 20.0, 0.0),
  ];

  for (final (name, size, dpr, top, bottom) in devices) {
    testWidgets('rehber görüntüleri $name', (tester) async {
      Sfx.skipInit = true;
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size * dpr;
      tester.view.devicePixelRatio = dpr;
      tester.view.padding = FakeViewPadding(top: top * dpr, bottom: bottom * dpr);
      tester.view.viewPadding = FakeViewPadding(
        top: top * dpr,
        bottom: bottom * dpr,
      );
      addTearDown(tester.view.reset);
      debugDisableShadows = false;
      try {
        await tester.runAsync(() async {
          final titillium = FontLoader('TitilliumWeb')
            ..addFont(rootBundle.load('assets/fonts/TitilliumWeb-Regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/TitilliumWeb-SemiBold.ttf'))
            ..addFont(rootBundle.load('assets/fonts/TitilliumWeb-Bold.ttf'));
          await titillium.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
          await loadBrandIdentity();
        });

        final key = GlobalKey();
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: appTheme(),
              home: RepaintBoundary(
                key: key,
                child: const GameScreen(guest: true),
              ),
            ),
          );
          final game = tester
              .widget<GameWidget<SutVeGolGame>>(
                find.byType(GameWidget<SutVeGolGame>),
              )
              .game!;
          await game.loaded;
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        final game = tester
            .widget<GameWidget<SutVeGolGame>>(
              find.byType(GameWidget<SutVeGolGame>),
            )
            .game!;

        Future<void> frames(double seconds) async {
          final n = (seconds / 0.016).round();
          for (var i = 0; i < n; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
        }

        Future<void> capture(String file) async {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: dpr);
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            final out = File('$dir/$name/$file.png');
            await out.parent.create(recursive: true);
            await out.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        // Açılış + top girişi; rehber ilk top hazır olunca açılır.
        for (var i = 0; i < 400 && !game.tutorialActive; i++) {
          await tester.pump(const Duration(milliseconds: 33));
        }
        expect(game.tutorialActive, isTrue);

        await frames(0.62);
        await capture('01-sut-nisan-parmak');
        await frames(0.6);
        await capture('02-sut-nisan-top');

        await tester.tap(find.text('FALSO'));
        await frames(0.74);
        await capture('03-sut-falso-parmak');
        await frames(0.72);
        await capture('04-sut-falso-top');

        await tester.tap(find.text('GÜÇ'));
        await frames(0.72);
        await capture('05-sut-guc-yavas');
        await frames(2.2);
        await capture('06-sut-guc-hizli');

        await tester.tap(find.text('İLERİ'));
        await frames(1.0);
        await capture('07-halka-kaleci');

        await tester.tap(find.text('İLERİ'));
        await frames(1.0);
        await capture('08-kalpler-sahneler');

        await tester.tap(find.text('ŞUT ÇEK'));
        await frames(0.7);
        await capture('09-sira-sende');

        final frame = WorldFrame.of(size);
        final ball = frame.toScreen(
          Offset(game.view.ballRest.x, game.view.ballRest.y),
        );
        await tester.timedDragFrom(
          ball,
          Offset(0, -size.height * 0.3),
          const Duration(milliseconds: 160),
        );
        await frames(0.45);
        await capture('10-hazirsin');
        await frames(2.0);
        expect(game.tutorialActive, isFalse);

        // Duraklat menüsünde "Nasıl oynanır".
        for (var i = 0; i < 200 && game.state != GameState.idle; i++) {
          await tester.pump(const Duration(milliseconds: 33));
        }
        game.pause();
        await frames(0.6);
        await capture('11-duraklat-nasil-oynanir');
        game.resume();
        await frames(0.3);
      } finally {
        debugDisableShadows = true;
      }
    }, skip: !export);
  }
}
