import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fever.dart';
import 'geometry.dart';
import 'hud.dart';
import 'scene.dart';
import 'splash.dart';

enum GameState { splash, idle, flying, resolving, paused, gameOver }

/// Geliştirme: `--dart-define=AUTOPLAY=true` ile oyun kendi kendine şut atar.
const bool kAutoplay = bool.fromEnvironment('AUTOPLAY');

/// Flutter tarafındaki perdelerin overlay anahtarları.
const String kGameOverOverlay = 'gameOver';
const String kPauseOverlay = 'pause';

class _Scheduled {
  _Scheduled(this.at, this.fn);
  final double at;
  final void Function() fn;
}

class KickLegendGame extends FlameGame {
  KickLegendGame()
      : super(
          camera: CameraComponent.withFixedResolution(
            width: kWorldW,
            height: kWorldH,
          ),
        );

  final Random rng = Random();

  ViewGeom view = kWide;
  GameState state = GameState.splash;
  int score = 0;
  int best = 0;
  int lives = 3;

  // Seri / fever.
  int streak = 0;
  bool fever = false;
  double feverTime = 0;
  static const int feverStreak = 5;
  static const double feverDuration = 10;

  late final SceneRoot scene;
  late final Background background;
  late final Ball ball;
  late final TargetComp target;
  late final List<Keeper> keepers;
  late final Scoreboard scoreboard;
  late final FeverOverlay feverOverlay;
  late final InputLayer input;
  SplashLayer? splash;

  /// Ayarlar (pause menüsü): ses ve titreşim.
  bool soundOn = true;
  bool hapticsOn = true;

  SharedPreferences? _prefs;
  double _clock = 0;
  final List<_Scheduled> _queue = [];

  @override
  Color backgroundColor() => const Color(0xFF000000);

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;
    await images.loadAll([
      'bg_wide.png',
      'bg_zoom.png',
      'splash_bg.png',
      'logo.png',
      'ball.png',
      'target.png',
      'keeper.png',
      'heart.png',
    ]);
    _prefs = await SharedPreferences.getInstance();
    best = _prefs?.getInt('best') ?? 0;
    soundOn = _prefs?.getBool('sound') ?? true;
    hapticsOn = _prefs?.getBool('haptics') ?? true;

    scene = SceneRoot()..position = Vector2(0, kWorldH);
    background = Background();
    target = TargetComp();
    keepers = [
      Keeper(),
      Keeper(phaseOffset: pi / 2, periodScale: 0.8),
    ];
    ball = Ball();
    scoreboard = Scoreboard();
    feverOverlay = FeverOverlay();
    scene.addAll([background, target, ...keepers, ball, feverOverlay, scoreboard]);

