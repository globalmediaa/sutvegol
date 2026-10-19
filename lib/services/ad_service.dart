import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_policy.dart';

/// Geliştirme / mağaza çekimi: `--dart-define=NO_ADS=true` reklamları tamamen kapatır.
const bool kNoAds = bool.fromEnvironment('NO_ADS');

/// Reklam birimleri. Mağaza birimleri gizli değildir (uygulama paketinin
/// içinde durur), bu yüzden burada: release derlemesi onları kullanır ve
/// derleme komutunda unutulamaz. Debug/profile derlemeleri ve
/// `--dart-define=ADMOB_TEST=true` Google'ın test birimlerini kullanır:
/// geliştiricinin gerçek reklamı görmesi/tıklaması AdMob hesabını geçersiz
/// trafik nedeniyle kapattırabilir. `--dart-define=ADMOB_REWARDED|ADMOB_INTERSTITIAL|ADMOB_BANNER`
/// verilirse koddakinin önüne geçer. Uygulama kimlikleri: iOS
/// `ios/Flutter/Ads.xcconfig`, Android `android/app/build.gradle.kts`.
class AdUnits {
  AdUnits._();

  /// Telefonda release testi: gerçek birimler yerine test reklamı.
  static const bool forceTest = bool.fromEnvironment('ADMOB_TEST');

  static const _rewardedDefine = String.fromEnvironment('ADMOB_REWARDED');
  static const _interstitialDefine = String.fromEnvironment(
    'ADMOB_INTERSTITIAL',
  );
  static const _bannerDefine = String.fromEnvironment('ADMOB_BANNER');

  // AdMob · iOS uygulaması ca-app-pub-5952420054302125~9606206828
  // (uygulama kimliği ios/Flutter/Ads.xcconfig içinde).
  static const _iosRewarded = 'ca-app-pub-5952420054302125/6194003054';
  static const _iosInterstitial = 'ca-app-pub-5952420054302125/3567839719';
  static const _iosBanner = 'ca-app-pub-5952420054302125/9941676376';

  // AdMob · Android uygulaması ca-app-pub-5952420054302125~9450721786
  // (uygulama kimliği android/app/build.gradle.kts içinde).
  static const _androidRewarded = 'ca-app-pub-5952420054302125/5898489580';
  static const _androidInterstitial = 'ca-app-pub-5952420054302125/9346780007';
  static const _androidBanner = 'ca-app-pub-5952420054302125/8797035537';

  static const _testPublisher = 'ca-app-pub-3940256099942544/';

  static String _pick(String define, String ios, String android, String test) {
    if (forceTest) return test;
    if (define.isNotEmpty) return define;
    final store = Platform.isIOS ? ios : android;
    return kReleaseMode && store.isNotEmpty ? store : test;
  }

  static bool get usingTestUnits => [
    rewarded,
    interstitial,
    banner(),
  ].any((unit) => unit.startsWith(_testPublisher));

  static String get rewarded => _pick(
    _rewardedDefine,
    _iosRewarded,
    _androidRewarded,
    Platform.isIOS
        ? '${_testPublisher}1712485313'
        : '${_testPublisher}5224354917',
  );

  static String get interstitial => _pick(
    _interstitialDefine,
    _iosInterstitial,
    _androidInterstitial,
    Platform.isIOS
        ? '${_testPublisher}4411468910'
        : '${_testPublisher}1033173712',
  );

  /// Tek banner birimi hem alt şeridi hem 300×250 kutuyu doldurur.
  static String banner({bool adaptive = true}) => _pick(
    _bannerDefine,
    _iosBanner,
    _androidBanner,
    _testPublisher +
        switch ((Platform.isIOS, adaptive)) {
          (true, true) => '2435281174',
          (true, false) => '2934735716',
          (false, true) => '9214589741',
          (false, false) => '6300978111',
        },
  );
}

/// Reklamın yeri: sıklık kuralı buna göre seçilir.
enum AdMoment { soloReplay, duelExit }

/// Ödüllü reklamın sonucu.
enum RewardResult {
  /// Sonuna kadar izlendi: ödül verilir.
  earned,

  /// Erken kapatıldı.
  skipped,

  /// Reklam yok ya da açılamadı (oyuncunun suçu değil).
  unavailable,
}

/// AdMob: onay (UMP / GDPR), iOS izleme izni, ön yükleme ve gösterim.
///
/// Oyun kodu yalnız bu sınıfı görür. Testlerde ve masaüstünde [supported]
/// yanlıştır: hiçbir platform çağrısı yapılmaz, teklifler görünmez, banner
/// boş kalır, akış reklamsız oyunla aynıdır.
class AdService extends ChangeNotifier with WidgetsBindingObserver {
  AdService._();
  static final AdService instance = AdService._();

  static bool get supported =>
      !kNoAds && !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static const _kTotalRuns = 'ads.totalRuns';

  /// Yüklenen reklam bu süreden sonra bayatlar (AdMob sınırı 1 saat).
  static const _maxAge = Duration(minutes: 55);

  final AdPolicy policy = AdPolicy();
  SharedPreferences? _prefs;

