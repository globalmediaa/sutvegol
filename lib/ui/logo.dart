import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../game/scene_art.dart';

/// "ŞUT VE GOL" logosu — taç, iki satırlık eğik 3D yazı ve alev izli top.
/// Hem Flame (splash) hem Flutter (leaderboard, loading) aynı çizimi kullanır.
/// [box] logonun sığacağı alan; oran ~2.05:1 olarak çizilir ve ortalanır.
void paintLogo(ui.Canvas canvas, ui.Rect box, {double alpha = 1, double reveal = 1, bool subtitle = true}) {
  final w = box.width;
  final h = min(box.height, w / 2.05);
  final r = ui.Rect.fromCenter(center: box.center, width: w, height: h);
  final u = w / 1000; // ölçek birimi
  canvas.save();
  canvas.translate(r.left, r.top);

  // Satır 1: ŞUT VE (turuncu-amber), satır 2: GOL (beyaz) + taç.
  final line1 = _text('ŞUT VE', 250 * u, FontWeight.w700);
  final line2 = _text('GOL', 250 * u, FontWeight.w700);
  final cx = w / 2;
  final y1 = h * 0.30;
  final y2 = h * 0.72;

  // Alev izi (arka planda, sağdan sola).
  final trail = Path()
    ..moveTo(w * 0.98, y1 + 20 * u)
    ..cubicTo(w * 0.80, y1 - 120 * u, w * 0.30, y2 + 40 * u, w * 0.02, y2 - 40 * u);
  canvas.drawPath(
    trail,
    Paint()
      ..color = const Color(0xFFFF7A1A).withValues(alpha: 0.35 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 34 * u
      ..strokeCap = StrokeCap.round
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 18 * u),
  );

  void drawLine(_Txt t, double y, List<Color> fill, double skewK) {
    final k = skewK.clamp(0.0, 1.0);
    if (k <= 0) return;
    canvas.save();
    canvas.translate(cx, y);
    canvas.scale(0.6 + 0.4 * k, 0.6 + 0.4 * k);
    canvas.skew(-0.18, 0);
    // 3D derinlik.
    for (var i = 7; i >= 1; i--) {
      t.paint(canvas, ui.Offset(i * 1.6 * u, i * 1.8 * u), const Color(0xFF0B1226).withValues(alpha: alpha * k));
    }
    // Kontur.
    for (final o in [ui.Offset(-3 * u, 0), ui.Offset(3 * u, 0), ui.Offset(0, -3 * u), ui.Offset(0, 3 * u)]) {
      t.paint(canvas, o, const Color(0xFF141F45).withValues(alpha: alpha * k));
    }
    t.paintGradient(canvas, ui.Offset.zero, fill.map((c) => c.withValues(alpha: alpha * k)).toList());
    canvas.restore();
  }

  drawLine(line1, y1, const [Color(0xFFFFE08A), Color(0xFFFF9A2E), Color(0xFFFF6A00)], reveal * 1.6);
  drawLine(line2, y2, const [Color(0xFFFFFFFF), Color(0xFFDDE4F5), Color(0xFFB9C3DE)], reveal * 1.6 - 0.35);

  // Taç: GOL'ün sağ üstünde, hafif yatık.
  final ck = ((reveal - 0.45) * 2.2).clamp(0.0, 1.0);
  if (ck > 0) {
    canvas.save();
    canvas.translate(cx + line2.width * 0.56, y2 - line2.height * 0.50 - (1 - ck) * 60 * u);
    canvas.rotate(0.2);
    canvas.scale(ck);
    paintCrown(canvas, 135 * u, alpha: alpha);
    canvas.restore();
  }

  // Top: satır 1'in sağında, alev izinin başında.
  final bk = ((reveal - 0.25) * 2).clamp(0.0, 1.0);
  if (bk > 0) {
    canvas.save();
    canvas.translate(w * 0.94, y1 + 24 * u);
    canvas.scale(bk);
    canvas.rotate(-0.35);
    // Yumuşak gölge + gerçek top geometrisi.
    canvas.drawCircle(
      ui.Offset(4 * u, 8 * u),
      46 * u,
      Paint()
        ..color = const Color(0xFF000000).withValues(alpha: 0.35 * alpha)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 8 * u),
    );
    if (alpha < 1) canvas.saveLayer(null, Paint()..color = Color.fromRGBO(255, 255, 255, alpha));
    SceneArt.paintBall(canvas, 46 * u);
    if (alpha < 1) canvas.restore();
    canvas.restore();
  }

  if (subtitle) {
    final sub = _text('SHOOT & SCORE', 46 * u, FontWeight.w600, spacing: 10 * u);
    sub.paint(canvas, ui.Offset(cx, h * 0.96), const Color(0xFFDDE4F5).withValues(alpha: 0.85 * alpha * reveal.clamp(0, 1)));
  }
  canvas.restore();
}

