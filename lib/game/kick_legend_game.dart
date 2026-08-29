import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'geometry.dart';
import 'hud.dart';
import 'scene.dart';
import 'splash.dart';

enum GameState { splash, idle, flying, resolving, paused, gameOver }

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

  late final SceneRoot scene;
  late final Background background;
  late final Ball ball;
  late final TargetComp target;
  late final Keeper keeper;
  late final Scoreboard scoreboard;
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
    keeper = Keeper();
    ball = Ball();
    scoreboard = Scoreboard();
    scene.addAll([background, target, keeper, ball, scoreboard]);

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
    if (_queue.isEmpty) return;
    final due = _queue.where((s) => s.at <= _clock).toList();
    _queue.removeWhere((s) => s.at <= _clock);
    for (final s in due) {
      s.fn();
    }
  }

  void schedule(double delay, void Function() fn) =>
      _queue.add(_Scheduled(_clock + delay, fn));

  /// Splash bitti: saha yerleşti, ilk top gelsin.
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

  /// Kullanıcı topu fırlattı.
  void kick(Vector2 landing) {
    if (state != GameState.idle) return;
    state = GameState.flying;
    ball.kick(landing);
  }

  /// Top kale düzlemine ulaştı.
  void resolveShot(Vector2 ballEnd, double ballRadius) {
    state = GameState.resolving;
    final g = view;

    final blocked = keeper.active && keeper.blocks(ballEnd, ballRadius);
    final onTarget = !blocked &&
        target.visible &&
        ballEnd.distanceTo(target.position) <
            kTargetDiameter / 2 * target.scale.x + ballRadius * 0.55;

    final inMouth = ballEnd.x > g.goalLeft - 30 &&
        ballEnd.x < g.goalRight + 30 &&
        ballEnd.y > g.crossbarY - 40;

    if (onTarget) {
      score += 30;
      if (score > best) {
        best = score;
        _prefs?.setInt('best', best);
      }
      scoreboard.flashScore();
      scene.add(NetRipple(target.position.clone()));
      scene.add(ScorePopup(target.position.clone(), '+30'));
      target.hide();
      HapticFeedback.mediumImpact();
      schedule(0.55, () => target.spawn());
    } else {
      lives = max(0, lives - 1);
      scoreboard.flashHeart();
      HapticFeedback.lightImpact();
    }

    if (inMouth) {
      final restX =
          ballEnd.x.clamp(g.goalLeft + ballRadius, g.goalRight - ballRadius);
      scene.add(RestingBall(Vector2(restX, g.groundY - ballRadius),
          ballRadius * 2 / kBallDiameter));
    }

    if (!keeper.active && score >= 30) {
      schedule(0.3, () => keeper.activate());
    }

    if (lives == 0) {
      schedule(0.7, () {
        state = GameState.gameOver;
        overlay.showGameOver();
      });
      return;
    }

    schedule(0.5, () {
      // Kamera değişimi: sunum varyasyonu (video: birkaç şutta bir yakın plan).
      if (rng.nextDouble() < 0.4) {
        switchView(view == kWide ? kZoom : kWide);
        schedule(0.45, ball.enter);
      } else {
        ball.enter();
      }
    });
  }

  void switchView(ViewGeom next) {
    view = next;
    background.crossfadeTo(next.bg);
    scene.children.whereType<RestingBall>().toList().forEach((b) => b.removeFromParent());
    target.spawn(immediate: true);
    keeper.onViewChanged();
  }

  // ---------------------------------------------------------------- pause / restart

  GameState? _stateBeforePause;

  void pause() {
    if (state == GameState.splash ||
        state == GameState.paused ||
        state == GameState.gameOver) {
      return;
    }
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
    score = 0;
    lives = 3;
    overlay.hide();
    scene.children.whereType<RestingBall>().toList().forEach((b) => b.removeFromParent());
    keeper.deactivate();
    if (view != kWide) switchView(kWide);
    target.spawn(immediate: true);
    state = GameState.resolving;
    ball.enter();
  }
}

/// Saha, kale, top, HUD — hepsi bu kökün altında; splash'ta aşağıdan kayar.
class SceneRoot extends PositionComponent {
  SceneRoot() : super(size: Vector2(kWorldW, kWorldH));
}
