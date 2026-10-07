import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/geometry.dart';
import '../game/scene_art.dart';
import 'logo.dart';
import 'theme.dart';

/// Perde arka planı: bulanık + lacivert karartma.
class DimBackdrop extends StatelessWidget {
  const DimBackdrop({super.key, this.alpha = 0.72});
  final double alpha;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
      child: ColoredBox(color: FK.navy.withValues(alpha: alpha)),
    ),
  );
}

/// Lacivert cam kart.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
    this.border,
    this.gradient,
  });
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
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 30,
          offset: const Offset(0, 14),
        ),
      ],
    ),
    child: child,
  );
}

/// Turuncu hap buton (birincil) ya da cam hap (ikincil).
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = true,
    this.height = 56,
    this.width,
    this.fontSize = 18,
    this.enabled = true,
  });
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool primary;
  final double height;
  final double? width;
  final double fontSize;

  /// Kapalıyken soluk görünür ve dokunmaya yanıt vermez.
  final bool enabled;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: height,
      width: width,
      padding: EdgeInsets.symmetric(horizontal: height * 0.3),
      decoration: BoxDecoration(
        gradient: primary ? FK.fire : null,
        color: primary ? null : FK.glass,
        borderRadius: BorderRadius.circular(height / 2),
        border: primary ? null : Border.all(color: FK.glassBorder, width: 1.2),
        boxShadow: primary && enabled ? FK.glow(height * 0.4) : null,
      ),
      foregroundDecoration: enabled
          ? null
          : BoxDecoration(
              color: FK.navy.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(height / 2),
            ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: fontSize * 1.35),
              SizedBox(width: fontSize * 0.5),
            ],
            Text(
              label,
              style: FK.t(size: fontSize, w: FontWeight.w700, spacing: 1.2),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Yuvarlak ikon butonu (cam ya da renkli).
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 52,
    this.color,
    this.iconColor = Colors.white,
    this.gradient,
  });
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
        border: gradient == null && color == null
            ? Border.all(color: FK.glassBorder, width: 1.2)
            : null,
        boxShadow: gradient != null
            ? FK.glow(size * 0.35)
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Icon(icon, color: iconColor, size: size * 0.5),
    ),
  );
}

/// İsimden üretilen avatar: gradyan daire + baş harfler. Fotoğraf yok.
class AvatarCircle extends StatelessWidget {
  const AvatarCircle(
    this.name, {
    super.key,
    this.size = 52,
    this.ring,
    this.ringWidth = 2.5,
  });
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
    final parts = n
        .trim()
        .split(RegExp(r'[\s_\-.]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final p = parts.first;
      return p.length >= 2 ? p.substring(0, 2).toUpperCase() : p.toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  static List<Color> colorsFor(String n) =>
      _palettes[n.hashCode.abs() % _palettes.length];

  @override
  Widget build(BuildContext context) {
    final cols = colorsFor(name);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ringWidth),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ring ?? Colors.white.withValues(alpha: 0.85),
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: cols,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          initials(name),
          style: FK.t(size: size * 0.36, w: FontWeight.w700, spacing: 0.5),
        ),
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
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, width / 2.05),
    painter: _LogoPainter(subtitle),
  );
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.subtitle);
  final bool subtitle;
  @override
  void paint(Canvas canvas, Size size) =>
      paintLogo(canvas, Offset.zero & size, subtitle: subtitle);
  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.subtitle != subtitle;
}

/// Küçük etiket (#sıra, seviye vb.).
class Chip2 extends StatelessWidget {
  const Chip2(
    this.text, {
    super.key,
    this.color = FK.orange,
    this.icon,
    this.fontSize = 12,
  });
  final String text;
  final Color color;
  final IconData? icon;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: fontSize * 0.8,
      vertical: fontSize * 0.25,
    ),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(fontSize),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: fontSize * 1.1, color: Colors.white),
          SizedBox(width: fontSize * 0.3),
        ],
        Text(
          text,
          style: FK.t(size: fontSize, w: FontWeight.w700),
        ),
      ],
    ),
  );
}

