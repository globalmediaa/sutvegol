import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Cihaz başı sayaçlar; toplam istatistik = cihazların toplamı.
const progressCounters = ['runs', 'shots', 'hits', 'feverHits', 'playMs'];
const _counterMax = 1000000000000;
const _maxDevices = 48;
final _deviceIdPattern = RegExp(r'^[A-Za-z0-9_-]{8,40}$');

int _int(Object? v, int max) {
  if (v is int) return v.clamp(0, max);
  if (v is double && v.isFinite) {
    return v <= 0 ? 0 : (v >= max ? max : v.toInt());
  }
  if (v is String && RegExp(r'^\d{1,15}$').hasMatch(v)) {
    return int.parse(v).clamp(0, max);
  }
  return 0;
}

/// Ses / titreşim tercihi; "son yazan kazanır" (`at`, ms).
@immutable
class ProgressSettings {
  const ProgressSettings({
    required this.sound,
    required this.haptics,
    required this.at,
  });
  final bool sound;
  final bool haptics;
  final int at;

  int get code => (sound ? 2 : 0) + (haptics ? 1 : 0);

  static ProgressSettings? fromJson(Object? raw) {
    if (raw is! Map || raw['sound'] is! bool || raw['haptics'] is! bool) {
      return null;
    }
    return ProgressSettings(
      sound: raw['sound'] as bool,
      haptics: raw['haptics'] as bool,
      at: _int(raw['at'], _counterMax * 10),
    );
  }

  Map<String, dynamic> toJson() => {
    'sound': sound,
    'haptics': haptics,
    'at': at,
  };
}

/// Birleştirilebilir oyuncu ilerlemesi. Sunucu karşılığı `backend/src/progress.php`;
/// birleştirme değişmeli, birleşmeli ve idempotenttir ("ileride olan kazanır").
@immutable
class ProgressData {
  const ProgressData({
    this.best = 0,
    this.maxStreak = 0,
    this.tutorialDone = false,
    this.devices = const {},
    this.settings,
  });

  static const empty = ProgressData();

  final int best;
  final int maxStreak;
  final bool tutorialDone;
  final Map<String, Map<String, int>> devices;
  final ProgressSettings? settings;

  factory ProgressData.fromJson(Object? raw) {
    final p = raw is Map ? raw : const {};
    final devices = <String, Map<String, int>>{};
    final rawDevices = p['devices'];
    if (rawDevices is Map) {
      rawDevices.forEach((id, c) {
        if (id is! String || !_deviceIdPattern.hasMatch(id) || c is! Map) {
          return;
        }
        devices[id] = {
          for (final k in progressCounters) k: _int(c[k], _counterMax),
        };
      });
    }
    return ProgressData(
      best: _int(p['best'], 10000000),
      maxStreak: _int(p['maxStreak'], 1000000),
      tutorialDone: p['tutorialDone'] == true,
      devices: _canonical(devices),
      settings: ProgressSettings.fromJson(p['settings']),
    );
  }

  /// Sıralı ve sınırlı cihaz eşlemi (sunucuyla aynı kural: en çok oynanan 48 cihaz).
  static Map<String, Map<String, int>> _canonical(
    Map<String, Map<String, int>> devices,
  ) {
    var ids = devices.keys.toList();
    if (ids.length > _maxDevices) {
      ids.sort((a, b) {
        final byRuns = devices[b]!['runs']!.compareTo(devices[a]!['runs']!);
        return byRuns != 0 ? byRuns : a.compareTo(b);
      });
      ids = ids.sublist(0, _maxDevices);
    }
    ids.sort();
    return Map.unmodifiable({
      for (final id in ids) id: Map<String, int>.unmodifiable(devices[id]!),
    });
  }

  Map<String, dynamic> toJson() => {
    'v': 1,
    'best': best,
    'maxStreak': maxStreak,
    'tutorialDone': tutorialDone,
    'devices': {
      for (final e in devices.entries)
        e.key: {for (final k in progressCounters) k: e.value[k] ?? 0},
    },
    'settings': settings?.toJson(),
  };

  Map<String, int> get totals {
    final t = {for (final k in progressCounters) k: 0};
    for (final c in devices.values) {
      for (final k in progressCounters) {
        t[k] = t[k]! + (c[k] ?? 0);
      }
    }
    return t;
  }

