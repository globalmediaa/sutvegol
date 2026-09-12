import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flame/events.dart';

import 'sut_ve_gol_game.dart';
import 'geometry.dart';
import 'led.dart';
import 'scene_art.dart';

/// 7-segment LED rakamlar + kalpler (arka plandaki tabela üzerine çizilir).
class Scoreboard extends PositionComponent with HasGameReference<SutVeGolGame> {
  Scoreboard() : super(priority: 30);

  static const Color white = Color(0xFFF5F7FF);
  static const Color amber = Color(0xFFFFB13B);
  static const Color heartRed = Color(0xFFFF3B5C);

  double _scoreFlash = 1;
  double _heartFlash = 1;

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
    _drawRow(canvas, g.scoreRect, game.score, white, pulse);
    _drawRow(canvas, g.bestRect, game.best, amber, 1);

    final hs = g.heartScale;
    for (var i = 0; i < 3; i++) {
      final c = g.heartFirst + Vector2(0, g.heartGap * i);
      final alive = i < game.lives;
      final justLost = !alive && i == game.lives && _heartFlash < 1;
      final blinkOn = justLost && ((_heartFlash * 10).floor() % 2 == 0);
      canvas.save();
      canvas.translate(c.x, c.y);
      SceneArt.paintHeart(
        canvas,
        54 * hs,
        48 * hs,
        heartRed,
        dead: !alive && !blinkOn,
      );
      canvas.restore();
    }
  }

  void _drawRow(
    Canvas canvas,
    Rect rect,
    int value,
    Color color,
    double pulse,
  ) {
    canvas.save();
    canvas.translate(rect.left, rect.top);
    if (pulse != 1) {
      canvas.translate(rect.width / 2, rect.height / 2);
      canvas.scale(pulse);
      canvas.translate(-rect.width / 2, -rect.height / 2);
    }
    drawSevenSegmentRow(
      canvas,
      Rect.fromLTWH(0, 0, rect.width, rect.height),
      value,
      color,
    );
    canvas.restore();
  }
}

/// Tüm ekranı kaplayan dokunma katmanı: kaydırma = şut, sağ üst = pause.
class InputLayer extends PositionComponent
    with HasGameReference<SutVeGolGame>, DragCallbacks, TapCallbacks {
  InputLayer() : super(size: Vector2(kWorldW, kWorldH), priority: 40);

  Vector2? _start;
  final List<(Vector2, int)> _samples = [];
  int? _pointer;

  void cancelGesture() {
    _pointer = null;
    _start = null;
    _samples.clear();
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (kPauseRect.contains(event.localPosition.toOffset())) game.pause();
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (_pointer != null || game.state != GameState.idle) return;
    if (kPauseRect.contains(event.localPosition.toOffset())) return;
    _pointer = event.pointerId;
    _start = event.localPosition.clone();
    _samples
      ..clear()
      ..add((
        _start!.clone(),
        (event.raw.sourceTimeStamp ?? Duration.zero).inMicroseconds,
      ));
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    if (_start == null || event.pointerId != _pointer) return;
    // Flame localStartPosition zaten mevcut globalPosition değeridir;
    // localEndPosition kullanmak son deltayı ikinci kez ekler.
    _samples.add((
      event.localStartPosition.clone(),
      event.timestamp.inMicroseconds,
    ));
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (event.pointerId == _pointer) _finish();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    if (event.pointerId == _pointer) cancelGesture();
  }

  void _finish() {
    final start = _start;
    _start = null;
    _pointer = null;
    if (start == null || _samples.length < 2 || game.state != GameState.idle) {
      return;
    }
    final end = _samples.last;
    final vec = end.$1 - start;
    if (vec.y > -60 || vec.length < 80) return;

    // Son ~90 ms'nin hızı (px/s) → güç; uzunluk da katkı verir.
    var early = _samples.first;
    for (final s in _samples) {
      if (end.$2 - s.$2 <= 90000) {
        early = s;
        break;
      }
    }
    // Seyrek olaylarda tek örnekten sıfır hız üretme.
    if (early == end) early = _samples[_samples.length - 2];
    final dtSeconds = max(0.001, (end.$2 - early.$2) / 1000000);
    final vel = (end.$1 - early.$1) / dtSeconds;
    final speed = vel.length.clamp(0, 9000).toDouble();
    // Dünya px/s (ekranın 3 katı): yavaş ~1500, normal ~3000-4000, sert ~6000+.
    final speedNorm = ((speed - 1000) / 3800).clamp(0.0, 1.0);
    final lenNorm = ((vec.length - 200) / 1000).clamp(0.0, 1.0);
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