/// Açma/kapama satırı (ses, titreşim).
class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.scale = 1,
  });
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
              decoration: BoxDecoration(
                color: FK.glass,
                borderRadius: BorderRadius.circular(12 * s),
              ),
              child: Icon(
                icon,
                color: value ? FK.amber : FK.muted,
                size: 22 * s,
              ),
            ),
            SizedBox(width: 12 * s),
            Expanded(
              child: Text(
                label,
                style: FK.t(size: 16 * s, w: FontWeight.w600),
              ),
            ),
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
              child: Container(
                width: 24 * s,
                height: 24 * s,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Birincil hap butonun "işlem sürüyor" hâli (aynı boyut, dönen halka).
class BusyPill extends StatelessWidget {
  const BusyPill({super.key, this.height = 56});
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      gradient: FK.fire,
      borderRadius: BorderRadius.circular(height / 2),
    ),
    alignment: Alignment.center,
    child: SizedBox(
      width: height * 0.4,
      height: height * 0.4,
      child: const CircularProgressIndicator(
        strokeWidth: 2.5,
        color: Colors.white,
      ),
    ),
  );
}

/// Marka başlığı: logonun arkasında yumuşak turuncu parıltı.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.width = 240});
  final double width;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Container(
        width: width * 0.9,
        height: width * 0.5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: FK.orange.withValues(alpha: 0.28),
              blurRadius: width * 0.3,
              spreadRadius: width * 0.02,
            ),
          ],
        ),
      ),
      LogoWidget(width: width, subtitle: false),
    ],
  );
}

