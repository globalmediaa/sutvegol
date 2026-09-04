import 'package:flutter/material.dart';

import '../game/led.dart';
import 'theme.dart';

/// Kartlardaki LED rakamlar: turuncu parıltılı, baştaki sıfırlar soluk.
class LedDigits extends StatelessWidget {
  const LedDigits({super.key, required this.value, this.height = 32, this.width = 160, this.color = FK.amber});
  final int value;
  final double height;
  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(width, height),
        painter: _LedPainter(value, color),
      );
}

class _LedPainter extends CustomPainter {
  _LedPainter(this.value, this.color);
  final int value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Parıltı katmanı.
    canvas.saveLayer(Offset.zero & size, Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    drawSevenSegmentRow(canvas, Offset.zero & size, value, color.withValues(alpha: 0.55), off: const Color(0x00000000), leadingColor: const Color(0x00000000));
    canvas.restore();
    drawSevenSegmentRow(
      canvas,
      Offset.zero & size,
      value,
      color,
      off: const Color(0x00000000),
      leadingColor: Colors.white.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(_LedPainter old) => old.value != value || old.color != color;
}