  bool _starting = false;
  bool _ready = false;
  bool _observing = false;
  bool _showing = false;
  int _initAttempts = 0;
  Timer? _initRetry;

  RewardedAd? _rewarded;
  DateTime? _rewardedAt;
  bool _rewardedLoading = false;
  int _rewardedFailures = 0;

  InterstitialAd? _interstitial;
  DateTime? _interstitialAt;
  bool _interstitialLoading = false;
  int _interstitialFailures = 0;

  bool _privacyOptionsRequired = false;

  /// SDK hazır ve onay reklam isteğine izin veriyor.
  bool get ready => _ready;

  /// AB/BK kullanıcısı: ayarlarda "Reklam tercihleri" gösterilmeli.
  bool get privacyOptionsRequired => _privacyOptionsRequired;

  /// Testler: ödüllü teklifleri SDK olmadan göstermek için (gösterim yine
  /// "reklam yok" döner).
  @visibleForTesting
  bool? debugRewardedReady;

  bool get rewardedReady {
    final forced = debugRewardedReady;
    if (forced != null) return forced;
    _dropStale();
    return _ready && !_showing && _rewarded != null;
  }

  bool canOfferContinue({required int score, required bool usedThisRun}) =>
      rewardedReady &&
      policy.canOfferContinue(score: score, usedThisRun: usedThisRun);

  bool get canOfferFeverStart => rewardedReady && policy.canOfferFeverStart;

