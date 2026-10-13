// Oyuncu güvenliği uçtan uca: gerçek istemci kodu (ApiClient + AuthService.checkUsername
// + ApiModerationRemote/ModerationService + GameSessionService.leaderboard) ↔ yerel
// PHP/MySQL. Canlı sunucuya asla bağlanmaz; yalnız backend/tests/moderation_e2e.py ile:
//   SV_PHP=… python3 backend/tests/moderation_e2e.py
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sut_ve_gol/services/api_client.dart';
import 'package:sut_ve_gol/services/auth_service.dart';
import 'package:sut_ve_gol/services/game_service.dart';
import 'package:sut_ve_gol/services/moderation_service.dart';

const _token = String.fromEnvironment('MOD_E2E_TOKEN');
const _refresh = String.fromEnvironment('MOD_E2E_REFRESH');
const _me = String.fromEnvironment('MOD_E2E_USER');
const _target = String.fromEnvironment('MOD_E2E_TARGET');

bool get _local =>
    apiBaseUrl.startsWith('http://127.0.0.1:') && _token.isNotEmpty;

void main() {
  test(
    'ad filtresi, şikâyet, engel ve sıralama etiketi (yerel sunucu)',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final api = ApiClient.instance;
      await api.saveTokens({'accessToken': _token, 'refreshToken': _refresh});
      // Uygulamadaki gibi giriş yapmış oyuncu: sıralama isteği oturumla gider.
      AuthService.instance.user = const AppUser(id: _me, username: 'e2e_ben');
      final mod = ModerationService.instance..remote = ApiModerationRemote(api);
      final board = GameSessionService();

      // 1) Kullanıcı adı: kayıt/ad seçimiyle aynı sunucu kuralı.
      final bad = await AuthService.instance.checkUsername('s1kt1r');
      expect((bad.valid, bad.allowed, bad.available), (true, false, false));
      expect(bad.message, contains('uygun değil'));
      final fake = await AuthService.instance.checkUsername('sutvegol_destek');
      expect(fake.allowed, false);
      final ok = await AuthService.instance.checkUsername('temiz_e2e_adi');
      expect((ok.allowed, ok.available), (true, true));

      // 2) Şikâyet: gönderim + aynı hedefe tekrar (idempotent) + kendini şikâyet reddi.
      await mod.report(
        targetId: _target,
        reason: ReportReason.cheating,
        context: ReportContext.leaderboard,
      );
      await mod.report(
        targetId: _target,
        reason: ReportReason.username,
        context: ReportContext.leaderboard,
        note: '  e2e notu  ',
      );
      await expectLater(
        mod.report(
          targetId: _me,
          reason: ReportReason.other,
          context: ReportContext.leaderboard,
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'cannot_report_self')
              .having((e) => e.status, 'status', 422),
        ),
      );
      await expectLater(
        mod.report(
          targetId: 'F' * 26,
          reason: ReportReason.other,
          context: ReportContext.leaderboard,
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'player_gone')
              .having((e) => e.status, 'status', 410),
        ),
      );

      // 3) Engel: sıralamada "Engellenen oyuncu" + blocked; listede görünür.
      var entries = await board.leaderboard('all');
      var target = entries.firstWhere((e) => e.id == _target);
      expect((target.username, target.blocked), ('e2e_rakip', false));
      await mod.block(_target);
      expect(mod.isBlocked(_target), true);
      entries = await board.leaderboard('all');
      target = entries.firstWhere((e) => e.id == _target);
      expect((target.username, target.blocked), (kBlockedLabel, true));
      final blocks = await mod.loadBlocks();
      expect(blocks.map((b) => (b.id, b.name)).toList(), [
        (_target, 'e2e_rakip'),
      ]);
      expect(blocks.single.blockedAt, isNotNull);

      // 4) Engeli kaldır: ad geri gelir, liste boşalır.
      await mod.unblock(_target);
      expect(mod.isBlocked(_target, server: true), false);
      entries = await board.leaderboard('all');
      target = entries.firstWhere((e) => e.id == _target);
      expect((target.username, target.blocked), ('e2e_rakip', false));
      expect(await mod.loadBlocks(), isEmpty);
      // Kendi satırı kalıcı kimlikle bulunur.
      expect(entries.where((e) => e.id == _me), hasLength(1));
    },
    skip: _local
        ? false
        : 'yalnız moderation_e2e.py ile (yerel API_BASE_URL + test kullanıcısı)',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