  ProgressData copyWith({
    int? best,
    int? maxStreak,
    bool? tutorialDone,
    Map<String, Map<String, int>>? devices,
    ProgressSettings? settings,
  }) => ProgressData(
    best: best ?? this.best,
    maxStreak: maxStreak ?? this.maxStreak,
    tutorialDone: tutorialDone ?? this.tutorialDone,
    devices: devices == null ? this.devices : _canonical(devices),
    settings: settings ?? this.settings,
  );

  /// "Sil ve baştan başla": rekor ve istatistik gider; ayar ve rehber tercihtir, kalır.
  ProgressData wiped() =>
      ProgressData(settings: settings, tutorialDone: tutorialDone);

  bool sameAs(ProgressData other) =>
      jsonEncode(toJson()) == jsonEncode(other.toJson());

  static ProgressData merge(ProgressData a, ProgressData b) {
    final devices = <String, Map<String, int>>{
      for (final e in a.devices.entries) e.key: Map.of(e.value),
    };
    b.devices.forEach((id, c) {
      final mine = devices[id];
      if (mine == null) {
        devices[id] = Map.of(c);
        return;
      }
      for (final k in progressCounters) {
        mine[k] = max(mine[k] ?? 0, c[k] ?? 0);
      }
    });
    final sa = a.settings, sb = b.settings;
    final ProgressSettings? settings;
    if (sa == null || sb == null) {
      settings = sa ?? sb;
    } else if (sa.at != sb.at) {
      settings = sa.at > sb.at ? sa : sb;
    } else {
      settings = sa.code >= sb.code ? sa : sb;
    }
    return ProgressData(
      best: max(a.best, b.best),
      maxStreak: max(a.maxStreak, b.maxStreak),
      tutorialDone: a.tutorialDone || b.tutorialDone,
      devices: _canonical(devices),
      settings: settings,
    );
  }
}

/// Sunucudaki kayıt: epoch (sıfırlama sayacı), revision (her değişiklikte artar), veri.
class ProgressSnapshot {
  const ProgressSnapshot(this.epoch, this.revision, this.data);
  factory ProgressSnapshot.fromJson(Object? raw) {
    final p = raw is Map ? raw : const {};
    return ProgressSnapshot(
      _int(p['epoch'], 1 << 31),
      _int(p['revision'], 1 << 31),
      ProgressData.fromJson(p['payload']),
    );
  }
  final int epoch;
  final int revision;
  final ProgressData data;
}

/// Sunucu: ilerleme başka bir cihazda sıfırlandı (epoch farklı) → güncel kayıt.
class ProgressResetException implements Exception {
  const ProgressResetException(this.server);
  final ProgressSnapshot server;
}

abstract class ProgressRemote {
  Future<ProgressSnapshot> fetch();
  Future<ProgressSnapshot> push(int epoch, ProgressData data);
  Future<ProgressSnapshot> reset();
}

class ApiProgressRemote implements ProgressRemote {
  ApiProgressRemote([ApiClient? api]) : api = api ?? ApiClient.instance;
  final ApiClient api;

  @override
  Future<ProgressSnapshot> fetch() async =>
      ProgressSnapshot.fromJson((await api.get('/v1/progress'))['progress']);

  @override
  Future<ProgressSnapshot> push(int epoch, ProgressData data) async {
    try {
      final r = await api.put(
        '/v1/progress',
        data: {'epoch': epoch, 'payload': data.toJson()},
      );
      return ProgressSnapshot.fromJson(r['progress']);
    } on ApiException catch (e) {
      if (e.code == 'progress_reset' && e.details?['progress'] != null) {
        throw ProgressResetException(
          ProgressSnapshot.fromJson(e.details!['progress']),
        );
      }
      rethrow;
    }
  }

  @override
  Future<ProgressSnapshot> reset() async => ProgressSnapshot.fromJson(
    (await api.post('/v1/progress/reset'))['progress'],
  );
}

/// Oyuncu ilerlemesi: yerelde anında (SharedPreferences), girişliyse bulutta.
///
/// * Her değişiklik 2 sn debounce (en geç 10 sn) ile yazılır; arka plana geçişte
///   hemen gönderilir. Çevrimdışıyken `dirty` kalıcıdır, üstel geri denemeyle
///   (2 s → 5 dk) gönderilir.
/// * Giriş / açılışta bulut çekilir ve sessizce birleştirilir: yeni kurulumda
///   hiçbir soru sormadan kaldığı yerden devam edilir.
/// * Sıfırlama yalnız [resetAll] ("Sil ve baştan başla") ile; sunucu epoch'u
///   artar, diğer cihazlar sonraki senkronda yerel ilerlemelerini siler.
class ProgressService extends ChangeNotifier with WidgetsBindingObserver {
  ProgressService({
    ProgressRemote? remote,
    this.debounce = const Duration(seconds: 2),
    this.maxWait = const Duration(seconds: 10),
    this.maxBackoff = const Duration(minutes: 5),
  }) : remote = remote ?? ApiProgressRemote();

