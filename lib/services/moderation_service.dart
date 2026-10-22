import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Kullanım Koşulları sürümü; sunucudaki `TERMS_VERSION` ile aynı
/// (backend/src/moderation.php). Metin değişirse ikisi birlikte artırılır.
const kTermsVersion = 1;
const kTermsUrl = 'https://globalmediaa.github.io/sutvegol/terms.html';

/// Gizlilik politikası (App Store Connect'teki Gizlilik Politikası URL'siyle aynı).
const kPrivacyUrl = 'https://globalmediaa.github.io/apps-privacy/sut-ve-gol/';
const kSupportEmail = 'info@globalmedia.com.tr';

/// Sunucunun engellenen oyuncu için kullandığı etiket (sıralama, düello).
const kBlockedLabel = 'Engellenen oyuncu';

/// Şikâyet sebebi; `name` sunucuya giden değerdir (username | cheating | other).
enum ReportReason {
  username(
    'Uygunsuz kullanıcı adı',
    'Küfür, hakaret, cinsel ya da nefret içeren veya resmî hesap taklidi yapan ad',
  ),
  cheating('Hile', 'Gerçek dışı skor ya da hileli oyun'),
  other('Diğer', 'Taciz ya da başka bir kural ihlali');

  const ReportReason(this.label, this.hint);
  final String label, hint;
}

/// Şikâyetin yapıldığı yer; `name` sunucuya giden değerdir.
enum ReportContext { duel, ghost, leaderboard }

class BlockedPlayer {
  const BlockedPlayer({required this.id, required this.name, this.blockedAt});
  factory BlockedPlayer.fromJson(Map<String, dynamic> j) => BlockedPlayer(
    id: j['id'] as String,
    name: j['name'] as String? ?? 'Oyuncu',
    blockedAt: DateTime.tryParse('${j['blockedAt']}'),
  );
  final String id, name;
  final DateTime? blockedAt;
}

/// Sunucu uçları: POST /v1/report, /v1/blocks (testlerde sahtesi verilir).
abstract class ModerationRemote {
  Future<void> report({
    required String targetId,
    required ReportReason reason,
    required ReportContext context,
    String? duelId,
    String? note,
  });
  Future<void> block(String userId);
  Future<void> unblock(String userId);
  Future<List<BlockedPlayer>> blocks();
}

class ApiModerationRemote implements ModerationRemote {
  ApiModerationRemote([ApiClient? api]) : api = api ?? ApiClient.instance;
  final ApiClient api;

  @override
  Future<void> report({
    required String targetId,
    required ReportReason reason,
    required ReportContext context,
    String? duelId,
    String? note,
  }) async {
    final text = note?.trim() ?? '';
    await api.post(
      '/v1/report',
      data: {
        'target_user_id': targetId,
        'reason': reason.name,
        'context': context.name,
        'duel_id': ?duelId,
        if (text.isNotEmpty) 'note': text,
      },
    );
  }

  @override
  Future<void> block(String userId) async {
    await api.post('/v1/blocks', data: {'user_id': userId});
  }

  @override
  Future<void> unblock(String userId) async {
    await api.delete('/v1/blocks/$userId');
  }

  @override
  Future<List<BlockedPlayer>> blocks() async {
    final r = await api.get('/v1/blocks');
    return (r['blocks'] as List? ?? const [])
        .map((e) => BlockedPlayer.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Oyuncu güvenliği: şikâyet, engelleme ve kullanım koşulu onayı.
/// Engel listesi girişte arka planda yüklenir; ekranlar (düello sonucu gibi
/// artık yoklanmayan) engeli sunucu yanıtını beklemeden yansıtır.
class ModerationService extends ChangeNotifier {
  ModerationService._();
  static final instance = ModerationService._();

  ModerationRemote remote = ApiModerationRemote();
  final _blocked = <String>{};
  final _unblocked = <String>{};

  /// Hesap değişince artar: önceki hesabın geç dönen yanıtı yeni önbelleğe yazılmaz.
  int _generation = 0;

  /// Bu oyuncu engelli mi? Yerel değişiklik (bu oturumda engelle/kaldır) sunucu
  /// bayrağından önce gelir; ikisi de yoksa sunucunun `blocked` değeri.
  bool isBlocked(String? id, {bool server = false}) {
    if (id == null) return false;
    if (_unblocked.contains(id)) return false;
    return _blocked.contains(id) || server;
  }

  Future<void> report({
    required String targetId,
    required ReportReason reason,
    required ReportContext context,
    String? duelId,
    String? note,
  }) => remote.report(
    targetId: targetId,
    reason: reason,
    context: context,
    duelId: duelId,
    note: note,
  );

  Future<void> block(String id) async {
    final generation = _generation;
    await remote.block(id);
    if (generation != _generation) return;
    _blocked.add(id);
    _unblocked.remove(id);
    notifyListeners();
  }

  Future<void> unblock(String id) async {
    final generation = _generation;
    await remote.unblock(id);
    if (generation != _generation) return;
    _blocked.remove(id);
    _unblocked.add(id);
    notifyListeners();
  }

  Future<List<BlockedPlayer>> loadBlocks() async {
    final generation = _generation;
    final list = await remote.blocks();
    if (generation != _generation) return list;
    _blocked
      ..clear()
      ..addAll(list.map((b) => b.id));
    _unblocked.clear();
    notifyListeners();
    return list;
  }

  /// Girişte ve açılışta: hata sessizce yutulur (liste ekranı yeniden dener).
  Future<void> refresh() async {
    try {
      await loadBlocks();
    } catch (_) {}
  }

  /// Çıkış / hesap silme: başka hesabın engel listesi taşınmaz.
  void reset() {
    _generation++;
    _blocked.clear();
    _unblocked.clear();
    notifyListeners();
  }

  /// Onay hesap başınadır: aynı cihazda başka hesap kendi onayını verir.
  static String _termsKey(String userId) => 'terms_accepted_version_$userId';

  /// Bu cihazda bu hesabın kabul ettiği koşul sürümü (0 = hiç).
  static Future<int> acceptedTermsVersion(String userId) async {
    try {
      return (await SharedPreferences.getInstance()).getInt(
            _termsKey(userId),
          ) ??
          0;
    } catch (_) {
      return 0;
    }
  }

  /// Onay sürümü cihaza yazılır (sunucu da saklar; sunucuya ulaşılamazsa cihaz kaydı geçerli).
  static Future<void> saveTermsAccepted(
    String userId, [
    int version = kTermsVersion,
  ]) async {
    try {
      await (await SharedPreferences.getInstance()).setInt(
        _termsKey(userId),
        version,
      );
    } catch (_) {}
  }
}
