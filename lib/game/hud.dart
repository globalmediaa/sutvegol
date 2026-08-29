import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart' show TextStyle, FontWeight;

import 'geometry.dart';
import 'kick_legend_game.dart';
import 'led.dart';

double _easeOut(double t) => 1 - pow(1 - t, 3).toDouble();

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

    // Son ~90 ms'nin hızı (px/s).
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
    final landing = end.$1 + (speed > 0 ? vel.normalized() * speed * 0.085 : Vector2.zero());

    // Falso: parmak yolunun düz çizgiden en büyük işaretli sapması.
    final chord = vec;
    final len = chord.length;
    var maxDev = 0.0;
    for (final s in _samples) {
      final d = s.$1 - start;
      final cross = (d.x * chord.y - d.y * chord.x) / len; // + = sağa bombe
      if (cross.abs() > maxDev.abs()) maxDev = cross;
    }
    // Ekranda yukarı giden kaydırmada "sağa bombe" = cross negatif; işaret düzelt.
    final curve = -maxDev * 1.4;
    game.kick(landing, curve);
  }
}

/// Pause perdesi (game over Flutter tarafında).
class OverlayLayer extends PositionComponent
    with HasGameReference<KickLegendGame>, TapCallbacks {
  OverlayLayer() : super(size: Vector2(kWorldW, kWorldH), priority: 60);

  bool _visible = false;
  double _t = 0;

  static final _title = TextPaint(
    style: const TextStyle(
      fontSize: 150,
      fontWeight: FontWeight.w700,
      fontFamily: 'TitilliumWeb',
      color: Color(0xFFFFB13B),
      letterSpacing: 4,
    ),
  );
  static final _hint = TextPaint(
    style: const TextStyle(
      fontSize: 48,
      fontWeight: FontWeight.w600,
      fontFamily: 'TitilliumWeb',
      color: Color(0xCCFFFFFF),
    ),
  );

  void showPaused() {
    _visible = true;
    _t = 0;
  }

  void hide() => _visible = false;

  @override
  bool containsLocalPoint(Vector2 point) => _visible && super.containsLocalPoint(point);

  @override
  void onTapUp(TapUpEvent event) {
    if (_t < 0.35) return;
    game.resume();
  }

  @override
  void update(double dt) => _t += dt;

  @override
  void render(Canvas canvas) {
    if (!_visible) return;
    final k = _easeOut((_t / 0.25).clamp(0, 1));
    canvas.drawRect(size.toRect(), Paint()..color = Color.fromRGBO(6, 36, 56, 0.75 * k));
    canvas.save();
    canvas.translate(kWorldW / 2, kWorldH * 0.42);
    canvas.scale(0.85 + 0.15 * k);
    _title.render(canvas, 'PAUSED', Vector2(0, -60), anchor: Anchor.center);
    _hint.render(canvas, 'TAP TO CONTINUE', Vector2(0, 120), anchor: Anchor.center);
    canvas.restore();
  }
}