  static ProgressService instance = ProgressService();

  static const kData = 'progress_v1';
  static const kEpoch = 'progress_epoch';
  static const kRevision = 'progress_revision';
  static const kOwner = 'progress_owner';
  static const kDirty = 'progress_dirty';
  static const kDevice = 'progress_device';
  static const kSaveOffer = 'save_offer_seen';

  final ProgressRemote remote;
  final Duration debounce;
  final Duration maxWait;
  final Duration maxBackoff;

  /// Ayar zaman damgası; testler sabitleyebilir.
  int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  SharedPreferences? _prefs;
  ProgressData data = ProgressData.empty;
  int epoch = 0;
  int revision = 0;

  /// Yerel ilerlemenin ait olduğu hesap (null: misafir ilerlemesi).
  String? owner;
  String deviceId = '';

  /// Bulutta henüz olmayan yerel değişiklik var.
  bool dirty = false;

  String? _user;
  Timer? _debounceTimer, _maxWaitTimer, _retryTimer;
  Future<void>? _pushing;
  bool _again = false;
  bool _halted = false;
  int _failures = 0;

  /// Sıfırlama / hesap değişiminde artar; eski yanıtlar yok sayılır.
  int _generation = 0;
  bool _observing = false;

  bool get signedIn => _user != null;
  int get best => data.best;
  bool get sound => data.settings?.sound ?? true;
  bool get haptics => data.settings?.haptics ?? true;
  Map<String, int> get totals => data.totals;
  int get failures => _failures;
  bool get saveOfferSeen => _prefs?.getBool(kSaveOffer) ?? false;

