import 'package:flutter/material.dart';

import 'mock_data.dart';
import 'theme.dart';

/// Oyuncu profil kartı: saha görseli, avatar + isim, istatistik hapları, rozetler.
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

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.entry});
  final LbEntry entry;

  @override
  Widget build(BuildContext context) {
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
                  const Positioned.fill(child: CustomPaint(painter: _PitchPainter())),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            image: DecorationImage(image: AssetImage('assets/images/${entry.avatar}'), fit: BoxFit.cover),
                          ),
                        ),
                        Transform.translate(
                          offset: const Offset(0, -6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                            child: Text(entry.name == 'You' ? kMeHandle : entry.name, style: KL.t(size: 16, w: FontWeight.w600, color: const Color(0xFF222222))),
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
                        _pill(Icons.shield, '${entry.badges}/37'),
                        _pill(null, 'Level ${entry.level}'),
                        _pill(Icons.favorite, '${entry.likes}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _badge('badge_welcome.png', 'Welcome'),
              const SizedBox(width: 6),
              _badge('badge_profile.png', 'Profile\npicture'),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _pill(IconData? icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
        decoration: BoxDecoration(color: KL.pill, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: Colors.white), const SizedBox(width: 5)],
            Text(text, style: KL.t(size: 17, w: FontWeight.w700)),
          ],
        ),
      );

  Widget _badge(String asset, String label) => SizedBox(
        width: 82,
        child: Column(
          children: [
            Image.asset('assets/images/$asset', width: 72),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: KL.t(size: 14, color: const Color(0xFF222222))),
          ],
        ),
      );
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
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final field = Rect.fromLTWH(30, 22, size.width - 60, size.height - 70);
    canvas.drawRRect(RRect.fromRectAndRadius(field, const Radius.circular(8)), line);
    canvas.drawLine(Offset(size.width / 2, field.top), Offset(size.width / 2, field.bottom), line);
    canvas.drawCircle(Offset(size.width / 2, field.center.dy), 34, line);
    // Ceza sahaları.
    for (final left in [true, false]) {
      final x = left ? field.left : field.right - 44;
      canvas.drawRect(Rect.fromLTWH(x, field.center.dy - 48, 44, 96), line);
      final gx = left ? field.left : field.right - 18;
      canvas.drawRect(Rect.fromLTWH(gx, field.center.dy - 24, 18, 48), line);
      // Kale + file.
      final goal = left ? Rect.fromLTWH(field.left - 18, field.center.dy - 42, 18, 84) : Rect.fromLTWH(field.right, field.center.dy - 42, 18, 84);
      canvas.drawRect(goal, line);
      final net = Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      for (var y = goal.top + 6; y < goal.bottom; y += 6) {
        canvas.drawLine(Offset(goal.left, y), Offset(goal.right, y), net);
      }
      for (var x = goal.left + 6; x < goal.right; x += 6) {
        canvas.drawLine(Offset(x, goal.top), Offset(x, goal.bottom), net);
      }
    }
    // Sağda birkaç altın top (rozet noktaları).
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
