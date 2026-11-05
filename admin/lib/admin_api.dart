import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AdminApiException implements Exception {
  const AdminApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AdminApi {
  AdminApi({
    String? apiBaseUrl,
    http.Client? client,
    FlutterSecureStorage? storage,
  })  : apiBaseUrl = (apiBaseUrl ??
                const String.fromEnvironment(
                  'API_BASE_URL',
                  defaultValue: 'http://127.0.0.1:8000/api',
                ))
            .replaceFirst(RegExp(r'/+$'), ''),
        _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'oddflip_admin_access_token';

  final String apiBaseUrl;
  final http.Client _client;
  final FlutterSecureStorage _storage;

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final payload = await _request(
      'POST',
      '/login',
      body: {'email': email, 'password': password},
      authenticated: false,
    );
    final user = _asMap(payload['user']);
    if (user['role'] != 'admin') {
      throw const AdminApiException(
        'Akaunti hii si admin. Tumia akaunti yenye role ya admin.',
      );
    }

    final token = payload['access_token'];
    if (token is! String || token.isEmpty) {
      throw const AdminApiException('Backend haikurudisha access token.');
    }
    await _storage.write(key: _tokenKey, value: token);
    return user;
  }

  Future<Map<String, dynamic>> currentUser() async {
    final payload = await _request('GET', '/user');
    final user = _asMap(payload);
    if (user['role'] != 'admin') {
      await logout();
      throw const AdminApiException(
        'Akaunti hii haina ruhusa ya kufungua admin panel.',
      );
    }
    return user;
  }

  Future<AdminStats> fetchStats() async {
    final payload = await _request('GET', '/admin/stats');
    return AdminStats.fromJson(payload);
  }

  Future<AdminUserPage> fetchUsers({
    int page = 1,
    String search = '',
    String? status,
  }) async {
    final query = <String, String>{'per_page': '20', 'page': '$page'};
    if (search.trim().isNotEmpty) query['search'] = search.trim();
    if (status != null && status.isNotEmpty) query['status'] = status;
    final payload = await _request(
      'GET',
      '/admin/users',
      query: query,
    );
    return AdminUserPage.fromJson(payload);
  }

  Future<void> setStatus({
    required int userId,
    required String status,
    String? reference,
    String? paymentMethod,
  }) async {
    final body = <String, dynamic>{'status': status};
    if (reference != null) body['reference'] = reference;
    if (paymentMethod != null) body['payment_method'] = paymentMethod;
    await _request(
      'POST',
      '/admin/users/$userId/toggle-status',
      body: body,
    );
  }

  Future<void> logout() async {
    try {
      await _request('POST', '/logout');
    } finally {
      await _storage.delete(key: _tokenKey);
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    final uri = Uri.parse('$apiBaseUrl$path').replace(queryParameters: query);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (authenticated) {
      final token = await readToken();
      if (token == null || token.isEmpty) {
        throw const AdminApiException('Tafadhali ingia tena.');
      }
      headers['Authorization'] = 'Bearer $token';
    }

    try {
      final request = switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? const <String, dynamic>{}),
          ),
        _ => throw AdminApiException('HTTP method haitumiki: $method'),
      };
      final response = await request.timeout(const Duration(seconds: 45));
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : _asMap(jsonDecode(response.body));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errors = decoded['errors'];
        final firstError = errors is Map && errors.isNotEmpty
            ? (errors.values.first is List
                ? (errors.values.first as List).first
                : errors.values.first)
            : null;
        throw AdminApiException(
          firstError?.toString() ??
              decoded['message']?.toString() ??
              'Ombi la server limeshindwa (HTTP ${response.statusCode}).',
        );
      }
      return decoded;
    } on TimeoutException {
      throw const AdminApiException(
        'Ombi limechukua zaidi ya sekunde 45. Jaribu tena au hakiki muunganisho wa API.',
      );
    } on AdminApiException {
      rethrow;
    } on FormatException catch (error) {
      throw AdminApiException('Majibu ya server si JSON sahihi: $error');
    } catch (error) {
      throw AdminApiException('Imeshindikana kuwasiliana na server: $error');
    }
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const AdminApiException('Muundo wa majibu ya server si sahihi.');
  }
}

class AdminStats {
  const AdminStats({
    required this.totalRevenue,
    required this.currency,
    required this.freeTrialUsers,
    required this.activePaidUsers,
  });

  final int totalRevenue;
  final String currency;
  final int freeTrialUsers;
  final int activePaidUsers;

  factory AdminStats.fromJson(Map<String, dynamic> json) => AdminStats(
        totalRevenue: (json['total_revenue'] as num?)?.toInt() ?? 0,
        currency: json['currency']?.toString() ?? 'TZS',
        freeTrialUsers: (json['free_trial_users'] as num?)?.toInt() ?? 0,
        activePaidUsers: (json['active_paid_users'] as num?)?.toInt() ?? 0,
      );
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    required this.plan,
    this.trialEndsAt,
    this.subscriptionEndsAt,
  });

  final int id;
  final String name;
  final String email;
  final String role;
  final String status;
  final String plan;
  final String? trialEndsAt;
  final String? subscriptionEndsAt;

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: (json['id'] as num).toInt(),
        name: json['name']?.toString() ?? 'User',
        email: json['email']?.toString() ?? '',
        role: json['role']?.toString() ?? 'user',
        status: json['subscription_status']?.toString() ?? 'unknown',
        plan: json['plan']?.toString() ?? 'free_trial',
        trialEndsAt: json['trial_ends_at']?.toString(),
        subscriptionEndsAt: json['subscription_ends_at']?.toString(),
      );
}

class AdminUserPage {
  const AdminUserPage({
    required this.users,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  final List<AdminUser> users;
  final int currentPage;
  final int lastPage;
  final int total;

  factory AdminUserPage.fromJson(Map<String, dynamic> json) {
    final rawUsers = json['data'];
    return AdminUserPage(
      users: rawUsers is List
          ? rawUsers
              .map((item) => AdminUser.fromJson(
                    Map<String, dynamic>.from(item as Map),
                  ))
              .toList()
          : const [],
      currentPage: (json['current_page'] as num?)?.toInt() ?? 1,
      lastPage: (json['last_page'] as num?)?.toInt() ?? 1,
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}
