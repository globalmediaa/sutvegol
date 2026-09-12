import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.example.com',
);

class ApiException implements Exception {
  const ApiException(this.code, this.message, [this.status = 0]);
  final String code;
  final String message;
  final int status;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();
  static final instance = ApiClient._();
  static const _storage = FlutterSecureStorage();
  String? _accessToken;
  String? _refreshToken;

  Future<void> restore() async {
    _accessToken = await _storage.read(key: 'access_token');
    _refreshToken = await _storage.read(key: 'refresh_token');
  }

  Future<void> saveTokens(Map<String, dynamic> data) async {
    _accessToken = data['accessToken'] as String? ?? _accessToken;
    _refreshToken = data['refreshToken'] as String? ?? _refreshToken;
    if (_accessToken != null) {
      await _storage.write(key: 'access_token', value: _accessToken);
    }
    if (_refreshToken != null) {
      await _storage.write(key: 'refresh_token', value: _refreshToken);
    }
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    await _storage.deleteAll();
  }

  Future<Map<String, dynamic>> get(String path, {bool auth = true}) =>
      _send('GET', path, auth: auth);
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
    bool auth = true,
  }) => _send('POST', path, data: data, auth: auth);
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? data,
    bool auth = true,
  }) => _send('PUT', path, data: data, auth: auth);
  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic>? data,
    bool auth = true,
  }) => _send('DELETE', path, data: data, auth: auth);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? data,
    required bool auth,
    bool retried = false,
  }) async {
    if (apiBaseUrl.contains('example.com')) {
      throw const ApiException(
        'not_configured',
        'Sunucu adresi henüz yapılandırılmadı.',
      );
    }
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-Platform': kIsWeb ? 'web' : Platform.operatingSystem,
    };
    if (auth && _accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    late http.Response response;
    try {
      final uri = Uri.parse('$apiBaseUrl$path');
      response = switch (method) {
        'POST' => await http.post(
          uri,
          headers: headers,
          body: jsonEncode(data ?? {}),
        ),
        'PUT' => await http.put(
          uri,
          headers: headers,
          body: jsonEncode(data ?? {}),
        ),
        'DELETE' => await http.delete(
          uri,
          headers: headers,
          body: jsonEncode(data ?? {}),
        ),
        _ => await http.get(uri, headers: headers),
      };
    } catch (_) {
      throw const ApiException(
        'network',
        'Sunucuya ulaşılamadı. Bağlantını kontrol et.',
      );
    }
    final decoded =
        jsonDecode(response.body.isEmpty ? '{}' : response.body)
            as Map<String, dynamic>;
    if (response.statusCode == 401 &&
        auth &&
        !retried &&
        _refreshToken != null) {
      final refreshed = await _send(
        'POST',
        '/v1/auth/refresh',
        data: {'refreshToken': _refreshToken},
        auth: false,
        retried: true,
      );
      await saveTokens(refreshed);
      return _send(method, path, data: data, auth: auth, retried: true);
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['ok'] == false) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw ApiException(
        error?['code'] as String? ?? 'server',
        error?['message'] as String? ?? 'İşlem tamamlanamadı.',
        response.statusCode,
      );
    }
    return decoded;
  }
}
