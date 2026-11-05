import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

class ApiService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _tokenKey = 'access_token';

  static String get baseUrl => defaultApiBaseUrl;

  static Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password,
  ) {
    return _sendAuthRequest(
      endpoint: 'register',
      successStatus: 201,
      body: {'name': name, 'email': email, 'password': password},
    );
  }

  static Future<Map<String, dynamic>> login(String email, String password) {
    return _sendAuthRequest(
      endpoint: 'login',
      successStatus: 200,
      body: {'email': email, 'password': password},
    );
  }

  static Future<Map<String, dynamic>> _sendAuthRequest({
    required String endpoint,
    required int successStatus,
    required Map<String, String> body,
  }) async {
    final uri = Uri.parse('$baseUrl/$endpoint');
    late final http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: _jsonHeaders,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
    } catch (error) {
      debugPrint('POST $uri failed: $error');
      return {
        'success': false,
        'message':
            'Could not connect to the API at $uri. Check that Laravel is running.',
      };
    }

    final data = _decodeMap(response.body);
    if (data == null) {
      debugPrint(
          'POST $uri returned invalid JSON (HTTP ${response.statusCode}).');
      return {
        'success': false,
        'message': 'The server returned an invalid response.',
      };
    }

    if (response.statusCode != successStatus) {
      return {
        'success': false,
        'message': data['message']?.toString() ?? 'Authentication failed.',
        if (data['errors'] is Map) 'errors': data['errors'],
      };
    }

    final token = data['access_token'];
    if (token is! String || token.isEmpty) {
      debugPrint('POST $uri succeeded without an access token.');
      return {
        'success': false,
        'message': 'The server did not return a valid access token.',
      };
    }

    try {
      await _secureStorage.write(key: _tokenKey, value: token);
    } catch (error) {
      debugPrint('Could not securely store the API token: $error');
      return {
        'success': false,
        'message': 'Could not securely save your login. Please try again.',
      };
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove('auth_mode');
      final user = data['user'];
      if (user is Map) {
        await prefs.setString(
          'auth_user',
          jsonEncode(Map<String, dynamic>.from(user)),
        );
      }
    } catch (error) {
      debugPrint('Could not cache the authenticated user: $error');
    }

    return {'success': true, 'data': data};
  }

  static Future<String?> _readAccessToken() async {
    final token = await _secureStorage.read(key: _tokenKey);
    if (token != null && token.isNotEmpty) return token;

    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString(_tokenKey);
    final wasMockToken = prefs.getString('auth_mode') == 'mock';
    if (legacyToken != null && legacyToken.isNotEmpty && !wasMockToken) {
      await _secureStorage.write(key: _tokenKey, value: legacyToken);
      await prefs.remove(_tokenKey);
      await prefs.remove('auth_mode');
      return legacyToken;
    }

    await prefs.remove(_tokenKey);
    await prefs.remove('auth_mode');
    return null;
  }

  static Future<Map<String, dynamic>?> fetchProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedUser = _decodeMap(prefs.getString('auth_user')) ?? const {};
    final token = await _readAccessToken();
    if (token == null) return null;

    final uri = Uri.parse('$baseUrl/user/profile');
    try {
      final response = await http
          .get(uri, headers: _authHeaders(token))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 401) {
        await _clearStoredToken();
        return null;
      }
      final payload = _decodeMap(response.body);
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          payload == null) {
        debugPrint(
          'GET $uri returned HTTP ${response.statusCode}: '
          '${payload?['message'] ?? 'invalid response'}',
        );
        return cachedUser.isEmpty
            ? null
            : _profilePayload(cachedUser, null, null, false);
      }

      final user = _decodeMap(payload['user']) ?? cachedUser;
      if (user.isEmpty) return null;
      await prefs.setString('auth_user', jsonEncode(user));
      return _profilePayload(
        user,
        payload['device_token'] as String?,
        _decodeMap(payload['subscription']),
        payload['is_pro'] == true,
      );
    } catch (error) {
      debugPrint('GET $uri failed: $error');
      if (cachedUser.isEmpty) return null;
      return _profilePayload(cachedUser, null, null, false);
    }
  }

  static Future<void> logout() async {
    String? token;
    try {
      token = await _readAccessToken();
    } catch (error) {
      debugPrint('Could not read the saved API token during logout: $error');
    }
    if (token != null) {
      final uri = Uri.parse('$baseUrl/logout');
      try {
        final response = await http
            .post(uri, headers: _authHeaders(token))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          debugPrint('POST $uri returned HTTP ${response.statusCode}.');
        }
      } catch (error) {
        debugPrint('POST $uri failed: $error');
      }
    }

    await _clearStoredToken(clearUser: true);
  }

  static Future<void> _clearStoredToken({bool clearUser = false}) async {
    try {
      await _secureStorage.delete(key: _tokenKey);
    } catch (error) {
      debugPrint('Could not remove the secure API token: $error');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove('auth_mode');
    if (clearUser) await prefs.remove('auth_user');
  }

  static Future<Map<String, dynamic>> updateProfile({
    required String name,
    required String email,
  }) async {
    final token = await _readAccessToken();
    if (token == null) {
      return {'success': false, 'message': 'Log in to edit your profile.'};
    }

    final uri = Uri.parse('$baseUrl/user/profile');
    try {
      final response = await http
          .put(
            uri,
            headers: _authHeaders(token),
            body: jsonEncode({'name': name, 'email': email}),
          )
          .timeout(const Duration(seconds: 30));
      final payload = _decodeMap(response.body);
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          payload == null) {
        return {
          'success': false,
          'message': payload?['message'] ?? 'Could not update profile.',
          if (payload?['errors'] is Map) 'errors': payload?['errors'],
        };
      }
      final user =
          _decodeMap(payload['user']) ?? {'name': name, 'email': email};
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_user', jsonEncode(user));
      return {'success': true, 'user': user};
    } catch (error) {
      debugPrint('PUT $uri failed: $error');
      return {'success': false, 'message': 'Could not connect to the API.'};
    }
  }

  static Future<Map<String, dynamic>> updatePassword({
    required String currentPassword,
    required String password,
  }) async {
    final token = await _readAccessToken();
    if (token == null) {
      return {'success': false, 'message': 'Log in to change your password.'};
    }

    final uri = Uri.parse('$baseUrl/user/password');
    try {
      final response = await http
          .put(
            uri,
            headers: _authHeaders(token),
            body: jsonEncode({
              'current_password': currentPassword,
              'password': password,
              'password_confirmation': password,
            }),
          )
          .timeout(const Duration(seconds: 30));
      final payload = _decodeMap(response.body);
      return {
        'success': response.statusCode >= 200 && response.statusCode < 300,
        if (response.statusCode < 200 ||
            response.statusCode >= 300 ||
            payload == null)
          'message': payload?['message'] ?? 'Could not change your password.',
        if (payload?['errors'] is Map) 'errors': payload?['errors'],
      };
    } catch (error) {
      debugPrint('PUT $uri failed: $error');
      return {'success': false, 'message': 'Could not connect to the API.'};
    }
  }

  static const Map<String, String> _jsonHeaders = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  static Map<String, String> _authHeaders(String token) => {
        ..._jsonHeaders,
        'Authorization': 'Bearer $token',
      };

  static Map<String, dynamic>? _decodeMap(Object? value) {
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      } on FormatException {
        return null;
      }
    }
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  static Map<String, dynamic> _profilePayload(
    Map<String, dynamic> user,
    String? deviceToken,
    Map<String, dynamic>? subscription,
    bool isPro,
  ) {
    return {
      'user': user,
      'device_token': deviceToken,
      'subscription': subscription,
      'is_pro': isPro,
    };
  }
}
