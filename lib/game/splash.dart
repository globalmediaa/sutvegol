import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextStyle, FontWeight;

import '../ui/logo.dart';
import 'sut_ve_gol_game.dart';
import 'geometry.dart';
import 'sfx.dart';

double _easeInOut(double t) =>
    t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2;

/// Açılış: gece göğü + "Yükleniyor", sonra logo alev izleriyle belirir,
/// köz parçacıkları yükselir, kamera sokağa iner.
class SplashLayer extends PositionComponent
    with HasGameReference<SutVeGolGame> {
  SplashLayer() : super(size: Vector2(kWorldW, kWorldH), priority: 50);

  static const double loading = 0.9;
  static const double logoIn = 0.9;
  static const double hold = 1.4;
  static const double pan = 0.9;

  late Sprite _sky;
  double _t = 0;
  bool _done = false;
  bool _whooshed = false;
  final List<_Ember> _embers = [];
  final Random _rng = Random(3);

  static final _loadingText = TextPaint(
    style: const TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w600,
      fontFamily: 'TitilliumWeb',
      color: Color(0xFFDDE4F5),
      letterSpacing: 2,
    ),
  );

  @override
  Future<void> onLoad() async {
    _sky = Sprite(game.images.fromCache('splash_sky'));
    for (var i = 0; i < 46; i++) {
      _embers.add(_Ember(_rng));
    }
  }

  @override
  void update(double dt) {
    if (_done) return;
    _t += dt;
    if (!_whooshed && _t >= loading) {
      _whooshed = true;
      Sfx.splash();
    }
    for (final e in _embers) {
      e.update(dt, _rng);
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
    final drift = min(0.0, -140 + max(0.0, _t - loading) * 60);
    _sky.render(
      canvas,
      position: Vector2(0, drift),
      size: Vector2(kWorldW, kWorldH + 140),
    );

    if (_t < loading) {
      final fade = _t > loading - 0.25 ? (loading - _t) / 0.25 : 1.0;
      final c = Offset(kWorldW / 2, kWorldH / 2 - 40);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: 28),
        _t * 6,
        4.2,
        false,
        Paint()
          ..color = Color.fromRGBO(255, 122, 26, 0.95 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
      _loadingText.render(
        canvas,
        'Yükleniyor',
        Vector2(kWorldW / 2, kWorldH / 2 + 34),
        anchor: Anchor.center,
      );
      return;
    }

    final k = ((_t - loading) / logoIn).clamp(0.0, 1.0);
    // Arka parıltı.
    canvas.drawCircle(
      const Offset(kWorldW / 2, 1080),
      560,
      Paint()
        ..color = Color.fromRGBO(255, 122, 26, 0.22 * k)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 120),
    );
    for (final e in _embers) {
      e.render(canvas, k);
    }
    // Kare ikon zemini yerine arka planla bütünleşen şeffaf marka sembolü.
    paintBrandMark(canvas, const Rect.fromLTWH(250, 620, 820, 820), reveal: k);
    if (k >= 1) {
      final tip = TextPaint(
        style: TextStyle(
          fontSize: 38,
          fontWeight: FontWeight.w600,
          fontFamily: 'TitilliumWeb',
          color: Color.fromRGBO(
            221,
            228,
            245,
            0.55 + 0.45 * ((sin(_t * 4) + 1) / 2),
          ),
          letterSpacing: 1,
        ),
      );
      tip.render(
        canvas,
        'Kaydır ve şut çek',
        Vector2(kWorldW / 2, 1560),
        anchor: Anchor.center,
      );
    }
  }
}

/// Logonun etrafında yükselen köz.
class _Ember {
  _Ember(Random rng) {
    reset(rng, initial: true);
  }
  late double x, y, vy, r, life, age, wobble;

  void reset(Random rng, {bool initial = false}) {
    x = 200 + rng.nextDouble() * (kWorldW - 400);
    y = initial ? 900 + rng.nextDouble() * 700 : 1420 + rng.nextDouble() * 200;
    vy = 90 + rng.nextDouble() * 140;
    r = 3 + rng.nextDouble() * 6;
    life = 2 + rng.nextDouble() * 2.5;
    age = initial ? rng.nextDouble() * life : 0;
    wobble = rng.nextDouble() * pi * 2;
  }

  void update(double dt, Random rng) {
    age += dt;
    y -= vy * dt;
    x += sin(age * 2 + wobble) * 30 * dt;
    if (age > life || y < 600) reset(rng);
  }

  void render(Canvas canvas, double k) {
    final a = (1 - age / life).clamp(0.0, 1.0) * k;
    canvas.drawCircle(
      Offset(x, y),
      r,
      Paint()
        ..color = Color.fromRGBO(255, 170, 60, 0.85 * a)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }
}
