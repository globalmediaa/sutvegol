import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextStyle, FontWeight;

import '../ui/logo.dart';
import 'sut_ve_gol_game.dart';
import 'geometry.dart';

double _easeOut(double t) => 1 - pow(1 - t, 3).toDouble();

/// KRAL MODU: altın-turuncu parıltı, bokeh, kıvılcımlar ve taçlı "KRAL MODU" levhası.
class FeverOverlay extends PositionComponent
    with HasGameReference<SutVeGolGame> {
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
      _bokeh.add(
        _Bokeh(
          Vector2(rng.nextDouble() * kWorldW, 900 + rng.nextDouble() * 1900),
          90 + rng.nextDouble() * 160,
          0.4 + rng.nextDouble() * 0.8,
          rng.nextDouble() * pi * 2,
        ),
      );
    }
    for (var i = 0; i < 22; i++) {
      _sparks.add(
        _Spark(
          Vector2(rng.nextDouble() * kWorldW, 700 + rng.nextDouble() * 2100),
          rng.nextDouble() * pi * 2,
          0.8 + rng.nextDouble() * 1.6,
          10 + rng.nextDouble() * 16,
        ),
      );
    }
  }

  @override
  void update(double dt) {
    _t += dt;
    final target = game.fever ? 1.0 : 0.0;
    final speed = game.fever ? dt / 0.5 : dt / 0.7;
    _alpha = target > _alpha
        ? min(target, _alpha + speed)
        : max(target, _alpha - speed);
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
    // Alt-orta merkezli altın parıltı.
    canvas.drawRect(
      size.toRect(),
      Paint()
        ..shader = Gradient.radial(
          const Offset(kWorldW / 2, kWorldH * 0.78),
          kWorldH * 0.8,
          [
            Color.fromRGBO(255, 190, 60, 0.22 * a),
            Color.fromRGBO(255, 140, 40, 0.10 * a),
            Color.fromRGBO(255, 120, 26, 0.0),
          ],
          const [0.0, 0.45, 1.0],
        ),
    );
    // Kenar vinyeti.
    canvas.drawRect(
      size.toRect(),
      Paint()
        ..shader = Gradient.linear(
          const Offset(0, 0),
          const Offset(0, kWorldH),
          [
            Color.fromRGBO(255, 160, 40, 0.24 * a),
            Color.fromRGBO(255, 200, 100, 0.0),
            Color.fromRGBO(255, 150, 40, 0.24 * a),
          ],
          const [0.0, 0.35, 1.0],
        ),
    );
    for (final b in _bokeh) {
      canvas.drawCircle(
        b.pos.toOffset(),
        b.r,
        Paint()
          ..color = Color.fromRGBO(255, 205, 90, 0.10 * a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
      );
    }
    final sp = Paint()..color = Color.fromRGBO(255, 245, 210, 0.9 * a);
    for (final s in _sparks) {
      final tw = (sin(_t * 3 * s.speed + s.phase) + 1) / 2;
      if (tw < 0.35) continue;
      _star(canvas, s.pos.toOffset(), s.size * tw, sp);
    }
    // Levha: tabelanın üstünde.
    final g = game.view;
    final cx = g.boardRect.center.dx;
    final cy = g.boardRect.top - 150;
    final pulse = 1 + 0.03 * sin(_t * 6);
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(pulse * (0.7 + 0.3 * a));
    _drawPlaque(canvas, a);
    canvas.restore();
  }

  static void _star(Canvas canvas, Offset p, double r, Paint paint) {
    final path = Path()
      ..moveTo(p.dx, p.dy - r)
      ..quadraticBezierTo(p.dx, p.dy, p.dx + r, p.dy)
      ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + r)
      ..quadraticBezierTo(p.dx, p.dy, p.dx - r, p.dy)
      ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - r)
      ..close();
    canvas.drawPath(path, paint);
  }

  /// Lacivert plaka, altın çerçeve, üstte taç, "KRAL MODU" altın yazı.
  void _drawPlaque(Canvas canvas, double a) {
    final rect = Rect.fromCenter(
      center: const Offset(0, 10),
      width: 560,
      height: 150,
    );
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(28));
    canvas.drawRRect(
      rr.inflate(14),
      Paint()
        ..color = Color.fromRGBO(255, 190, 60, 0.45 * a)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = Gradient.linear(rect.topLeft, rect.bottomLeft, [
          Color.fromRGBO(30, 44, 99, a),
          Color.fromRGBO(11, 18, 38, a),
        ]),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..color = Color.fromRGBO(255, 197, 61, a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );
    // Ampuller: çerçeve boyunca sırayla parlar.
    final phase = (_t * 6).floor();
    var i = 0;
    for (var x = rect.left + 24; x < rect.right; x += 44) {
      for (final y in [rect.top, rect.bottom]) {
        final on = (i + phase) % 2 == 0;
        canvas.drawCircle(
          Offset(x, y),
          7,
          Paint()
            ..color = Color.fromRGBO(255, on ? 245 : 190, on ? 160 : 60, a),
        );
        if (on) {
          canvas.drawCircle(
            Offset(x, y),
            12,
            Paint()
              ..color = Color.fromRGBO(255, 220, 120, 0.5 * a)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
          );
        }
        i++;
      }
    }
    canvas.save();
    canvas.translate(0, rect.top - 30);
    paintCrown(canvas, 120, alpha: a);
    canvas.restore();

    const text = 'KRAL MODU';
    const size = 92.0;
    for (var d = 6; d >= 1; d--) {
      TextPaint(
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w700,
          fontFamily: 'TitilliumWeb',
          color: Color.fromRGBO(120, 70, 0, a),
          letterSpacing: 4,
        ),
      ).render(
        canvas,
        text,
        Vector2(0, 14 + d.toDouble()),
        anchor: Anchor.center,
      );
    }
    TextPaint(
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w700,
        fontFamily: 'TitilliumWeb',
        letterSpacing: 4,
        foreground: Paint()
          ..shader = Gradient.linear(
            const Offset(0, -40),
            const Offset(0, 50),
            [
              Color.fromRGBO(255, 240, 150, a),
              Color.fromRGBO(255, 196, 40, a),
              Color.fromRGBO(240, 150, 20, a),
            ],
            const [0, 0.55, 1],
          ),
      ),
    ).render(canvas, text, Vector2(0, 14), anchor: Anchor.center);
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

