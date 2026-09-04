import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, FontWeight, TextDirection;

import 'geometry.dart';

typedef _V3 = (double, double, double);

/// Prosedürel sahne sanatı: hiçbir görsel dosyadan yüklenmez, tüm arka planlar,
/// top ve küçük öğeler koddan çizilir. Sahne (sokak / halı saha / stadyum) ve
/// kamera (geniş / yakın) kombinasyonu için bir kez render edilip cache'lenir.
class SceneArt {
  SceneArt._();

  // ------------------------------------------------------------- görseller

  static Future<ui.Image> background(Stage stage, ViewGeom g) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    _paintScene(c, stage, g);
    return rec.endRecording().toImage(kWorldW.toInt(), kWorldH.toInt());
  }

  /// Açılış göğü: üstte gece laciverti, altta sokak sahnesinin gök rengiyle birleşir.
  static Future<ui.Image> splashSky() {
    const h = kWorldH + 140;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(
      const Rect.fromLTWH(0, 0, kWorldW, h),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, h), const [
          Color(0xFF060A1C),
          Color(0xFF12173A),
          Color(0xFF2B1E5C),
        ], const [0, 0.55, 1]),
    );
    final rng = Random(11);
    for (var i = 0; i < 160; i++) {
      final y = rng.nextDouble() * h * 0.75;
      final a = (0.25 + rng.nextDouble() * 0.7) * (1 - y / (h * 0.8));
      c.drawCircle(Offset(rng.nextDouble() * kWorldW, y), 1.5 + rng.nextDouble() * 2.5, Paint()..color = Color.fromRGBO(255, 255, 255, a.clamp(0, 1)));
    }
    // Ufuk parıltısı (alttaki sokak gün batımı).
    c.drawRect(
      const Rect.fromLTWH(0, h * 0.55, kWorldW, h * 0.45),
      Paint()
        ..shader = ui.Gradient.radial(const Offset(kWorldW * 0.3, h), kWorldW * 1.1, [
          const Color(0xFFFF7A1A).withValues(alpha: 0.28),
          const Color(0xFFFF7A1A).withValues(alpha: 0.0),
        ]),
    );
    _clouds(c, rng, 0.6 * h, 0.92 * h, 7, const Color(0xFF5A4A8C), const Color(0xFF7C6AAE));
    return rec.endRecording().toImage(kWorldW.toInt(), h.toInt());
  }

  /// Top: kesik ikosahedron (12 beşgen) izdüşümü, gölgeli küre (görsel olarak cache'lenir).
  static Future<ui.Image> ball({bool king = false}) {
    const d = kBallDiameter;
    const r = d / 2;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.translate(r, r);
    paintBall(c, r, king: king);
    return rec.endRecording().toImage(d.toInt(), d.toInt());
  }

  /// Topu doğrudan bir canvas'a çizer (merkez orijinde, yarıçap [r]).
  /// Logo ve arayüz gibi görsel cache'i olmayan yerlerde kullanılır.
  static void paintBall(Canvas c, double r, {bool king = false}) {
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r - 0.5)));
    final base = king ? const [Color(0xFFFFF3B8), Color(0xFFF7C23A), Color(0xFFC87A08)] : const [Color(0xFFFFFFFF), Color(0xFFEDF0F6), Color(0xFFB9C1D3)];
    c.drawCircle(
      Offset.zero,
      r,
      Paint()..shader = ui.Gradient.radial(Offset(-r * 0.35, -r * 0.4), r * 1.45, base, const [0, 0.5, 1]),
    );
    final panel = Paint()..color = king ? const Color(0xFF8A4A00) : const Color(0xFF1E2230);
    final seam = Paint()
      ..color = king ? const Color(0xFFB8771A) : const Color(0xFF8A90A3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.2, r / 49);
    _drawTruncatedIcosahedron(c, r, panel, seam);
    c.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = ui.Gradient.radial(Offset(-r * 0.3, -r * 0.3), r * 1.35, const [
          Color(0x00000000),
          Color(0x00000000),
          Color(0x66000000),
        ], const [0, 0.55, 1]),
    );
    c.drawOval(
      Rect.fromCenter(center: Offset(-r * 0.42, -r * 0.48), width: r * 0.6, height: r * 0.36),
      Paint()
        ..color = const Color(0x8CFFFFFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r / 12),
    );
    c.restore();
  }

  static void _drawTruncatedIcosahedron(Canvas c, double r, Paint panel, Paint seam) {
    const phi = 1.618033988749895;
    final raw = <_V3>[];
    void evenPerms(double a, double b, double z) {
      raw.add((a, b, z));
      raw.add((b, z, a));
      raw.add((z, a, b));
    }

    for (final s1 in [1.0, -1.0]) {
      for (final s2 in [1.0, -1.0]) {
        evenPerms(0, s1, s2 * 3 * phi);
        for (final s3 in [1.0, -1.0]) {
          evenPerms(s1, s2 * (2 + phi), s3 * 2 * phi);
          evenPerms(s1 * phi, s2 * 2, s3 * (2 * phi + 1));
        }
      }
    }
    final centersRaw = <_V3>[];
    for (final s1 in [1.0, -1.0]) {
      for (final s2 in [1.0, -1.0]) {
        centersRaw.add((0, s1, s2 * phi));
        centersRaw.add((s1, s2 * phi, 0));
        centersRaw.add((s2 * phi, 0, s1));
      }
    }
    // Döndür (biraz eğik bakış) ve küreye normalize et.
    _V3 rot(_V3 v) {
      const ax = 0.55, ay = 0.35, az = 0.15;
      var (x, y, z) = v;
      var y1 = y * cos(ax) - z * sin(ax), z1 = y * sin(ax) + z * cos(ax);
      y = y1;
      z = z1;
      var x1 = x * cos(ay) + z * sin(ay);
      z1 = -x * sin(ay) + z * cos(ay);
      x = x1;
      z = z1;
      x1 = x * cos(az) - y * sin(az);
      y1 = x * sin(az) + y * cos(az);
      final len = sqrt(x1 * x1 + y1 * y1 + z * z);
      return (x1 / len, y1 / len, z / len);
    }

    final verts = raw.map(rot).toList();
    final centers = centersRaw.map(rot).toList();
    double dot(_V3 a, _V3 b) => a.$1 * b.$1 + a.$2 * b.$2 + a.$3 * b.$3;
    _V3 cross(_V3 a, _V3 b) => (a.$2 * b.$3 - a.$3 * b.$2, a.$3 * b.$1 - a.$1 * b.$3, a.$1 * b.$2 - a.$2 * b.$1);
    _V3 norm(_V3 a) {
      final l = sqrt(dot(a, a));
      return (a.$1 / l, a.$2 / l, a.$3 / l);
    }

    Offset proj(_V3 v) => Offset(v.$1 * r, -v.$2 * r);
    _V3 slerp(_V3 a, _V3 b, double t) {
      final o = acos(dot(a, b).clamp(-1.0, 1.0));
      if (o < 1e-6) return a;
      final sa = sin((1 - t) * o) / sin(o), sb = sin(t * o) / sin(o);
      return (a.$1 * sa + b.$1 * sb, a.$2 * sa + b.$2 * sb, a.$3 * sa + b.$3 * sb);
    }

    // Dikişler: ham koordinatlarda uzunluğu 2 olan kenarlar.
    for (var i = 0; i < raw.length; i++) {
      for (var j = i + 1; j < raw.length; j++) {
        final dx = raw[i].$1 - raw[j].$1, dy = raw[i].$2 - raw[j].$2, dz = raw[i].$3 - raw[j].$3;
        if ((dx * dx + dy * dy + dz * dz - 4).abs() > 1e-6) continue;
        final a = verts[i], b = verts[j];
        if (a.$3 < -0.05 && b.$3 < -0.05) continue;
        final path = Path()..moveTo(proj(a).dx, proj(a).dy);
        for (var k = 1; k <= 5; k++) {
          final p = proj(slerp(a, b, k / 5));
          path.lineTo(p.dx, p.dy);
        }
        c.drawPath(path, seam);
      }
    }
    // Beşgenler: merkeze en yakın 5 köşe, açıya göre sıralı.
    for (final ctr in centers) {
      if (ctr.$3 < -0.15) continue;
      final near = List<int>.generate(verts.length, (i) => i)..sort((a, b) => dot(verts[b], ctr).compareTo(dot(verts[a], ctr)));
      final five = near.take(5).toList();
      final u = norm(cross(ctr, ctr.$1.abs() < 0.9 ? (1, 0, 0) : (0, 1, 0)));
      final v = cross(ctr, u);
      five.sort((a, b) => atan2(dot(verts[a], v), dot(verts[a], u)).compareTo(atan2(dot(verts[b], v), dot(verts[b], u))));
      final path = Path();
      for (var i = 0; i < 5; i++) {
        final a = verts[five[i]], b = verts[five[(i + 1) % 5]];
        if (i == 0) path.moveTo(proj(a).dx, proj(a).dy);
        for (var k = 1; k <= 5; k++) {
          final p = proj(slerp(a, b, k / 5));
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      c.drawPath(path, panel);
    }
  }

  // ------------------------------------------------------------- küçük öğeler

  /// Kalp (merkez orijinde, [w]x[h]).
  static void paintHeart(Canvas c, double w, double h, Color color, {bool dead = false}) {
    final p = Path()
      ..moveTo(0, h * 0.48)
      ..cubicTo(-w * 0.62, h * 0.08, -w * 0.5, -h * 0.55, 0, -h * 0.22)
      ..cubicTo(w * 0.5, -h * 0.55, w * 0.62, h * 0.08, 0, h * 0.48)
      ..close();
    if (!dead) {
      c.drawPath(p.shift(const Offset(0, 4)), Paint()..color = const Color(0x55000000));
    }
    c.drawPath(
      p,
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, -h / 2), Offset(0, h / 2), dead ? const [Color(0xFF3A4157), Color(0xFF232A3E)] : [color, Color.lerp(color, const Color(0xFF7A0020), 0.45)!]),
    );
    if (!dead) {
      c.drawOval(
        Rect.fromCenter(center: Offset(-w * 0.2, -h * 0.18), width: w * 0.22, height: h * 0.16),
        Paint()..color = const Color(0x99FFFFFF),
      );
    }
  }

  /// Hedef halkası (merkez orijinde, yarıçap [r]).
  static void paintTarget(Canvas c, double r, Color accent, double alpha) {
    c.drawCircle(
      Offset.zero,
      r * 1.1,
      Paint()
        ..color = accent.withValues(alpha: 0.38 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    c.drawCircle(Offset.zero, r * 0.86, Paint()..color = const Color(0xFF0B1226).withValues(alpha: 0.55 * alpha)..style = PaintingStyle.stroke..strokeWidth = r * 0.30);
    c.drawCircle(Offset.zero, r * 0.86, Paint()..color = accent.withValues(alpha: alpha)..style = PaintingStyle.stroke..strokeWidth = r * 0.22);
    c.drawCircle(Offset.zero, r * 0.52, Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: alpha)..style = PaintingStyle.stroke..strokeWidth = r * 0.12);
    c.drawCircle(Offset.zero, r * 0.24, Paint()..color = accent.withValues(alpha: alpha));
    c.drawCircle(Offset.zero, r * 0.09, Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: alpha));
  }

  /// Kaleci mankeni: klasik siyah silüet (kafa, omuzlar, gövde, iki ince bacak).
  /// bottomCenter orijinde, [w]x[h] (referans 116x280).
  static void paintKeeper(Canvas c, double w, double h, double alpha) {
    final fill = Paint()..color = const Color(0xFF1C2230).withValues(alpha: alpha);
    final leg = Paint()
      ..color = const Color(0xFF12161F).withValues(alpha: alpha)
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round;
    // Bacaklar: gövde altından raya doğru hafif açılarak.
    c.drawLine(Offset(-w * 0.30, -h * 0.40), Offset(-w * 0.44, 0), leg);
    c.drawLine(Offset(w * 0.30, -h * 0.40), Offset(w * 0.44, 0), leg);
    // Gövde: omuzları yuvarlak, hafif geniş plaka.
    final torso = Path()
      ..moveTo(-w * 0.34, -h * 0.72)
      ..quadraticBezierTo(-w * 0.5, -h * 0.72, -w * 0.5, -h * 0.60)
      ..lineTo(-w * 0.46, -h * 0.40)
      ..lineTo(w * 0.46, -h * 0.40)
      ..lineTo(w * 0.5, -h * 0.60)
      ..quadraticBezierTo(w * 0.5, -h * 0.72, w * 0.34, -h * 0.72)
      ..close();
    c.drawPath(torso, fill);
    // Boyun ve kafa.
    c.drawRect(Rect.fromLTWH(-w * 0.09, -h * 0.80, w * 0.18, h * 0.1), fill);
    c.drawCircle(Offset(0, -h * 0.865), w * 0.29, fill);
    // Aşınma lekeleri.
    final spot = Paint()..color = const Color(0xFF0B0E16).withValues(alpha: 0.6 * alpha);
    c.drawCircle(Offset(w * 0.22, -h * 0.55), w * 0.06, spot);
    c.drawCircle(Offset(w * 0.12, -h * 0.47), w * 0.04, spot);
    c.drawCircle(Offset(-w * 0.1, -h * 0.9), w * 0.035, spot);
  }

  // ------------------------------------------------------------- sahne

  static void _paintScene(Canvas c, Stage stage, ViewGeom g) {
    final rng = Random(stage.index * 97 + 5);
    _sky(c, stage, rng);
    c.save();
    c.translate(kWorldW / 2, g.groundY);
    c.scale(g.zoom);
    c.translate(-kWorldW / 2, -g.groundY);
    switch (stage) {
      case Stage.street:
        _streetBackdrop(c, g, rng);
      case Stage.beach:
        _beachBackdrop(c, g, rng);
      case Stage.cage:
        _cageBackdrop(c, g, rng);
      case Stage.stadium:
        _stadiumBackdrop(c, g, rng);
    }
    c.restore();
    _ground(c, stage, g, rng);
    _goal(c, stage, g);
    _board(c, stage, g);
    _pauseButton(c);
  }

  static void _sky(Canvas c, Stage stage, Random rng) {
    final colors = switch (stage) {
      Stage.street => const [Color(0xFF2B1E5C), Color(0xFF7A3E8E), Color(0xFFE8684A), Color(0xFFFFB35C)],
      Stage.beach => const [Color(0xFF2F8FE8), Color(0xFF56B0F5), Color(0xFF9DD6FB), Color(0xFFDCEFFB)],
      Stage.cage => const [Color(0xFF050A1C), Color(0xFF0A1330), Color(0xFF122650), Color(0xFF1B3466)],
      Stage.stadium => const [Color(0xFF0B1240), Color(0xFF1B2A6B), Color(0xFF3B4C9C), Color(0xFF6C7FCB)],
    };
    c.drawRect(
      const Rect.fromLTWH(0, 0, kWorldW, kWorldH),
      Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(0, 1100), colors, const [0, 0.35, 0.72, 1]),
    );
    if (stage == Stage.street) {
      // Güneş.
      c.drawCircle(const Offset(300, 830), 210, Paint()..color = const Color(0x55FFD27A)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 90));
      c.drawCircle(const Offset(300, 830), 105, Paint()..color = const Color(0xFFFFE6A3));
      _clouds(c, rng, 120, 640, 6, const Color(0xFFF6B8A8), const Color(0xFFFFE0D2));
    } else if (stage == Stage.beach) {
      c.drawCircle(const Offset(1010, 300), 200, Paint()..color = const Color(0x66FFF3B0)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80));
      c.drawCircle(const Offset(1010, 300), 92, Paint()..color = const Color(0xFFFFF6C8));
      _clouds(c, rng, 140, 620, 5, const Color(0xFFF4FAFF), const Color(0xFFFFFFFF));
    } else {
      for (var i = 0; i < (stage == Stage.cage ? 170 : 60); i++) {
        final y = rng.nextDouble() * 900;
        c.drawCircle(Offset(rng.nextDouble() * kWorldW, y), 1.5 + rng.nextDouble() * 2, Paint()..color = Color.fromRGBO(255, 255, 255, (0.3 + rng.nextDouble() * 0.6) * (1 - y / 1000)));
      }
      if (stage == Stage.cage) {
        c.drawCircle(const Offset(1060, 360), 140, Paint()..color = const Color(0x33CFE6FF)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60));
        c.drawCircle(const Offset(1060, 360), 68, Paint()..color = const Color(0xFFF2F6FF));
        c.drawCircle(const Offset(1085, 345), 58, Paint()..color = const Color(0xFF0A1330));
      } else {
        _clouds(c, rng, 150, 600, 4, const Color(0xFF2E3D80), const Color(0xFF4A5CA8));
      }
    }
  }

  static void _clouds(Canvas c, Random rng, double y0, double y1, int n, Color base, Color light) {
    for (var i = 0; i < n; i++) {
      final x = rng.nextDouble() * kWorldW;
      final y = y0 + rng.nextDouble() * (y1 - y0);
      final w = 220 + rng.nextDouble() * 320;
      final h = w * 0.32;
      for (var k = 0; k < 4; k++) {
        final ox = (k - 1.5) * w * 0.22;
        final rr = h * (0.45 + rng.nextDouble() * 0.35);
        c.drawCircle(Offset(x + ox, y - rr * 0.35), rr, Paint()..color = base);
      }
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y), width: w, height: h), Radius.circular(h / 2)), Paint()..color = base);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x - w * 0.08, y - h * 0.22), width: w * 0.6, height: h * 0.45), Radius.circular(h / 2)), Paint()..color = light);
    }
  }

  // ---- Sokak: gün batımı, apartman siluetleri, tuğla duvar, grafiti, sokak lambası.
  static void _streetBackdrop(Canvas c, ViewGeom g, Random rng) {
    final wallTop = g.crossbarY - 300;
    final wallBottom = g.groundY - 130;
    // Uzak siluet.
    final far = Paint()..color = const Color(0xFF3A2450);
    var x = -40.0;
    while (x < kWorldW + 40) {
      final w = 90 + rng.nextDouble() * 160;
      final top = wallTop - 120 - rng.nextDouble() * 320;
      c.drawRect(Rect.fromLTRB(x, top, x + w, wallTop + 20), far);
      if (rng.nextDouble() < 0.4) c.drawRect(Rect.fromLTWH(x + w * 0.3, top - 60, 8, 60), far);
      if (rng.nextDouble() < 0.3) {
        c.drawRect(Rect.fromLTWH(x + w * 0.55, top - 40, 40, 40), far);
      }
      final win = Paint()..color = const Color(0xCCFFD27A);
      for (var wy = top + 30; wy < wallTop - 10; wy += 44) {
        for (var wx = x + 14; wx < x + w - 20; wx += 30) {
          if (rng.nextDouble() < 0.35) c.drawRect(Rect.fromLTWH(wx, wy, 14, 20), win);
        }
      }
      x += w + 6 + rng.nextDouble() * 30;
    }
    // Yakın apartmanlar (sol / sağ).
    for (final b in [(0.0, 340.0, 0xFF8C5A47), (960.0, 1320.0, 0xFF6E4A3E)]) {
      final rect = Rect.fromLTRB(b.$1, wallTop - 420, b.$2, wallTop + 40);
      c.drawRect(rect, Paint()..color = Color(b.$3));
      c.drawRect(Rect.fromLTRB(rect.left, rect.top, rect.right, rect.top + 26), Paint()..color = const Color(0xFF4A2E2A));
      for (var wy = rect.top + 60; wy < rect.bottom - 40; wy += 96) {
        for (var wx = rect.left + 40; wx < rect.right - 60; wx += 90) {
          final lit = rng.nextDouble() < 0.4;
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(wx, wy, 52, 64), const Radius.circular(4)), Paint()..color = lit ? const Color(0xFFFFD27A) : const Color(0xFF2F2233));
          c.drawRect(Rect.fromLTWH(wx - 6, wy + 64, 64, 8), Paint()..color = const Color(0xFF4A2E2A));
        }
      }
    }
    // Tuğla duvar.
    final wall = Rect.fromLTRB(-40, wallTop, kWorldW + 40, wallBottom);
    c.drawRect(wall, Paint()..shader = ui.Gradient.linear(Offset(0, wallTop), Offset(0, wallBottom), const [Color(0xFFB0644A), Color(0xFF8E4B36)]));
    final mortar = Paint()
      ..color = const Color(0x8C5C2A1C)
      ..strokeWidth = 4;
    var row = 0;
    for (var y = wallTop + 46; y < wallBottom; y += 46) {
      c.drawLine(Offset(-40, y), Offset(kWorldW + 40, y), mortar);
      final off = row.isEven ? 0.0 : 62.0;
      for (var bx = -40 + off; bx < kWorldW + 40; bx += 124) {
        c.drawLine(Offset(bx, y - 46), Offset(bx, y), mortar);
        if (rng.nextDouble() < 0.12) {
          c.drawRect(Rect.fromLTWH(bx + 4, y - 42, 116, 38), Paint()..color = Color.fromRGBO(255, 230, 200, 0.05 + rng.nextDouble() * 0.06));
        }
      }
      row++;
    }
    c.drawRect(Rect.fromLTRB(-40, wallTop - 18, kWorldW + 40, wallTop + 8), Paint()..color = const Color(0xFFC99B7A));
    // Grafiti: yumuşak lekeler ve kalın fırça izleri.
    for (final s in [(160.0, wallTop + 260, 0xFF35D5F2), (1130.0, wallTop + 330, 0xFFFF7A1A), (260.0, wallTop + 420, 0xFFFFC53D)]) {
      c.drawOval(Rect.fromCenter(center: Offset(s.$1, s.$2), width: 240, height: 130), Paint()..color = Color(s.$3).withValues(alpha: 0.55)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 16;
    c.drawPath(
      Path()
        ..moveTo(80, wallTop + 250)
        ..cubicTo(140, wallTop + 180, 200, wallTop + 320, 260, wallTop + 240)
        ..cubicTo(300, wallTop + 190, 330, wallTop + 300, 360, wallTop + 260),
      stroke..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85),
    );
    c.drawPath(
      Path()
        ..moveTo(1040, wallTop + 320)
        ..cubicTo(1090, wallTop + 260, 1150, wallTop + 380, 1210, wallTop + 300)
        ..lineTo(1260, wallTop + 340),
      stroke..color = const Color(0xFFFFE08A).withValues(alpha: 0.9),
    );
    // Sokak lambası ve ışık konisi.
    const lx = 1200.0;
    c.drawRect(Rect.fromLTWH(lx - 9, wallTop - 560, 18, wallBottom - wallTop + 560), Paint()..color = const Color(0xFF2A2E38));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(lx - 70, wallTop - 600, 140, 44), const Radius.circular(10)), Paint()..color = const Color(0xFF2A2E38));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(lx - 52, wallTop - 566, 104, 16), const Radius.circular(6)), Paint()..color = const Color(0xFFFFF1C2));
    c.drawPath(
      Path()
        ..moveTo(lx - 60, wallTop - 560)
        ..lineTo(lx + 60, wallTop - 560)
        ..lineTo(lx + 330, wallBottom + 40)
        ..lineTo(lx - 330, wallBottom + 40)
        ..close(),
      Paint()..shader = ui.Gradient.linear(Offset(0, wallTop - 560), Offset(0, wallBottom), const [Color(0x66FFE2A0), Color(0x00FFE2A0)]),
    );
    // Çöp konteyneri (sol).
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(40, wallBottom - 190, 250, 190), const Radius.circular(14)), Paint()..color = const Color(0xFF2E6B4A));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(30, wallBottom - 214, 270, 40), const Radius.circular(10)), Paint()..color = const Color(0xFF3B865C));
    c.drawRect(Rect.fromLTWH(60, wallBottom - 140, 210, 8), Paint()..color = const Color(0x55000000));
    // Duvar dibi gölgesi.
    c.drawRect(Rect.fromLTRB(-40, wallBottom - 90, kWorldW + 40, wallBottom), Paint()..shader = ui.Gradient.linear(Offset(0, wallBottom - 90), Offset(0, wallBottom), const [Color(0x00000000), Color(0x66000000)]));
  }

  // ---- Sahil: deniz, köpük, palmiyeler, şemsiye.
  static void _beachBackdrop(Canvas c, ViewGeom g, Random rng) {
    final horizon = g.crossbarY - 420;
    final shore = g.groundY - 130;
    c.drawRect(
      Rect.fromLTRB(-40, horizon, kWorldW + 40, shore),
      Paint()..shader = ui.Gradient.linear(Offset(0, horizon), Offset(0, shore), const [Color(0xFF1B6FD0), Color(0xFF2AA8DD), Color(0xFF4FD0E6)], const [0, 0.55, 1]),
    );
    // Ufukta yelkenli.
    final sail = Paint()..color = const Color(0xFFFFFFFF);
    c.drawPath(Path()..moveTo(300, horizon + 6)..lineTo(300, horizon - 70)..lineTo(350, horizon + 6)..close(), sail);
    c.drawPath(Path()..moveTo(280, horizon + 8)..lineTo(372, horizon + 8)..lineTo(360, horizon + 22)..lineTo(292, horizon + 22)..close(), Paint()..color = const Color(0xFF1B2A6B));
    // Dalga köpükleri: yaklaştıkça uzun ve belirgin.
    for (var i = 0; i < 80; i++) {
      final t = rng.nextDouble();
      final y = horizon + 20 + t * (shore - horizon - 60);
      final x = rng.nextDouble() * kWorldW;
      final w = 30 + 220 * t;
      c.drawPath(
        Path()..moveTo(x - w / 2, y)..quadraticBezierTo(x, y - 6 - 10 * t, x + w / 2, y),
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, 0.3 + 0.5 * t)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 + 5 * t
          ..strokeCap = StrokeCap.round,
      );
    }
    // Kıyı köpüğü.
    final foam = Path()..moveTo(-40, shore + 10);
    for (var x = -40.0; x <= kWorldW + 40; x += 20) {
      foam.lineTo(x, shore - 26 + sin(x / 90) * 12 + sin(x / 37) * 5);
    }
    foam.lineTo(kWorldW + 40, shore + 10);
    foam.close();
    c.drawPath(foam, Paint()..color = const Color(0xE6FFFFFF));
    c.drawPath(foam, Paint()..color = const Color(0x55FFFFFF)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    // Palmiyeler.
    _palm(c, Offset(150, shore + 20), 680, 1, rng);
    _palm(c, Offset(1190, shore + 20), 600, -1, rng);
    // Şemsiye (sağ).
    c.save();
    c.translate(1000, shore - 40);
    c.rotate(-0.12);
    c.drawRect(const Rect.fromLTWH(-6, -330, 12, 330), Paint()..color = const Color(0xFFE9E3D5));
    for (var i = 0; i < 8; i++) {
      c.drawArc(Rect.fromCircle(center: const Offset(0, -320), radius: 160), pi + i * pi / 8, pi / 8, true, Paint()..color = i.isEven ? const Color(0xFFFF5C8A) : const Color(0xFFFFFFFF));
    }
    c.drawArc(Rect.fromCircle(center: const Offset(0, -320), radius: 160), pi, pi, false, Paint()..color = const Color(0xFFB03A5B)..style = PaintingStyle.stroke..strokeWidth = 6);
    c.restore();
  }

  static void _palm(Canvas c, Offset base, double h, double dir, Random rng) {
    final top = Offset(base.dx + dir * 110, base.dy - h);
    final trunk = Path()
      ..moveTo(base.dx, base.dy)
      ..quadraticBezierTo(base.dx + dir * 10, base.dy - h * 0.6, top.dx, top.dy);
    c.drawPath(trunk, Paint()..color = const Color(0xFF7A4B26)..style = PaintingStyle.stroke..strokeWidth = 30..strokeCap = StrokeCap.round);
    c.drawPath(trunk, Paint()..color = const Color(0xFF9C6436)..style = PaintingStyle.stroke..strokeWidth = 14..strokeCap = StrokeCap.round);
    for (var i = 0; i < 7; i++) {
      final a = -pi * 0.95 + i * (pi * 0.9 / 6);
      final len = 210 + rng.nextDouble() * 60;
      final tip = top + Offset(cos(a) * len, sin(a) * len + 60);
      final ctrl = top + Offset(cos(a) * len * 0.55, sin(a) * len * 0.55 - 50);
      final n = Offset(-(tip.dy - top.dy), tip.dx - top.dx) / len * 26;
      final leaf = Path()
        ..moveTo(top.dx, top.dy)
        ..quadraticBezierTo(ctrl.dx + n.dx, ctrl.dy + n.dy, tip.dx, tip.dy)
        ..quadraticBezierTo(ctrl.dx - n.dx, ctrl.dy - n.dy, top.dx, top.dy)
        ..close();
      c.drawPath(leaf, Paint()..color = i.isEven ? const Color(0xFF2E9E4F) : const Color(0xFF3BB662));
    }
    c.drawCircle(top + const Offset(0, 8), 16, Paint()..color = const Color(0xFF7A4B26));
  }

  // ---- Halı saha: gece, projektör direkleri, tel örgü.
  static void _cageBackdrop(Canvas c, ViewGeom g, Random rng) {
    final fenceTop = g.crossbarY - 420;
    final fenceBottom = g.groundY - 130;
    // Uzak şehir ışıkları.
    final far = Paint()..color = const Color(0xFF0B1430);
    var x = -40.0;
    while (x < kWorldW + 40) {
      final w = 80 + rng.nextDouble() * 150;
      final top = fenceTop - 60 - rng.nextDouble() * 300;
      c.drawRect(Rect.fromLTRB(x, top, x + w, fenceTop + 40), far);
      for (var wy = top + 24; wy < fenceTop; wy += 36) {
        for (var wx = x + 12; wx < x + w - 14; wx += 26) {
          if (rng.nextDouble() < 0.3) c.drawRect(Rect.fromLTWH(wx, wy, 10, 14), Paint()..color = rng.nextBool() ? const Color(0xAAFFE08A) : const Color(0xAA8FD3FF));
        }
      }
      x += w + 8 + rng.nextDouble() * 24;
    }
    // Tel örgü arkası (koyu) ve projektör ışığı.
    c.drawRect(Rect.fromLTRB(-40, fenceTop, kWorldW + 40, fenceBottom), Paint()..color = const Color(0xFF0E1A33));
    for (final lx in [150.0, 1170.0]) {
      c.drawRect(Rect.fromLTWH(lx - 12, fenceTop - 520, 24, fenceBottom - fenceTop + 520), Paint()..color = const Color(0xFF3A4150));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(lx - 110, fenceTop - 600, 220, 90), const Radius.circular(8)), Paint()..color = const Color(0xFF2A303C));
      for (var i = 0; i < 4; i++) {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(lx - 98 + i * 52, fenceTop - 588, 42, 66), const Radius.circular(6)), Paint()..color = const Color(0xFFF4F9FF));
      }
      c.drawCircle(Offset(lx, fenceTop - 555), 200, Paint()..color = const Color(0x44CFE6FF)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80));
      final toward = lx < kWorldW / 2 ? 1.0 : -1.0;
      c.drawPath(
        Path()
          ..moveTo(lx - 110, fenceTop - 520)
          ..lineTo(lx + 110, fenceTop - 520)
          ..lineTo(lx + toward * 700 + 420, fenceBottom + 500)
          ..lineTo(lx + toward * 700 - 420, fenceBottom + 500)
          ..close(),
        Paint()..shader = ui.Gradient.linear(Offset(0, fenceTop - 520), Offset(0, fenceBottom + 300), const [Color(0x4CCFE6FF), Color(0x00CFE6FF)]),
      );
    }
    // Tel örgü: yeşil kaplı direkler + baklava kafes.
    final mesh = Paint()
      ..color = const Color(0x8CB8C4D0)
      ..strokeWidth = 2.5;
    const sp = 46.0;
    c.save();
    c.clipRect(Rect.fromLTRB(-40, fenceTop, kWorldW + 40, fenceBottom));
    for (var d = -kWorldH; d < kWorldW + kWorldH; d += sp) {
      c.drawLine(Offset(d, fenceTop), Offset(d + (fenceBottom - fenceTop), fenceBottom), mesh);
      c.drawLine(Offset(d, fenceBottom), Offset(d + (fenceBottom - fenceTop), fenceTop), mesh);
    }
    c.restore();
    for (var px = 60.0; px < kWorldW; px += 240) {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(px - 8, fenceTop - 10, 16, fenceBottom - fenceTop + 10), const Radius.circular(4)), Paint()..color = const Color(0xFF1E5F3A));
    }
    c.drawRect(Rect.fromLTRB(-40, fenceTop - 14, kWorldW + 40, fenceTop), Paint()..color = const Color(0xFF2A7A4C));
    c.drawRect(Rect.fromLTRB(-40, fenceBottom - 80, kWorldW + 40, fenceBottom), Paint()..shader = ui.Gradient.linear(Offset(0, fenceBottom - 80), Offset(0, fenceBottom), const [Color(0x00000000), Color(0x77000000)]));
  }

  // ---- Stadyum: çatı, tribün katları (kalabalık noktaları), reklam panoları.
  static void _stadiumBackdrop(Canvas c, ViewGeom g, Random rng) {
    final standTop = g.crossbarY - 780;
    final standBottom = g.groundY - 130;
    // Projektör kuleleri.
    for (final lx in [110.0, 1210.0]) {
      c.drawRect(Rect.fromLTWH(lx - 10, standTop - 380, 20, 400), Paint()..color = const Color(0xFF2A3044));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(lx - 90, standTop - 470, 180, 100), const Radius.circular(8)), Paint()..color = const Color(0xFF2A3044));
      for (var r = 0; r < 2; r++) {
        for (var i = 0; i < 4; i++) {
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(lx - 82 + i * 42, standTop - 462 + r * 46, 36, 40), const Radius.circular(5)), Paint()..color = const Color(0xFFFFFDF2));
        }
      }
      c.drawCircle(Offset(lx, standTop - 420), 260, Paint()..color = const Color(0x55FFF4CC)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100));
    }
    // Çatı.
    c.drawRect(Rect.fromLTRB(-40, standTop - 90, kWorldW + 40, standTop), Paint()..shader = ui.Gradient.linear(Offset(0, standTop - 90), Offset(0, standTop), const [Color(0xFF3A4260), Color(0xFF1B2032)]));
    for (var x = 20.0; x < kWorldW; x += 120) {
      c.drawRect(Rect.fromLTWH(x, standTop - 40, 60, 14), Paint()..color = const Color(0xFFFFF4CC));
    }
    // Tribün katları.
    final palette = [const Color(0xFFFF7A1A), const Color(0xFFFF9A3C), const Color(0xFF1B2A6B), const Color(0xFF2B3F8C), const Color(0xFFF5F7FF), const Color(0xFFC9D1E3), const Color(0xFFFFC53D)];
    final tiers = [
      Rect.fromLTRB(-40, standTop + 10, kWorldW + 40, standTop + 330),
      Rect.fromLTRB(-40, standTop + 380, kWorldW + 40, standBottom - 90),
    ];
    for (final t in tiers) {
      c.drawRect(t, Paint()..color = const Color(0xFF182046));
      for (var y = t.top + 10; y < t.bottom - 6; y += 15) {
        for (var x = t.left + 6; x < t.right; x += 15) {
          if (rng.nextDouble() < 0.12) continue;
          c.drawCircle(Offset(x + rng.nextDouble() * 6, y + rng.nextDouble() * 4), 5.5, Paint()..color = palette[rng.nextInt(palette.length)].withValues(alpha: 0.85));
        }
      }
      // Merdiven koridorları.
      for (final ax in [330.0, 660.0, 990.0]) {
        c.drawRect(Rect.fromLTWH(ax - 12, t.top, 24, t.height), Paint()..color = const Color(0xFF2E3A6E));
      }
      c.drawRect(Rect.fromLTRB(t.left, t.bottom, t.right, t.bottom + 30), Paint()..color = const Color(0xFF3B4568));
    }
    // Reklam panoları: sade renk blokları + oyunun adı.
    final ad = Rect.fromLTRB(-40, standBottom - 90, kWorldW + 40, standBottom);
    c.drawRect(ad, Paint()..color = const Color(0xFF141F45));
    var ax = -40.0;
    var i = 0;
    while (ax < kWorldW + 40) {
      final w = i % 3 == 1 ? 420.0 : 260.0;
      final rect = Rect.fromLTWH(ax, ad.top + 8, w - 10, ad.height - 16);
      final col = [const Color(0xFFFF7A1A), const Color(0xFFF5F7FF), const Color(0xFF35D5F2)][i % 3];
      c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), Paint()..color = col);
      if (i % 3 == 1) {
        final tp = TextPainter(
          text: const TextSpan(text: 'FRİKİK KRAL', style: TextStyle(fontFamily: 'TitilliumWeb', fontSize: 44, fontWeight: FontWeight.w700, color: Color(0xFF1B2A6B), letterSpacing: 6)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2));
      } else {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: rect.center, width: rect.width * 0.5, height: 14), const Radius.circular(7)), Paint()..color = i % 3 == 0 ? const Color(0xFF141F45) : const Color(0xFF0B1226));
      }
      ax += w;
      i++;
    }
    c.drawRect(Rect.fromLTRB(-40, standBottom - 40, kWorldW + 40, standBottom), Paint()..shader = ui.Gradient.linear(Offset(0, standBottom - 40), Offset(0, standBottom), const [Color(0x00000000), Color(0x55000000)]));
  }

  // ---- Zemin: sahneye göre asfalt / halı / çim; çizgiler; penaltı noktası.
  static void _ground(Canvas c, Stage stage, ViewGeom g, Random rng) {
    final top = g.groundY - 130;
    final area = Rect.fromLTRB(0, top, kWorldW, kWorldH);
    switch (stage) {
      case Stage.street:
        c.drawRect(area, Paint()..shader = ui.Gradient.linear(Offset(0, top), const Offset(0, kWorldH), const [Color(0xFF474B57), Color(0xFF2C3039)]));
        for (var i = 0; i < 90; i++) {
          c.drawOval(
            Rect.fromCenter(center: Offset(rng.nextDouble() * kWorldW, top + rng.nextDouble() * (kWorldH - top)), width: 80 + rng.nextDouble() * 200, height: 14 + rng.nextDouble() * 30),
            Paint()..color = Color.fromRGBO(255, 255, 255, 0.025 + rng.nextDouble() * 0.04),
          );
        }
        final crack = Paint()
          ..color = const Color(0x66141820)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;
        c.drawPath(Path()..moveTo(120, 2100)..lineTo(180, 2220)..lineTo(150, 2330)..lineTo(230, 2480), crack);
        c.drawPath(Path()..moveTo(1180, 1900)..lineTo(1120, 2010)..lineTo(1160, 2140), crack);
        _pitchLines(c, g, const Color(0xCCFFFFFF), 9, rough: true);
      case Stage.beach:
        c.drawRect(area, Paint()..shader = ui.Gradient.linear(Offset(0, top), const Offset(0, kWorldH), const [Color(0xFFF2DCA8), Color(0xFFE2C387)]));
        c.drawRect(Rect.fromLTWH(0, top, kWorldW, 70), Paint()..shader = ui.Gradient.linear(Offset(0, top), Offset(0, top + 70), const [Color(0xFFD5B67E), Color(0x00D5B67E)]));
        for (var i = 0; i < 700; i++) {
          c.drawCircle(Offset(rng.nextDouble() * kWorldW, top + rng.nextDouble() * (kWorldH - top)), 1.5 + rng.nextDouble() * 2.5, Paint()..color = Color.fromRGBO(150, 110, 50, 0.08 + rng.nextDouble() * 0.12));
        }
        _pitchLines(c, g, const Color(0xCCB98F4E), 9);
      case Stage.cage:
        c.drawRect(area, Paint()..shader = ui.Gradient.linear(Offset(0, top), const Offset(0, kWorldH), const [Color(0xFF2FA352), Color(0xFF1F7A3C)]));
        c.drawRect(area, Paint()..shader = ui.Gradient.radial(Offset(kWorldW / 2, g.groundY + 500), 1400, const [Color(0x33FFFFFF), Color(0x00FFFFFF)]));
        for (var y = top; y < kWorldH; y += 160) {
          c.drawRect(Rect.fromLTWH(0, y, kWorldW, 80), Paint()..color = const Color(0x12000000));
        }
        _pitchLines(c, g, const Color(0xF2FFFFFF), 11);
      case Stage.stadium:
        c.drawRect(area, Paint()..color = const Color(0xFF2F9C45));
        var y = top;
        var i = 0;
        var band = 90.0;
        while (y < kWorldH) {
          if (i.isEven) c.drawRect(Rect.fromLTWH(0, y, kWorldW, band), Paint()..color = const Color(0xFF37AD4E));
          y += band;
          band *= 1.12;
          i++;
        }
        c.drawRect(area, Paint()..shader = ui.Gradient.radial(Offset(kWorldW / 2, g.groundY + 300), 1500, const [Color(0x2EFFFFFF), Color(0x00FFFFFF)]));
        _pitchLines(c, g, const Color(0xFFFFFFFF), 12);
    }
    // Zemin başlangıcında ince gölge (arka plan ile birleşim).
    c.drawRect(Rect.fromLTWH(0, top, kWorldW, 40), Paint()..shader = ui.Gradient.linear(Offset(0, top), Offset(0, top + 40), const [Color(0x66000000), Color(0x00000000)]));
  }

  /// Kale çizgisi, ceza sahası (perspektifli yamuk), yay ve penaltı noktası.
  static void _pitchLines(Canvas c, ViewGeom g, Color color, double width, {bool rough = false}) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final cx = g.goalCenterX;
    final y0 = g.groundY;
    final spotY = g.ballRest.y + kBallDiameter / 2 * g.ballRestScale + 12;
    final boxBottom = y0 + 680;
    final halfTop = g.goalWidth / 2 + 250;
    final halfBottom = g.goalWidth / 2 + 520;
    void seg(Offset a, Offset b) {
      if (!rough) {
        c.drawLine(a, b, p);
        return;
      }
      // Tebeşir: kısa kesik parçalar, hafif titrek.
      final n = ((b - a).distance / 26).ceil();
      final rng = Random(a.dx.toInt() ^ b.dy.toInt());
      for (var i = 0; i < n; i++) {
        if (rng.nextDouble() < 0.12) continue;
        final t0 = i / n, t1 = (i + 0.75) / n;
        final j = Offset(rng.nextDouble() * 3 - 1.5, rng.nextDouble() * 3 - 1.5);
        c.drawLine(Offset.lerp(a, b, t0)! + j, Offset.lerp(a, b, t1)! + j, p);
      }
    }

    seg(Offset(0, y0), Offset(kWorldW, y0));
    seg(Offset(cx - halfTop, y0), Offset(cx - halfBottom, boxBottom));
    seg(Offset(cx + halfTop, y0), Offset(cx + halfBottom, boxBottom));
    seg(Offset(cx - halfBottom, boxBottom), Offset(cx + halfBottom, boxBottom));
    // Kale sahası (küçük).
    seg(Offset(cx - g.goalWidth / 2 - 60, y0), Offset(cx - g.goalWidth / 2 - 90, y0 + 230));
    seg(Offset(cx + g.goalWidth / 2 + 60, y0), Offset(cx + g.goalWidth / 2 + 90, y0 + 230));
    seg(Offset(cx - g.goalWidth / 2 - 90, y0 + 230), Offset(cx + g.goalWidth / 2 + 90, y0 + 230));
    c.drawCircle(Offset(cx, spotY), width * 0.9, Paint()..color = color);
  }

  /// Kale: direkler, üst direk, derinlikli file (arka panel + yan/üst paneller).
  static void _goal(Canvas c, Stage stage, ViewGeom g) {
    const post = 24.0;
    final l = g.goalLeft, r = g.goalRight, top = g.crossbarY, bottom = g.groundY;
    final back = Rect.fromLTRB(l + 72, top + 96, r - 72, bottom - 52);
    // File panelleri (yarı saydam koyu dolgu → derinlik).
    final fill = Paint()..color = const Color(0x2E0B1226);
    final side = Path()..moveTo(l, top)..lineTo(back.left, back.top)..lineTo(back.left, back.bottom)..lineTo(l, bottom)..close();
    final side2 = Path()..moveTo(r, top)..lineTo(back.right, back.top)..lineTo(back.right, back.bottom)..lineTo(r, bottom)..close();
    final roof = Path()..moveTo(l, top)..lineTo(r, top)..lineTo(back.right, back.top)..lineTo(back.left, back.top)..close();
    for (final p in [side, side2, roof]) {
      c.drawPath(p, fill);
    }
    c.drawRect(back, fill);
    // Kafes: tüm panelleri kapsayan alanı kırp, baklava çizgileri.
    final netColor = stage == Stage.street ? const Color(0xB3FFFFFF) : const Color(0xD9FFFFFF);
    final mesh = Paint()
      ..color = netColor
      ..strokeWidth = 2.6;
    c.save();
    c.clipPath(Path()..addRect(Rect.fromLTRB(l, top, r, bottom)));
    for (var d = -1200.0; d < 1200; d += 30) {
      c.drawLine(Offset(l + d, top), Offset(l + d + (bottom - top), bottom), mesh);
      c.drawLine(Offset(l + d, bottom), Offset(l + d + (bottom - top), top), mesh);
    }
    c.restore();
    // Panel kenar çizgileri.
    final edge = Paint()
      ..color = netColor
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    c.drawRect(back, edge);
    c.drawLine(Offset(l, top), Offset(back.left, back.top), edge);
    c.drawLine(Offset(r, top), Offset(back.right, back.top), edge);
    c.drawLine(Offset(l, bottom), Offset(back.left, back.bottom), edge);
    c.drawLine(Offset(r, bottom), Offset(back.right, back.bottom), edge);
    // Direkler.
    final postColor = stage == Stage.street ? const Color(0xFFD6DAE3) : const Color(0xFFFFFFFF);
    final shade = stage == Stage.street ? const Color(0xFF8E939F) : const Color(0xFFB9C1D3);
    void bar(Rect rect, {bool vertical = true}) {
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      c.drawRRect(rr.shift(const Offset(6, 6)), Paint()..color = const Color(0x44000000));
      c.drawRRect(
        rr,
        Paint()
          ..shader = ui.Gradient.linear(
            vertical ? rect.topLeft : rect.topLeft,
            vertical ? rect.topRight : rect.bottomLeft,
            [postColor, shade],
            const [0.35, 1],
          ),
      );
    }

    bar(Rect.fromLTWH(l - post, top - post, post, bottom - top + post + 10));
    bar(Rect.fromLTWH(r, top - post, post, bottom - top + post + 10));
    bar(Rect.fromLTWH(l - post, top - post, r - l + 2 * post, post), vertical: false);
    if (stage == Stage.street) {
      // Pas lekeleri.
      final rust = Paint()..color = const Color(0x8C8A4A2A);
      for (final o in [Offset(l - 12, top + 120), Offset(r + 12, top + 200), Offset(r + 12, bottom - 90), Offset(l + 120, top - 12)]) {
        c.drawOval(Rect.fromCenter(center: o, width: 22, height: 40), rust);
      }
    }
  }

  /// Skor tabelası: lacivert panel, sahne rengi çerçeve, top / kupa ikonları.
  static void _board(Canvas c, Stage stage, ViewGeom g) {
    final b = g.boardRect;
    final accent = stage.accent;
    // Taşıyıcı direkler.
    for (final x in [b.left + 60, b.right - 60]) {
      c.drawRect(Rect.fromLTWH(x - 9, b.bottom - 10, 18, g.crossbarY - 300 - b.bottom + 40), Paint()..color = const Color(0xFF2A2E38));
    }
    final rr = RRect.fromRectAndRadius(b, const Radius.circular(22));
    c.drawRRect(rr.shift(const Offset(0, 14)), Paint()..color = const Color(0x66000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    c.drawRRect(rr, Paint()..shader = ui.Gradient.linear(b.topLeft, b.bottomLeft, const [Color(0xFF162049), Color(0xFF0B1226)]));
    c.drawRRect(rr, Paint()..color = accent..style = PaintingStyle.stroke..strokeWidth = 8);
    c.drawRRect(rr.deflate(8), Paint()..color = const Color(0x33FFFFFF)..style = PaintingStyle.stroke..strokeWidth = 2);
    // Satır arka planları.
    for (final row in [g.scoreRect, g.bestRect]) {
      final rowRect = Rect.fromLTRB(b.left + 26, row.top - 12, row.right + 20, row.bottom + 12);
      c.drawRRect(RRect.fromRectAndRadius(rowRect, const Radius.circular(12)), Paint()..color = const Color(0x22000000));
    }
    // İkonlar.
    final iconX = b.left + 68;
    _ballIcon(c, Offset(iconX, g.scoreRect.center.dy), g.scoreRect.height * 0.42);
    _trophyIcon(c, Offset(iconX, g.bestRect.center.dy), g.bestRect.height * 0.46, accent);
    // Sahne etiketi (alt şerit).
    final tp = TextPainter(
      text: TextSpan(text: stage.label, style: TextStyle(fontFamily: 'TitilliumWeb', fontSize: 30, fontWeight: FontWeight.w700, color: accent.withValues(alpha: 0.9), letterSpacing: 8)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(b.center.dx - tp.width / 2, b.bottom - tp.height - 10));
  }

  static void _ballIcon(Canvas c, Offset o, double r) {
    c.drawCircle(o, r, Paint()..color = const Color(0xFFF5F7FF));
    final dark = Paint()..color = const Color(0xFF1E2230);
    c.drawCircle(o, r * 0.28, dark);
    for (var i = 0; i < 5; i++) {
      final a = -pi / 2 + i * 2 * pi / 5;
      c.drawCircle(o + Offset(cos(a), sin(a)) * r * 0.68, r * 0.2, dark);
    }
    c.drawCircle(o, r, Paint()..color = const Color(0xFF1E2230)..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  static void _trophyIcon(Canvas c, Offset o, double r, Color color) {
    final p = Paint()..color = color;
    final cup = Path()
      ..moveTo(o.dx - r * 0.7, o.dy - r)
      ..lineTo(o.dx + r * 0.7, o.dy - r)
      ..lineTo(o.dx + r * 0.5, o.dy + r * 0.15)
      ..quadraticBezierTo(o.dx, o.dy + r * 0.6, o.dx - r * 0.5, o.dy + r * 0.15)
      ..close();
    c.drawPath(cup, p);
    c.drawRect(Rect.fromCenter(center: Offset(o.dx, o.dy + r * 0.5), width: r * 0.2, height: r * 0.4), p);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(o.dx, o.dy + r * 0.85), width: r * 1.0, height: r * 0.28), const Radius.circular(4)), p);
    final handle = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.16;
    c.drawArc(Rect.fromCenter(center: Offset(o.dx - r * 0.75, o.dy - r * 0.5), width: r * 0.6, height: r * 0.8), pi / 2, pi, false, handle);
    c.drawArc(Rect.fromCenter(center: Offset(o.dx + r * 0.75, o.dy - r * 0.5), width: r * 0.6, height: r * 0.8), -pi / 2, pi, false, handle);
  }

  /// Sağ üst pause: cam daire, iki çubuk.
  static void _pauseButton(Canvas c) {
    final o = kPauseRect.center;
    const r = 92.0;
    c.drawCircle(o.translate(0, 8), r, Paint()..color = const Color(0x55000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    c.drawCircle(o, r, Paint()..color = const Color(0x8C0B1226));
    c.drawCircle(o, r, Paint()..color = const Color(0xB3FFFFFF)..style = PaintingStyle.stroke..strokeWidth = 6);
    final bar = Paint()..color = const Color(0xFFFFFFFF);
    for (final dx in [-24.0, 24.0]) {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o.translate(dx, 0), width: 22, height: 80), const Radius.circular(8)), bar);
    }
  }
}
