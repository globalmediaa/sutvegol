import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

ui.Image? _brandIcon;

Future<void> loadBrandIdentity() async {
  final data = await rootBundle.load(
    'assets/branding/sut-ve-gol-icon-master.png',
  );
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  _brandIcon = (await codec.getNextFrame()).image;
}

/// Uygulama ikonunu kırpmadan, verilen kare alana birebir çizer.
void paintBrandIcon(
  ui.Canvas canvas,
  ui.Rect box, {
  double alpha = 1,
  double reveal = 1,
}) {
  final icon = _brandIcon;
  if (icon == null) return;
  final k = reveal.clamp(0.0, 1.0);
  canvas.saveLayer(
    box,
    Paint()..color = Color.fromRGBO(255, 255, 255, alpha * k),
  );
  canvas.translate(0, (1 - k) * 20);
  canvas.drawImageRect(
    icon,
    ui.Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble()),
    box,
    Paint()..filterQuality = FilterQuality.high,
  );
  canvas.restore();
}

/// Uygulama ikonu ile aynı S biçimli şut yolu, top ve kale amblemi.
void paintLogo(
  ui.Canvas canvas,
  ui.Rect box, {
  double alpha = 1,
  double reveal = 1,
  bool subtitle = true,
}) {
  final w = box.width;
  final h = min(box.height, w / 2.05);
  final r = ui.Rect.fromCenter(center: box.center, width: w, height: h);
  final k = reveal.clamp(0.0, 1.0);
  canvas.saveLayer(
    box,
    Paint()..color = Color.fromRGBO(255, 255, 255, alpha * k),
  );
  canvas.translate(r.left, r.top + (1 - k) * 20);
  if (_brandIcon case final icon?) {
    final size = h * .86;
    canvas.drawImageRect(
      icon,
      ui.Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble()),
      ui.Rect.fromLTWH(w * .015, h * .03, size, size),
      Paint()..filterQuality = FilterQuality.high,
    );
  }
  final line1 = _text('ŞUT VE', w * .145, FontWeight.w700, spacing: 0);
  final line2 = _text('GOL', w * .195, FontWeight.w700, spacing: w * .009);
  line1.paint(canvas, Offset(w * .68, h * .32), const Color(0xFFF5F7FF));
  line2.paint(canvas, Offset(w * .68, h * .67), const Color(0xFFFF6B18));
  if (subtitle) {
    _text(
      'HER ŞUT BİR ŞANS.',
      w * .032,
      FontWeight.w600,
      spacing: w * .004,
    ).paint(canvas, Offset(w * .5, h * .97), const Color(0xFFB9C3DE));
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
        [
          const Color(0xFFFFE58A).withValues(alpha: alpha),
          const Color(0xFFFFB13B).withValues(alpha: alpha),
          const Color(0xFFE08A12).withValues(alpha: alpha),
        ],
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
    RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(-52 * s, 18 * s, 104 * s, 16 * s),
      ui.Radius.circular(4 * s),
    ),
    Paint()..color = const Color(0xFFC77A0E).withValues(alpha: alpha),
  );
  // Mücevherler.
  for (final e in [
    (-30.0, 25.0, 0xFFFF3B5C),
    (0.0, 25.0, 0xFF35D5F2),
    (30.0, 25.0, 0xFF2ED47A),
  ]) {
    canvas.drawCircle(
      ui.Offset(e.$1 * s, e.$2 * s),
      5 * s,
      Paint()..color = Color(e.$3).withValues(alpha: alpha),
    );
  }
  for (final x in [-58.0, 0.0, 58.0]) {
    final y = x == 0 ? -40.0 : -22.0;
    canvas.drawCircle(
      ui.Offset(x * s, y * s),
      5.5 * s,
      Paint()..color = const Color(0xFFFFF4C2).withValues(alpha: alpha),
    );
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

_Txt _text(String s, double size, FontWeight w, {double spacing = 2}) =>
    _Txt(s, size, w, spacing);
