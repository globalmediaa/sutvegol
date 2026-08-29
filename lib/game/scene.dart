import 'dart:math';
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextStyle, FontWeight;

import 'geometry.dart';
import 'kick_legend_game.dart';

double _easeOut(double t) => 1 - pow(1 - t, 3).toDouble();
double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Arka plan: geniş / yakın sahne, çapraz geçiş.
class Background extends PositionComponent with HasGameReference<KickLegendGame> {
  Background() : super(size: Vector2(kWorldW, kWorldH), priority: 0);

  late Sprite _current;
  Sprite? _next;
  double _fade = 0;
  static const double _fadeDur = 0.4;

  @override
  Future<void> onLoad() async {
    _current = Sprite(game.images.fromCache(game.view.bg));
  }

  void crossfadeTo(String asset) {
    _next = Sprite(game.images.fromCache(asset));
    _fade = 0;
  }

  @override
  void update(double dt) {
    if (_next != null) {
      _fade += dt / _fadeDur;
      if (_fade >= 1) {
        _current = _next!;
        _next = null;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    _current.render(canvas, size: size);
    if (_next != null) {
      final k = _easeOut(_fade.clamp(0, 1));
      _next!.render(
        canvas,
        size: size,
        overridePaint: Paint()..color = Color.fromRGBO(255, 255, 255, k),
      );
    }
  }
}

enum BallPhase { hidden, entering, idle, flying, dropping, netting, out }

/// Oyuncunun topu: soldan yuvarlanarak gelir, bekler, fırlatılır, kaleye
/// küçülerek (hafif muz eğrisiyle) uçar; direğe çarparsa düşer.
class Ball extends PositionComponent with HasGameReference<KickLegendGame> {
  Ball() : super(anchor: Anchor.center, priority: 20);

  static const double flightDur = 0.6;
  static const double enterDur = 0.55;
  static const double dropDur = 0.45;

  late Sprite _sprite;
  BallPhase phase = BallPhase.hidden;
  double _t = 0;
  double _angle = 0;
  double _spin = 0;

  late Vector2 _start;
  late double _startScale;
  late double _xEnd;
  late double _hEnd;
  late double _lob;
  late Vector2 _ctrl; // bezier kontrol noktası (parmağın ilk yönü)

  // Düşme (direk/üst direk).
  late Vector2 _dropFrom;
  late Vector2 _dropTo;

  // Gölge için yer izi.
  double _groundY = 0;
  double _height = 0;

  double get radius => kBallDiameter / 2 * scale.x;
  double get goalRadius => kBallDiameter / 2 * game.view.ballGoalScale;

  @override
  Future<void> onLoad() async {
    _sprite = Sprite(game.images.fromCache('ball.png'));
    size = Vector2.all(kBallDiameter);
  }

  /// Sol kenardan yuvarlanarak gelir.
  void enter() {
    final g = game.view;
    phase = BallPhase.entering;
    _t = 0;
    scale = Vector2.all(g.ballRestScale);
    position = Vector2(-140, g.ballRest.y);
    _groundY = position.y;
    _height = 0;
  }

  /// Parmak yolunun şekli topun yer izine ölçeklenir:
  /// [chord] başlangıç→bırakma vektörü (y<0), [dev] yolun kirişten en büyük
  /// işaretli sapması (px, + = kirişin sağ normali yönünde), [tMax] o sapmanın
  /// kiriş üzerindeki konumu (0..1), [power] 0..1 yükseklik.
  void kick(Vector2 chord, double dev, double tMax, double power) {
    final g = game.view;
    phase = BallPhase.flying;
    _t = 0;
    _start = position.clone();
    _startScale = scale.x;
    final trackEndY = g.groundY - goalRadius;
    final c = chord.clone();
    if (c.y > -40) c.y = -40;
    final k = (_start.y - trackEndY) / (-c.y); // parmak → saha ölçeği
    final end = _start + c * k;
    _xEnd = end.x.clamp(-220.0, kWorldW + 220.0);
    _hEnd = power.clamp(0, 1) * g.goalHeight * 1.3;
    _lob = 50 + _hEnd * 0.1;
    // Kontrol noktası: kiriş üzerinde tMax'ta, normal yönünde sapma × ölçek.
    final n = Vector2(-c.y, c.x)..normalize();
    final tm = tMax.clamp(0.2, 0.8);
    _ctrl = _start + c * (k * tm) + n * (dev * k * 2.4);
    final midX = (_start.x + _xEnd) / 2;
    _ctrl.x = midX + (_ctrl.x - midX).clamp(-480.0, 480.0);
    _spin = 14 + dev.sign * 10;
  }

  /// Fileye/hedefe çarptıktan sonra ağ boyunca yere düşüş (derine küçülerek).
  void settleInNet(Vector2 from, Vector2 to, double toScale) {
    phase = BallPhase.netting;
    _t = 0;
    _dropFrom = from.clone();
    _dropTo = to.clone();
    _netStartScale = scale.x;
    _netEndScale = toScale;
  }

  /// Kale dışına / üstünden: görüş dışına devam eder.
  void flyOut(Vector2 dir) {
    phase = BallPhase.out;
    _t = 0;
    _dropFrom = position.clone();
    _dropTo = position + dir * 500;
  }

  double _netStartScale = 0.2;
  double _netEndScale = 0.17;

  /// Direk/üst direkten yere düşme.
  void drop(Vector2 from, Vector2 to) {
    phase = BallPhase.dropping;
    _t = 0;
    _dropFrom = from.clone();
    _dropTo = to.clone();
  }

  void hide() => phase = BallPhase.hidden;

  @override
  void update(double dt) {
    final g = game.view;
    switch (phase) {
      case BallPhase.hidden:
        break;
      case BallPhase.entering:
        _t += dt;
        final k = _easeOut((_t / enterDur).clamp(0, 1));
        final x = _lerp(-140, g.ballRest.x, k);
        _angle += (x - position.x) / radius;
        position = Vector2(x, g.ballRest.y);
        _groundY = position.y;
        if (_t >= enterDur) {
          phase = BallPhase.idle;
          position = g.ballRest.clone();
          game.onBallReady();
        }
      case BallPhase.idle:
        break;
      case BallPhase.flying:
        _t += dt;
        final z = (_t / flightDur).clamp(0.0, 1.0);
        final trackEndY = g.groundY - goalRadius;
        // Perspektif: ekranda hızlı başlar, kaleye yaklaşırken yavaşlar;
        // top başta yavaş, sonda hızlı küçülür (videodan ölçüldü).
        final sProg = 1 - pow(1 - z, 1.7).toDouble();
        final u = 1 - sProg;
        final gx = u * u * _start.x + 2 * u * sProg * _ctrl.x + sProg * sProg * _xEnd;
        final gy = u * u * _start.y + 2 * u * sProg * _ctrl.y + sProg * sProg * trackEndY;
        _groundY = gy;
        _height = _hEnd * sProg + _lob * sin(pi * sProg);
        final shrink = pow(z, 1.56).toDouble();
        scale = Vector2.all(_lerp(_startScale, g.ballGoalScale, shrink));
        position = Vector2(gx, _groundY - _height);
        _angle += _spin * dt;
        if (z >= 1) {
          final end = position.clone();
          final r = radius;
          phase = BallPhase.hidden;
          game.resolveShot(end, r);
        }
      case BallPhase.netting:
        _t += dt;
        const dur = 0.32;
        final k = (_t / dur).clamp(0.0, 1.0);
        final fall = k * k;
        final bounce = k > 0.78 ? sin((k - 0.78) / 0.22 * pi) * 14 : 0.0;
        position = Vector2(
          _lerp(_dropFrom.x, _dropTo.x, k),
          _lerp(_dropFrom.y, _dropTo.y, fall) - bounce,
        );
        scale = Vector2.all(_lerp(_netStartScale, _netEndScale, k));
        _groundY = _dropTo.y + radius;
        _height = _groundY - position.y;
        _angle += 9 * dt;
        if (k >= 1) {
          final end = position.clone();
          final r = radius;
          phase = BallPhase.hidden;
          game.onBallSettled(end, r);
        }
      case BallPhase.out:
        _t += dt;
        final k = (_t / 0.3).clamp(0.0, 1.0);
        position = Vector2(_lerp(_dropFrom.x, _dropTo.x, k), _lerp(_dropFrom.y, _dropTo.y, k));
        scale = Vector2.all(_lerp(_startScale * 0.2, _startScale * 0.12, k));
        _groundY = position.y + 200;
        _height = 200;
        _angle += 9 * dt;
        if (k >= 1) {
          phase = BallPhase.hidden;
          game.onBallOut();
        }
      case BallPhase.dropping:
        _t += dt;
        final k = (_t / dropDur).clamp(0.0, 1.0);
        // Yerçekimi: y'de hızlanan düşüş, x'te küçük kayma; sonda ufak sekme.
        final fall = k * k;
        final bounce = k > 0.8 ? sin((k - 0.8) / 0.2 * pi) * 18 : 0.0;
        position = Vector2(
          _lerp(_dropFrom.x, _dropTo.x, k),
          _lerp(_dropFrom.y, _dropTo.y, fall) - bounce,
        );
        _groundY = _dropTo.y + radius;
        _height = _groundY - position.y;
        _angle += 6 * dt;
        if (k >= 1) {
          final end = position.clone();
          final r = radius;
          phase = BallPhase.hidden;
          game.resolveDrop(end, r);
        }
    }
  }

  @override
  void render(Canvas canvas) {
    final s = scale.x;
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(1 / s);

    // Gölge (yerde, hafif sağ-alt).
    final shadowDy = (_groundY - position.y) + radius * 0.85;
    final shadowW = kBallDiameter * s * 0.95;
    final shadowH = kBallDiameter * s * 0.28;
    final shadowAlpha = (0.38 - _height / 1200).clamp(0.08, 0.38);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(radius * 0.12, shadowDy), width: shadowW, height: shadowH),
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, shadowAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Fever: altın top + parıltı.
    final fever = game.fever;
    if (fever) {
      canvas.drawCircle(
        Offset.zero,
        radius * 1.35,
        Paint()
          ..color = const Color(0x66FFE066)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
      );
    }

    // Top.
    canvas.save();
    canvas.rotate(_angle);
    _sprite.render(
      canvas,
      size: Vector2.all(kBallDiameter * s),
      anchor: Anchor.center,
      overridePaint: fever
          ? (Paint()..colorFilter = const ColorFilter.mode(Color(0xFFFFC21A), BlendMode.modulate))
          : null,
    );
    if (fever) {
      // Siyah yamalar turuncuya: üstüne yumuşak turuncu katman.
      canvas.drawCircle(
        Offset.zero,
        radius,
        Paint()
          ..color = const Color(0x55FF8A00)
          ..blendMode = BlendMode.screen,
      );
    }
    canvas.restore();

    canvas.restore();
  }
}

/// Kaledeki hedef.
class TargetComp extends PositionComponent with HasGameReference<KickLegendGame> {
  TargetComp() : super(anchor: Anchor.center, priority: 8);

