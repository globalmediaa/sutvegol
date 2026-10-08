import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fever.dart';
import 'geometry.dart';
import 'hud.dart';
import 'scene.dart';
import 'scene_art.dart';
import 'sfx.dart';
import 'shot_record.dart';
import 'splash.dart';

export 'shot_record.dart';

enum GameState { splash, idle, flying, resolving, paused, gameOver }

/// Oyunun çalışma kipi.
/// - [solo]: bugünkü tek kişilik akış (splash, tabela, duraklat, rekor kaydı).
/// - [duel]: yerel oyuncunun düello koşusu — splash yok, geri sayımla
///   `startRun()`; kamera kale+top bandına kırpılır; rekor/perde yok.
/// - [replica]: rakibin kopyası — giriş, ses, titreşim, kayıt, perde yok;
///   şutlar `applyRemoteShot` ile dışarıdan gelir, sonuçları kayıttan zorlanır.
enum GameMode { solo, duel, replica }

/// Geliştirme: `--dart-define=AUTOPLAY=true` ile oyun kendi kendine şut atar.
const bool kAutoplay = bool.fromEnvironment('AUTOPLAY');

/// Geliştirme: `--dart-define=FEVER_TEST=true` ilk toptan itibaren Kral Modu açar.
const bool kFeverTest = bool.fromEnvironment('FEVER_TEST');

/// Geliştirme: `--dart-define=STAGE=cage|stadium` ile o sahneden başlar.
const String kStageOverride = String.fromEnvironment('STAGE');

/// Flutter tarafındaki perdelerin overlay anahtarları.
const String kGameOverOverlay = 'gameOver';
const String kPauseOverlay = 'pause';

class _Scheduled {
  _Scheduled(this.at, this.fn);
  final double at;
  final void Function() fn;
}

/// Şut anında alınan ve sonuç belli olunca [ShotRecord]'a dönüşen taslak.
class _ShotCapture {
  _ShotCapture({
    required this.t,
    required this.stage,
    required this.view,
    required this.target,
    required this.chord,
    required this.dev,
    required this.tMax,
    required this.power,
    required this.keeper,
  });
  final int t;
  final Stage stage;
  final ViewGeom view;
  final Vector2? target;
  final Vector2 chord;
  final double dev;
  final double tMax;
  final double power;
  final List<double?> keeper;
  ShotPath path = ShotPath.net;
  Vector2 end = Vector2.zero();
  Vector2? drop;
}

class SutVeGolGame extends FlameGame {
  SutVeGolGame({this.mode = GameMode.solo, int? seed})
    : rng = Random(seed),
      super(
        camera: mode == GameMode.solo
            ? CameraComponent.withFixedResolution(
                width: kWorldW,
                height: kWorldH,
              )
            : CameraComponent(viewport: MaxViewport()),
      ) {
    // Her örnek kendi görsel önbelleğini kullanır: düelloda iki oyun aynı
    // anda yaşar ve Flame'in global önbelleği aynı anahtarı silip dispose eder.
    images = Images();
    if (mode == GameMode.solo) camera.viewfinder.anchor = Anchor.topLeft;
  }

  final GameMode mode;
  bool get isReplica => mode == GameMode.replica;
  bool get isDuel => mode != GameMode.solo;

  /// Oyun mantığının rastgeleliği (hedef konumu, direk sekmesi, kamera).
  /// Düelloda sunucu tohumuyla kurulur; doğruluk buna dayanmaz.
  final Random rng;

  ViewGeom view = kWide;
  Stage stage = Stage.street;
  Stage? _pendingStage;
  GameState state = GameState.splash;
  int score = 0;
  int best = 0;
  int lives = 3;
  int runShots = 0;
  int runHits = 0;
  int runMisses = 0;
  int runFeverHits = 0;
  int runMaxStreak = 0;
  DateTime _runStartedAt = DateTime.now();
  double _runStartClock = 0;

  // Seri / Kral Modu.
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
  final Map<String, Future<void>> _preparing = {};
  bool _disposed = false;

