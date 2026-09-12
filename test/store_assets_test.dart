import 'dart:io';
import 'dart:ui' as ui;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sut_ve_gol/game/geometry.dart';
import 'package:sut_ve_gol/game/sfx.dart';
import 'package:sut_ve_gol/game/sut_ve_gol_game.dart';

void main() {
  const export = bool.fromEnvironment('EXPORT_STORE_ASSETS');
  for (final tablet in [false, true]) {
  for (final stage in Stage.values) {
    testWidgets('store capture ${tablet ? 'ipad' : 'iphone'} ${stage.name}', (tester) async {
      Sfx.skipInit = true;
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = tablet ? const Size(2064, 2752) : const Size(kWorldW, kWorldH);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final font = FontLoader('TitilliumWeb')..addFont(rootBundle.load('assets/fonts/TitilliumWeb-Bold.ttf'));
      await font.load();
      final game = SutVeGolGame()..stage = stage;
      final key = GlobalKey();
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(home: RepaintBoundary(key: key, child: GameWidget(game: game))));
        await game.loaded;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      for (var i = 0; i < 180; i++) { await tester.pump(const Duration(milliseconds: 33)); }
      expect(game.state, GameState.idle);
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/store/${tablet ? 'ipad' : 'iphone'}/${stage.name}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }, skip: !export);
  }
  }
}