  late Sprite _sprite;
  bool visible = false;
  double _pop = 1;
  Vector2? _last;

  @override
  Future<void> onLoad() async {
    _sprite = Sprite(game.images.fromCache('target.png'));
    size = Vector2.all(kTargetDiameter);
  }

  double get _viewScale => game.view == kWide ? 1.0 : 1.2;
  double get radius => kTargetDiameter / 2 * _viewScale;

  void spawn({bool immediate = false}) {
    final g = game.view;
    final r = radius;
    final rng = game.rng;
    Vector2 p;
    var tries = 0;
    do {
      p = Vector2(
        g.goalLeft + r + 6 + rng.nextDouble() * (g.goalWidth - 2 * r - 12),
        g.crossbarY + r + 6 + rng.nextDouble() * (g.goalHeight - 2 * r - 6),
      );
      tries++;
    } while (_last != null && p.distanceTo(_last!) < 220 && tries < 12);
    _last = p;
    position = p;
    scale = Vector2.all(_viewScale);
    visible = true;
    _shrink = -1;
    _pop = immediate ? 1 : 0;
  }

  void hide() => visible = false;

  double _shrink = -1; // >=0: küçülerek kaybolma animasyonu

  /// Vuruş kaydedilince hedef küçülerek yok olur.
  void shrinkAway() {
    if (!visible) return;
    _shrink = 0;
  }

