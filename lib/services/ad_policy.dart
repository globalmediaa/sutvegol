/// Reklam sıklığı kuralları (saf Dart; testler saati verir).
///
/// - Oyun sırasında hiçbir reklam yok; yalnız koşu/maç aralarında.
/// - Yeni oyuncu ilk [graceRuns] koşuda geçiş reklamı görmez.
/// - Tek kişilik: her [runsPerInterstitial] koşuda bir, "TEKRAR OYNA"da.
/// - Düello: her [duelsPerInterstitial] maçta bir, sonuç ekranından çıkarken
///   (rövanşta asla).
/// - İki tam ekran reklam (ödüllü dahil) arasında en az [minGap].
/// - Ödüllü "1 hak daha" koşu başına bir kez, en az bir gol atılmışsa.
class AdPolicy {
  AdPolicy({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  static const int graceRuns = 3;
  static const int runsPerInterstitial = 3;
  static const int duelsPerInterstitial = 2;
  static const Duration minGap = Duration(seconds: 90);

  /// "Kral Modu ile başla" teklifi bu kadar koşudan sonra açılır.
  static const int feverOfferAfterRuns = 2;

  /// Kurulumdan beri biten tek kişilik koşular (kalıcı; [AdService] yazar).
  int totalRuns = 0;
  int runsSinceInterstitial = 0;
  int duelsSinceInterstitial = 0;
  DateTime? lastFullscreen;

  void runFinished() {
    totalRuns++;
    runsSinceInterstitial++;
  }

  void duelFinished() => duelsSinceInterstitial++;

  bool get _gapOk {
    final last = lastFullscreen;
    return last == null || _now().difference(last) >= minGap;
  }

  bool get soloInterstitialDue =>
      totalRuns >= graceRuns &&
      runsSinceInterstitial >= runsPerInterstitial &&
      _gapOk;

  bool get duelInterstitialDue =>
      duelsSinceInterstitial >= duelsPerInterstitial && _gapOk;

  bool canOfferContinue({required int score, required bool usedThisRun}) =>
      !usedThisRun && score > 0;

  bool get canOfferFeverStart => totalRuns >= feverOfferAfterRuns;

  /// Tam ekran reklam gösterildi: aralık sayacı başlar; geçiş reklamıysa
  /// koşu/maç sayaçları sıfırlanır (ödüllü izlemek sırayı bozmaz).
  void fullscreenShown({required bool interstitial}) {
    lastFullscreen = _now();
    if (interstitial) {
      runsSinceInterstitial = 0;
      duelsSinceInterstitial = 0;
    }
  }
}