/// Altın taç: üç sivri uç, alt bant, mücevherler.
void paintCrown(ui.Canvas canvas, double size, {double alpha = 1}) {
  final s = size / 100;
  final path = Path()
    ..moveTo(-50 * s, 30 * s)
    ..lineTo(-58 * s, -22 * s)
    ..lineTo(-28 * s, 2 * s)
    ..lineTo(0, -40 * s)
    ..lineTo(28 * s, 2 * s)
    ..lineTo(58 * s, -22 * s)
    ..lineTo(50 * s, 30 * s)
    ..close();
  canvas.drawPath(
    path.shift(ui.Offset(3 * s, 5 * s)),
    Paint()..color = const Color(0xFF6B3E00).withValues(alpha: 0.7 * alpha),
  );
  canvas.drawPath(
    path,
    Paint()
      ..shader = ui.Gradient.linear(
        ui.Offset(0, -40 * s),
        ui.Offset(0, 30 * s),
        [const Color(0xFFFFE58A).withValues(alpha: alpha), const Color(0xFFFFB13B).withValues(alpha: alpha), const Color(0xFFE08A12).withValues(alpha: alpha)],
        const [0, 0.55, 1],
      ),
  );
  canvas.drawPath(
    path,
    Paint()
      ..color = const Color(0xFF8A4B00).withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * s
      ..strokeJoin = StrokeJoin.round,
  );
  // Bant.
  canvas.drawRRect(
    RRect.fromRectAndRadius(ui.Rect.fromLTWH(-52 * s, 18 * s, 104 * s, 16 * s), ui.Radius.circular(4 * s)),
    Paint()..color = const Color(0xFFC77A0E).withValues(alpha: alpha),
  );
  // Mücevherler.
  for (final e in [(-30.0, 25.0, 0xFFFF3B5C), (0.0, 25.0, 0xFF35D5F2), (30.0, 25.0, 0xFF2ED47A)]) {
    canvas.drawCircle(ui.Offset(e.$1 * s, e.$2 * s), 5 * s, Paint()..color = Color(e.$3).withValues(alpha: alpha));
  }
  for (final x in [-58.0, 0.0, 58.0]) {
    final y = x == 0 ? -40.0 : -22.0;
    canvas.drawCircle(ui.Offset(x * s, y * s), 5.5 * s, Paint()..color = const Color(0xFFFFF4C2).withValues(alpha: alpha));
  }
}

class _Txt {
  _Txt(this.text, this.size, this.weight, this.spacing);
  final String text;
  final double size;
  final FontWeight weight;
  final double spacing;

  TextPainter _tp(Color color, {Paint? fg}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'TitilliumWeb',
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing,
          color: fg == null ? color : null,
          foreground: fg,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  }

  double get width => _tp(const Color(0xFFFFFFFF)).width;
  double get height => _tp(const Color(0xFFFFFFFF)).height;

  void paint(ui.Canvas canvas, ui.Offset center, Color color) {
    final tp = _tp(color);
    tp.paint(canvas, center - ui.Offset(tp.width / 2, tp.height / 2));
  }

  void paintGradient(ui.Canvas canvas, ui.Offset center, List<Color> colors) {
    final probe = _tp(const Color(0xFFFFFFFF));
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        ui.Offset(0, center.dy - probe.height / 2),
        ui.Offset(0, center.dy + probe.height / 2),
        colors,
        List.generate(colors.length, (i) => i / (colors.length - 1)),
      );
    final tp = _tp(const Color(0xFFFFFFFF), fg: paint);
    tp.paint(canvas, center - ui.Offset(tp.width / 2, tp.height / 2));
  }
}

_Txt _text(String s, double size, FontWeight w, {double spacing = 2}) => _Txt(s, size, w, spacing);