  Future<bool> _addGenerated(String key, Future<ui.Image> generated) async {
    final image = await generated;
    if (_disposed) {
      image.dispose();
      return false;
    }
    images.add(key, image);
    return true;
  }

  @override
  void onDispose() {
    _disposed = true;
    pauseEngine();
    _queue.clear();
    _inbox.clear();
    onShotResolved = null;
    onRunFinished = null;
    images.clearCache();
    super.onDispose();
  }

  // Şut kaydı (düello): yerel şutun taslağı ve kopyaya zorlanan sonuç.
  _ShotCapture? _capture;
  ShotRecord? _forced;
  int _recordsEmitted = 0;
  final List<ShotRecord> _inbox = [];
  int _lastApplied = 0;

  /// Her şut sonuçlandığında (skor/kalp işlendiğinde) tam kaydı verir.
  void Function(ShotRecord record)? onShotResolved;

  @override
  Color backgroundColor() => const Color(0xFF0B1226);

  @override
  Future<void> onLoad() async {
    if (kStageOverride.isNotEmpty && mode == GameMode.solo) {
      stage = Stage.values.firstWhere(
        (s) => s.name == kStageOverride,
        orElse: () => Stage.street,
      );
    }
    // Tüm görseller koddan üretilir (scene_art.dart).
    if (!await _addGenerated('ball', SceneArt.ball())) return;
    if (!await _addGenerated('ball_king', SceneArt.ball(king: true))) return;
    if (mode == GameMode.solo) {
      if (!await _addGenerated('splash_sky', SceneArt.splashSky())) return;
    }
    await _prepareStage(stage);
    if (_disposed) return;

    _prefs = await SharedPreferences.getInstance();
    best = isReplica ? 0 : _prefs?.getInt('best') ?? 0;
    soundOn = _prefs?.getBool('sound') ?? true;
    hapticsOn = !isReplica && (_prefs?.getBool('haptics') ?? true);
    if (!isReplica) {
      Sfx.enabled = soundOn;
      await Sfx.preload();
      Sfx.startAmbience(stage);
    }

    scene = SceneRoot()
      ..position = Vector2(0, mode == GameMode.solo ? kWorldH : 0);
    background = Background();
    target = TargetComp();
    keepers = [Keeper(), Keeper(phaseOffset: pi / 2, periodScale: 0.8)];
    ball = Ball();
    scoreboard = Scoreboard();
    feverOverlay = FeverOverlay();
    scene.addAll([
      background,
      target,
      ...keepers,
      ball,
      feverOverlay,
      scoreboard,
    ]);

    input = InputLayer();
    switch (mode) {
      case GameMode.solo:
        splash = SplashLayer();
        world.addAll([scene, input, splash!]);
      case GameMode.duel:
        world.addAll([scene, input]);
      case GameMode.replica:
        world.add(scene); // giriş katmanı yok: dokunuşlar işlenmez
    }
    _prewarmNextStage();
  }

  /// Sahnenin kamera görünümlerini üretip görsel cache'ine koyar. Düelloda
  /// yalnız geniş görünüm (yakın kamera kapalı) ve tabela/duraklat çizilmez.
  Future<void> _prepareStage(Stage s) async {
    for (final g in isDuel ? [kWide] : [kWide, kZoom]) {
      final key = g.bgKey(s);
      if (images.containsKey(key)) continue;
      final pending = _preparing[key];
      if (pending != null) {
        await pending;
        continue;
      }
      final job =
          SceneArt.background(
            s,
            g,
            hud: !isDuel,
            region: isDuel ? kDuelBand : null,
          ).then((img) {
            if (_disposed || images.containsKey(key)) {
              img.dispose();
            } else {
              images.add(key, img);
            }
          });
      _preparing[key] = job;
      try {
        await job;
      } finally {
        _preparing.remove(key);
      }
    }
  }

  /// Düello: bir sonraki sahnenin arka planını önceden üretir ki sahne
  /// geçişi görsel üretimini beklemesin (iki cihazda zamanlama aynı kalsın).
  void _prewarmNextStage() {
    if (!isDuel) return;
    final i = stage.index + 1;
    if (i >= Stage.values.length) return;
    _prepareStage(Stage.values[i]).ignore();
  }

