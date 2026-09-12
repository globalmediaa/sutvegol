import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'api_client.dart';

class AppUser {
  const AppUser({
    required this.id,
    this.email,
    this.username,
    this.displayName,
    this.avatarUrl,
  });
  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    email: json['email'] as String?,
    username: json['username'] as String?,
    displayName: json['displayName'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
  );
  final String id;
  final String? email;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
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
      final account = await GoogleSignIn(scopes: const ['email']).signIn();
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
      final credential = await SignInWithApple.getAppleIDCredential(
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
      await api.delete('/v1/me');
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
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
