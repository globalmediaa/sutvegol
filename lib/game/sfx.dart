import 'package:flame_audio/flame_audio.dart';

/// Videonun ses kanalından kesilen efektler (assets/audio). Ses ayarı kapalıysa çalmaz.
class Sfx {
  Sfx._();

  static bool enabled = true;

  static const _files = [
    'sfx_kick.wav',
    'sfx_hit.wav',
    'sfx_miss.wav',
    'sfx_roll.wav',
    'sfx_fever_start.wav',
    'sfx_fever_hit.wav',
    'sfx_fever_end.wav',
    'sfx_gameover.wav',
    'sfx_count_end.wav',
    'sfx_splash.wav',
  ];

  static Future<void> preload() async {
    try {
      await FlameAudio.audioCache.loadAll([..._files, 'ambience.wav']);
      FlameAudio.bgm.initialize();
    } catch (_) {
      // ses yoksa oyun devam eder
    }
  }

  static bool _ambienceOn = false;

  /// Sürekli stadyum ambiyansı (videoda kayıt boyunca aynı seviyede).
  static Future<void> startAmbience() async {
    if (!enabled || _ambienceOn) return;
    _ambienceOn = true;
    try {
      await FlameAudio.bgm.play('ambience.wav', volume: 0.55);
    } catch (_) {
      _ambienceOn = false;
    }
  }

  static Future<void> stopAmbience() async {
    _ambienceOn = false;
    try {
      await FlameAudio.bgm.stop();
    } catch (_) {}
  }

  static void setEnabled(bool v) {
    enabled = v;
    if (v) {
      startAmbience();
    } else {
      stopAmbience();
    }
  }

  static void play(String name, {double volume = 1}) {
    if (!enabled) return;
    try {
      FlameAudio.play('$name.wav', volume: volume);
    } catch (_) {}
  }

  static void kick() => play('sfx_kick');
  static void hit() => play('sfx_hit');
  static void miss() => play('sfx_miss', volume: 0.9);
  static void roll() => play('sfx_roll', volume: 0.8);
  static void feverStart() => play('sfx_fever_start');
  static void feverHit() => play('sfx_fever_hit');
  static void feverEnd() => play('sfx_fever_end');
  static void gameOver() => play('sfx_gameover');
  static void countEnd() => play('sfx_count_end');
  static void splash() => play('sfx_splash', volume: 0.6);
}
