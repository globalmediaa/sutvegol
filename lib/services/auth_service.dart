import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'api_client.dart';
import 'moderation_service.dart';
import 'progress_service.dart';

/// Google OAuth istemci kimlikleri derleme anında verilir:
/// `--dart-define=GOOGLE_IOS_CLIENT_ID=…apps.googleusercontent.com`
/// `--dart-define=GOOGLE_SERVER_CLIENT_ID=…apps.googleusercontent.com` (Web
/// istemcisi; Android'de idToken almak için gerekir).
const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

/// Testler için: Google düğmesinin görünürlüğünü zorlar (null = derleme yapılandırması).
@visibleForTesting
bool? debugGoogleAvailable;

/// Google girişi bu derlemede çalışır mı? iOS/macOS'ta iOS istemci kimliği, Android'de
/// idToken için Web (server) istemci kimliği şarttır. Yoksa düğme hiç gösterilmez
/// (çalışmayan düğme mağaza incelemesinde ret sebebidir).
bool get googleAvailable {
  final forced = debugGoogleAvailable;
  if (forced != null) return forced;
  if (kIsWeb) return false;
  if (Platform.isIOS || Platform.isMacOS) return googleIosClientId.isNotEmpty;
  if (Platform.isAndroid) return googleServerClientId.isNotEmpty;
  return false;
}

/// Sign in with Apple yalnız Apple platformlarında sunulur.
bool get appleSignInAvailable =>
    !kIsWeb && (Platform.isIOS || Platform.isMacOS);

/// Bulut kaydının girişte en fazla bu kadar beklenir; sonra arka planda sürer.
const progressAttachTimeout = Duration(seconds: 4);

/// /v1/username/check yanıtı: biçim, topluluk kuralı (filtre + yönetici yasağı) ve boşluk.
class UsernameCheck {
  const UsernameCheck({
    required this.valid,
    required this.allowed,
    required this.available,
    this.message,
  });
  factory UsernameCheck.fromJson(Map<String, dynamic> j) => UsernameCheck(
    valid: j['valid'] == true,
    // Eski sunucu `allowed` göndermez: yalnız `available` belirleyicidir.
    allowed: j['allowed'] != false,
    available: j['available'] == true,
    message: j['message'] as String?,
  );
  final bool valid, allowed, available;

  /// Uygunsuz adda sunucunun Türkçe açıklaması.
  final String? message;
}

/// Sunucu hatası `username_not_allowed` gelmezse gösterilen açıklama.
const kUsernameNotAllowed =
    'Bu kullanıcı adı uygun değil. Küfür, hakaret, cinsel içerik, nefret söylemi '
    'ya da resmî hesap taklidi içeremez.';

/// Testler için: kullanıcı adı kontrolünü sunucusuz yanıtlar.
@visibleForTesting
Future<UsernameCheck> Function(String value)? debugUsernameCheck;

class AppUser {
  const AppUser({
    required this.id,
    this.email,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.providers = const [],
    this.termsVersion = 0,
  });
  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    email: json['email'] as String?,
    username: json['username'] as String?,
    displayName: json['displayName'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    providers: (json['providers'] as List? ?? const []).cast<String>(),
    termsVersion: (json['termsVersion'] as num?)?.toInt() ?? 0,
  );
  final String id;
  final String? email;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final List<String> providers;

  /// Sunucuda kayıtlı kabul edilen Kullanım Koşulları sürümü (0 = kayıt yok).
  final int termsVersion;

  AppUser withTerms(int version) => AppUser(
    id: id,
    email: email,
    username: username,
    displayName: displayName,
    avatarUrl: avatarUrl,
    providers: providers,
    termsVersion: version,
  );
  bool get needsUsername => username == null || username!.isEmpty;
}

class AuthService extends ChangeNotifier {
  AuthService._();
  static final instance = AuthService._();
  final api = ApiClient.instance;
  AppUser? user;
  bool loading = true;
  String? error;

  /// Açılıştaki oturum kontrolü bitti mi (yükleme ekranı yalnız bu sırada gösterilir).
  bool initialized = false;

  /// Giriş yapmış (adı seçilmiş) hesap güncel Kullanım Koşulları'nı henüz onaylamadı:
  /// kayıttan önce açılmış hesaplar uygulamada bir kez onaylar (sunucu + cihaz kaydı).
  bool termsPending = false;

  Future<void> initialize() async {
    await api.restore();
    try {
      user = AppUser.fromJson(
        (await api.get('/v1/me'))['user'] as Map<String, dynamic>,
      );
    } on ApiException catch (e) {
      user = null;
      // Askıya alınan hesap: giriş ekranı açıklamayı gösterir, saklı oturum silinir.
      if (e.code == 'account_suspended') {
        error = e.message;
        await api.clear();
      }
    } catch (_) {
      user = null;
    }
    if (user != null) unawaited(ModerationService.instance.refresh());
    await _attachProgress();
    await _updateTermsState();
    loading = false;
    initialized = true;
    notifyListeners();
  }

  Future<void> _updateTermsState() async {
    final u = user;
    termsPending =
        u != null &&
        !u.needsUsername &&
        u.termsVersion < kTermsVersion &&
        await ModerationService.acceptedTermsVersion(u.id) < kTermsVersion;
  }

  /// Koşul kapısındaki onay: önce cihaza yazılır (sunucuya ulaşılamasa da oyuncu takılmaz),
  /// sonra sunucuya gönderilir.
  Future<void> acceptTerms() async {
    final u = user;
    if (u == null) return;
    await ModerationService.saveTermsAccepted(u.id);
    termsPending = false;
    notifyListeners();
    try {
      final r = await api.post(
        '/v1/me/terms',
        data: {'termsVersion': kTermsVersion},
      );
      final v = (r['termsVersion'] as num?)?.toInt();
      if (v != null && user?.id == u.id) user = u.withTerms(v);
    } catch (_) {}
  }

