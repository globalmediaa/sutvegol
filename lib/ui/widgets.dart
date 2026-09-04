import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'logo.dart';
import 'theme.dart';

/// Perde arka planı: bulanık + lacivert karartma.
class DimBackdrop extends StatelessWidget {
  const DimBackdrop({super.key, this.alpha = 0.72});
  final double alpha;

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
          child: ColoredBox(color: FK.navy.withValues(alpha: alpha)),
        ),
      );
}

/// Lacivert cam kart.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.radius = 24, this.padding = EdgeInsets.zero, this.border, this.gradient});
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final Color? border;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: gradient ?? FK.surface,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: border ?? FK.glassBorder, width: 1.2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 30, offset: const Offset(0, 14))],
        ),
        child: child,
      );
}

/// Turuncu hap buton (birincil) ya da cam hap (ikincil).
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.label, required this.onTap, this.icon, this.primary = true, this.height = 56, this.width, this.fontSize = 18});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool primary;
  final double height;
  final double? width;
  final double fontSize;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: height,
          width: width,
          padding: EdgeInsets.symmetric(horizontal: height * 0.5),
          decoration: BoxDecoration(
            gradient: primary ? FK.fire : null,
            color: primary ? null : FK.glass,
            borderRadius: BorderRadius.circular(height / 2),
            border: primary ? null : Border.all(color: FK.glassBorder, width: 1.2),
            boxShadow: primary ? FK.glow(height * 0.4) : null,
          ),
          child: Row(
            mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, color: Colors.white, size: fontSize * 1.35), SizedBox(width: fontSize * 0.5)],
              Text(label, style: FK.t(size: fontSize, w: FontWeight.w700, spacing: 1.2)),
            ],
          ),
        ),
      );
}

/// Yuvarlak ikon butonu (cam ya da renkli).
class RoundButton extends StatelessWidget {
  const RoundButton({super.key, required this.icon, required this.onTap, this.size = 52, this.color, this.iconColor = Colors.white, this.gradient});
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color? color;
  final Color iconColor;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: gradient,
            color: gradient == null ? (color ?? FK.glass) : null,
            border: gradient == null && color == null ? Border.all(color: FK.glassBorder, width: 1.2) : null,
            boxShadow: gradient != null ? FK.glow(size * 0.35) : [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Icon(icon, color: iconColor, size: size * 0.5),
        ),
      );
}

/// İsimden üretilen avatar: gradyan daire + baş harfler. Fotoğraf yok.
class AvatarCircle extends StatelessWidget {
  const AvatarCircle(this.name, {super.key, this.size = 52, this.ring, this.ringWidth = 2.5});
  final String name;
  final double size;
  final Color? ring;
  final double ringWidth;

  static const _palettes = [
    [Color(0xFFFF7A1A), Color(0xFFFFB13B)],
    [Color(0xFF35D5F2), Color(0xFF2563EB)],
    [Color(0xFF2ED47A), Color(0xFF0E9F6E)],
    [Color(0xFFB36BFF), Color(0xFF6B3FD9)],
    [Color(0xFFFF3B5C), Color(0xFFB4173A)],
    [Color(0xFFFFC53D), Color(0xFFE08A12)],
    [Color(0xFF4CC2FF), Color(0xFF1E5FBF)],
    [Color(0xFFFF8FB1), Color(0xFFD9457A)],
  ];

  static String initials(String n) {
    final parts = n.trim().split(RegExp(r'[\s_\-.]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final p = parts.first;
      return p.length >= 2 ? p.substring(0, 2).toUpperCase() : p.toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  static List<Color> colorsFor(String n) => _palettes[n.hashCode.abs() % _palettes.length];

  @override
  Widget build(BuildContext context) {
    final cols = colorsFor(name);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ringWidth),
      decoration: BoxDecoration(shape: BoxShape.circle, color: ring ?? Colors.white.withValues(alpha: 0.85)),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: cols),
        ),
        alignment: Alignment.center,
        child: Text(initials(name), style: FK.t(size: size * 0.36, w: FontWeight.w700, spacing: 0.5)),
      ),
    );
  }
}

/// Logo widget'ı (paintLogo sarmalayıcısı).
class LogoWidget extends StatelessWidget {
  const LogoWidget({super.key, required this.width, this.subtitle = true});
  final double width;
  final bool subtitle;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(width, width / 2.05), painter: _LogoPainter(subtitle));
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.subtitle);
  final bool subtitle;
  @override
  void paint(Canvas canvas, Size size) => paintLogo(canvas, Offset.zero & size, subtitle: subtitle);
  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.subtitle != subtitle;
}

/// Küçük etiket (#sıra, seviye vb.).
class Chip2 extends StatelessWidget {
  const Chip2(this.text, {super.key, this.color = FK.orange, this.icon, this.fontSize = 12});
  final String text;
  final Color color;
  final IconData? icon;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: fontSize * 0.8, vertical: fontSize * 0.25),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(fontSize)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: fontSize * 1.1, color: Colors.white), SizedBox(width: fontSize * 0.3)],
            Text(text, style: FK.t(size: fontSize, w: FontWeight.w700)),
          ],
        ),
      );
}

/// Açma/kapama satırı (ses, titreşim).
class ToggleRow extends StatelessWidget {
  const ToggleRow({super.key, required this.icon, required this.label, required this.value, required this.onChanged, this.scale = 1});
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8 * s),
        child: Row(
          children: [
            Container(
              width: 40 * s,
              height: 40 * s,
              decoration: BoxDecoration(color: FK.glass, borderRadius: BorderRadius.circular(12 * s)),
              child: Icon(icon, color: value ? FK.amber : FK.muted, size: 22 * s),
            ),
            SizedBox(width: 12 * s),
            Expanded(child: Text(label, style: FK.t(size: 16 * s, w: FontWeight.w600))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 52 * s,
              height: 30 * s,
              padding: EdgeInsets.all(3 * s),
              decoration: BoxDecoration(
                gradient: value ? FK.fire : null,
                color: value ? null : const Color(0xFF2A3560),
                borderRadius: BorderRadius.circular(15 * s),
              ),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(width: 24 * s, height: 24 * s, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
