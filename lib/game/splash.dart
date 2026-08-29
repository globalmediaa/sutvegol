import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import 'geometry.dart';
import 'kick_legend_game.dart';

double _easeInOut(double t) => t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2;
double _easeOutBack(double t) {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2);
}

/// Açılış: gökyüzü + soldan kayan KICK LEGEND logosu, sonra sahaya pan.
class SplashLayer extends PositionComponent with HasGameReference<KickLegendGame> {
  SplashLayer() : super(size: Vector2(kWorldW, kWorldH), priority: 50);

  static const double logoIn = 0.45;
  static const double hold = 1.6;
  static const double pan = 0.9;

  late Sprite _bg;
  late Sprite _logo;
  double _t = 0;
  bool _done = false;

  @override
  Future<void> onLoad() async {
    _bg = Sprite(game.images.fromCache('splash_bg.png'));
    _logo = Sprite(game.images.fromCache('logo.png'));
  }

  @override
  void update(double dt) {
    if (_done) return;
    _t += dt;
    final panStart = logoIn + hold;
    if (_t >= panStart + pan) {
      _done = true;
      game.onSplashFinished();
      return;
    }
    if (_t > panStart) {
      final k = _easeInOut(((_t - panStart) / pan).clamp(0, 1));
      position.y = -kWorldH * k;
      game.scene.position.y = kWorldH * (1 - k);
    }
  }

  @override
  void render(Canvas canvas) {
    _bg.render(canvas, size: size);
    final k = _easeOutBack((_t / logoIn).clamp(0, 1));
    final x = -1300 + (48 + 1300) * k;
    _logo.render(canvas, position: Vector2(x, 740), size: Vector2(1192, 570));
  }
}