  /// İlerleme hesabına bağlanır: bulut çekilip sessizce birleştirilir (yeni kurulumda
  /// soru sormadan geri yüklenir). Ağ yavaşsa giriş beklemez, senkron arka planda sürer.
  Future<void> _attachProgress() async {
    try {
      await ProgressService.instance
          .attach(user?.id)
          .timeout(progressAttachTimeout);
    } catch (_) {}
  }

  Future<void> emailAuth(
    String email,
    String password, {
    required bool register,
    String? username,
  }) async {
    await _run(() async {
      final result = await api.post(
        '/v1/auth/${register ? 'register' : 'login'}',
        data: {
          'email': email.trim(),
          'password': password,
          if (register) 'username': username?.trim(),
          // Kayıt ekranında işaretlenen Kullanım Koşulları sürümü (sunucuda saklanır).
          if (register) 'termsVersion': kTermsVersion,
        },
        auth: false,
      );
      await _accept(result);
      if (register && user != null) {
        await ModerationService.saveTermsAccepted(user!.id);
      }
    });
  }

  Future<void> google() async {
    await _run(() async {
      final apple = !kIsWeb && (Platform.isIOS || Platform.isMacOS);
      if (apple && googleIosClientId.isEmpty) {
        throw const ApiException(
          'google_config',
          'Google girişi bu derlemede yapılandırılmamış.',
        );
      }
      final account = await GoogleSignIn(
        scopes: const ['email'],
        clientId: apple ? googleIosClientId : null,
        serverClientId: googleServerClientId.isEmpty
            ? null
            : googleServerClientId,
      ).signIn();
      if (account == null) return;
      final token = (await account.authentication).idToken;
      if (token == null) {
        throw const ApiException('google_token', 'Google kimliği alınamadı.');
      }
      await _accept(
        await api.post(
          '/v1/auth/google',
          data: {'identityToken': token, 'displayName': account.displayName},
          auth: false,
        ),
      );
    });
  }

  Future<void> apple() async {
    await _run(() async {
      final challenge = await api.post('/v1/auth/apple/challenge', auth: false);
      final credential = await SignInWithApple.getAppleIDCredential(
        nonce: challenge['nonce'] as String,
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      if (credential.identityToken == null) {
        throw const ApiException('apple_token', 'Apple kimliği alınamadı.');
      }
      await _accept(
        await api.post(
          '/v1/auth/apple',
          data: {
            'identityToken': credential.identityToken,
            'challengeId': challenge['challengeId'],
            'displayName': [
              credential.givenName,
              credential.familyName,
            ].whereType<String>().join(' '),
          },
          auth: false,
        ),
      );
    });
  }

  /// Kayıt ve ad seçimi ile aynı kural: biçim, topluluk kuralı, boşluk.
  Future<UsernameCheck> checkUsername(String value) async {
    final hook = debugUsernameCheck;
    if (hook != null) return hook(value);
    final result = await api.get(
      '/v1/username/check?username=${Uri.encodeQueryComponent(value)}',
      auth: false,
    );
    return UsernameCheck.fromJson(result);
  }

  Future<bool> usernameAvailable(String value) async =>
      (await checkUsername(value)).available;

  Future<void> chooseUsername(String value) async {
    await _run(() async {
      final result = await api.put(
        '/v1/me/username',
        data: {'username': value.trim(), 'termsVersion': kTermsVersion},
      );
      user = AppUser.fromJson(result['user'] as Map<String, dynamic>);
      await ModerationService.saveTermsAccepted(user!.id);
      termsPending = false;
    });
  }

  Future<void> logout() async {
    try {
      await ProgressService.instance.flush().timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {}
    await ProgressService.instance.attach(null);
    await api.clear();
    ModerationService.instance.reset();
    user = null;
    termsPending = false;
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    await _run(() async {
      Map<String, dynamic>? data;
      if (user?.providers.contains('apple') == true) {
        final credential = await SignInWithApple.getAppleIDCredential(
          scopes: const [],
        );
        data = {
          'identityToken': credential.identityToken,
          'authorizationCode': credential.authorizationCode,
        };
      }
      await api.delete('/v1/me', data: data);
      // Sunucu bulut ilerlemesini de sildi; bu cihazdaki kopya da temizlenir.
      await ProgressService.instance.forgetAccount();
      await api.clear();
      ModerationService.instance.reset();
      user = null;
    });
  }

  Future<void> _accept(Map<String, dynamic> result) async {
    await api.saveTokens(result);
    user = AppUser.fromJson(result['user'] as Map<String, dynamic>);
    ModerationService.instance.reset();
    unawaited(ModerationService.instance.refresh());
    await _attachProgress();
    await _updateTermsState();
  }

  Future<void> _run(Future<void> Function() action) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } on ApiException catch (e) {
      error = e.message;
      rethrow;
    } on SignInWithAppleAuthorizationException catch (e) {
      // Kullanıcı vazgeçtiyse sessiz kal.
      if (e.code != AuthorizationErrorCode.canceled) {
        error = 'Apple girişi tamamlanamadı.';
      }
      rethrow;
    } on PlatformException catch (e) {
      if (e.code != 'sign_in_canceled' && e.code != 'canceled') {
        error = e.code == 'network_error'
            ? 'Bağlantı kurulamadı. İnternetini kontrol et.'
            : 'Giriş tamamlanamadı (${e.code}).';
      }
      rethrow;
    } catch (_) {
      error = 'Giriş tamamlanamadı. Tekrar dene.';
      rethrow;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