/// Beyaz "… ile devam et" butonu (Apple / Google).
class SocialButton extends StatelessWidget {
  const SocialButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.55,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 26, height: 26, child: Center(child: icon)),
              const SizedBox(width: 10),
              Text(
                label,
                style: FK.t(
                  size: 16,
                  w: FontWeight.w700,
                  color: FK.navy,
                  spacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Koddan çizilen çok renkli "G" işareti (dosya yok).
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _GooglePainter());
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final stroke = r * 0.42;
    final rect = Rect.fromCircle(center: c, radius: r - stroke / 2);
    Paint p(Color col) => Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const d = math.pi / 180;
    // Saat yönü: 0° sağ, 90° alt, 180° sol, 270° üst.
    canvas.drawArc(rect, 200 * d, 115 * d, false, p(const Color(0xFFEA4335)));
    canvas.drawArc(rect, 135 * d, 65 * d, false, p(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, 45 * d, 90 * d, false, p(const Color(0xFF34A853)));
    canvas.drawArc(rect, 0, 45 * d, false, p(const Color(0xFF4285F4)));
    canvas.drawRect(
      Rect.fromLTRB(c.dx, c.dy - stroke / 2, r * 2, c.dy + stroke / 2),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// İki (ya da daha çok) seçenekli hap anahtar; seçili dilim turuncu kayar.
class SegmentedPill extends StatelessWidget {
  const SegmentedPill({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });
  final List<String> labels;
  final int index;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: FK.navy.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(23),
      border: Border.all(color: FK.glassBorder, width: 1.2),
    ),
    child: LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth / labels.length;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              left: w * index,
              top: 0,
              bottom: 0,
              width: w,
              child: Container(
                decoration: BoxDecoration(
                  gradient: FK.fire,
                  borderRadius: BorderRadius.circular(19),
                  boxShadow: FK.glow(10, alpha: 0.35, dy: 3),
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onChanged == null ? null : () => onChanged!(i),
                      child: Center(
                        child: Text(
                          labels[i],
                          style: FK.t(
                            size: 14,
                            w: FontWeight.w700,
                            color: i == index ? Colors.white : FK.muted,
                            spacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

/// Giriş ekranı metin alanı: koyu cam zemin, yuvarlak kenar, turuncu odak.
InputDecoration gameInput({
  required String label,
  IconData? icon,
  String? helper,
  TextStyle? helperStyle,
  Widget? suffix,
}) {
  OutlineInputBorder border(Color color, [double width = 1.2]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    labelText: label,
    labelStyle: FK.t(size: 15, color: FK.muted),
    floatingLabelStyle: FK.t(size: 13, color: FK.amber),
    helperText: helper,
    helperStyle: helperStyle ?? FK.t(size: 12, color: FK.muted),
    helperMaxLines: 2,
    prefixIcon: icon == null ? null : Icon(icon, color: FK.muted, size: 22),
    suffixIcon: suffix,
    filled: true,
    fillColor: FK.navy.withValues(alpha: 0.55),
    border: border(FK.glassBorder),
    enabledBorder: border(FK.glassBorder),
    focusedBorder: border(FK.orange, 1.6),
    errorBorder: border(FK.red),
    focusedErrorBorder: border(FK.red, 1.6),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    counterText: '',
  );
}

/// Oyunun prosedürel sahnesini bulanık, karartılmış ve yavaşça nefes alan bir
/// zemin olarak çizer (giriş ekranları). Görsel sahne başına bir kez üretilir.
class GameBackdrop extends StatefulWidget {
  const GameBackdrop({super.key, this.stage = Stage.street, this.child});
  final Stage stage;
  final Widget? child;

  @override
  State<GameBackdrop> createState() => _GameBackdropState();
}

class _GameBackdropState extends State<GameBackdrop>
    with SingleTickerProviderStateMixin {
  static final Map<Stage, Future<ui.Image>> _cache = {};
  late final AnimationController _breath;
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat(reverse: true);
    (_cache[widget.stage] ??= _render(widget.stage)).then((img) {
      if (mounted) setState(() => _image = img);
    });
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  /// Sahneyi çeyrek boyutta, bulanıklığı bir kez pişirilmiş olarak üretir;
  /// böylece her karede BackdropFilter çalışmaz.
  static Future<ui.Image> _render(Stage stage) async {
    final sharp = await SceneArt.background(stage, kWide, hud: false);
    const w = kWorldW / 4, h = kWorldH / 4;
    final rec = ui.PictureRecorder();
    Canvas(rec).drawImageRect(
      sharp,
      const Rect.fromLTWH(0, 0, kWorldW, kWorldH),
      const Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: 4,
          sigmaY: 4,
          tileMode: TileMode.clamp,
        ),
    );
    final blurred = await rec.endRecording().toImage(w.toInt(), h.toInt());
    sharp.dispose();
    return blurred;
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: FK.navy),
      AnimatedOpacity(
        duration: const Duration(milliseconds: 600),
        opacity: _image == null ? 0 : 1,
        child: _image == null
            ? const SizedBox.shrink()
            : AnimatedBuilder(
                animation: _breath,
                builder: (context, child) => Transform.scale(
                  scale:
                      1.04 +
                      0.05 * Curves.easeInOut.transform(_breath.value),
                  child: child,
                ),
                child: CustomPaint(painter: _CoverPainter(_image!)),
              ),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x730B1226), Color(0xA60B1226), Color(0xEB0B1226)],
            stops: [0, 0.5, 1],
          ),
        ),
      ),
      if (widget.child != null) widget.child!,
    ],
  );
}

/// Görseli alanı kaplayacak biçimde (cover) çizer; üst-orta hizalı.
class _CoverPainter extends CustomPainter {
  _CoverPainter(this.image);
  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    final scale = math.max(size.width / iw, size.height / ih);
    final w = iw * scale, h = ih * scale;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, iw, ih),
      Rect.fromLTWH((size.width - w) / 2, (size.height - h) * 0.35, w, h),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _CoverPainter old) => old.image != image;
}
