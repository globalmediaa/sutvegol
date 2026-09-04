import 'dart:math';

import 'package:flutter/material.dart';

import 'mock_data.dart';
import 'theme.dart';
import 'widgets.dart';

/// Oyuncu profil kartı: sahne afişi (gece sahası ya da sokak duvarı),
/// avatar + isim, istatistik hapları (rozet, seviye, beğeni), 5'li rozet carousel'i.
Future<void> showProfileDialog(BuildContext context, LbEntry e) => showDialog<void>(
      context: context,
      barrierColor: FK.navy.withValues(alpha: 0.82),
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: Colors.transparent,
        child: GlassCard(radius: 26, child: _ProfileCard(entry: e)),
      ),
    );

class _ProfileCard extends StatefulWidget {
  const _ProfileCard({required this.entry});
  final LbEntry entry;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  bool _liked = false;
  late int _likes = widget.entry.likes;
  final PageController _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final badges = e.earnedBadges;
    final pageCount = max(1, (badges.length / 5).ceil());
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 220,
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: e.street ? const _StreetPainter() : const _NightPitchPainter())),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: FK.glow(20, alpha: 0.4, dy: 6)),
                              child: AvatarCircle(e.name == kMeName ? kMeHandle : e.name, size: 72, ring: FK.orange, ringWidth: 3),
                            ),
                            Positioned(
                              right: -4,
                              top: -2,
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                                child: Icon(Icons.favorite, size: 13, color: _liked ? FK.red : const Color(0xFFBDBDBD)),
                              ),
                            ),
                          ],
                        ),
                        Transform.translate(
                          offset: const Offset(0, -6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                            decoration: BoxDecoration(color: FK.navy.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(12), border: Border.all(color: FK.glassBorder)),
                            child: Text(
                              e.name == kMeName ? '@$kMeHandle' : e.name,
                              style: FK.t(size: 15, w: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 10,
                    top: 10,
                    child: RoundButton(icon: Icons.close_rounded, size: 32, color: FK.navy.withValues(alpha: 0.7), onTap: () => Navigator.of(context).pop()),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _pill(Icons.shield_rounded, '${badges.length}/${kBadges.length}'),
                        _pill(Icons.military_tech_rounded, 'Seviye ${e.level}'),
                        GestureDetector(
                          onTap: () => setState(() {
                            _liked = !_liked;
                            _likes += _liked ? 1 : -1;
                          }),
                          child: _pill(Icons.favorite, '$_likes', iconColor: _liked ? FK.red : Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text('ROZETLER', style: FK.t(size: 11, w: FontWeight.w700, color: FK.muted, spacing: 2)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 132,
            child: PageView.builder(
              controller: _pages,
              itemCount: pageCount,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final slice = badges.skip(i * 5).take(5).toList();
                return Row(
                  children: [
                    for (final b in slice) _BadgeTile(b),
                    for (var k = slice.length; k < 5; k++) const Expanded(child: SizedBox()),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < pageCount; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == _page ? 18 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: i == _page ? FK.orange : FK.glassBorder),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String text, {Color iconColor = Colors.white}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: FK.navy.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(20), border: Border.all(color: FK.glassBorder)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: iconColor),
            const SizedBox(width: 5),
            Text(text, style: FK.t(size: 14, w: FontWeight.w700)),
          ],
        ),
      );
}

/// Rozet: gradyanlı yuvarlak kare + ikon/sayı; outline türü çerçeveli.
class _BadgeTile extends StatelessWidget {
  const _BadgeTile(this.b);
  final FkBadge b;

  @override
  Widget build(BuildContext context) {
    final color = Color(b.color);
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: b.outline ? null : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(color, Colors.white, 0.18)!, color]),
              color: b.outline ? FK.glass : null,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: b.outline ? color : Colors.white.withValues(alpha: 0.25), width: b.outline ? 2 : 1),
              boxShadow: b.outline ? null : [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 5))],
            ),
            alignment: Alignment.center,
            child: b.icon != null
                ? Icon(b.icon, color: b.outline ? color : Colors.white, size: 26)
                : Text(b.text!, style: FK.t(size: b.text!.length > 2 ? 14 : 20, w: FontWeight.w700, color: b.outline ? color : Colors.white)),
          ),
          const SizedBox(height: 6),
          Text(b.label, textAlign: TextAlign.center, maxLines: 3, style: FK.t(size: 10.5, color: const Color(0xFFDDE4F5))),
        ],
      ),
    );
  }
}

/// Gece halı sahası: koyu yeşil zemin, projektör parıltısı, beyaz çizgiler.
class _NightPitchPainter extends CustomPainter {
  const _NightPitchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1F7A3C), Color(0xFF14522A)]).createShader(Offset.zero & size));
    final stripe = Paint()..color = const Color(0x14FFFFFF);
    const n = 9;
    final w = size.width / n;
    for (var i = 0; i < n; i += 2) {
      canvas.drawRect(Rect.fromLTWH(i * w, 0, w, size.height), stripe);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: Offset(size.width / 2, 0), radius: size.width * 0.8)));
    _drawLines(canvas, size, Colors.white.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Sokak duvarı: tuğla dokusu, grafiti lekeleri, asfalt bant.
class _StreetPainter extends CustomPainter {
  const _StreetPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF8E4B36));
    final mortar = Paint()
      ..color = const Color(0x665C2A1C)
      ..strokeWidth = 2;
    var row = 0;
    for (var y = 0.0; y < size.height * 0.78; y += 18) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), mortar);
      final off = row.isEven ? 0.0 : 24.0;
      for (var x = off; x < size.width; x += 48) {
        canvas.drawLine(Offset(x, y), Offset(x, y + 18), mortar);
      }
      row++;
    }
    final rng = Random(5);
    for (final c in [FK.cyan, FK.orange, FK.gold]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(rng.nextDouble() * size.width, 30 + rng.nextDouble() * 100), width: 110, height: 56),
        Paint()..color = c.withValues(alpha: 0.5)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.78, size.width, size.height * 0.22), Paint()..color = const Color(0xFF3B3F4A));
    final chalk = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, size.height * 0.86), Offset(size.width, size.height * 0.86), chalk);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _drawLines(Canvas canvas, Size size, Color color) {
  final line = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  final field = Rect.fromLTWH(30, 22, size.width - 60, size.height - 70);
  canvas.drawRRect(RRect.fromRectAndRadius(field, const Radius.circular(8)), line);
  canvas.drawLine(Offset(size.width / 2, field.top), Offset(size.width / 2, field.bottom), line);
  canvas.drawCircle(Offset(size.width / 2, field.center.dy), 34, line);
  for (final left in [true, false]) {
    final x = left ? field.left : field.right - 44;
    canvas.drawRect(Rect.fromLTWH(x, field.center.dy - 48, 44, 96), line);
    final gx = left ? field.left : field.right - 18;
    canvas.drawRect(Rect.fromLTWH(gx, field.center.dy - 24, 18, 48), line);
  }
}
