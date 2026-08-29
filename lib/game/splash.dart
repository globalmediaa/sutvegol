import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import 'geometry.dart';
import 'kick_legend_game.dart';

double _easeInOut(double t) => t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2;
double _easeOutBack(double t) {
  const c1 = 1.2;
  const c3 = c1 + 1;
  return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2);
}

/// Açılış: gökyüzü aşağı akar, KICK LEGEND logosu alttan yükselip ortaya
/// oturur, ardından kamera sahaya iner.
class SplashLayer extends PositionComponent with HasGameReference<KickLegendGame> {
  SplashLayer() : super(size: Vector2(kWorldW, kWorldH), priority: 50);

  static const double logoIn = 0.55;
  static const double hold = 1.5;
  static const double pan = 0.9;
  static const double cloudSpeed = 70; // px/s, aşağı

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
    // Gökyüzü yavaşça aşağı akar (kamera yukarı bakıyor hissi).
    final off = min(0.0, -140 + _t * cloudSpeed);
    _bg.render(canvas, position: Vector2(0, off), size: Vector2(kWorldW, kWorldH + 140));

    // Logo: alttan yükselir, hafif taşma ile oturur.
    final k = _easeOutBack((_t / logoIn).clamp(0, 1));
    final y = 740 + (kWorldH - 740) * (1 - k);
    _logo.render(canvas, position: Vector2(48, y), size: Vector2(1192, 570));
  }
}
