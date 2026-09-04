import 'package:flame_audio/flame_audio.dart';

import 'geometry.dart';

/// Sentezle üretilmiş ses seti (assets/audio, tools/make_audio.py).
/// Ses ayarı kapalıysa çalmaz; testlerde eklenti olmadığından tamamen atlanır.
class Sfx {
  Sfx._();

  static bool enabled = true;

  /// Testlerde platform eklentisi yok: yükleme ve çalma tamamen atlanır.
  static bool skipInit = false;

  static const _files = [
    'sfx_kick.wav',
    'sfx_hit.wav',
    'sfx_miss.wav',
    'sfx_roll.wav',
    'sfx_king_start.wav',
    'sfx_king_hit.wav',
    'sfx_king_end.wav',
    'sfx_gameover.wav',
    'sfx_count_end.wav',
    'sfx_splash.wav',
    'sfx_stage_up.wav',
  ];

  static String _ambienceFile(Stage s) => 'amb_${s.name}.wav';

  static Future<void> preload() async {
    if (skipInit) return;
    try {
      await FlameAudio.audioCache.loadAll([
        ..._files,
        'king_loop.wav',
        for (final s in Stage.values) _ambienceFile(s),
      ]);
      FlameAudio.bgm.initialize();
    } catch (_) {
      // ses yoksa oyun devam eder
    }
  }

  static Stage? _ambience;

  /// Sahneye özel sürekli ambiyans (sokak trafiği / gece halı saha / tribün).
  static Future<void> startAmbience(Stage s) async {
    if (skipInit || !enabled || _ambience == s) return;
    _ambience = s;
    try {
      await FlameAudio.bgm.stop();
      await FlameAudio.bgm.play(_ambienceFile(s), volume: 0.5);
    } catch (_) {
      _ambience = null;
    }
  }

  static Future<void> stopAmbience() async {
    _ambience = null;
    try {
      await FlameAudio.bgm.stop();
    } catch (_) {}
  }

  static AudioPlayer? _feverLoop;

  /// Kral Modu süresince alev çıtırtısı + parıltı döngüsü.
  static Future<void> startFeverLoop() async {
    if (skipInit || !enabled || _feverLoop != null) return;
    try {
      _feverLoop = await FlameAudio.loopLongAudio('king_loop.wav', volume: 0.35);
    } catch (_) {}
  }

  static Future<void> stopFeverLoop() async {
    final p = _feverLoop;
    _feverLoop = null;
    try {
      await p?.stop();
      await p?.dispose();
    } catch (_) {}
  }

  static void setEnabled(bool v, Stage stage) {
    enabled = v;
    if (v) {
      startAmbience(stage);
    } else {
      stopAmbience();
      stopFeverLoop();
    }
  }

  static void play(String name, {double volume = 1}) {
    if (skipInit || !enabled) return;
    try {
      // Bir sonraki karede çal: dokunma/karar karesini bloklamasın.
      Future<void>.microtask(() => FlameAudio.play('$name.wav', volume: volume));
    } catch (_) {}
  }

  static void kick() => play('sfx_kick');
  static void hit() => play('sfx_hit');
  static void miss() => play('sfx_miss', volume: 0.9);
  static void roll() => play('sfx_roll', volume: 0.8);
  static void feverStart() => play('sfx_king_start');
  static void feverHit() => play('sfx_king_hit');
  static void feverEnd() => play('sfx_king_end');
  static void gameOver() => play('sfx_gameover');
  static void countEnd() => play('sfx_count_end');
  static void splash() => play('sfx_splash', volume: 0.6);
  static void stageUp() => play('sfx_stage_up', volume: 0.9);
}
