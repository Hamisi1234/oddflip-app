import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

String _normalizeApiOrigin(String value) {
  var origin = value.trim().replaceFirst(RegExp(r'/+$'), '');
  if (origin.toLowerCase().endsWith('/api')) {
    origin = origin.substring(0, origin.length - 4);
  }
  return origin;
}

String resolveApiOrigin([String? override]) {
  final configured = _normalizeApiOrigin(
    override ?? const String.fromEnvironment('API_BASE_URL'),
  );
  if (configured.isNotEmpty) return configured;
  if (kIsWeb) {
    final browserHost = Uri.base.host;
    final host = browserHost.isEmpty ? 'localhost' : browserHost;
    return 'http://$host:8000';
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://127.0.0.1:8000';
}

String get defaultApiBaseUrl => '${resolveApiOrigin()}/api';

class ApiClient {
  ApiClient({
    String? baseUrl,
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  })  : baseUrl = resolveApiOrigin(baseUrl),
        _client = client,
        _tokenProvider = tokenProvider ?? _readAccessToken;

  final String baseUrl;
  final http.Client? _client;
  final Future<String?> Function() _tokenProvider;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const _tokenKey = 'access_token';
  static const _liveFixturesCacheKey = 'cached_live_fixtures_v1';
  static const _upcomingFixturesCacheKey = 'cached_upcoming_fixtures_v2';

  static Future<String?> _readAccessToken() =>
      _secureStorage.read(key: _tokenKey);

  Future<List<LiveFixture>> fetchLiveFixtures() async {
    try {
      final payload = await _get(
        '/api/fixtures/live',
        timeout: const Duration(seconds: 30),
      );
      final fixtures = _parseLiveFixtures(payload['data']);
      final meta = payload['meta'];
      final isStale = meta is Map && meta['stale'] == true;
      if (!isStale) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            _liveFixturesCacheKey,
            jsonEncode(payload['data'] ?? const []),
          );
        } catch (error) {
          debugPrint('Could not cache live fixtures: $error');
        }
      }
      return fixtures;
    } on ApiException {
      final cachedFixtures = await _readCachedLiveFixtures();
      if (cachedFixtures != null) return cachedFixtures;
      rethrow;
    }
  }

  Future<List<LiveFixture>> fetchUpcomingFixtures({
    String? date,
    String? timeFrom,
    String? timeTo,
    String? league,
    String? country,
  }) async {
    final filters = <String, String>{
      if (date != null && date.isNotEmpty) 'date': date,
      if (timeFrom != null && timeFrom.isNotEmpty) 'time_from': timeFrom,
      if (timeTo != null && timeTo.isNotEmpty) 'time_to': timeTo,
      if (league != null && league.isNotEmpty) 'league': league,
      if (country != null && country.isNotEmpty) 'country': country,
    };
    final path = Uri(
      path: '/api/fixtures/upcoming',
      queryParameters: filters.isEmpty ? null : filters,
    ).toString();
    final cacheKey = filters.isEmpty
        ? _upcomingFixturesCacheKey
        : '${_upcomingFixturesCacheKey}_${Uri(queryParameters: filters).query}';

    try {
      final payload = await _get(
        path,
        timeout: const Duration(seconds: 30),
      );
      final fixtures = _parseLiveFixtures(payload['data']);
      final meta = payload['meta'];
      final isStale = meta is Map && meta['stale'] == true;
      if (!isStale) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            cacheKey,
            jsonEncode(payload['data'] ?? const []),
          );
        } catch (error) {
          debugPrint('Could not cache upcoming fixtures: $error');
        }
      }
      return fixtures;
    } on ApiException {
      final cachedFixtures = await _readCachedFixtures(cacheKey);
      if (cachedFixtures != null) return cachedFixtures;
      rethrow;
    }
  }

  List<LiveFixture> _parseLiveFixtures(dynamic data) {
    final fixtures = data is List ? data : const [];
    return fixtures
        .map((item) =>
            LiveFixture.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<List<LiveFixture>?> _readCachedLiveFixtures() async {
    return _readCachedFixtures(_liveFixturesCacheKey);
  }

  Future<List<LiveFixture>?> _readCachedFixtures(String cacheKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(cacheKey);
      if (cached == null) return null;
      return _parseLiveFixtures(jsonDecode(cached));
    } on FormatException catch (error) {
      debugPrint('Cached fixtures are invalid JSON: $error');
    } on TypeError catch (error) {
      debugPrint('Cached fixtures have an invalid format: $error');
    } catch (error) {
      debugPrint('Could not read cached fixtures: $error');
    }
    return null;
  }

  Future<List<MatchEvent>> fetchEvents(String fixtureId) async {
    final payload = await _get(
      '/api/fixtures/${Uri.encodeComponent(fixtureId)}/events',
      timeout: const Duration(seconds: 30),
    );
    final data = payload['data'] as List<dynamic>? ?? const [];
    return data
        .map((item) =>
            MatchEvent.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<MatchInsights> fetchMatchInsights(String fixtureId) async {
    final payload = await _get(
      '/api/fixtures/${Uri.encodeComponent(fixtureId)}/insights',
      timeout: const Duration(seconds: 30),
    );
    return MatchInsights.fromJson(
      Map<String, dynamic>.from(payload['data'] as Map),
    );
  }

  Future<MkariaChatResponse> fetchAiAnalysis(String fixtureId) async {
    final uri = Uri.parse(
      '$baseUrl/api/fixtures/${Uri.encodeComponent(fixtureId)}/ai-analysis',
    );
    try {
      final headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };
      final token = await _tokenProvider();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final request = _client == null
          ? http.post(uri, headers: headers, body: '{}')
          : _client.post(uri, headers: headers, body: '{}');
      final response = await request.timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final payload = _decodeMap(response.body);
        throw ApiException(
          payload?['message']?.toString() ??
              'AI analyst returned HTTP ${response.statusCode}.',
        );
      }

      final payload = _decodeMap(response.body);
      final data = payload?['data'];
      if (data is! Map ||
          data['reply'] is! String ||
          (data['betslip'] != null && data['betslip'] is! Map)) {
        throw const ApiException('AI analyst returned an invalid response.');
      }

      return MkariaChatResponse.fromJson(Map<String, dynamic>.from(data));
    } on TimeoutException catch (error) {
      debugPrint('POST $uri timed out: $error');
      throw const ApiException(
        'AI analysis timed out. Please try again in a moment.',
      );
    } catch (error) {
      if (error is ApiException) rethrow;
      debugPrint('POST $uri failed: $error');
      throw const ApiException(
        'Could not reach the AI analyst. Check your connection and try again.',
      );
    }
  }

  Future<MkariaChatResponse> sendMkariaChat({
    required String message,
    List<Map<String, String>> history = const [],
    String? fixtureId,
    String? conversationId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/mkaria-chat');
    String? token;
    try {
      token = await _tokenProvider();
    } catch (error) {
      debugPrint('Could not read the Mkaria chat access token: $error');
      throw const ApiException(
        'Could not read your login session. Please log in again.',
      );
    }
    if (token == null || token.isEmpty) {
      throw const ApiException('Please log in to chat with Mkamaria AI.');
    }

    try {
      final headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
      final body = <String, dynamic>{
        'message': message,
        'history': history
            .take(10)
            .map((turn) => {
                  'role': turn['role'],
                  'content': turn['content'],
                })
            .toList(),
      };
      if (fixtureId != null && fixtureId.isNotEmpty) {
        body['fixture_id'] = fixtureId;
      }
      if (conversationId != null && conversationId.isNotEmpty) {
        body['conversation_id'] =
            int.tryParse(conversationId) ?? conversationId;
      }

      final request = _client == null
          ? http.post(uri, headers: headers, body: jsonEncode(body))
          : _client.post(uri, headers: headers, body: jsonEncode(body));
      final response = await request.timeout(const Duration(seconds: 45));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final payload = _decodeMap(response.body);
        throw ApiException(
          payload?['message']?.toString() ??
              'Mkamaria AI returned HTTP ${response.statusCode}.',
        );
      }

      final payload = _decodeMap(response.body);
      final data = payload?['data'];
      if (data is! Map ||
          data['reply'] is! String ||
          (data['betslip'] != null && data['betslip'] is! Map)) {
        throw const ApiException('Mkamaria AI returned an invalid response.');
      }
      return MkariaChatResponse.fromJson(Map<String, dynamic>.from(data));
    } on TimeoutException catch (error) {
      debugPrint('POST $uri timed out: $error');
      throw const ApiException(
        'Mkamaria AI timed out after 45 seconds. Please try again.',
      );
    } catch (error) {
      if (error is ApiException) rethrow;
      debugPrint('POST $uri failed: $error');
      throw const ApiException(
        'Could not reach Mkamaria AI. Check your connection and try again.',
      );
    }
  }

  Future<List<MkariaConversationSummary>> fetchMkariaConversations() async {
    final uri = Uri.parse('$baseUrl/api/mkaria-chats');
    final headers = await _mkariaChatHeaders();
    try {
      final request = _client == null
          ? http.get(uri, headers: headers)
          : _client.get(uri, headers: headers);
      final response = await request.timeout(const Duration(seconds: 20));
      final payload = _decodeMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          payload?['message']?.toString() ??
              'Could not load chat history (HTTP ${response.statusCode}).',
        );
      }
      final data = payload?['data'];
      if (data is! List) {
        throw const ApiException('The chat history response is invalid.');
      }
      return data
          .whereType<Map>()
          .map((item) => MkariaConversationSummary.fromJson(
              Map<String, dynamic>.from(item)))
          .toList();
    } on TimeoutException catch (error) {
      debugPrint('GET $uri timed out: $error');
      throw const ApiException('Loading chat history timed out. Please retry.');
    } catch (error) {
      if (error is ApiException) rethrow;
      debugPrint('GET $uri failed: $error');
      throw const ApiException(
          'Could not load chat history. Check your connection.');
    }
  }

  Future<MkariaConversation> fetchMkariaConversation(String id) async {
    final uri = Uri.parse('$baseUrl/api/mkaria-chats/$id');
    final headers = await _mkariaChatHeaders();
    try {
      final request = _client == null
          ? http.get(uri, headers: headers)
          : _client.get(uri, headers: headers);
      final response = await request.timeout(const Duration(seconds: 20));
      final payload = _decodeMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          payload?['message']?.toString() ??
              'Could not load this conversation (HTTP ${response.statusCode}).',
        );
      }
      final data = payload?['data'];
      if (data is! Map) {
        throw const ApiException('The conversation response is invalid.');
      }
      return MkariaConversation.fromJson(Map<String, dynamic>.from(data));
    } on TimeoutException catch (error) {
      debugPrint('GET $uri timed out: $error');
      throw const ApiException(
          'Loading this conversation timed out. Please retry.');
    } catch (error) {
      if (error is ApiException) rethrow;
      debugPrint('GET $uri failed: $error');
      throw const ApiException('Could not load this conversation.');
    }
  }

  Future<Map<String, String>> _mkariaChatHeaders() async {
    String? token;
    try {
      token = await _tokenProvider();
    } catch (error) {
      debugPrint('Could not read the Mkaria chat access token: $error');
      throw const ApiException(
        'Could not read your login session. Please log in again.',
      );
    }
    if (token == null || token.isEmpty) {
      throw const ApiException('Please log in to view chat history.');
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': '******',
    };
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final headers = const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };
      final request = _client == null
          ? http.get(uri, headers: headers)
          : _client.get(uri, headers: headers);
      final response = await request.timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final payload = _decodeMap(response.body);
        throw ApiException(
          payload?['message']?.toString() ??
              'Server returned HTTP ${response.statusCode}.',
        );
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on TimeoutException catch (error) {
      debugPrint('GET $uri timed out: $error');
      throw ApiException(
        'Request to $uri timed out. The API server may be busy or the live-data provider may be slow.',
      );
    } catch (error) {
      if (error is ApiException) rethrow;
      debugPrint('GET $uri failed: $error');
      throw ApiException(
        'Could not reach $uri. Check that the API server is running and reachable.',
      );
    }
  }

  Map<String, dynamic>? _decodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }
}