  @override
  void update(double dt) {
    if (visible && _pop < 1) _pop = min(1, _pop + dt / 0.18);
    if (_shrink >= 0) {
      _shrink += dt / 0.16;
      if (_shrink >= 1) {
        _shrink = -1;
        visible = false;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (!visible) return;
    final k = _easeOut(_pop);
    var s = 0.6 + 0.4 * k + (k < 1 ? 0.12 * sin(k * pi) : 0);
    if (_shrink >= 0) s *= 1 - _shrink;
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(s);
    _sprite.render(canvas, size: size, anchor: Anchor.center);
    canvas.restore();
  }
}

/// Ray üstünde kayan siyah manken (kaleci). Birden fazla olabilir.
class Keeper extends PositionComponent with HasGameReference<KickLegendGame> {
  Keeper({this.phaseOffset = 0, this.periodScale = 1}) : super(priority: 10);

  static const double railLen = 536;
  static const double railH = 33;
  static const double keeperW = 116;
  static const double keeperH = 280;
  static const double keeperOffsetInRail = 182;

  final double phaseOffset;
  final double periodScale;

  late Sprite _sprite;
  bool active = false;
  double _t = 0;
  double _appear = 0;
  double cx = 0;

  @override
  Future<void> onLoad() async {
    _sprite = Sprite(game.images.fromCache('keeper.png'));
  }

  void activate() {
    if (active) return;
    active = true;
    _appear = 0;
    _t = 0;
  }

  void deactivate() => active = false;

  double get _s => game.view.keeperScale;

  double get _period => (3.2 - min(1.0, game.score / 1500)) * periodScale;

  bool blocks(Vector2 p, double r) {
    if (!active) return false;
    final g = game.view;
    final top = g.railY - keeperH * _s;
    final halfW = keeperW * _s * 0.5;
    return (p.x - cx).abs() < halfW + r * 0.5 && p.y + r > top;
  }

  @override
  void update(double dt) {
    if (!active) return;
    _t += dt;
    _appear = min(1, _appear + dt / 0.4);
    final g = game.view;
    final amp = g.goalWidth / 2 + 110;
    cx = g.goalCenterX + amp * sin(2 * pi * _t / _period + phaseOffset);
  }

  @override
  void render(Canvas canvas) {
    if (!active) return;
    final g = game.view;
    final s = _s;
    final k = _easeOut(_appear);
    final railLeft = cx - keeperOffsetInRail * s;
    final rail = RRect.fromRectAndRadius(
      Rect.fromLTWH(railLeft, g.railY, railLen * s, railH * s),
      Radius.circular(6 * s),
    );
    canvas.drawRRect(rail, Paint()..color = Color.fromRGBO(24, 24, 24, k));
    canvas.drawRect(
      Rect.fromLTWH(railLeft, g.railY, railLen * s, 5 * s),
      Paint()..color = Color.fromRGBO(70, 70, 70, k),
    );
    final h = keeperH * s;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(cx - keeperW * s, g.railY - h * k - 2, keeperW * 2 * s, h * k + 4));
    _sprite.render(
      canvas,
      position: Vector2(cx, g.railY + 2),
      size: Vector2(keeperW * s, h),
      anchor: Anchor.bottomCenter,
    );
    canvas.restore();
  }
}

/// Kale çizgisinde kalan küçük top.
class RestingBall extends PositionComponent with HasGameReference<KickLegendGame> {
  RestingBall(Vector2 pos, double s)
      : super(position: pos, anchor: Anchor.center, priority: 5) {
    scale = Vector2.all(s);
    size = Vector2.all(kBallDiameter);
  }

