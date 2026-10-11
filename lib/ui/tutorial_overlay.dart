import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/geometry.dart';
import '../game/scene.dart';
import '../game/scene_art.dart';
import '../game/sut_ve_gol_game.dart';
import 'logo.dart';
import 'theme.dart';
import 'widgets.dart';

/// Rehberin adımları: canlı parmakla şut, halka ve kaleci, kalpler ve
/// sahneler, rehber eşliğinde ilk şut.
enum TutorialStep { shot, target, score, practice }

/// Şut adımının üç dersi; parmak animasyonu bunları sırayla oynatır.
enum ShotLesson {
  aim(
    'NİŞAN',
    'Parmağını toptan kaleye doğru kaydır. Top kaydırdığın yöne gider.',
    2.4,
  ),
  curve('FALSO', 'Kaydırırken yay çiz. Top havada aynı yöne kavis alır.', 2.6),
  power(
    'GÜÇ',
    'Hızlı kaydırırsan top yükselir. Çok sert vurma, üstten kaçar.',
    4.0,
  );

  const ShotLesson(this.label, this.text, this.seconds);
  final String label;
  final String text;
  final double seconds;
}

/// Oyun dünyasını (1320x2868) ekrana yerleştiren dönüşüm. Flame'in
/// FixedResolutionViewport hesabıyla aynıdır: sığdırılmış ve ortalanmış.
@immutable
class WorldFrame {
  const WorldFrame._(this.scale, this.origin);

  factory WorldFrame.of(Size size) {
    final s = math.min(size.width / kWorldW, size.height / kWorldH);
    return WorldFrame._(
      s,
      Offset((size.width - kWorldW * s) / 2, (size.height - kWorldH * s) / 2),
    );
  }

  final double scale;
  final Offset origin;

  Offset toScreen(Offset world) => origin + world * scale;
}

