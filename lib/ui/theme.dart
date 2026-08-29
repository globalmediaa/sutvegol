import 'package:flutter/material.dart';

/// Videodan örneklenen renkler.
class KL {
  static const red = Color(0xFFFE0000);
  static const tabBlack = Color(0xFF050505);
  static const bodyTop = Color(0xFF2F99DB);
  static const bodyBottom = Color(0xFF102677);
  static const row = Color(0x66FFFFFF);
  static const youRow = Color(0x99FFFFFF);
  static const dim = Color(0xFF062438);
  static const cardGray = Color(0xFFEBEBEB);
  static const orange = Color(0xFFFFA726);
  static const pitchDark = Color(0xFF487519);
  static const pitchLight = Color(0xFF65A024);
  static const pill = Color(0xFF224D04);

  static const font = 'TitilliumWeb';

  static TextStyle t({
    double size = 16,
    FontWeight w = FontWeight.w400,
    Color color = Colors.white,
    double? spacing,
  }) =>
      TextStyle(fontFamily: font, fontSize: size, fontWeight: w, color: color, letterSpacing: spacing, height: 1.1);
}