  void _dropStage(Stage s) {
    for (final g in [kWide, kZoom]) {
      final key = g.bgKey(s);
      if (images.containsKey(key)) images.clear(key);
    }
  }

  // ---------------------------------------------------------------- kamera

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isDuel) _fitDuelBand(size);
  }

  /// Düello kameraları: kale + top bandını ([kDuelBand]) genişliğe sığdırır;
  /// bant yüksekliği sığmıyorsa küçültüp yanlardan boşluk bırakır.
  void _fitDuelBand(Vector2 size) {
    if (size.x <= 0 || size.y <= 0) return;
    camera.viewfinder.anchor = Anchor.topLeft;
    final zoom = min(size.x / kWorldW, size.y / kDuelBand.height);
    final visibleW = size.x / zoom;
    final visibleH = size.y / zoom;
    camera.viewfinder.zoom = zoom;
    camera.viewfinder.position = Vector2(
      (kWorldW - visibleW) / 2,
      kDuelBand.center.dy - visibleH / 2,
    );
  }

  // ---------------------------------------------------------------- akış

  @override
  void update(double dt) {
    if (state == GameState.paused) return; // perde açıkken sahne donar
    // Kısa kare kayıplarında süreyi koru; fiziği küçük adımlarla ilerlet.
    var remaining = dt.clamp(0.0, 0.1);
    while (remaining > 0) {
      final step = min(remaining, 1 / 120);
      super.update(step);
      _step(step);
      remaining -= step;
    }
  }

  void _step(double dt) {
    _clock += dt;
    if (fever) {
      feverTime -= dt;
      if (feverTime <= 0) endFever();
    }
    if (kAutoplay && !isReplica) _autoplay(dt);
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
      if (_autoIdle > 2.5 && mode == GameMode.solo) {
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
    autoShot();
  }

  /// Bot şutu: %85 hedefe (hafif sapmayla), %15 bilerek dışarı.
  void autoShot() {
    final miss = rng.nextDouble() < 0.15;
    final jitter = Vector2(
      rng.nextDouble() * 50 - 25,
      rng.nextDouble() * 50 - 25,
    );
    final aim = miss
        ? Vector2(
            view.goalCenterX + (rng.nextBool() ? 1 : -1) * 350,
            view.groundY - 60,
          )
        : target.position + jitter;
    final rGoal = kBallDiameter / 2 * view.ballGoalScale;
    final trackEndY = view.groundY - rGoal;
    final chord =
        Vector2(aim.x - ball.position.x, trackEndY - ball.position.y) * 0.4;
    final power = ((trackEndY - aim.y) / (view.goalHeight * 1.15)).clamp(
      0.0,
      1.0,
    );
    kick(chord, rng.nextDouble() * 120 - 60, 0.5, power);
  }

  void schedule(double delay, void Function() fn) =>
      _queue.add(_Scheduled(_clock + delay, fn));

  /// Ses yan etkileri yalnız yerel oyunlarda (kopya sessizdir).
  void sfx(void Function() fn) {
    if (!isReplica) fn();
  }

  void onSplashFinished() {
    splash?.removeFromParent();
    splash = null;
    startRun();
  }

  /// Koşuyu başlatır: hedef gelir, top sahaya girer. Solo'da splash bitince,
  /// düelloda geri sayım sıfırlanınca (her iki oyun için) çağrılır.
  void startRun() {
    if (state != GameState.splash) return;
    scene.position = Vector2.zero();
    target.spawn();
    ball.enter();
    _resetRunStats();
    onRunStarted?.call();
  }

  void onBallReady() {
    if (state != GameState.gameOver && state != GameState.paused) {
      state = GameState.idle;
    }
    if (kFeverTest && !fever) startFever();
    if (isReplica) _drainInbox();
  }

  void kick(Vector2 chord, double dev, double tMax, double power) {
    if (state != GameState.idle) return;
    state = GameState.flying;
    runShots++;
    _capture = _ShotCapture(
      t: ((_clock - _runStartClock) * 1000).round(),
      stage: stage,
      view: view,
      target: target.visible ? target.position.clone() : null,
      chord: chord.clone(),
      dev: dev,
      tMax: tMax,
      power: power,
      keeper: [for (final k in keepers) k.active ? k.elapsed : null],
    );
    haptic(HapticFeedback.lightImpact);
    sfx(Sfx.kick);
    ball.kick(chord, dev, tMax, power);
  }

  void haptic(void Function() fn) {
    if (hapticsOn) fn();
  }

  void setSound(bool v) {
    soundOn = v;
    if (isReplica) return;
    Sfx.setEnabled(v, stage);
    _prefs?.setBool('sound', v);
  }

  void setHaptics(bool v) {
    if (isReplica) return;
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
    final forced = _forced;
    if (forced != null) {
      _resolveForced(forced, end, r);
      return;
    }
    final c = _capture;
    c?.end = end.clone();

    // Kaleci bloğu: top mankenin önüne düşer.
    if (keepers.any((k) => k.blocks(end, r))) {
      _pendingHit = false;
      final to = Vector2(end.x + (rng.nextDouble() * 60 - 30), g.railY - r);
      c
        ?..path = ShotPath.keeper
        ..drop = to.clone();
      ball.drop(end, to);
      return;
    }

    // Direk / üst direk: top düşer, yerde tekrar değerlendirilir.
    final postL = g.goalLeft - 16;
    final postR = g.goalRight + 16;
    final hitsPost =
        ((end.x - postL).abs() < r + 14 || (end.x - postR).abs() < r + 14) &&
        end.y > g.crossbarY - r - 20;
    final hitsBar =
        (end.y - g.crossbarY + 14).abs() < r + 14 &&
        end.x > postL &&
        end.x < postR;
    if (hitsPost || hitsBar) {
      final inward = end.x < g.goalCenterX ? 1.0 : -1.0;
      final toX = hitsBar
          ? end.x + rng.nextDouble() * 40 - 20
          : end.x + inward * (r + 30);
      final to = Vector2(toX, g.groundY - r);
      c
        ?..path = ShotPath.post
        ..drop = to.clone();
      ball.drop(end, to);
      return;
    }

    final inMouth =
        end.x > g.goalLeft && end.x < g.goalRight && end.y + r > g.crossbarY;
    if (!inMouth) {
      // Auta / üstten: top görüş dışına gider.
      _pendingHit = false;
      c?.path = ShotPath.out;
      final velocity = ball.flightVelocity;
      ball.flyOut(
        velocity.length2 > 0 ? velocity.normalized() : Vector2(0, -1),
      );
      return;
    }
    c?.path = ShotPath.net;
    _pendingHit =
        target.visible &&
        end.distanceTo(target.position) < target.radius + r * 0.55;
    if (_pendingHit) {
      scene.add(NetRipple(target.position.clone(), stage.accent));
    }
    final rNet = kBallDiameter / 2 * g.ballGoalScale * 0.85;
    ball.settleInNet(
      end,
      Vector2(end.x, g.groundY + 18 - rNet),
      g.ballGoalScale * 0.85,
    );
  }

  /// Kopya: yol ve isabet rakibin kaydından; top yine girdiden uçtu.
  void _resolveForced(ShotRecord f, Vector2 end, double r) {
    final g = view;
    switch (f.path) {
      case ShotPath.keeper:
      case ShotPath.post:
        _pendingHit = false;
        ball.drop(end, f.drop?.clone() ?? Vector2(end.x, g.groundY - r));
      case ShotPath.out:
        _pendingHit = false;
        final velocity = ball.flightVelocity;
        ball.flyOut(
          velocity.length2 > 0 ? velocity.normalized() : Vector2(0, -1),
        );
      case ShotPath.net:
        _pendingHit = f.hit;
        if (f.hit) {
          scene.add(NetRipple(target.position.clone(), stage.accent));
        }
        final rNet = kBallDiameter / 2 * g.ballGoalScale * 0.85;
        ball.settleInNet(
          end,
          Vector2(end.x, g.groundY + 18 - rNet),
          g.ballGoalScale * 0.85,
        );
    }
  }

  /// Direkten/kaleciden düşen top yere geldi.
  void resolveDrop(Vector2 end, double r) {
    final hit =
        _forced?.hit ??
        (target.visible &&
            end.distanceTo(target.position) < target.radius + r * 0.6);
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
      if (lives == 0 || state == GameState.gameOver) return;
      final next = _pendingStage;
      if (next != null) {
        _pendingStage = null;
        _enterStage(next);
        return;
      }
      if (!isDuel && rng.nextDouble() < 0.4) {
        switchView(view == kWide ? kZoom : kWide);
        schedule(0.45, ball.enter);
      } else {
        ball.enter();
      }
    });
  }

  /// Sahne geçişi: yeni arka planlar üretilir, geniş kameraya dönülür,
  /// afiş + ses; top kısa süre sonra gelir.
  Future<void> _enterStage(Stage next) async {
    final prev = stage;
    await _prepareStage(next);
    if (_disposed || state == GameState.gameOver) return;
    stage = next;
    view = kWide;
    background.crossfadeTo(view.bgKey(stage));
    scene.children.whereType<RestingBall>().toList().forEach(
      (b) => b.removeFromParent(),
    );
    target.spawn(immediate: true);
    scene.add(StageBanner(next));
    sfx(Sfx.stageUp);
    sfx(() => Sfx.startAmbience(stage));
    haptic(HapticFeedback.heavyImpact);
    schedule(1.2, ball.enter);
    schedule(1.0, () => _dropStage(prev));
    _prewarmNextStage();
  }

  void _hit(Vector2 end, double r) {
    final f = _forced;
    final before = score;
    final gain = fever ? 60 : 30;
    score += gain;
    runHits++;
    if (fever) runFeverHits++;
    streak++;
    runMaxStreak = max(runMaxStreak, streak);
    if (f != null) _syncFromRecord(f);
    if (mode == GameMode.solo && score > best) {
      best = score;
      _prefs?.setInt('best', best);
    }
    scoreboard.flashScore();
    scene.add(
      ScorePopup(
        target.position.clone(),
        '+${score - before}',
        color: fever ? const Color(0xFFFFE066) : const Color(0xFFFFFFFF),
      ),
    );
    target.shrinkAway();
    if (fever) {
      sfx(Sfx.feverHit);
    } else {
      sfx(Sfx.hit);
    }
    haptic(HapticFeedback.mediumImpact);
    schedule(0.7, () => target.spawn());

    if (f == null && !fever && streak >= feverStreak) startFever();
    final ns = Stage.forScore(score);
    if (ns.index > stage.index && _pendingStage == null) _pendingStage = ns;
    _afterShot();
    _emitRecord(hit: true);
  }

  void _miss(Vector2 end, double r) {
    final f = _forced;
    runMisses++;
    streak = 0;
    lives = max(0, lives - 1);
    if (f != null) _syncFromRecord(f);
    scoreboard.flashHeart();
    sfx(Sfx.miss);
    haptic(HapticFeedback.lightImpact);
    if (f == null && fever) endFever();

    if (lives == 0) {
      _emitRecord(hit: false);
      schedule(0.7, () {
        state = GameState.gameOver;
        sfx(Sfx.gameOver);
        if (mode == GameMode.solo) overlays.add(kGameOverOverlay);
        onRunFinished?.call(runSummary);
      });
      return;
    }
    _afterShot();
    _emitRecord(hit: false);
  }

  /// Taslaktaki girdi + sonuç + güncel durum → [ShotRecord] → [onShotResolved].
  void _emitRecord({required bool hit}) {
    final c = _capture;
    _capture = null;
    if (c == null || isReplica) return;
    final record = ShotRecord(
      seq: ++_recordsEmitted,
      t: c.t,
      stage: c.stage.name,
      view: c.view.name,
      target: c.target,
      chord: c.chord,
      dev: c.dev,
      tMax: c.tMax,
      power: c.power,
      keeper: c.keeper,
      path: c.path,
      hit: hit,
      end: c.end,
      drop: c.drop,
      score: score,
      lives: lives,
      streak: streak,
      fever: fever,
      feverLeft: fever ? max(0, feverTime) : 0,
      shots: runShots,
      hits: runHits,
      misses: runMisses,
      feverHits: runFeverHits,
      maxStreak: runMaxStreak,
    );
    onShotResolved?.call(record);
  }

  /// Kopya: sayaçlar ve Kral Modu durumu rakibin kaydından alınır.
  void _syncFromRecord(ShotRecord f) {
    _forced = null;
    score = f.score;
    lives = f.lives;
    streak = f.streak;
    runShots = f.shots;
    runHits = f.hits;
    runMisses = f.misses;
    runFeverHits = f.feverHits;
    runMaxStreak = f.maxStreak;
    if (f.fever && !fever) startFever();
    if (!f.fever && fever) endFever();
    if (fever) feverTime = f.feverLeft;
  }

  void _afterShot() {
    if (!keepers[0].active && score >= 30) schedule(0.3, keepers[0].activate);
    if (!keepers[1].active && score >= 420) schedule(0.3, keepers[1].activate);
  }

  void startFever() {
    fever = true;
    feverTime = feverDuration;
    sfx(Sfx.feverStart);
    sfx(Sfx.startFeverLoop);
    haptic(HapticFeedback.heavyImpact);
  }

  void endFever() {
    if (!fever) return;
    fever = false;
    streak = 0;
    sfx(Sfx.stopFeverLoop);
    sfx(Sfx.feverEnd);
    scene.add(FeverBurst(Vector2(kWorldW / 2, kWorldH * 0.55)));
  }

  void switchView(ViewGeom next) {
    view = next;
    background.crossfadeTo(next.bgKey(stage));
    scene.children.whereType<RestingBall>().toList().forEach(
      (b) => b.removeFromParent(),
    );
    target.spawn(immediate: true);
  }

  // ---------------------------------------------------------------- düello kopyası

  /// Rakibin şut kaydını sıraya alır; kopya boşta olunca uygular. Tekrar gelen
  /// ya da eski kayıtlar yok sayılır; yığılma olursa son kayda atlanır.
  void applyRemoteShot(ShotRecord record) {
    assert(isReplica, 'applyRemoteShot yalnız kopya oyunda');
    if (!isReplica || record.seq <= _lastApplied) return;
    if (_inbox.any((r) => r.seq == record.seq)) return;
    _inbox
      ..add(record)
      ..sort((a, b) => a.seq.compareTo(b.seq));
    _drainInbox();
  }

  /// Uygulanmış son kayıt numarası (kopya).
  int get lastAppliedSeq => _lastApplied;

  /// Bekleyen kayıt sayısı (kopya).
  int get pendingRemoteShots => _inbox.length;

  void _drainInbox() {
    if (_inbox.isEmpty || state == GameState.gameOver) return;
    if (_inbox.length > 2) {
      // Kopya yetişemiyor (yeniden bağlanma vb.): son duruma atla.
      final last = _inbox.last;
      _inbox.clear();
      _fastForward(last);
      return;
    }
    if (state != GameState.idle) return;
    final r = _inbox.first;
    final wanted = Stage.values.byName(r.stage);
    if (wanted != stage) {
      // Rakip sahne atlamış: önce sahneye geç, top gelince devam et.
      state = GameState.resolving;
      _pendingStage = null;
      _enterStage(wanted);
      return;
    }
    _inbox.removeAt(0);
    _lastApplied = r.seq;
    if (r.target != null) target.spawnAt(r.target!);
    for (var i = 0; i < keepers.length && i < r.keeper.length; i++) {
      keepers[i].syncTime(r.keeper[i]);
    }
    _forced = r;
    kick(r.chord, r.dev, r.tMax, r.power);
  }

  /// Kopyayı animasyonsuz olarak kaydın SONRAKİ durumuna getirir.
  void _fastForward(ShotRecord r) {
    _lastApplied = r.seq;
    _forced = null;
    _capture = null;
    _queue.clear();
    ball.hide();
    scene.children.whereType<RestingBall>().toList().forEach(
      (b) => b.removeFromParent(),
    );
    _syncFromRecord(r);
    for (var i = 0; i < keepers.length && i < r.keeper.length; i++) {
      keepers[i].syncTime(r.keeper[i]);
    }
    _afterShot();
    state = GameState.resolving;
    final wanted = Stage.values.byName(r.stage);
    if (r.lives == 0) {
      state = GameState.gameOver;
      onRunFinished?.call(runSummary);
      return;
    }
    if (wanted != stage) {
      _pendingStage = null;
      _enterStage(wanted);
      return;
    }
    target.spawn(immediate: true);
    ball.enter();
  }

  /// Koşuyu dışarıdan bitirir (düello süresi doldu / rakip bitirdi):
  /// perde eklenmez, uçmakta olan top sayılmaz.
  void finishRun() {
    if (state == GameState.gameOver || state == GameState.splash) return;
    input.cancelGesture();
    _queue.clear();
    _capture = null;
    _forced = null;
    _inbox.clear();
    ball.hide();
    target.hide();
    if (fever) endFever();
    state = GameState.gameOver;
    onRunFinished?.call(runSummary);
  }

  // ---------------------------------------------------------------- pause / restart / exit

  GameState? _stateBeforePause;

  void pause() {
    if (isDuel ||
        state == GameState.splash ||
        state == GameState.paused ||
        state == GameState.gameOver) {
      return;
    }
    input.cancelGesture();
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
    if (isDuel) return;
    final completed = state == GameState.gameOver;
    if (!completed && runShots > 0) onRunFinished?.call(runSummary);
    input.cancelGesture();
    _queue.clear();
    _capture = null;
    overlays.remove(kGameOverOverlay);
    overlays.remove(kPauseOverlay);
    score = 0;
    lives = 3;
    streak = 0;
    fever = false;
    _resetRunStats();
    onRunStarted?.call();
    _pendingStage = null;
    Sfx.stopFeverLoop();
    scene.children.whereType<RestingBall>().toList().forEach(
      (b) => b.removeFromParent(),
    );
    for (final k in keepers) {
      k.deactivate();
    }
    state = GameState.resolving;
    final first = kStageOverride.isNotEmpty ? stage : Stage.street;
    if (stage != first) {
      final prev = stage;
      _prepareStage(first).then((_) {
        stage = first;
        view = kWide;
        background.crossfadeTo(view.bgKey(stage));
        target.spawn(immediate: true);
        Sfx.startAmbience(stage);
        schedule(0.5, ball.enter);
        schedule(1.0, () => _dropStage(prev));
      });
      return;
    }
    if (view != kWide) switchView(kWide);
    target.spawn(immediate: true);
    ball.enter();
  }

  /// Sol üst çıkış butonu — Flutter tarafı bağlar.
  void Function()? onExit;
  void Function()? onRunStarted;
  void Function(GameRunSummary summary)? onRunFinished;

  void _resetRunStats() {
    runShots = 0;
    runHits = 0;
    runMisses = 0;
    runFeverHits = 0;
    runMaxStreak = 0;
    _recordsEmitted = 0;
    _runStartedAt = DateTime.now();
    _runStartClock = _clock;
  }

  GameRunSummary get runSummary => GameRunSummary(
    score: score,
    shots: runShots,
    hits: runHits,
    misses: runMisses,
    feverHits: runFeverHits,
    maxStreak: runMaxStreak,
    durationMs: DateTime.now().difference(_runStartedAt).inMilliseconds,
    stage: stage.name,
  );
}

class GameRunSummary {
  const GameRunSummary({
    required this.score,
    required this.shots,
    required this.hits,
    required this.misses,
    required this.feverHits,
    required this.maxStreak,
    required this.durationMs,
    required this.stage,
  });
  final int score, shots, hits, misses, feverHits, maxStreak, durationMs;
  final String stage;
}

/// Saha, kale, top, HUD — hepsi bu kökün altında; splash'ta aşağıdan kayar.
class SceneRoot extends PositionComponent {
  SceneRoot() : super(size: Vector2(kWorldW, kWorldH));
}