/// İlk açılış rehberi. Bilgi adımlarında dokunuşları yutar (yanlışlıkla şut
/// çıkmaz); son adımda oyuncu gerçek ilk şutunu çeker. "Geç" her adımda
/// kapatır. Bitince ya da geçilince bayrak kalıcı yazılır.
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({super.key, required this.game});
  final SutVeGolGame game;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with TickerProviderStateMixin {
  static const _cardMove = Duration(milliseconds: 420);

  TutorialStep step = TutorialStep.shot;
  ShotLesson lesson = ShotLesson.aim;

  /// İlk şut atıldı: kısa bir "Hazırsın" kartı, sonra perde kapanır.
  bool shotTaken = false;
  bool _closing = false;
  int _kicksAtPractice = 0;
  Timer? _closeTimer;

  late final AnimationController _fade;
  late final AnimationController _demo;
  late final AnimationController _move;
  Rect _spotFrom = Rect.zero;
  double _dimFrom = 0;
  double _dimTo = 0;

  SutVeGolGame get game => widget.game;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
    _demo = AnimationController(vsync: this)
      ..addStatusListener(_onDemoStatus)
      ..addListener(_watchPractice);
    _move = AnimationController(vsync: this, duration: _cardMove);
    _spotFrom = _spotFor(step);
    _dimTo = _dimFor(step);
    _move.forward(from: 0);
    _playDemo();
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _fade.dispose();
    _demo.dispose();
    _move.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- akış

  Duration _secs(double s) => Duration(milliseconds: (s * 1000).round());

  void _playDemo() {
    switch (step) {
      case TutorialStep.shot:
        _demo.duration = _secs(lesson.seconds);
        _demo.forward(from: 0);
      case TutorialStep.target:
        _demo.duration = _secs(2.8);
        _demo
          ..value = 0
          ..repeat();
      case TutorialStep.score:
        _demo.duration = _secs(1.6);
        _demo
          ..value = 0
          ..repeat();
      case TutorialStep.practice:
        _demo.duration = _secs(2.2);
        _demo
          ..value = 0
          ..repeat();
    }
  }

  /// Şut dersleri kendiliğinden sırayla döner: nişan → falso → güç.
  void _onDemoStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed ||
        step != TutorialStep.shot ||
        !mounted) {
      return;
    }
    setState(() {
      lesson = ShotLesson.values[(lesson.index + 1) % ShotLesson.values.length];
    });
    _playDemo();
  }

  void _pickLesson(ShotLesson next) {
    if (step != TutorialStep.shot) return;
    setState(() => lesson = next);
    _playDemo();
  }

  Rect get _spot => Rect.lerp(
    _spotFrom,
    _spotFor(step),
    Curves.easeInOutCubic.transform(_move.value),
  )!;

  double get _dim => ui.lerpDouble(_dimFrom, _dimTo, _move.value)!;

  /// Adımın ilgi alanı (dünya koordinatı); dışı karartılır.
  Rect _spotFor(TutorialStep s) {
    final g = game.view;
    return switch (s) {
      TutorialStep.shot => Rect.fromLTRB(
        g.goalLeft - 170,
        g.crossbarY - 130,
        g.goalRight + 170,
        g.ballRest.y + 240,
      ),
      TutorialStep.target => Rect.fromLTRB(
        g.goalLeft - 100,
        g.crossbarY - 110,
        g.goalRight + 100,
        g.railY + 80,
      ),
      TutorialStep.score => g.boardRect.inflate(40),
      TutorialStep.practice => const Rect.fromLTRB(
        -400,
        -400,
        kWorldW + 400,
        kWorldH + 400,
      ),
    };
  }

  double _dimFor(TutorialStep s) => s == TutorialStep.practice ? 0 : 1;

  void _goTo(TutorialStep next) {
    if (_closing) return;
    setState(() {
      _spotFrom = _spot;
      _dimFrom = _dim;
      step = next;
      _dimTo = _dimFor(next);
      if (next == TutorialStep.practice) _kicksAtPractice = game.kicks;
    });
    // Menüden açıldıysa oyun bilgi adımlarında donuk bekler; şut için açılır.
    if (next == TutorialStep.practice) game.resume();
    _move.forward(from: 0);
    _playDemo();
  }

  void _next() {
    if (step.index < TutorialStep.values.length - 1) {
      _goTo(TutorialStep.values[step.index + 1]);
    }
  }

  /// Son adımda oyuncunun gerçek şutunu bekler.
  void _watchPractice() {
    if (step != TutorialStep.practice || shotTaken || _closing) return;
    if (game.kicks > _kicksAtPractice) {
      game.markTutorialDone();
      setState(() => shotTaken = true);
      _closeTimer = Timer(const Duration(milliseconds: 1500), _close);
    }
  }

  void _skip() {
    game.markTutorialDone();
    _close();
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _closeTimer?.cancel();
    game.resume();
    await _fade.reverse();
    if (mounted) game.closeTutorial();
  }

  // ---------------------------------------------------------------- görünüm

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = c.biggest;
        final frame = WorldFrame.of(size);
        final pad = MediaQuery.paddingOf(context);
        final s = (math.min(size.width, 440.0) / 440).clamp(0.8, 1.0);
        final practice = step == TutorialStep.practice;
        // Son adımda kart duraklat düğmesinin altında kalır; düğme çalışır.
        final pauseBottom = frame.toScreen(Offset(0, kPauseRect.bottom)).dy;
        final top = practice
            ? math.max(pad.top + 8, pauseBottom + 10)
            : pad.top + 8;
        final atBottom =
            step == TutorialStep.target || step == TutorialStep.score;
        return FadeTransition(
          opacity: _fade,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Bilgi adımlarında dokunuş oyuna geçmez.
              if (!practice) const AbsorbPointer(child: SizedBox.expand()),
              IgnorePointer(
                child: CustomPaint(
                  painter: _TutorialPainter(
                    game: game,
                    step: step,
                    lesson: lesson,
                    shotTaken: shotTaken,
                    demo: _demo,
                    spot: () => _spot,
                    dim: () => _dim,
                    repaint: Listenable.merge([_demo, _move]),
                  ),
                ),
              ),
              AnimatedPadding(
                duration: _cardMove,
                curve: Curves.easeInOutCubic,
                padding: EdgeInsets.fromLTRB(16, top, 16, pad.bottom + 12),
                child: AnimatedAlign(
                  duration: _cardMove,
                  curve: Curves.easeInOutCubic,
                  alignment: atBottom
                      ? Alignment.bottomCenter
                      : Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: _card(s),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _card(double s) => GlassCard(
    radius: 24 * s,
    padding: EdgeInsets.fromLTRB(18 * s, 16 * s, 14 * s, 14 * s),
    child: AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(a),
            child: child,
          ),
        ),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        child: KeyedSubtree(
          key: ValueKey('${step.name}-$shotTaken'),
          child: shotTaken ? _readyContent(s) : _stepContent(s),
        ),
      ),
    ),
  );

  (String, String) get _copy => switch (step) {
    TutorialStep.shot => ('Kaydır ve şut çek', lesson.text),
    TutorialStep.target => (
      'Halkayı vur',
      'Halkaya her isabet 30 puan. Halkayı kaçıran gol sayılmaz. '
          'İlk isabetten sonra kaleci mankeni kaymaya başlar.',
    ),
    TutorialStep.score => (
      'Üç kalbin var',
      'Her ıska bir kalp götürür, kalpler bitince oyun biter. '
          'Puan topladıkça yeni sahneler açılır.',
    ),
    TutorialStep.practice => ('İlk şutunu çek', 'Topu halkaya doğru kaydır.'),
  };

  Widget _stepContent(double s) {
    final (title, body) = _copy;
    final bodyStyle = FK.t(
      size: 15 * s,
      color: FK.text.withValues(alpha: 0.86),
      height: 1.35,
    );
    final practice = step == TutorialStep.practice;
    // Büyük yazı tipi ayarında da taşmasın: başlık kısalır, sayaç ve
    // noktalar yerinde kalır.
    final eyebrow = Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  'NASIL OYNANIR',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: FK.t(
                    size: 12 * s,
                    w: FontWeight.w700,
                    color: FK.amber,
                    spacing: 2.4 * s,
                  ),
                ),
              ),
              SizedBox(width: 8 * s),
              Text(
                '${step.index + 1}/${TutorialStep.values.length}',
                style: FK.t(size: 12 * s, w: FontWeight.w600, color: FK.muted),
              ),
            ],
          ),
        ),
        SizedBox(width: 8 * s),
        _dots(s),
      ],
    );
    final heading = <Widget>[
      eyebrow,
      SizedBox(height: 6 * s),
      Text(title, style: FK.t(size: 24 * s, w: FontWeight.w700)),
      SizedBox(height: 6 * s),
      if (step == TutorialStep.shot)
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [...previous, ?current],
          ),
          child: Text(body, key: ValueKey(lesson), style: bodyStyle),
        )
      else
        Text(body, style: bodyStyle),
    ];
    if (practice) {
      // Son adım: kısa şerit, "Geç" yanda; parmak ipucu sahada.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: heading,
            ),
          ),
          SizedBox(width: 8 * s),
          _skipButton(s),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...heading,
        if (step == TutorialStep.shot) ...[
          SizedBox(height: 12 * s),
          _lessonChips(s),
        ],
        if (step == TutorialStep.score) ...[
          SizedBox(height: 12 * s),
          _stageStrip(s),
          SizedBox(height: 10 * s),
          _kingRow(s),
        ],
        SizedBox(height: 12 * s),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: _skipButton(s)),
            SizedBox(width: 8 * s),
            // Dar ekranda hap düğmenin yazısı sığacak kadar küçülür.
            Flexible(
              child: PillButton(
                label: step == TutorialStep.score ? 'ŞUT ÇEK' : 'İLERİ',
                icon: step == TutorialStep.score
                    ? Icons.sports_soccer_rounded
                    : null,
                onTap: _next,
                height: 46 * s,
                fontSize: 16 * s,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _skipButton(double s) => TextButton(
    onPressed: _skip,
    style: TextButton.styleFrom(
      foregroundColor: FK.muted,
      minimumSize: Size(56 * s, 44 * s),
      padding: EdgeInsets.symmetric(horizontal: 14 * s),
      shape: const StadiumBorder(),
    ),
    child: Text(
      'Geç',
      style: FK.t(size: 15 * s, w: FontWeight.w600, color: FK.muted),
    ),
  );

  Widget _readyContent(double s) => Row(
    children: [
      Container(
        width: 46 * s,
        height: 46 * s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: FK.fire,
          boxShadow: FK.glow(16 * s, alpha: 0.4, dy: 4),
        ),
        child: Icon(
          Icons.sports_soccer_rounded,
          color: Colors.white,
          size: 26 * s,
        ),
      ),
      SizedBox(width: 14 * s),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hazırsın!', style: FK.t(size: 22 * s, w: FontWeight.w700)),
            SizedBox(height: 3 * s),
            Text(
              'Bol gol, rekorunu kır.',
              style: FK.t(size: 15 * s, color: FK.muted),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _dots(double s) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final st in TutorialStep.values)
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: EdgeInsets.only(left: 6 * s),
          width: (st == step ? 22 : 8) * s,
          height: 8 * s,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4 * s),
            gradient: st == step ? FK.fire : null,
            color: st == step
                ? null
                : Colors.white.withValues(alpha: st.index < step.index ? 0.55 : 0.22),
          ),
        ),
    ],
  );

  Widget _lessonChips(double s) => AnimatedBuilder(
    animation: _demo,
    builder: (context, _) => Row(
      children: [
        for (final l in ShotLesson.values) ...[
          if (l.index > 0) SizedBox(width: 8 * s),
          Expanded(
            child: GestureDetector(
              onTap: () => _pickLesson(l),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 34 * s,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  gradient: l == lesson ? FK.fire : null,
                  color: l == lesson ? null : FK.glass,
                  borderRadius: BorderRadius.circular(17 * s),
                  border: l == lesson
                      ? null
                      : Border.all(color: FK.glassBorder, width: 1.2),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6 * s),
                          child: Text(
                            l.label,
                            maxLines: 1,
                            style: FK.t(
                              size: 13 * s,
                              w: FontWeight.w700,
                              spacing: 1.4 * s,
                              color: l == lesson ? Colors.white : FK.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Etkin dersin ilerlemesi: dersler kendiliğinden döner.
                    if (l == lesson)
                      Positioned(
                        left: 0,
                        bottom: 0,
                        right: 0,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: _demo.value,
                            child: Container(
                              height: 3 * s,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _stageStrip(double s) => Row(
    children: [
      for (final st in Stage.values) ...[
        if (st.index > 0)
          Icon(Icons.chevron_right_rounded, size: 16 * s, color: FK.muted),
        Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 7 * s, horizontal: 4 * s),
            decoration: BoxDecoration(
              color: FK.glass,
              borderRadius: BorderRadius.circular(12 * s),
              border: Border.all(color: st.accent.withValues(alpha: 0.6)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    st.label,
                    maxLines: 1,
                    style: FK.t(
                      size: 11 * s,
                      w: FontWeight.w700,
                      color: st.accent,
                      spacing: 0.6 * s,
                    ),
                  ),
                ),
                SizedBox(height: 3 * s),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    st.minScore == 0 ? 'başlangıç' : '${st.minScore} puan',
                    maxLines: 1,
                    style: FK.t(size: 11 * s, w: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );

  Widget _kingRow(double s) => Container(
    padding: EdgeInsets.fromLTRB(10 * s, 8 * s, 12 * s, 8 * s),
    decoration: BoxDecoration(
      color: FK.gold.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14 * s),
      border: Border.all(color: FK.gold.withValues(alpha: 0.45)),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 30 * s,
          height: 24 * s,
          child: const CustomPaint(painter: _CrownPainter()),
        ),
        SizedBox(width: 10 * s),
        Expanded(
          child: Text(
            'Üst üste 5 isabet: Kral Modu, 10 sn çift puan.',
            style: FK.t(size: 13 * s, w: FontWeight.w600, height: 1.3),
          ),
        ),
      ],
    ),
  );
}

class _CrownPainter extends CustomPainter {
  const _CrownPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2 + size.height * 0.08);
    paintCrown(canvas, size.width * 0.86);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CrownPainter oldDelegate) => false;
}

// -------------------------------------------------------------------- çizim

double _easeInOut(double t) =>
    t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
double _easeOut(double t) => 1 - math.pow(1 - t, 3).toDouble();
double _span(double t, double from, double to) =>
    ((t - from) / (to - from)).clamp(0.0, 1.0);

Offset _quad(Offset a, Offset c, Offset b, double t) {
  final u = 1 - t;
  return a * (u * u) + c * (2 * u * t) + b * (t * t);
}

Offset _unit(Offset v) {
  final d = v.distance;
  return d == 0 ? const Offset(0, -1) : v / d;
}

Offset _rotate(Offset v, double a) => Offset(
  v.dx * math.cos(a) - v.dy * math.sin(a),
  v.dx * math.sin(a) + v.dy * math.cos(a),
);

/// Parmak animasyonundaki tek kaydırma: parmak yolu, hayalet topun yolu ve
/// zaman çizelgesi (dersin 0..1 süresi içinde).
class _Swipe {
  const _Swipe({
    required this.from,
    required this.to,
    this.bend = Offset.zero,
    required this.land,
    required this.lift,
    this.curve = Offset.zero,
    required this.start,
    required this.dragFrom,
    required this.dragTo,
    this.flyFrom = 0,
    this.flyTo = 0,
    required this.end,
    this.ghost = true,
    this.popup,
    this.tag,
    this.fast = false,
  });

  final Offset from, to, bend, land, curve;
  final double lift;
  final double start, dragFrom, dragTo, flyFrom, flyTo, end;
  final bool ghost, fast;
  final String? popup, tag;

  Offset finger(double u) => _quad(from, (from + to) / 2 + bend, to, u);
  Offset ball(double p) =>
      _quad(from, (from + land) / 2 + Offset(0, -lift) + curve, land, p);
}

class _TutorialPainter extends CustomPainter {
  _TutorialPainter({
    required this.game,
    required this.step,
    required this.lesson,
    required this.shotTaken,
    required this.demo,
    required this.spot,
    required this.dim,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final SutVeGolGame game;
  final TutorialStep step;
  final ShotLesson lesson;
  final bool shotTaken;
  final Animation<double> demo;
  final Rect Function() spot;
  final double Function() dim;

  static final String _fingerGlyph = String.fromCharCode(
    Icons.pan_tool_alt_rounded.codePoint,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final frame = WorldFrame.of(size);
    canvas.save();
    canvas.translate(frame.origin.dx, frame.origin.dy);
    canvas.scale(frame.scale);
    final g = game.view;
    final full = Rect.fromLTWH(
      -frame.origin.dx / frame.scale,
      -frame.origin.dy / frame.scale,
      size.width / frame.scale,
      size.height / frame.scale,
    ).inflate(8);
    final a = dim();
    if (a > 0.01) _paintDim(canvas, full, spot(), a);
    final t = demo.value;
    switch (step) {
      case TutorialStep.shot:
        for (final w in _lessonSwipes(g)) {
          _paintSwipe(canvas, g, w, t);
        }
      case TutorialStep.target:
        _paintTargetStep(canvas, g, t);
      case TutorialStep.score:
        _paintScoreStep(canvas, g, t);
      case TutorialStep.practice:
        if (!shotTaken) _paintPracticeStep(canvas, g, t);
    }
    canvas.restore();
  }

  Offset get _target {
    final g = game.view;
    final tg = game.target;
    return tg.visible
        ? Offset(tg.position.x, tg.position.y)
        : Offset(g.goalCenterX, (g.crossbarY + g.groundY) / 2);
  }

  Offset _ballRest(ViewGeom g) => Offset(g.ballRest.x, g.ballRest.y);

  /// Kaydırma yönü: oyundaki gibi yer izinin kale çizgisine ulaştığı nokta.
  Offset _aimDir(ViewGeom g) {
    final b = _ballRest(g);
    final track = g.groundY - kBallDiameter / 2 * g.ballGoalScale;
    return _unit(Offset(_target.dx - b.dx, track - b.dy));
  }

  List<_Swipe> _lessonSwipes(ViewGeom g) {
    final b = _ballRest(g);
    final tgt = _target;
    final dir = _aimDir(g);
    switch (lesson) {
      case ShotLesson.aim:
        return [
          _Swipe(
            from: b,
            to: b + dir * 520,
            land: tgt,
            lift: 230,
            start: 0.02,
            dragFrom: 0.10,
            dragTo: 0.30,
            flyFrom: 0.31,
            flyTo: 0.62,
            end: 0.97,
            popup: '+30',
          ),
        ];
      case ShotLesson.curve:
        // Hedefin biraz soluna nişan, sağa yay: top kavis alıp halkaya döner.
        final d = _rotate(dir, -0.2);
        final right = Offset(-d.dy, d.dx);
        return [
          _Swipe(
            from: b,
            to: b + d * 520,
            bend: right * 160,
            land: tgt,
            lift: 190,
            curve: const Offset(300, 0),
            start: 0.02,
            dragFrom: 0.10,
            dragTo: 0.32,
            flyFrom: 0.33,
            flyTo: 0.64,
            end: 0.97,
            popup: '+30',
          ),
        ];
      case ShotLesson.power:
        return [
          _Swipe(
            from: b,
            to: b + dir * 400,
            land: Offset(tgt.dx, g.groundY - 40),
            lift: 120,
            start: 0.0,
            dragFrom: 0.05,
            dragTo: 0.25,
            flyFrom: 0.26,
            flyTo: 0.40,
            end: 0.49,
            tag: 'YAVAŞ',
          ),
          _Swipe(
            from: b,
            to: b + dir * 620,
            land: Offset(tgt.dx, g.crossbarY + 36),
            lift: 300,
            start: 0.51,
            dragFrom: 0.56,
            dragTo: 0.61,
            flyFrom: 0.62,
            flyTo: 0.77,
            end: 0.98,
            tag: 'HIZLI',
            fast: true,
          ),
        ];
    }
  }

  void _paintDim(Canvas canvas, Rect full, Rect spot, double a) {
    final rr = RRect.fromRectAndRadius(spot, const Radius.circular(54));
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(full)
        ..addRRect(rr),
      Paint()..color = FK.navy.withValues(alpha: 0.72 * a),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..color = FK.amber.withValues(alpha: 0.32 * a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..color = FK.amber.withValues(alpha: 0.8 * a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  void _paintSwipe(Canvas canvas, ViewGeom g, _Swipe w, double t) {
    if (t < w.start || t > w.end) return;
    final fade = 1 - _span(t, w.end - 0.1, w.end);
    final u = _easeInOut(_span(t, w.dragFrom, w.dragTo));
    final dir = _unit(w.to - w.from);

    // Dokunma halkası.
    final press = _span(t, w.start + 0.03, w.start + 0.15);
    if (press > 0 && press < 1) {
      canvas.drawCircle(
        w.from,
        40 + 100 * _easeOut(press),
        Paint()
          ..color = FK.amber.withValues(alpha: 0.8 * (1 - press))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8,
      );
    }
    if (t >= w.dragFrom) _paintTrail(canvas, w, u, fade);

    if (w.ghost && t >= w.flyFrom && w.flyTo > w.flyFrom) {
      final z = _span(t, w.flyFrom, w.flyTo);
      _paintGhostBall(canvas, g, w, z, fade);
      if (z >= 1) {
        final k = _span(t, w.flyTo, w.flyTo + 0.16);
        _paintBurst(canvas, w.land, k, w.popup);
      }
    }

    final appear = _span(t, w.start, w.start + 0.06);
    final release = _span(t, w.dragTo, w.dragTo + 0.07);
    final alpha = appear * (1 - release);
    if (alpha > 0) {
      _paintFinger(
        canvas,
        w.finger(u) + dir * (50 * release),
        alpha,
        1.25 - 0.25 * appear + 0.1 * release,
      );
    }
    final tag = w.tag;
    if (tag != null && appear > 0) {
      final at = w.finger(0.5 * math.max(u, 0.4));
      _paintTag(canvas, at + const Offset(190, 0), tag, fade * appear);
    }
  }

  void _paintTrail(Canvas canvas, _Swipe w, double u, double fade) {
    if (u <= 0.01) return;
    final path = Path()..moveTo(w.from.dx, w.from.dy);
    const n = 24;
    for (var i = 1; i <= n; i++) {
      final p = w.finger(u * i / n);
      path.lineTo(p.dx, p.dy);
    }
    final end = w.finger(u);
    if ((end - w.from).distance < 2) return;
    // Topun üstünde saydam başlar, parmağa doğru parlar.
    Shader shade(double a) => ui.Gradient.linear(
      w.from,
      end,
      [
        FK.orange.withValues(alpha: 0),
        FK.orange.withValues(alpha: 0.55 * a),
        FK.amber.withValues(alpha: a),
      ],
      const [0, 0.3, 1],
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = shade(0.4 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 48
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = shade(0.95 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (w.fast && u < 1) {
      // Hız çizgileri: sert kaydırma.
      final d = _unit(w.to - w.from);
      final n2 = Offset(-d.dy, d.dx);
      final line = Paint()
        ..color = Colors.white.withValues(alpha: 0.7 * fade)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round;
      for (final k in const [-1.0, 0.0, 1.0]) {
        final base = end - d * (110 + 30 * k.abs()) + n2 * (56 * k);
        canvas.drawLine(base, base - d * (90 - 20 * k.abs()), line);
      }
    }
  }

  void _paintGhostBall(
    Canvas canvas,
    ViewGeom g,
    _Swipe w,
    double z,
    double fade,
  ) {
    final s0 = g.ballRestScale;
    final ratio = s0 / g.ballGoalScale;
    double scaleAt(double v) => s0 / (1 + (ratio - 1) * v);
    double progress(double v) => v * ratio / (1 + (ratio - 1) * v);

    final dots = Paint()..color = Colors.white.withValues(alpha: 0.7 * fade);
    const n = 22;
    for (var i = 1; i < n; i++) {
      final v = z * i / n;
      canvas.drawCircle(
        w.ball(progress(v)),
        5 + 8 * math.sqrt(scaleAt(v) / s0),
        dots,
      );
    }
    if (!game.images.containsKey('ball')) return;
    final image = game.images.fromCache('ball');
    final p = w.ball(progress(z));
    final r = kBallDiameter / 2 * scaleAt(z);
    canvas.drawCircle(
      p,
      r * 1.25,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.28 * fade)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + r * 0.25),
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromCircle(center: p, radius: r),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(255, 255, 255, 0.92 * fade),
    );
  }

  void _paintBurst(Canvas canvas, Offset c, double k, String? popup) {
    if (k <= 0 || k >= 1) return;
    final color = game.stage.accent;
    canvas.drawCircle(
      c,
      60 + 110 * _easeOut(k),
      Paint()
        ..color = color.withValues(alpha: 0.85 * (1 - k))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12 * (1 - k) + 3,
    );
    if (popup == null) return;
    final alpha = k < 0.6 ? 1.0 : 1 - (k - 0.6) / 0.4;
    _paintText(
      canvas,
      c + Offset(0, -70 - 70 * _easeOut(k)),
      popup,
      size: 64,
      color: Colors.white.withValues(alpha: alpha),
      outline: Colors.black.withValues(alpha: 0.75 * alpha),
    );
  }

  void _paintFinger(Canvas canvas, Offset tip, double alpha, double scale) {
    const icon = Icons.pan_tool_alt_rounded;
    TextPainter glyph({Color? color, Paint? foreground, List<Shadow>? shadows}) =>
        TextPainter(
          text: TextSpan(
            text: _fingerGlyph,
            style: TextStyle(
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              fontSize: 280 * scale,
              height: 1,
              color: color,
              foreground: foreground,
              shadows: shadows,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
    final outline = glyph(
      foreground: Paint()
        ..color = FK.navy.withValues(alpha: 0.9 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeJoin = StrokeJoin.round,
      shadows: [
        Shadow(
          color: Colors.black.withValues(alpha: 0.5 * alpha),
          blurRadius: 20,
          offset: const Offset(8, 14),
        ),
      ],
    );
    final fill = glyph(color: Colors.white.withValues(alpha: alpha));
    // Glifte işaret parmağının ucu yaklaşık (0.40, 0.08) noktasında.
    final at = tip - Offset(fill.width * 0.40, fill.height * 0.08);
    outline
      ..paint(canvas, at)
      ..dispose();
    fill
      ..paint(canvas, at)
      ..dispose();
  }

  void _paintTag(Canvas canvas, Offset center, String text, double alpha) {
    if (alpha <= 0) return;
    final tp = _layout(text, 46, FK.amber.withValues(alpha: alpha), 3);
    final rect = Rect.fromCenter(
      center: center,
      width: tp.width + 44,
      height: tp.height + 18,
    );
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
    canvas.drawRRect(rr, Paint()..color = FK.navy.withValues(alpha: 0.88 * alpha));
    canvas.drawRRect(
      rr,
      Paint()
        ..color = FK.amber.withValues(alpha: 0.8 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    tp
      ..paint(canvas, center - Offset(tp.width / 2, tp.height / 2))
      ..dispose();
  }

  void _paintTargetStep(Canvas canvas, ViewGeom g, double t) {
    final tgt = _target;
    final r = game.target.radius;
    final accent = game.stage.accent;

    // Kaleci önizlemesi (henüz çıkmadıysa hayalet manken), spot içinde kalır.
    final keeper = game.keepers.first;
    final cx = keeper.active
        ? keeper.cx
        : g.goalCenterX + (g.goalWidth / 2 - 40) * math.sin(2 * math.pi * t);
    if (!keeper.active) {
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(spot(), const Radius.circular(54)),
      );
      _paintGhostKeeper(canvas, g, cx);
      canvas.restore();
    }

    for (var i = 0; i < 2; i++) {
      final k = (t * 2 + i * 0.5) % 1.0;
      canvas.drawCircle(
        tgt,
        r * (1.05 + 0.9 * k),
        Paint()
          ..color = accent.withValues(alpha: 0.85 * (1 - k))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8 * (1 - k) + 2,
      );
    }
    // "+30" etiketi hedefin kale ortasına bakan yanında.
    final side = tgt.dx < g.goalCenterX ? 1.0 : -1.0;
    _paintPill(canvas, tgt + Offset((r + 104) * side, 0), '+30');
    _paintTag(
      canvas,
      Offset(cx, g.railY - Keeper.keeperH * g.keeperScale - 50),
      'KALECİ',
      1,
    );
  }

  void _paintGhostKeeper(Canvas canvas, ViewGeom g, double cx) {
    final s = g.keeperScale;
    final h = Keeper.keeperH * s;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, g.railY - h * 0.5),
          width: Keeper.keeperW * s * 1.4,
          height: h * 1.05,
        ),
        Radius.circular(40 * s),
      ),
      Paint()
        ..color = FK.amber.withValues(alpha: 0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
    );
    final railLeft = cx - Keeper.keeperOffsetInRail * s;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(railLeft, g.railY, Keeper.railLen * s, Keeper.railH * s),
        Radius.circular(6 * s),
      ),
      Paint()..color = const Color(0xD9181818),
    );
    canvas.save();
    canvas.translate(cx, g.railY + 2);
    SceneArt.paintKeeper(canvas, Keeper.keeperW * s, h, 0.92);
    canvas.restore();
  }

  void _paintScoreStep(Canvas canvas, ViewGeom g, double t) {
    final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(g.heartFirst.x, g.heartFirst.y + g.heartGap * i),
        42 * g.heartScale,
        Paint()
          ..color = FK.red.withValues(alpha: 0.16 + 0.26 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
    }
    final left = g.boardRect.left - 64;
    _paintLabel(canvas, Offset(left, g.scoreRect.center.dy), 'SKOR', FK.text);
    _paintLabel(canvas, Offset(left, g.bestRect.center.dy), 'REKOR', FK.amber);
    _paintLabel(
      canvas,
      Offset(g.boardRect.right + 64, g.heartFirst.y + g.heartGap),
      'KALP',
      FK.red,
      alignRight: false,
    );
  }

  void _paintPracticeStep(Canvas canvas, ViewGeom g, double t) {
    final tgt = _target;
    final k = (t * 2) % 1.0;
    canvas.drawCircle(
      tgt,
      game.target.radius * (1.05 + 0.7 * k),
      Paint()
        ..color = game.stage.accent.withValues(alpha: 0.7 * (1 - k))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7 * (1 - k) + 2,
    );
    final b = _ballRest(g);
    _paintSwipe(
      canvas,
      g,
      _Swipe(
        from: b,
        to: b + _aimDir(g) * 600,
        land: tgt,
        lift: 0,
        start: 0.0,
        dragFrom: 0.12,
        dragTo: 0.42,
        end: 0.8,
        ghost: false,
      ),
      t,
    );
  }

  /// Turuncu hap etiket (ör. "+30").
  void _paintPill(Canvas canvas, Offset center, String text) {
    final tp = _layout(text, 54, Colors.white, 1);
    final rect = Rect.fromCenter(
      center: center,
      width: tp.width + 46,
      height: tp.height + 16,
    );
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
    canvas.drawRRect(
      rr.shift(const Offset(0, 6)),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, const [
          FK.orange,
          FK.amber,
        ]),
    );
    tp
      ..paint(canvas, center - Offset(tp.width / 2, tp.height / 2))
      ..dispose();
  }

  /// Karartılmış alanda tabela parçalarını adlandıran yazı ve kısa çizgi.
  void _paintLabel(
    Canvas canvas,
    Offset anchor,
    String text,
    Color color, {
    bool alignRight = true,
  }) {
    final tp = _layout(text, 46, color, 3);
    final x = alignRight ? anchor.dx - tp.width : anchor.dx;
    tp
      ..paint(canvas, Offset(x, anchor.dy - tp.height / 2))
      ..dispose();
    final lineFrom = alignRight
        ? Offset(anchor.dx + 10, anchor.dy)
        : Offset(anchor.dx - 10, anchor.dy);
    final lineTo = alignRight
        ? Offset(anchor.dx + 44, anchor.dy)
        : Offset(anchor.dx - 44, anchor.dy);
    canvas.drawLine(
      lineFrom,
      lineTo,
      Paint()
        ..color = color.withValues(alpha: 0.8)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintText(
    Canvas canvas,
    Offset center,
    String text, {
    required double size,
    required Color color,
    Color? outline,
  }) {
    if (outline != null) {
      final back = _layout(text, size, outline, 1, weight: FontWeight.w900);
      for (final o in const [
        Offset(-3, 0),
        Offset(3, 0),
        Offset(0, -3),
        Offset(0, 3),
      ]) {
        back.paint(canvas, center + o - Offset(back.width / 2, back.height / 2));
      }
      back.dispose();
    }
    final tp = _layout(text, size, color, 1, weight: FontWeight.w900);
    tp
      ..paint(canvas, center - Offset(tp.width / 2, tp.height / 2))
      ..dispose();
  }

  TextPainter _layout(
    String text,
    double size,
    Color color,
    double spacing, {
    FontWeight weight = FontWeight.w700,
  }) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: FK.font,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
        height: 1.1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  bool shouldRepaint(covariant _TutorialPainter old) =>
      old.step != step ||
      old.lesson != lesson ||
      old.shotTaken != shotTaken ||
      old.game != game;
}
