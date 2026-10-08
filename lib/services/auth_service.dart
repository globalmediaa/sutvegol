import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'api_client.dart';

/// Google OAuth istemci kimlikleri derleme anında verilir:
/// `--dart-define=GOOGLE_IOS_CLIENT_ID=…apps.googleusercontent.com`
/// `--dart-define=GOOGLE_SERVER_CLIENT_ID=…apps.googleusercontent.com` (Web
/// istemcisi; Android'de idToken almak için gerekir).
const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

class AppUser {
  const AppUser({
    required this.id,
    this.email,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.providers = const [],
  });
  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    email: json['email'] as String?,
    username: json['username'] as String?,
    displayName: json['displayName'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    providers: (json['providers'] as List? ?? const []).cast<String>(),
  );
  final String id;
  final String? email;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final List<String> providers;
  bool get needsUsername => username == null || username!.isEmpty;
}

class AuthService extends ChangeNotifier {
  AuthService._();
  static final instance = AuthService._();
  final api = ApiClient.instance;
  AppUser? user;
  bool loading = true;
  String? error;

  Future<void> initialize() async {
    await api.restore();
    try {
      user = AppUser.fromJson(
        (await api.get('/v1/me'))['user'] as Map<String, dynamic>,
      );
    } catch (_) {
      user = null;
    }
    loading = false;
    notifyListeners();
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
        },
        auth: false,
      );
      await _accept(result);
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

  Future<bool> usernameAvailable(String value) async {
    final result = await api.get(
      '/v1/username/check?username=${Uri.encodeQueryComponent(value)}',
      auth: false,
    );
    return result['available'] == true;
  }

  Future<void> chooseUsername(String value) async {
    await _run(() async {
      final result = await api.put(
        '/v1/me/username',
        data: {'username': value.trim()},
      );
      user = AppUser.fromJson(result['user'] as Map<String, dynamic>);
    });
  }

  Future<void> logout() async {
    await api.clear();
    user = null;
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
      await api.clear();
      user = null;
    });
  }

  Future<void> _accept(Map<String, dynamic> result) async {
    await api.saveTokens(result);
    user = AppUser.fromJson(result['user'] as Map<String, dynamic>);
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
