import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart' show TextStyle, FontWeight;

import 'geometry.dart';
import 'kick_legend_game.dart';

double _easeOut(double t) => 1 - pow(1 - t, 3).toDouble();

/// 7-segment LED rakamlar + kalpler (arka plandaki tabela üzerine çizilir).
class Scoreboard extends PositionComponent with HasGameReference<KickLegendGame> {
  Scoreboard() : super(priority: 30);

  static const Color white = Color(0xFFFFFFFF);
  static const Color yellow = Color(0xFFFFE561);

  // a b c d e f g  ->  bit 6..0
  static const List<int> _digits = [
    0x7E, 0x30, 0x6D, 0x79, 0x33, 0x5B, 0x5F, 0x70, 0x7F, 0x7B,
  ];

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
      // Yeni kaybedilen kalp kısa süre yanıp söner.
      final justLost = !alive && i == game.lives && _heartFlash < 1;
      final blinkOn = justLost && ((_heartFlash * 10).floor() % 2 == 0);
      final paint = Paint();
      if (!alive && !blinkOn) {
        paint.colorFilter = const ColorFilter.mode(Color(0xFF2E2E2E), BlendMode.srcIn);
      }
      _heart.render(
        canvas,
        position: c,
        size: Vector2(57 * hs, 50 * hs),
        anchor: Anchor.center,
        overridePaint: paint,
      );
    }
  }

  void _drawRow(Canvas canvas, Rect rect, int value, Color color, double skew, double pulse) {
    final text = value.clamp(0, 999999).toString().padLeft(6, '0');
    final cellW = rect.width / 6;
    final dw = cellW * 0.74;
    final h = rect.height;
    canvas.save();
    canvas.translate(rect.left, rect.top);
    if (skew != 0) canvas.skew(0, skew);
    if (pulse != 1) {
      canvas.translate(rect.width / 2, h / 2);
      canvas.scale(pulse);
      canvas.translate(-rect.width / 2, -h / 2);
    }
    for (var i = 0; i < 6; i++) {
      final x = i * cellW + (cellW - dw) / 2;
      canvas.save();
      canvas.translate(x, 0);
      _drawDigit(canvas, int.parse(text[i]), dw, h, color);
      canvas.restore();
    }
    canvas.restore();
  }

  void _drawDigit(Canvas canvas, int d, double dw, double h, Color color) {
    final t = h * 0.17;
    final on = Paint()..color = color;
    final off = Paint()..color = color.withAlpha(0x16);
    final r = Radius.circular(t * 0.3);
    final segs = <Rect>[
      Rect.fromLTWH(t * 0.55, 0, dw - 1.1 * t, t), // a
      Rect.fromLTWH(dw - t, t * 0.55, t, h / 2 - t * 0.8), // b
      Rect.fromLTWH(dw - t, h / 2 + t * 0.25, t, h / 2 - t * 0.8), // c
      Rect.fromLTWH(t * 0.55, h - t, dw - 1.1 * t, t), // d
      Rect.fromLTWH(0, h / 2 + t * 0.25, t, h / 2 - t * 0.8), // e
      Rect.fromLTWH(0, t * 0.55, t, h / 2 - t * 0.8), // f
      Rect.fromLTWH(t * 0.55, h / 2 - t / 2, dw - 1.1 * t, t), // g
    ];
    final bits = _digits[d];
    for (var i = 0; i < 7; i++) {
      final lit = (bits >> (6 - i)) & 1 == 1;
      canvas.drawRRect(RRect.fromRectAndRadius(segs[i].deflate(1.2), r), lit ? on : off);
    }
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
    if (kPauseRect.contains(event.localPosition.toOffset())) {
      game.pause();
    }
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
    if (_samples.length > 8) _samples.removeAt(0);
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
    // Yukarı doğru, yeterince uzun bir kaydırma olmalı.
    if (vec.y > -60 || vec.length < 80) return;

    // Son ~80 ms'nin hızı (px/s).
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
    // Bırakma noktası + hız payı = iniş noktası.
    final landing = end.$1 + (speed > 0 ? vel.normalized() * speed * 0.085 : Vector2.zero());
    game.kick(landing);
  }
}

/// Pause ve oyun sonu perdesi.
class OverlayLayer extends PositionComponent
    with HasGameReference<KickLegendGame>, TapCallbacks {
  OverlayLayer() : super(size: Vector2(kWorldW, kWorldH), priority: 60);

  String? _mode;
  double _t = 0;

  static final _title = TextPaint(
    style: const TextStyle(
      fontSize: 150,
      fontWeight: FontWeight.w900,
      color: Color(0xFFFFB13B),
      letterSpacing: 4,
    ),
  );
  static final _sub = TextPaint(
    style: const TextStyle(
      fontSize: 64,
      fontWeight: FontWeight.w700,
      color: Color(0xFFFFFFFF),
    ),
  );
  static final _hint = TextPaint(
    style: const TextStyle(
      fontSize: 48,
      fontWeight: FontWeight.w600,
      color: Color(0xCCFFFFFF),
    ),
  );

  void showPaused() {
    _mode = 'paused';
    _t = 0;
  }

  void showGameOver() {
    _mode = 'gameover';
    _t = 0;
  }

  void hide() => _mode = null;

  @override
  bool containsLocalPoint(Vector2 point) => _mode != null && super.containsLocalPoint(point);

  @override
  void onTapUp(TapUpEvent event) {
    if (_t < 0.35) return; // yanlışlıkla anında kapanmasın
    if (_mode == 'paused') {
      game.resume();
    } else if (_mode == 'gameover') {
      game.restart();
    }
  }

  @override
  void update(double dt) => _t += dt;

  @override
  void render(Canvas canvas) {
    if (_mode == null) return;
    final k = _easeOut((_t / 0.25).clamp(0, 1));
    canvas.drawRect(size.toRect(), Paint()..color = Color.fromRGBO(0, 0, 0, 0.6 * k));
    final cy = kWorldH * 0.42;
    canvas.save();
    canvas.translate(kWorldW / 2, cy);
    canvas.scale(0.85 + 0.15 * k);
    if (_mode == 'paused') {
      _title.render(canvas, 'PAUSED', Vector2(0, -60), anchor: Anchor.center);
      _hint.render(canvas, 'TAP TO CONTINUE', Vector2(0, 120), anchor: Anchor.center);
    } else {
      _title.render(canvas, 'GAME OVER', Vector2(0, -160), anchor: Anchor.center);
      _sub.render(canvas, 'SCORE  ${game.score}', Vector2(0, 20), anchor: Anchor.center);
      _sub.render(canvas, 'BEST  ${game.best}', Vector2(0, 110), anchor: Anchor.center);
      _hint.render(canvas, 'TAP TO PLAY AGAIN', Vector2(0, 260), anchor: Anchor.center);
    }
    canvas.restore();
  }
}
