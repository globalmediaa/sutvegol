import 'package:flutter/material.dart';

import '../game/led.dart';

/// Game over kartındaki LED rakamlar (koyu gri, baştaki sıfırlar açık gri).
class LedDigits extends StatelessWidget {
  const LedDigits({super.key, required this.value, this.height = 32, this.width = 160});
  final int value;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(width, height),
        painter: _LedPainter(value),
      );
}

class _LedPainter extends CustomPainter {
  _LedPainter(this.value);
  final int value;

  @override
  void paint(Canvas canvas, Size size) {
    drawSevenSegmentRow(
      canvas,
      Offset.zero & size,
      value,
      const Color(0xFF3C3C3C),
      off: const Color(0x00000000),
      leadingColor: const Color(0xFFBDBDBD),
    );
  }

  @override
  bool shouldRepaint(_LedPainter old) => old.value != value;
}