/// Kral Modu bitişi: ekranı kaplayan büyüyen ışık halkası.
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
        ..color = Color.fromRGBO(255, 220, 140, 0.55 * (1 - k))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 60 * (1 - k) + 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(
      Offset.zero,
      r * 0.9,
      Paint()..color = Color.fromRGBO(255, 230, 170, 0.18 * (1 - k)),
    );
  }
}

/// Sahne geçiş afişi: "YENİ SAHNE" + sahne adı, ortadan büyüyüp söner.
class StageBanner extends PositionComponent {
  StageBanner(this.stage)
    : super(position: Vector2(kWorldW / 2, kWorldH * 0.42), priority: 28);
  final Stage stage;
  double _t = 0;
  static const double dur = 2.0;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= dur) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final k = (_t / dur).clamp(0.0, 1.0);
    final inK = _easeOut((k / 0.18).clamp(0.0, 1.0));
    final outK = k > 0.8 ? (k - 0.8) / 0.2 : 0.0;
    final a = inK * (1 - outK);
    canvas.save();
    canvas.scale(0.7 + 0.3 * inK);
    final rect = Rect.fromCenter(center: Offset.zero, width: 760, height: 220);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(32));
    canvas.drawRRect(
      rr.inflate(12),
      Paint()
        ..color = stage.accent.withValues(alpha: 0.45 * a)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
    canvas.drawRRect(rr, Paint()..color = Color.fromRGBO(11, 18, 38, 0.92 * a));
    canvas.drawRRect(
      rr,
      Paint()
        ..color = stage.accent.withValues(alpha: a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    TextPaint(
      style: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w600,
        fontFamily: 'TitilliumWeb',
        color: Color.fromRGBO(154, 166, 200, a),
        letterSpacing: 10,
      ),
    ).render(canvas, 'YENİ SAHNE', Vector2(0, -52), anchor: Anchor.center);
    TextPaint(
      style: TextStyle(
        fontSize: 104,
        fontWeight: FontWeight.w700,
        fontFamily: 'TitilliumWeb',
        color: stage.accent.withValues(alpha: a),
        letterSpacing: 6,
      ),
    ).render(canvas, stage.label, Vector2(0, 24), anchor: Anchor.center);
    canvas.restore();
  }
}