    input = InputLayer();
    splash = SplashLayer();
    world.addAll([scene, input, splash!]);
  }

  // ---------------------------------------------------------------- akış

  @override
  void update(double dt) {
    if (state == GameState.paused) return; // perde açıkken sahne donar
    super.update(dt);
    _clock += dt;
    if (fever) {
      feverTime -= dt;
      if (feverTime <= 0) endFever();
    }
    if (kAutoplay) _autoplay(dt);
    if (_queue.isEmpty) return;
    final due = _queue.where((s) => s.at <= _clock).toList();
    _queue.removeWhere((s) => s.at <= _clock);
    for (final s in due) {
      s.fn();
    }
  }

  double _autoIdle = 0;
  void _autoplay(double dt) {
    if (state == GameState.gameOver) {
      _autoIdle += dt;
      if (_autoIdle > 2.5) {
        _autoIdle = 0;
        restart();
      }
      return;
    }
    if (state != GameState.idle) {
      _autoIdle = 0;
      return;
    }
    _autoIdle += dt;
    if (_autoIdle < 0.9) return;
    _autoIdle = 0;
    final miss = rng.nextDouble() < 0.15;
    final jitter = Vector2(rng.nextDouble() * 50 - 25, rng.nextDouble() * 50 - 25);
    final aim = miss
        ? Vector2(view.goalCenterX + (rng.nextBool() ? 1 : -1) * 350, view.groundY - 60)
        : target.position + jitter;
    final rGoal = kBallDiameter / 2 * view.ballGoalScale;
    final trackEndY = view.groundY - rGoal;
    final chord = Vector2(aim.x - ball.position.x, trackEndY - ball.position.y) * 0.4;
    final power = ((trackEndY - aim.y) / (view.goalHeight * 1.3)).clamp(0.0, 1.0);
    kick(chord, rng.nextDouble() * 120 - 60, 0.5, power);
  }

  void schedule(double delay, void Function() fn) =>
      _queue.add(_Scheduled(_clock + delay, fn));

  void onSplashFinished() {
    splash?.removeFromParent();
    splash = null;
    scene.position = Vector2.zero();
    target.spawn();
    ball.enter();
  }

  void onBallReady() {
    if (state != GameState.gameOver && state != GameState.paused) {
      state = GameState.idle;
    }
  }

  void kick(Vector2 chord, double dev, double tMax, double power) {
    if (state != GameState.idle) return;
    state = GameState.flying;
    ball.kick(chord, dev, tMax, power);
  }

  void haptic(void Function() fn) {
    if (hapticsOn) fn();
  }

  void setSound(bool v) {
    soundOn = v;
    _prefs?.setBool('sound', v);
  }

  void setHaptics(bool v) {
    hapticsOn = v;
    _prefs?.setBool('haptics', v);
  }

  // ---------------------------------------------------------------- sonuç

  /// Top kale düzlemine ulaştı: sonuç burada belirlenir, görsel olarak top
  /// fileden aşağı düşer; skor/hedef/kalp düşüş bittikten sonra işlenir.
  bool _pendingHit = false;

  void resolveShot(Vector2 end, double r) {
    state = GameState.resolving;
    final g = view;

    // Kaleci bloğu: top mankenin önüne düşer.
    if (keepers.any((k) => k.blocks(end, r))) {
      _pendingHit = false;
      ball.drop(end, Vector2(end.x + (rng.nextDouble() * 60 - 30), g.railY - r));
      return;
    }

    // Direk / üst direk: top düşer, yerde tekrar değerlendirilir.
    final postL = g.goalLeft - 16;
    final postR = g.goalRight + 16;
    final hitsPost = ((end.x - postL).abs() < r + 14 || (end.x - postR).abs() < r + 14) &&
        end.y > g.crossbarY - r - 20;
    final hitsBar = (end.y - g.crossbarY + 14).abs() < r + 14 && end.x > postL && end.x < postR;
    if (hitsPost || hitsBar) {
      final inward = end.x < g.goalCenterX ? 1.0 : -1.0;
      final toX = hitsBar ? end.x + rng.nextDouble() * 40 - 20 : end.x + inward * (r + 30);
      ball.drop(end, Vector2(toX, g.groundY - r));
      return;
    }

    final inMouth = end.x > g.goalLeft && end.x < g.goalRight && end.y + r > g.crossbarY;
    if (!inMouth) {
      // Auta / üstten: top görüş dışına gider.
      _pendingHit = false;
      final dir = Vector2(end.x - ball.position.x, -1).normalized();
      ball.flyOut(Vector2(dir.x * 0.6, -1)..normalize());
      return;
    }
    _pendingHit = target.visible && end.distanceTo(target.position) < target.radius + r * 0.55;
    if (_pendingHit) scene.add(NetRipple(target.position.clone()));
    final rNet = kBallDiameter / 2 * g.ballGoalScale * 0.85;
    ball.settleInNet(end, Vector2(end.x, g.groundY + 18 - rNet), g.ballGoalScale * 0.85);
  }

  /// Direkten/kaleciden düşen top yere geldi.
  void resolveDrop(Vector2 end, double r) {
    final hit = target.visible && end.distanceTo(target.position) < target.radius + r * 0.6;
    scene.add(RestingBall(end.clone(), r * 2 / kBallDiameter));
    schedule(0.45, () => hit ? _hit(end, r) : _miss(end, r));
    _scheduleNextBall(0.6);
  }

  /// File içinde yere oturdu: dinlenen top; kısa süre sonra skor/hedef.
  void onBallSettled(Vector2 end, double r) {
    scene.add(RestingBall(end.clone(), r * 2 / kBallDiameter));
    final hit = _pendingHit;
    _pendingHit = false;
    schedule(0.5, () => hit ? _hit(end, r) : _miss(end, r));
    _scheduleNextBall(0.55);
  }

  /// Auta giden top.
  void onBallOut() {
    schedule(0.3, () => _miss(ball.position, 0));
    _scheduleNextBall(0.4);
  }

  void _scheduleNextBall(double delay) {
    schedule(delay, () {
      if (lives == 0) return;
      if (rng.nextDouble() < 0.4) {
        switchView(view == kWide ? kZoom : kWide);
        schedule(0.45, ball.enter);
      } else {
        ball.enter();
      }
    });
  }

  void _hit(Vector2 end, double r) {
    final gain = fever ? 60 : 30;
    score += gain;
    streak++;
    if (score > best) {
      best = score;
      _prefs?.setInt('best', best);
    }
    scoreboard.flashScore();
    scene.add(ScorePopup(
      target.position.clone(),
      '+$gain',
      color: fever ? const Color(0xFFFFE066) : const Color(0xFFFFFFFF),
    ));
    target.shrinkAway();
    haptic(HapticFeedback.mediumImpact);
    schedule(0.7, () => target.spawn());

    if (!fever && streak >= feverStreak) startFever();
    _afterShot();
  }

  void _miss(Vector2 end, double r) {
    streak = 0;
    lives = max(0, lives - 1);
    scoreboard.flashHeart();
    haptic(HapticFeedback.lightImpact);
    if (fever) endFever();

    if (lives == 0) {
      schedule(0.7, () {
        state = GameState.gameOver;
        overlays.add(kGameOverOverlay);
      });
      return;
    }
    _afterShot();
  }

  void _afterShot() {
    if (!keepers[0].active && score >= 30) schedule(0.3, keepers[0].activate);
    if (!keepers[1].active && score >= 420) schedule(0.3, keepers[1].activate);
  }

  void startFever() {
    fever = true;
    feverTime = feverDuration;
    haptic(HapticFeedback.heavyImpact);
  }

  void endFever() {
    if (!fever) return;
    fever = false;
    streak = 0;
    scene.add(FeverBurst(Vector2(kWorldW / 2, kWorldH * 0.55)));
  }

  void switchView(ViewGeom next) {
    view = next;
    background.crossfadeTo(next.bg);
    scene.children.whereType<RestingBall>().toList().forEach((b) => b.removeFromParent());
    target.spawn(immediate: true);
  }

  // ---------------------------------------------------------------- pause / restart / exit

  GameState? _stateBeforePause;

  void pause() {
    if (state == GameState.splash || state == GameState.paused || state == GameState.gameOver) return;
    _stateBeforePause = state;
    state = GameState.paused;
    overlays.add(kPauseOverlay);
  }

  void resume() {
    if (state != GameState.paused) return;
    overlays.remove(kPauseOverlay);
    state = _stateBeforePause ?? GameState.idle;
  }

  void restart() {
    _queue.clear();
    overlays.remove(kGameOverOverlay);
    overlays.remove(kPauseOverlay);
    score = 0;
    lives = 3;
    streak = 0;
    fever = false;
    scene.children.whereType<RestingBall>().toList().forEach((b) => b.removeFromParent());
    for (final k in keepers) {
      k.deactivate();
    }
    if (view != kWide) switchView(kWide);
    target.spawn(immediate: true);
    state = GameState.resolving;
    ball.enter();
  }

  /// Sol üst çıkış butonu — Flutter tarafı bağlar.
  void Function()? onExit;
}

/// Saha, kale, top, HUD — hepsi bu kökün altında; splash'ta aşağıdan kayar.
class SceneRoot extends PositionComponent {
  SceneRoot() : super(size: Vector2(kWorldW, kWorldH));
}
