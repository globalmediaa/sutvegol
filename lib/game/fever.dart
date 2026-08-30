import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextStyle, FontWeight;

import 'geometry.dart';
import 'kick_legend_game.dart';

/// FEVER modu: sarı-yeşil parıltı, bokeh, yıldızlar ve "FEVER" yazısı.
class FeverOverlay extends PositionComponent with HasGameReference<KickLegendGame> {
  FeverOverlay() : super(size: Vector2(kWorldW, kWorldH), priority: 26);

  double _alpha = 0; // 0..1 görünürlük
  double _t = 0;
  final List<_Bokeh> _bokeh = [];
  final List<_Spark> _sparks = [];

  bool get visible => _alpha > 0.001;

  @override
  Future<void> onLoad() async {
    final rng = Random(7);
    for (var i = 0; i < 9; i++) {
      _bokeh.add(_Bokeh(
        Vector2(rng.nextDouble() * kWorldW, 900 + rng.nextDouble() * 1900),
        90 + rng.nextDouble() * 160,
        0.4 + rng.nextDouble() * 0.8,
        rng.nextDouble() * pi * 2,
      ));
    }
    for (var i = 0; i < 22; i++) {
      _sparks.add(_Spark(
        Vector2(rng.nextDouble() * kWorldW, 700 + rng.nextDouble() * 2100),
        rng.nextDouble() * pi * 2,
        0.8 + rng.nextDouble() * 1.6,
        10 + rng.nextDouble() * 16,
      ));
    }
  }

  @override
  void update(double dt) {
    _t += dt;
    final target = game.fever ? 1.0 : 0.0;
    final speed = game.fever ? dt / 0.5 : dt / 0.7;
    _alpha = target > _alpha ? min(target, _alpha + speed) : max(target, _alpha - speed);
    for (final b in _bokeh) {
      b.pos.y -= 18 * b.speed * dt;
      b.pos.x += sin(_t * 0.7 + b.phase) * 10 * dt;
      if (b.pos.y < 600) b.pos.y = kWorldH + 100;
    }
  }