  late Sprite _sprite;

  @override
  Future<void> onLoad() async {
    _sprite = Sprite(game.images.fromCache('ball.png'));
    final others = parent!.children.whereType<RestingBall>().where((b) => b != this).toList();
    if (others.length >= 4) others.first.removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2 + 8, size.y * 0.95),
        width: size.x * 0.9,
        height: size.y * 0.25,
      ),
      Paint()..color = const Color.fromRGBO(0, 0, 0, 0.3),
    );
    _sprite.render(canvas, size: size);
  }
}

/// File dalgası: isabet noktasında büyüyen şeffaf halkalar.
class NetRipple extends PositionComponent {
  NetRipple(Vector2 pos) : super(position: pos, priority: 12);
  double _t = 0;
  static const double dur = 0.5;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= dur) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final k = (_t / dur).clamp(0.0, 1.0);
    for (var i = 0; i < 2; i++) {
      final kk = (k - i * 0.18).clamp(0.0, 1.0);
      if (kk <= 0) continue;
      final r = 30 + 120 * _easeOut(kk);
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, 0.55 * (1 - kk))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10 * (1 - kk) + 2,
      );
    }
  }
}

/// "+30" / "+60" yazısı: vuruş noktasından yukarı süzülür, söner.
class ScorePopup extends PositionComponent {
  ScorePopup(Vector2 pos, this.text, {this.color = const Color(0xFFFFFFFF)})
      : super(position: pos, priority: 14);
  final String text;
  final Color color;
  double _t = 0;
  static const double dur = 0.75;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= dur) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final k = (_t / dur).clamp(0.0, 1.0);
    final dy = -90 * _easeOut(k);
    final a = k < 0.6 ? 1.0 : 1 - (k - 0.6) / 0.4;
    final p = Vector2(0, dy);
    for (final o in const [Offset(-2, 0), Offset(2, 0), Offset(0, -2), Offset(0, 2)]) {
      TextPaint(
        style: TextStyle(
          fontSize: 38,
          fontWeight: FontWeight.w900,
          color: Color.fromRGBO(20, 20, 20, a),
          fontFamily: 'monospace',
        ),
      ).render(canvas, text, p + Vector2(o.dx, o.dy), anchor: Anchor.center);
    }
    TextPaint(
      style: TextStyle(
        fontSize: 38,
        fontWeight: FontWeight.w900,
        color: color.withValues(alpha: a),
        fontFamily: 'monospace',
      ),
    ).render(canvas, text, p, anchor: Anchor.center);
  }
}