  /// Açılışta bir kez (ilk kareden sonra): onay formu gerekiyorsa açılır,
  /// iOS'ta izleme izni sorulur, SDK başlar, reklamlar önceden yüklenir.
  /// Ağ yoksa ya da onay alınamadıysa artan aralıklarla yeniden denenir.
  Future<void> initialize() async {
    if (!supported || _ready || _starting) return;
    _starting = true;
    _initRetry?.cancel();
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      policy.totalRuns = prefs.getInt(_kTotalRuns) ?? policy.totalRuns;
      await _gatherConsent();
      if (Platform.isIOS) await _requestTracking();
      if (!await ConsentInformation.instance.canRequestAds()) {
        _scheduleInitRetry();
        return;
      }
      await MobileAds.instance.updateRequestConfiguration(
        // Oyun 13+ için; reklam içeriği "Teen" ile sınırlı.
        RequestConfiguration(maxAdContentRating: MaxAdContentRating.t),
      );
      await MobileAds.instance.initialize();
      _ready = true;
      _initAttempts = 0;
      debugPrint(
        AdUnits.usingTestUnits
            ? '[ads] Google test birimleri kullanılıyor.'
            : '[ads] Mağaza birimleri kullanılıyor.',
      );
      _loadRewarded();
      _loadInterstitial();
      notifyListeners();
    } catch (e) {
      debugPrint('[ads] başlatılamadı: $e');
      _scheduleInitRetry();
    } finally {
      _starting = false;
    }
  }

  void _scheduleInitRetry() {
    final wait = Duration(seconds: min(600, 30 << min(_initAttempts++, 4)));
    _initRetry?.cancel();
    _initRetry = Timer(wait, initialize);
  }

  Future<void> _gatherConsent() {
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
        } catch (_) {}
        finish();
      },
      // Ağ yok: önceki oturumun onayı geçerliyse reklam yine istenebilir.
      (_) => finish(),
    );
    return done.future.then((_) => _refreshPrivacyOptions());
  }

  Future<void> _refreshPrivacyOptions() async {
    try {
      final status = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
      final required = status == PrivacyOptionsRequirementStatus.required;
      if (required != _privacyOptionsRequired) {
        _privacyOptionsRequired = required;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// UMP'nin IDFA mesajı AdMob'da tanımlıysa izin orada sorulur; sorulmadıysa
  /// burada bir kez sorulur. Reddedilirse reklamlar kişiselleştirilmeden gelir.
  Future<void> _requestTracking() async {
    try {
      if (await AppTrackingTransparency.trackingAuthorizationStatus !=
          TrackingStatus.notDetermined) {
        return;
      }
      // Uygulama tam etkin olmadan sorulursa iOS iletişim kutusunu göstermez.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await AppTrackingTransparency.requestTrackingAuthorization();
    } catch (_) {}
  }

  /// Duraklat menüsündeki "Reklam tercihleri" (AB/BK onayını değiştirme).
  Future<void> showPrivacyOptions() async {
    if (!supported) return;
    try {
      await ConsentForm.showPrivacyOptionsForm((_) {});
    } catch (_) {}
    await _refreshPrivacyOptions();
    if (!_ready) {
      unawaited(initialize());
    } else if (!await ConsentInformation.instance.canRequestAds()) {
      // Onay geri çekildi: bu oturumda yeni reklam istenmez.
      _ready = false;
      _disposeLoaded();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- yükleme

  Duration _backoff(int failures) =>
      Duration(seconds: min(300, 15 << min(failures, 4)));

  bool _stale(DateTime? at) =>
      at == null || DateTime.now().difference(at) > _maxAge;

  void _dropStale() {
    if (_rewarded != null && !_showing && _stale(_rewardedAt)) {
      _rewarded?.dispose();
      _rewarded = null;
      _loadRewarded();
    }
    if (_interstitial != null && !_showing && _stale(_interstitialAt)) {
      _interstitial?.dispose();
      _interstitial = null;
      _loadInterstitial();
    }
  }

  void _loadRewarded() {
    if (!_ready || _rewarded != null || _rewardedLoading) return;
    _rewardedLoading = true;
    RewardedAd.load(
      adUnitId: AdUnits.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedLoading = false;
          _rewardedFailures = 0;
          _rewarded = ad;
          _rewardedAt = DateTime.now();
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          _rewardedLoading = false;
          Timer(_backoff(_rewardedFailures++), _loadRewarded);
        },
      ),
    );
  }

  void _loadInterstitial() {
    if (!_ready || _interstitial != null || _interstitialLoading) return;
    _interstitialLoading = true;
    InterstitialAd.load(
      adUnitId: AdUnits.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialLoading = false;
          _interstitialFailures = 0;
          _interstitial = ad;
          _interstitialAt = DateTime.now();
        },
        onAdFailedToLoad: (error) {
          _interstitialLoading = false;
          Timer(_backoff(_interstitialFailures++), _loadInterstitial);
        },
      ),
    );
  }

  void _disposeLoaded() {
    _rewarded?.dispose();
    _rewarded = null;
    _interstitial?.dispose();
    _interstitial = null;
  }

  // ---------------------------------------------------------------- gösterim

  /// Ödüllü reklam. [onOpen] / [onClose]: oyun sesi ve motoru (reklam
  /// sesiyle çakışmasın). Sonuç [RewardResult].
  Future<RewardResult> showRewarded({
    VoidCallback? onOpen,
    VoidCallback? onClose,
  }) async {
    final ad = rewardedReady ? _rewarded : null;
    if (ad == null) return RewardResult.unavailable;
    _rewarded = null;
    var earned = false;
    final shown = await _present<RewardedAd>(
      ad,
      (cb) => ad.fullScreenContentCallback = cb,
      () => ad.show(onUserEarnedReward: (_, _) => earned = true),
      onOpen: onOpen,
      onClose: onClose,
    );
    // Ödül bildirimi kapanıştan hemen sonra gelebilir (platform kanalı sırası).
    if (shown && !earned) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    policy.fullscreenShown(interstitial: false);
    _loadRewarded();
    notifyListeners();
    if (!shown) return RewardResult.unavailable;
    return earned ? RewardResult.earned : RewardResult.skipped;
  }

  /// Sıklık kuralı izin veriyorsa ve reklam hazırsa geçiş reklamı gösterir;
  /// kapanınca (ya da hiç gösterilmezse hemen) döner.
  Future<bool> maybeShowInterstitial(
    AdMoment moment, {
    VoidCallback? onOpen,
    VoidCallback? onClose,
  }) async {
    _dropStale();
    final due = switch (moment) {
      AdMoment.soloReplay => policy.soloInterstitialDue,
      AdMoment.duelExit => policy.duelInterstitialDue,
    };
    final ad = _interstitial;
    if (!_ready || _showing || !due || ad == null) return false;
    _interstitial = null;
    final shown = await _present<InterstitialAd>(
      ad,
      (cb) => ad.fullScreenContentCallback = cb,
      ad.show,
      onOpen: onOpen,
      onClose: onClose,
    );
    if (shown) policy.fullscreenShown(interstitial: true);
    _loadInterstitial();
    return shown;
  }

  /// Tam ekran reklamı açar, kapanana dek bekler. Açılamadıysa false.
  Future<bool> _present<T extends AdWithoutView>(
    T ad,
    void Function(FullScreenContentCallback<T>) bind,
    Future<void> Function() show, {
    VoidCallback? onOpen,
    VoidCallback? onClose,
  }) async {
    _showing = true;
    final closed = Completer<bool>();
    bind(
      FullScreenContentCallback<T>(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          if (!closed.isCompleted) closed.complete(true);
        },
        onAdFailedToShowFullScreenContent: (ad, _) {
          ad.dispose();
          if (!closed.isCompleted) closed.complete(false);
        },
      ),
    );
    onOpen?.call();
    try {
      await ad.setImmersiveMode(true);
      await show();
    } catch (_) {
      ad.dispose();
      if (!closed.isCompleted) closed.complete(false);
    }
    final shown = await closed.future;
    _showing = false;
    // Android'de reklam sistem çubuklarını geri getirebilir.
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    onClose?.call();
    return shown;
  }

  // ---------------------------------------------------------------- sayaçlar

  /// Tek kişilik koşu bitti (sıklık + yeni oyuncu sayacı, kalıcı).
  void runFinished() {
    policy.runFinished();
    unawaited(_prefs?.setInt(_kTotalRuns, policy.totalRuns));
  }

  void duelFinished() => policy.duelFinished();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!_ready) {
      unawaited(initialize());
    } else {
      _dropStale();
      _loadRewarded();
      _loadInterstitial();
    }
  }
}