  @override
  void render(Canvas canvas) {
    if (!visible) return;
    final a = _alpha;
    // Alt-orta merkezli sarı-yeşil parıltı.
    canvas.drawRect(
      size.toRect(),
      Paint()
        ..shader = Gradient.radial(
          const Offset(kWorldW / 2, kWorldH * 0.78),
          kWorldH * 0.8,
          [
            Color.fromRGBO(240, 255, 120, 0.20 * a),
            Color.fromRGBO(220, 250, 90, 0.10 * a),
            Color.fromRGBO(255, 240, 120, 0.0),
          ],
          const [0.0, 0.45, 1.0],
        ),
    );
    // Kenar vinyeti (üst köşeler sarımsı).
    canvas.drawRect(
      size.toRect(),
      Paint()
        ..shader = Gradient.linear(
          const Offset(0, 0),
          const Offset(0, kWorldH),
          [Color.fromRGBO(255, 240, 130, 0.22 * a), Color.fromRGBO(255, 245, 150, 0.0), Color.fromRGBO(230, 255, 120, 0.22 * a)],
          const [0.0, 0.35, 1.0],
        ),
    );
    // Bokeh.
    for (final b in _bokeh) {
      canvas.drawCircle(
        b.pos.toOffset(),
        b.r,
        Paint()
          ..color = Color.fromRGBO(235, 255, 140, 0.09 * a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
      );
    }
    // Yıldız pırıltıları.
    final sp = Paint()..color = Color.fromRGBO(255, 255, 230, 0.9 * a);
    for (final s in _sparks) {
      final tw = (sin(_t * 3 * s.speed + s.phase) + 1) / 2;
      if (tw < 0.35) continue;
      final r = s.size * tw;
      final p = s.pos.toOffset();
      final path = Path()
        ..moveTo(p.dx, p.dy - r)
        ..quadraticBezierTo(p.dx, p.dy, p.dx + r, p.dy)
        ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + r)
        ..quadraticBezierTo(p.dx, p.dy, p.dx - r, p.dy)
        ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - r)
        ..close();
      canvas.drawPath(path, sp);
    }
    // FEVER tabelası (skor tabelasının üstü): ampullü altın levha + 3D yazı.
    final g = game.view;
    final cx = g == kWide ? 650.0 : 468.0;
    final cy = g == kWide ? 690.0 : 520.0;
    final pulse = 1 + 0.03 * sin(_t * 6);
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(pulse * (0.7 + 0.3 * a));
    _drawSign(canvas, a);
    _drawFeverText(canvas, a);
    canvas.restore();
  }

  /// Beş köşeli levha (üstü sivri), açık bej dolgu, altın kenar, ampuller.
  void _drawSign(Canvas canvas, double a) {
    final board = Path()
      ..moveTo(-230, -20)
      ..lineTo(0, -120)
      ..lineTo(230, -20)
      ..lineTo(230, 60)
      ..lineTo(-230, 60)
      ..close();
    canvas.drawPath(
      board,
      Paint()
        ..shader = Gradient.linear(
          const Offset(0, -120),
          const Offset(0, 60),
          [Color.fromRGBO(255, 244, 205, a), Color.fromRGBO(245, 210, 120, a)],
        ),
    );
    canvas.drawPath(
      board,
      Paint()
        ..color = Color.fromRGBO(232, 168, 30, a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeJoin = StrokeJoin.round,
    );
    // Ampuller: kenar boyunca, sırayla parlar.
    final pts = <Offset>[];
    void edge(Offset p0, Offset p1, int n) {
      for (var i = 0; i < n; i++) {
        final t = i / n;
        pts.add(Offset(p0.dx + (p1.dx - p0.dx) * t, p0.dy + (p1.dy - p0.dy) * t));
      }
    }
    edge(const Offset(-230, -20), const Offset(0, -120), 6);
    edge(const Offset(0, -120), const Offset(230, -20), 6);
    edge(const Offset(230, -20), const Offset(230, 60), 2);
    edge(const Offset(230, 60), const Offset(-230, 60), 10);
    edge(const Offset(-230, 60), const Offset(-230, -20), 2);
    final phase = (_t * 6).floor();
    for (var i = 0; i < pts.length; i++) {
      final on = (i + phase) % 2 == 0;
      canvas.drawCircle(pts[i], 9, Paint()..color = Color.fromRGBO(255, on ? 250 : 200, on ? 160 : 60, a));
      if (on) {
        canvas.drawCircle(
          pts[i],
          14,
          Paint()
            ..color = Color.fromRGBO(255, 240, 120, 0.5 * a)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
    }
    // Levha üstü pırıltılar.
    final sp = Paint()..color = Color.fromRGBO(255, 255, 240, 0.9 * a);
    for (var i = 0; i < 5; i++) {
      final tw = (sin(_t * 4 + i * 1.3) + 1) / 2;
      if (tw < 0.5) continue;
      final p = Offset(-170 + i * 85.0, -40 + (i.isEven ? 20 : -10));
      final r = 6 + 8 * tw;
      canvas.drawPath(
        Path()
          ..moveTo(p.dx, p.dy - r)
          ..quadraticBezierTo(p.dx, p.dy, p.dx + r, p.dy)
          ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + r)
          ..quadraticBezierTo(p.dx, p.dy, p.dx - r, p.dy)
          ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - r)
          ..close(),
        sp,
      );
    }
  }

  void _drawFeverText(Canvas canvas, double a) {
    const text = 'FEVER';
    const size = 124.0;
    // 3D derinlik: koyu kahve katmanlar.
    for (var i = 8; i >= 1; i--) {
      TextPaint(
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w900,
          fontFamily: 'TitilliumWeb',
          color: Color.fromRGBO(120, 70, 0, a),
          letterSpacing: 3,
        ),
      ).render(canvas, text, Vector2(0, 8 + i.toDouble()), anchor: Anchor.center);
    }
    // Koyu kontur.
    for (final o in const [Offset(-3, 0), Offset(3, 0), Offset(0, -3), Offset(0, 3)]) {
      TextPaint(
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w900,
          fontFamily: 'TitilliumWeb',
          color: Color.fromRGBO(140, 80, 0, a),
          letterSpacing: 3,
        ),
      ).render(canvas, text, Vector2(o.dx, 8 + o.dy), anchor: Anchor.center);
    }
    // Altın dolgu.
    final tp = TextPaint(
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w900,
        fontFamily: 'TitilliumWeb',
        letterSpacing: 3,
        foreground: Paint()
          ..shader = Gradient.linear(
            const Offset(0, -50),
            const Offset(0, 50),
            [Color.fromRGBO(255, 240, 150, a), Color.fromRGBO(255, 196, 40, a), Color.fromRGBO(240, 150, 20, a)],
            const [0, 0.55, 1],
          ),
      ),
    );
    tp.render(canvas, text, Vector2(0, 8), anchor: Anchor.center);
  }
}

class _Bokeh {
  _Bokeh(this.pos, this.r, this.speed, this.phase);
  Vector2 pos;
  double r, speed, phase;
}

class _Spark {
  _Spark(this.pos, this.phase, this.speed, this.size);
  Vector2 pos;
  double phase, speed, size;
}

/// Fever bitişi: ekranı kaplayan büyüyen ışık halkası.
class FeverBurst extends PositionComponent {
  FeverBurst(Vector2 pos) : super(position: pos, priority: 27);
  double _t = 0;
  static const double dur = 0.9;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= dur) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final k = (_t / dur).clamp(0.0, 1.0);
    final r = 100 + 2200 * (1 - pow(1 - k, 2).toDouble());
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..color = Color.fromRGBO(255, 255, 200, 0.55 * (1 - k))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 60 * (1 - k) + 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(
      Offset.zero,
      r * 0.9,
      Paint()..color = Color.fromRGBO(255, 255, 220, 0.18 * (1 - k)),
    );
  }
}
