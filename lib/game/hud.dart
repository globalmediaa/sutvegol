import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flame/events.dart';

import 'geometry.dart';
import 'kick_legend_game.dart';
import 'led.dart';

/// 7-segment LED rakamlar + kalpler (arka plandaki tabela üzerine çizilir).
class Scoreboard extends PositionComponent with HasGameReference<KickLegendGame> {
  Scoreboard() : super(priority: 30);

  static const Color white = Color(0xFFFFFFFF);
  static const Color yellow = Color(0xFFFFE561);

  late Sprite _heart;
  double _scoreFlash = 1;
  double _heartFlash = 1;

  @override
  Future<void> onLoad() async {
    _heart = Sprite(game.images.fromCache('heart.png'));
  }

  void flashScore() => _scoreFlash = 0;
  void flashHeart() => _heartFlash = 0;

  @override
  void update(double dt) {
    _scoreFlash = min(1, _scoreFlash + dt / 0.3);
    _heartFlash = min(1, _heartFlash + dt / 0.5);
  }

  @override
  void render(Canvas canvas) {
    final g = game.view;
    final pulse = _scoreFlash < 1 ? 1 + 0.14 * sin(_scoreFlash * pi) : 1.0;
    _drawRow(canvas, g.scoreRect, game.score, white, g.skew, pulse);
    _drawRow(canvas, g.bestRect, game.best, yellow, g.skew, 1);

    final hs = g.heartScale;
    for (var i = 0; i < 3; i++) {
      final c = g.heartFirst + Vector2(0, g.heartGap * i);
      final alive = i < game.lives;
      final justLost = !alive && i == game.lives && _heartFlash < 1;
      final blinkOn = justLost && ((_heartFlash * 10).floor() % 2 == 0);
      final paint = Paint();
      if (!alive && !blinkOn) {
        paint.colorFilter = const ColorFilter.mode(Color(0xFF2E2E2E), BlendMode.srcIn);
      }
      _heart.render(canvas, position: c, size: Vector2(57 * hs, 50 * hs), anchor: Anchor.center, overridePaint: paint);
    }
  }

  void _drawRow(Canvas canvas, Rect rect, int value, Color color, double skew, double pulse) {
    canvas.save();
    canvas.translate(rect.left, rect.top);
    if (skew != 0) canvas.skew(0, skew);
    if (pulse != 1) {
      canvas.translate(rect.width / 2, rect.height / 2);
      canvas.scale(pulse);
      canvas.translate(-rect.width / 2, -rect.height / 2);
    }
    drawSevenSegmentRow(canvas, Rect.fromLTWH(0, 0, rect.width, rect.height), value, color);
    canvas.restore();
  }
}

/// Tüm ekranı kaplayan dokunma katmanı: kaydırma = şut, sağ üst = pause.
class InputLayer extends PositionComponent
    with HasGameReference<KickLegendGame>, DragCallbacks, TapCallbacks {
  InputLayer() : super(size: Vector2(kWorldW, kWorldH), priority: 40);

  Vector2? _start;
  final List<(Vector2, int)> _samples = [];
  final Stopwatch _sw = Stopwatch()..start();

  @override
  void onTapUp(TapUpEvent event) {
    if (kPauseRect.contains(event.localPosition.toOffset())) game.pause();
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (game.state != GameState.idle) {
      _start = null;
      return;
    }
    _start = event.localPosition.clone();
    _samples
      ..clear()
      ..add((_start!.clone(), _sw.elapsedMilliseconds));
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    if (_start == null) return;
    _samples.add((event.localEndPosition.clone(), _sw.elapsedMilliseconds));
    if (_samples.length > 80) _samples.removeAt(0);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _finish();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _start = null;
  }

  void _finish() {
    final start = _start;
    _start = null;
    if (start == null || _samples.length < 2 || game.state != GameState.idle) return;
    final end = _samples.last;
    final vec = end.$1 - start;
    if (vec.y > -60 || vec.length < 80) return;

    // Son ~90 ms'nin hızı (px/s) → güç; uzunluk da katkı verir.
    var early = _samples.first;
    for (final s in _samples) {
      if (end.$2 - s.$2 <= 90) {
        early = s;
        break;
      }
    }
    final dtMs = max(1, end.$2 - early.$2);
    final vel = (end.$1 - early.$1) / (dtMs / 1000);
    final speed = vel.length.clamp(0, 9000).toDouble();
    // Dünya px/s (ekranın 3 katı): yavaş ~1500, normal ~3000-4000, sert ~6000+.
    final speedNorm = ((speed - 1300) / 4600).clamp(0.0, 1.0);
    final lenNorm = ((vec.length - 250) / 1200).clamp(0.0, 1.0);
    final power = 0.75 * speedNorm + 0.25 * lenNorm;

    // Falso: parmak yolunun kirişten en büyük işaretli sapması ve konumu.
    final n = Vector2(-vec.y, vec.x)..normalize();
    final len = vec.length;
    var dev = 0.0;
    var tMax = 0.5;
    for (final s in _samples) {
      final d = s.$1 - start;
      final off = d.dot(n);
      if (off.abs() > dev.abs()) {
        dev = off;
        tMax = (d.dot(vec) / (len * len)).clamp(0.0, 1.0);
      }
    }
    if (dev.abs() < 12) dev = 0; // titreme
    game.kick(vec, dev, tMax, power);
  }
}

