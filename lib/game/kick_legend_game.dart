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

/// Flutter tarafındaki game over perdesinin overlay anahtarı.
const String kGameOverOverlay = 'gameOver';

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
  late final OverlayLayer overlay;
  SplashLayer? splash;

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
    overlay = OverlayLayer();
    splash = SplashLayer();
    world.addAll([scene, input, overlay, splash!]);
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
    kick(aim, rng.nextDouble() * 300 - 150);
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

  void kick(Vector2 landing, double curve) {
    if (state != GameState.idle) return;
    state = GameState.flying;
    ball.kick(landing, curve);
  }

  // ---------------------------------------------------------------- sonuç

  /// Top kale düzlemine ulaştı.
  void resolveShot(Vector2 end, double r) {
    state = GameState.resolving;
    final g = view;

    // Kaleci bloğu.
    if (keepers.any((k) => k.blocks(end, r))) {
      _miss(end, r, inMouth: true);
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
    if (inMouth && target.visible && end.distanceTo(target.position) < target.radius + r * 0.55) {
      _hit(end, r);
    } else {
      _miss(end, r, inMouth: inMouth);
    }
  }

  /// Direkten düşen top yere geldi.
  void resolveDrop(Vector2 end, double r) {
    if (target.visible && end.distanceTo(target.position) < target.radius + r * 0.6) {
      _hit(end, r);
    } else {
      _miss(end, r, inMouth: true);
    }
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
    scene.add(NetRipple(target.position.clone()));
    scene.add(ScorePopup(
      target.position.clone(),
      '+$gain',
      color: fever ? const Color(0xFFFFE066) : const Color(0xFFFFFFFF),
    ));
    target.hide();
    HapticFeedback.mediumImpact();
    schedule(0.55, () => target.spawn());

    if (!fever && streak >= feverStreak) startFever();

    _restBall(end, r);
    _afterShot();
  }

  void _miss(Vector2 end, double r, {required bool inMouth}) {
    streak = 0;
    lives = max(0, lives - 1);
    scoreboard.flashHeart();
    HapticFeedback.lightImpact();
    if (fever) endFever();
    if (inMouth) _restBall(end, r);

    if (lives == 0) {
      schedule(0.7, () {
        state = GameState.gameOver;
        overlays.add(kGameOverOverlay);
      });
      return;
    }
    _afterShot();
  }

  void _restBall(Vector2 end, double r) {
    final g = view;
    final restX = end.x.clamp(g.goalLeft + r, g.goalRight - r);
    scene.add(RestingBall(Vector2(restX, g.groundY - r), r * 2 / kBallDiameter));
  }

  void _afterShot() {
    if (!keepers[0].active && score >= 30) schedule(0.3, keepers[0].activate);
    if (!keepers[1].active && score >= 420) schedule(0.3, keepers[1].activate);

    schedule(0.5, () {
      if (rng.nextDouble() < 0.4) {
        switchView(view == kWide ? kZoom : kWide);
        schedule(0.45, ball.enter);
      } else {
        ball.enter();
      }
    });
  }

  void startFever() {
    fever = true;
    feverTime = feverDuration;
    HapticFeedback.heavyImpact();
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
    overlay.showPaused();
  }

  void resume() {
    if (state != GameState.paused) return;
    overlay.hide();
    state = _stateBeforePause ?? GameState.idle;
  }

  void restart() {
    _queue.clear();
    overlays.remove(kGameOverOverlay);
    score = 0;
    lives = 3;
    streak = 0;
    fever = false;
    overlay.hide();
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
