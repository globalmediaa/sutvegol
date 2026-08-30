import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextStyle, FontWeight;

import 'geometry.dart';
import 'kick_legend_game.dart';
import 'sfx.dart';

double _easeInOut(double t) => t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2;
double _easeOutBack(double t) {
  const c1 = 1.2;
  const c3 = c1 + 1;
  return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2);
}

/// Açılış: gök + "Loading" spinner, sonra logo alttan yükselir, kamera sahaya iner.
class SplashLayer extends PositionComponent with HasGameReference<KickLegendGame> {
  SplashLayer() : super(size: Vector2(kWorldW, kWorldH), priority: 50);

  static const double loading = 0.9;
  static const double logoIn = 0.55;
  static const double hold = 1.5;
  static const double pan = 0.9;
  static const double cloudSpeed = 70;

  late Sprite _bg;
  late Sprite _logo;
  double _t = 0;
  bool _done = false;
  bool _whooshed = false;

  static final _loadingText = TextPaint(
    style: const TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w600,
      fontFamily: 'TitilliumWeb',
      color: Color(0xFFFFFFFF),
    ),
  );

  @override
  Future<void> onLoad() async {
    _bg = Sprite(game.images.fromCache('splash_bg.png'));
    _logo = Sprite(game.images.fromCache('logo.png'));
  }

  @override
  void update(double dt) {
    if (_done) return;
    _t += dt;
    if (!_whooshed && _t >= loading) {
      _whooshed = true;
      Sfx.splash();
    }
    final panStart = loading + logoIn + hold;
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
    final off = min(0.0, -140 + max(0.0, _t - loading) * cloudSpeed);
    _bg.render(canvas, position: Vector2(0, off), size: Vector2(kWorldW, kWorldH + 140));

    if (_t < loading) {
      // Yükleme: hafif karartma + dönen yay + "Loading".
      final fade = _t > loading - 0.25 ? (loading - _t) / 0.25 : 1.0;
      canvas.drawRect(size.toRect(), Paint()..color = Color.fromRGBO(0, 0, 0, 0.35 * fade));
      final c = Offset(kWorldW / 2, kWorldH / 2 - 40);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: 26),
        _t * 6,
        4.2,
        false,
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, 0.9 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
      _loadingText.render(canvas, 'Loading', Vector2(kWorldW / 2, kWorldH / 2 + 30), anchor: Anchor.center);
      return;
    }

    final k = _easeOutBack(((_t - loading) / logoIn).clamp(0, 1));
    final y = 740 + (kWorldH - 740) * (1 - k);
    _logo.render(canvas, position: Vector2(48, y), size: Vector2(1192, 570));
  }
}
