import 'dart:math';

import 'package:flutter/material.dart';

import 'mock_data.dart';
import 'theme.dart';

/// Oyuncu profil kartı: saha (ya da karatahta), avatar + isim, istatistik
/// hapları (rozet sayısı, seviye, beğeni), 5'li sayfalı rozet carousel'i.
Future<void> showProfileDialog(BuildContext context, LbEntry e) => showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 10),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: _ProfileCard(entry: e),
      ),
    );

class _ProfileCard extends StatefulWidget {
  const _ProfileCard({required this.entry});
  final LbEntry entry;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  late bool _liked = false;
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
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 224,
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: e.chalk ? const _ChalkPainter() : const _PitchPainter())),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 66,
                              height: 66,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                image: DecorationImage(image: AssetImage('assets/images/${e.avatar}'), fit: BoxFit.cover),
                              ),
                            ),
                            Positioned(
                              right: -4,
                              top: -2,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                                child: Icon(Icons.favorite, size: 13, color: _liked ? const Color(0xFFE53935) : const Color(0xFFBDBDBD)),
                              ),
                            ),
                          ],
                        ),
                        Transform.translate(
                          offset: const Offset(0, -6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                            child: Text(
                              e.name == 'You' ? kMeHandle : (e.name.length > 10 ? '${e.name.substring(0, 8)}...' : e.name),
                              style: KL.t(size: 16, w: FontWeight.w600, color: const Color(0xFF222222)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF444444)),
                        child: const Icon(Icons.close, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _pill(Icons.shield, '${badges.length}/${kBadges.length}'),
                        _pill(null, 'Level ${e.level}'),
                        GestureDetector(
                          onTap: () => setState(() {
                            _liked = !_liked;
                            _likes += _liked ? 1 : -1;
                          }),
                          child: _pill(Icons.favorite, '$_likes', iconColor: _liked ? const Color(0xFFFF5A5A) : Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
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
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? const Color(0xFF444444) : const Color(0xFFCCCCCC)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _pill(IconData? icon, String text, {Color iconColor = Colors.white}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
        decoration: BoxDecoration(color: KL.pill, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: iconColor), const SizedBox(width: 5)],
            Text(text, style: KL.t(size: 17, w: FontWeight.w700)),
          ],
        ),
      );
}

/// Oval rozet: dolu renk + icon/sayı; outline türü açık mavi çerçeveli.
class _BadgeTile extends StatelessWidget {
  const _BadgeTile(this.b);
  final KlBadge b;

  @override
  Widget build(BuildContext context) {
    final color = Color(b.color);
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 62,
            height: 84,
            decoration: BoxDecoration(
              color: b.outline ? Colors.white : color,
              borderRadius: BorderRadius.circular(31),
              border: Border.all(color: b.outline ? color : color.withValues(alpha: 0.0), width: 2),
            ),
            child: Container(
              margin: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: b.outline ? color.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.35), width: 1.5),
              ),
              alignment: Alignment.center,
              child: b.icon != null
                  ? Icon(b.icon, color: b.outline ? color : Colors.white, size: 28)
                  : Text(
                      b.text!,
                      style: KL.t(size: b.text!.length > 2 ? 15 : 22, w: FontWeight.w700, color: b.outline ? color : Colors.white),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(b.label, textAlign: TextAlign.center, maxLines: 3, style: KL.t(size: 10.5, color: const Color(0xFF222222))),
        ],
      ),
    );
  }
}

/// Çizgili yeşil saha, beyaz çizgiler, iki kale.
class _PitchPainter extends CustomPainter {
  const _PitchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = KL.pitchDark);
    final stripe = Paint()..color = KL.pitchLight;
    const n = 9;
    final w = size.width / n;
    for (var i = 0; i < n; i += 2) {
      canvas.drawRect(Rect.fromLTWH(i * w, 0, w, size.height), stripe);
    }
    _drawLines(canvas, size, Colors.white.withValues(alpha: 0.85));
    final coin = Paint()..color = const Color(0xFFF5B400);
    final coinIn = Paint()..color = const Color(0xFFFFE680);
    for (final o in [Offset(size.width * 0.70, 60), Offset(size.width * 0.70, 90), Offset(size.width * 0.65, 120), Offset(size.width * 0.70, 140)]) {
      canvas.drawCircle(o, 6, coin);
      canvas.drawCircle(o, 3, coinIn);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Karatahta taktik tahtası: koyu zemin, tebeşir çizgiler, X/O ve oklar.
class _ChalkPainter extends CustomPainter {
  const _ChalkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1F2A24));
    _drawLines(canvas, size, Colors.white.withValues(alpha: 0.7));
    final chalk = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rng = Random(3);
    for (var i = 0; i < 7; i++) {
      final o = Offset(40 + rng.nextDouble() * (size.width - 80), 40 + rng.nextDouble() * (size.height - 110));
      if (i.isEven) {
        canvas.drawLine(o + const Offset(-6, -6), o + const Offset(6, 6), chalk);
        canvas.drawLine(o + const Offset(-6, 6), o + const Offset(6, -6), chalk);
      } else {
        canvas.drawCircle(o, 7, chalk);
      }
      final to = Offset(o.dx + (rng.nextDouble() * 80 - 40), o.dy + (rng.nextDouble() * 60 - 30));
      canvas.drawLine(o, to, chalk);
    }
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
    final goal = left ? Rect.fromLTWH(field.left - 18, field.center.dy - 42, 18, 84) : Rect.fromLTWH(field.right, field.center.dy - 42, 18, 84);
    canvas.drawRect(goal, line);
    final net = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var y = goal.top + 6; y < goal.bottom; y += 6) {
      canvas.drawLine(Offset(goal.left, y), Offset(goal.right, y), net);
    }
    for (var x = goal.left + 6; x < goal.right; x += 6) {
      canvas.drawLine(Offset(x, goal.top), Offset(x, goal.bottom), net);
    }
  }
}
