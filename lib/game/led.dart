import 'dart:ui';

/// 7-segment LED rakam çizimi — hem Flame tabelası hem Flutter kartı kullanır.
/// a b c d e f g -> bit 6..0
const List<int> kSevenSegDigits = [
  0x7E, 0x30, 0x6D, 0x79, 0x33, 0x5B, 0x5F, 0x70, 0x7F, 0x7B,
];

/// [rect] içine 6 haneli değeri çizer. [leadingColor] verilirse baştaki sıfırlar
/// o renkle çizilir (game over kartındaki açık gri sıfırlar gibi).
void drawSevenSegmentRow(
  Canvas canvas,
  Rect rect,
  int value,
  Color on, {
  Color? off,
  Color? leadingColor,
  int digits = 6,
}) {
  final text = value.clamp(0, 999999).toString().padLeft(digits, '0');
  final firstSig = text.indexOf(RegExp('[1-9]'));
  final cellW = rect.width / digits;
  final dw = cellW * 0.74;
  final h = rect.height;
  canvas.save();
  canvas.translate(rect.left, rect.top);
  for (var i = 0; i < digits; i++) {
    final x = i * cellW + (cellW - dw) / 2;
    final isLeading = firstSig == -1 || i < firstSig;
    final color = (isLeading && leadingColor != null) ? leadingColor : on;
    canvas.save();
    canvas.translate(x, 0);
    drawSevenSegmentDigit(canvas, int.parse(text[i]), dw, h, color, off);
    canvas.restore();
  }
  canvas.restore();
}

void drawSevenSegmentDigit(Canvas canvas, int d, double dw, double h, Color color, Color? off) {
  final t = h * 0.17;
  final onPaint = Paint()..color = color;
  final offPaint = Paint()..color = off ?? color.withAlpha(0x16);
  final r = Radius.circular(t * 0.3);
  final segs = <Rect>[
    Rect.fromLTWH(t * 0.55, 0, dw - 1.1 * t, t), // a
    Rect.fromLTWH(dw - t, t * 0.55, t, h / 2 - t * 0.8), // b
    Rect.fromLTWH(dw - t, h / 2 + t * 0.25, t, h / 2 - t * 0.8), // c
    Rect.fromLTWH(t * 0.55, h - t, dw - 1.1 * t, t), // d
    Rect.fromLTWH(0, h / 2 + t * 0.25, t, h / 2 - t * 0.8), // e
    Rect.fromLTWH(0, t * 0.55, t, h / 2 - t * 0.8), // f
    Rect.fromLTWH(t * 0.55, h / 2 - t / 2, dw - 1.1 * t, t), // g
  ];
  final bits = kSevenSegDigits[d];
  for (var i = 0; i < 7; i++) {
    final lit = (bits >> (6 - i)) & 1 == 1;
    if (!lit && off == null && color.a == 0) continue;
    canvas.drawRRect(RRect.fromRectAndRadius(segs[i].deflate(1.2), r), lit ? onPaint : offPaint);
  }
}