  /// Uygulama yaşam döngüsü: arka planda gönder, öne gelince çek.
  void bindLifecycle() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(flush());
      case AppLifecycleState.resumed:
        unawaited(pull());
    }
  }

  /// SharedPreferences'tan yükler (tekrar çağrı ucuz; test sahte deposu değişirse yeniden okur).
  Future<void> ensureLoaded() async {
    final p = await SharedPreferences.getInstance();
    if (!identical(p, _prefs)) _loadFrom(p);
  }

  void _loadFrom(SharedPreferences p) {
    _cancelTimers();
    _prefs = p;
    final raw = p.getString(kData);
    var d = ProgressData.empty;
    if (raw != null) {
      try {
        d = ProgressData.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
    // Bulut kaydından önceki sürümler yalnız bu anahtarları yazardı.
    final legacyBest = p.getInt('best') ?? 0;
    final legacySettings = p.containsKey('sound') || p.containsKey('haptics');
    d = d.copyWith(
      best: max(d.best, legacyBest),
      tutorialDone: d.tutorialDone || (p.getBool('tutorial_done') ?? false),
      settings:
          d.settings ??
          (legacySettings
              ? ProgressSettings(
                  sound: p.getBool('sound') ?? true,
                  haptics: p.getBool('haptics') ?? true,
                  at: 0,
                )
              : null),
    );
    data = d;
    epoch = p.getInt(kEpoch) ?? 0;
    revision = p.getInt(kRevision) ?? 0;
    owner = p.getString(kOwner);
    dirty =
        (p.getBool(kDirty) ?? false) ||
        (raw == null && !d.sameAs(ProgressData.empty));
    var id = p.getString(kDevice);
    if (id == null || !_deviceIdPattern.hasMatch(id)) {
      final r = Random.secure();
      const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
      id = List.generate(16, (_) => chars[r.nextInt(chars.length)]).join();
      p.setString(kDevice, id);
    }
    deviceId = id;
  }

  void _persist() {
    final p = _prefs;
    if (p == null) return;
    p.setString(kData, jsonEncode(data.toJson()));
    p.setInt('best', data.best);
    final s = data.settings;
    if (s != null) {
      p.setBool('sound', s.sound);
      p.setBool('haptics', s.haptics);
    }
    if (data.tutorialDone) p.setBool('tutorial_done', true);
    p.setInt(kEpoch, epoch);
    p.setInt(kRevision, revision);
    if (owner == null) {
      p.remove(kOwner);
    } else {
      p.setString(kOwner, owner!);
    }
    p.setBool(kDirty, dirty);
  }

  // ------------------------------------------------------------ değişiklikler

  void recordBest(int score) {
    if (score > data.best) _update(data.copyWith(best: score));
  }

  /// Biten bir koşu (yalnız tek kişilik mod): bu cihazın sayaçlarına eklenir.
  void recordRun({
    required int score,
    required int shots,
    required int hits,
    required int feverHits,
    required int maxStreak,
    required int durationMs,
  }) {
    if (shots <= 0) return;
    final c = Map<String, int>.of(
      data.devices[deviceId] ?? {for (final k in progressCounters) k: 0},
    );
    void add(String k, int v) =>
        c[k] = min(_counterMax, (c[k] ?? 0) + max(0, v));
    add('runs', 1);
    add('shots', shots);
    add('hits', hits);
    add('feverHits', feverHits);
    add('playMs', durationMs);
    _update(
      data.copyWith(
        best: max(data.best, score),
        maxStreak: max(data.maxStreak, maxStreak),
        devices: {...data.devices, deviceId: c},
      ),
    );
  }

  int get _settingsAt => max(now(), (data.settings?.at ?? 0) + 1);

  void setSound(bool v) => _update(
    data.copyWith(
      settings: ProgressSettings(sound: v, haptics: haptics, at: _settingsAt),
    ),
  );

  void setHaptics(bool v) => _update(
    data.copyWith(
      settings: ProgressSettings(sound: sound, haptics: v, at: _settingsAt),
    ),
  );

  void setTutorialDone() {
    if (!data.tutorialDone) _update(data.copyWith(tutorialDone: true));
  }

  Future<void> markSaveOfferSeen() async {
    await ensureLoaded();
    await _prefs?.setBool(kSaveOffer, true);
  }

  void _update(ProgressData next) {
    if (next.sameAs(data)) return;
    data = next;
    dirty = true;
    _persist();
    notifyListeners();
    _schedule();
  }

  // ------------------------------------------------------------ senkron

  /// Oturum değişti (açılış, giriş, çıkış). Girişte bulut çekilip birleştirilir.
  Future<void> attach(String? userId) async {
    await ensureLoaded();
    if (userId != null && userId == _user) {
      _halted = false; // aynı hesapla yeniden giriş: durdurulmuş senkron sürer
      await pull();
      if (dirty) _schedule();
      return;
    }
    _generation++;
    _cancelTimers();
    _user = userId;
    _halted = false;
    _failures = 0;
    if (userId == null) return;
    if (owner != null && owner != userId) {
      // Bu cihazdaki ilerleme başka bir hesaba ait: yeni hesaba karışmaz.
      data = data.wiped();
      epoch = 0;
      revision = 0;
      owner = null;
      dirty = false;
      _persist();
      notifyListeners();
    }
    await pull();
  }

  /// Bulutu çeker ve sessizce birleştirir (yeni kurulumda doğrudan uygular).
  Future<void> pull() async {
    final user = _user, gen = _generation;
    if (user == null || _halted) return;
    try {
      final snap = await remote.fetch();
      if (gen != _generation || user != _user) return;
      if (owner == user && snap.epoch != epoch) {
        _applyServerEpoch(snap);
      } else {
        _adopt(snap);
      }
    } on ApiException catch (e) {
      if (gen != _generation) return;
      if (e.status == 401 || e.status == 403) {
        _halted = true;
      } else if (dirty) {
        _retryLater();
      }
    } catch (_) {
      if (gen == _generation && dirty) _retryLater();
    }
  }

  /// Bekleyen değişikliği hemen gönderir (arka plana geçiş, çıkış).
  Future<void> flush() async {
    _cancelTimers();
    await _push();
  }

  void _schedule() {
    if (_user == null || _halted || !dirty) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, _fire);
    _maxWaitTimer ??= Timer(maxWait, _fire);
  }

  void _fire() {
    _cancelTimers();
    unawaited(_push());
  }

  void _cancelTimers() {
    _debounceTimer?.cancel();
    _maxWaitTimer?.cancel();
    _retryTimer?.cancel();
    _debounceTimer = _maxWaitTimer = _retryTimer = null;
  }

  Future<void> _push() {
    final running = _pushing;
    if (running != null) {
      _again = true;
      return running;
    }
    if (_user == null || !dirty || _halted) return Future.value();
    final future = _doPush().whenComplete(() {
      _pushing = null;
      if (_again) {
        _again = false;
        if (dirty && _retryTimer == null) _schedule();
      }
    });
    return _pushing = future;
  }

  Future<void> _doPush() async {
    final user = _user, gen = _generation;
    try {
      final snap = await remote.push(epoch, data);
      if (gen != _generation || user != _user) return;
      _failures = 0;
      _adopt(snap);
    } on ProgressResetException catch (e) {
      if (gen != _generation || user != _user) return;
      _failures = 0;
      _applyServerEpoch(e.server);
    } on ApiException catch (e) {
      if (gen != _generation) return;
      if (e.status == 401 || e.status == 403) {
        _halted = true; // oturum yok; yeniden girişte attach sürdürür
        return;
      }
      _retryLater();
    } catch (_) {
      if (gen == _generation) _retryLater();
    }
  }

  /// Üstel geri deneme: 2, 4, 8 … sn, en çok [maxBackoff].
  void _retryLater() {
    _failures++;
    final ms = min(
      maxBackoff.inMilliseconds,
      2000 * (1 << min(_failures - 1, 16)),
    );
    _debounceTimer?.cancel();
    _maxWaitTimer?.cancel();
    _debounceTimer = _maxWaitTimer = null;
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: ms), () {
      _retryTimer = null;
      unawaited(_push());
    });
  }

  /// Sunucu kaydını yerelle birleştirir; sunucuda olmayan yerel değişiklik kaldıysa yeniden yazar.
  void _adopt(ProgressSnapshot snap) {
    final merged = ProgressData.merge(data, snap.data);
    final changed = !merged.sameAs(data);
    data = merged;
    epoch = snap.epoch;
    revision = snap.revision;
    owner = _user;
    dirty = !merged.sameAs(snap.data);
    _persist();
    if (changed) notifyListeners();
    if (dirty) _schedule();
  }

  /// Epoch farkı: başka cihazda "Sil ve baştan başla" yapıldıysa yerel rekor ve
  /// istatistik silinir, sunucu benimsenir. Misafir ilerlemesi silinmez.
  void _applyServerEpoch(ProgressSnapshot snap) {
    final wipe = owner == _user && snap.epoch > epoch;
    final base = wipe ? data.wiped() : data;
    final merged = ProgressData.merge(base, snap.data);
    final changed = !merged.sameAs(data);
    data = merged;
    epoch = snap.epoch;
    revision = snap.revision;
    owner = _user;
    dirty = !merged.sameAs(snap.data);
    _persist();
    if (changed) notifyListeners();
    if (dirty) _schedule();
  }

  /// "Sil ve baştan başla": girişliyse önce bulut (diğer cihazlara epoch ile yayılır);
  /// sunucuya ulaşılamazsa yerelde de silinmez ve hata fırlatır. Misafirde yalnız yerel.
  Future<void> resetAll() async {
    await ensureLoaded();
    _cancelTimers();
    if (_user != null) {
      final gen = ++_generation;
      final snap = await remote.reset();
      if (gen != _generation) return;
      final merged = ProgressData.merge(data.wiped(), snap.data);
      data = merged;
      epoch = snap.epoch;
      revision = snap.revision;
      owner = _user;
      _halted = false;
      _failures = 0;
      dirty = !merged.sameAs(snap.data);
    } else {
      data = data.wiped();
      dirty = false; // misafir: buluta gidecek bir şey yok
    }
    _persist();
    notifyListeners();
    if (dirty) _schedule();
  }

  /// Hesap silindi: bulut kaydı sunucuda silindi; bu cihazdaki ilerleme de temizlenir.
  Future<void> forgetAccount() async {
    await ensureLoaded();
    _generation++;
    _cancelTimers();
    _user = null;
    data = data.wiped();
    epoch = 0;
    revision = 0;
    owner = null;
    dirty = false;
    _persist();
    notifyListeners();
  }

  /// Testler için: zamanlayıcıları durdurur ve oturumu bırakır.
  @visibleForTesting
  void debugDetach() {
    _cancelTimers();
    _generation++;
    _user = null;
    _pushing = null;
    _again = false;
  }
}
