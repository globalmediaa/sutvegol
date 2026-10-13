// Bulut kaydı uçtan uca: gerçek istemci kodu (ApiClient + ApiProgressRemote +
// ProgressService) ↔ yerel PHP/MySQL sunucusu. Canlı sunucuya asla bağlanmaz;
// yalnız backend/tests/progress_e2e.py tarafından çalıştırılır:
//   SV_PHP=… python3 backend/tests/progress_e2e.py
// (yerel php -S + yeni sutvegol_test_* DB açar, bu dosyayı dart-define ile koşar).
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sut_ve_gol/services/api_client.dart';
import 'package:sut_ve_gol/services/progress_service.dart';

const _token = String.fromEnvironment('PROGRESS_E2E_TOKEN');
const _refresh = String.fromEnvironment('PROGRESS_E2E_REFRESH');
const _user = String.fromEnvironment('PROGRESS_E2E_USER');

bool get _local =>
    apiBaseUrl.startsWith('http://127.0.0.1:') && _token.isNotEmpty;

/// Bir "cihazın" SharedPreferences içeriği (kurulum silinince kaybolur).
Future<Map<String, Object>> _snapshot() async {
  final p = await SharedPreferences.getInstance();
  return {for (final k in p.getKeys()) k: p.get(k)!};
}

Future<ProgressService> _device(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final s = ProgressService(debounce: const Duration(milliseconds: 300));
  await s.ensureLoaded();
  await s.attach(_user);
  return s;
}

void main() {
  test(
    'iki cihaz + yeniden kurulum + sıfırlama + hesap silme (yerel sunucu)',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = ApiClient.instance;
      await api.saveTokens({'accessToken': _token, 'refreshToken': _refresh});
      final remote = ApiProgressRemote(api);

      // 1) Cihaz A: misafir olarak oynanmış eski sürüm verisi + girişte birleşme.
      final a = await _device({'best': 120, 'sound': false, 'haptics': true});
      expect(a.dirty, isTrue, reason: 'eski kurulum verisi buluta gidecek');
      a.recordRun(
        score: 90,
        shots: 6,
        hits: 3,
        feverHits: 0,
        maxStreak: 3,
        durationMs: 12000,
      );
      // 2 sn yerine 300 ms debounce: zamanlayıcıyla gerçekten gönderilir.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      var server = await remote.fetch();
      expect(server.data.best, 120);
      expect(server.data.totals['runs'], 1);
      expect(server.data.settings!.sound, isFalse);
      expect(a.dirty, isFalse);
      final prefsA = await _snapshot();
      a.debugDetach();

      // 2) Uygulama silinip yeniden yüklendi (B: boş depo): girişte sorusuz geri yükleme.
      final b = await _device({});
      expect(b.best, 120);
      expect(b.sound, isFalse);
      expect(b.totals['runs'], 1);
      expect((b.dirty, b.owner), (false, _user));
      b.recordRun(
        score: 300,
        shots: 10,
        hits: 10,
        feverHits: 5,
        maxStreak: 10,
        durationMs: 20000,
      );
      b.setHaptics(false);
      await b.flush(); // arka plana geçişteki flush
      server = await remote.fetch();
      expect(server.data.best, 300);
      expect(server.data.totals['runs'], 2, reason: 'cihazların toplamı');
      final prefsB = await _snapshot();
      b.debugDetach();

      // 3) Cihaz A geri döner: buluttaki ileri durum sessizce birleşir.
      final a2 = await _device(prefsA);
      expect((a2.best, a2.haptics, a2.totals['runs']), (300, false, 2));

      // 4) A'da "Sil ve baştan başla" → epoch artar, rekor/istatistik gider, ayar kalır.
      await a2.resetAll();
      expect((a2.best, a2.totals['runs'], a2.haptics), (0, 0, false));
      server = await remote.fetch();
      expect((server.epoch, server.data.best), (1, 0));
      a2.debugDetach();

      // 5) B eski epoch'la çevrimdışı oynamıştı: açılış çekişi sıfırlamayı yayar
      //    (yerel rekor/istatistik silinir), eski epoch'lu doğrudan yazım 409 alır.
      SharedPreferences.setMockInitialValues(prefsB);
      final b2 = ProgressService(debounce: const Duration(milliseconds: 300));
      await b2.ensureLoaded();
      b2.recordRun(
        score: 600,
        shots: 20,
        hits: 20,
        feverHits: 5,
        maxStreak: 20,
        durationMs: 40000,
      );
      final stale = b2.data;
      await b2.attach(_user);
      expect((b2.epoch, b2.best, b2.totals['runs']), (1, 0, 0));
      await expectLater(
        remote.push(0, stale),
        throwsA(
          isA<ProgressResetException>().having(
            (e) => e.server.epoch,
            'epoch',
            1,
          ),
        ),
      );
      server = await remote.fetch();
      expect(server.data.best, 0, reason: 'eski epoch verisi geri gelmedi');
      b2.debugDetach();

      // 6) Hesap silme: sunucu bulut kaydını siler; istemci yereli temizler.
      final c = await _device({});
      await api.delete('/v1/me');
      await c.forgetAccount();
      expect((c.best, c.owner, c.signedIn), (0, null, false));
      await expectLater(
        remote.fetch(),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
    },
    skip: _local
        ? false
        : 'yalnız progress_e2e.py ile (yerel API_BASE_URL + test kullanıcısı)',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
