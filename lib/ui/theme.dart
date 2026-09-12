import 'package:flutter/material.dart';

/// Şut ve Gol görsel kimliği: gece laciverti zemin, ateş turuncusu vurgu.
class FK {
  FK._();

  static const navy = Color(0xFF0B1226);
  static const navy2 = Color(0xFF141F45);
  static const navy3 = Color(0xFF1E2C63);
  static const orange = Color(0xFFFF7A1A);
  static const amber = Color(0xFFFFB13B);
  static const gold = Color(0xFFFFC53D);
  static const cyan = Color(0xFF35D5F2);
  static const green = Color(0xFF2ED47A);
  static const red = Color(0xFFFF3B5C);
  static const text = Color(0xFFF5F7FF);
  static const muted = Color(0xFF9AA6C8);
  static const glass = Color(0x16FFFFFF);
  static const glassBorder = Color(0x2EFFFFFF);
  static const silver = Color(0xFFC9D1E3);
  static const bronze = Color(0xFFD08A4E);

  static const fire = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [orange, amber],
  );

  static const surface = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1A2756), Color(0xFF0F1838)],
  );

  static const font = 'TitilliumWeb';

  static TextStyle t({
    double size = 16,
    FontWeight w = FontWeight.w400,
    Color color = text,
    double? spacing,
    double height = 1.1,
  }) => TextStyle(
    fontFamily: font,
    fontSize: size,
    fontWeight: w,
    color: color,
    letterSpacing: spacing,
    height: height,
  );

  /// Turuncu buton/parıltı gölgesi.
  static List<BoxShadow> glow(
    double blur, {
    Color color = orange,
    double alpha = 0.45,
    double dy = 6,
  }) => [
    BoxShadow(
      color: color.withValues(alpha: alpha),
      blurRadius: blur,
      offset: Offset(0, dy),
    ),
  ];
}
