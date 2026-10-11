import 'package:shared_preferences/shared_preferences.dart';

/// İlk açılış rehberinin kalıcı durumu. Oyunun mevcut tercih kaydını
/// (SharedPreferences) kullanır; ayrı dosya ya da sunucu kaydı yoktur.
class TutorialProgress {
  TutorialProgress._();

  /// Rehber bitti ya da "Geç" ile kapatıldı: bir daha kendiliğinden açılmaz.
  static const String doneKey = 'tutorial_done';

  /// Rehberden önceki sürümlerde oynamış oyuncunun izleri: rekor ya da
  /// duraklat menüsünde değiştirilmiş ses/titreşim ayarı.
  static bool hasLegacyProgress(SharedPreferences prefs) =>
      (prefs.getInt('best') ?? 0) > 0 ||
      prefs.containsKey('sound') ||
      prefs.containsKey('haptics');

  /// Rehber gösterilmeli mi? İlerlemesi olan eski oyuncu için bayrak sessizce
  /// yazılır; böylece güncellemeden sonra rehber hiç çıkmaz.
  static bool shouldShow(SharedPreferences prefs) {
    if (prefs.getBool(doneKey) ?? false) return false;
    if (hasLegacyProgress(prefs)) {
      prefs.setBool(doneKey, true);
      return false;
    }
    return true;
  }

  static Future<void> markDone(SharedPreferences prefs) =>
      prefs.setBool(doneKey, true);
}
