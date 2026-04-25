import 'dart:convert';
import 'dart:io';
import 'dart:async';

import '../config/app_config.dart';
import 'api_models.dart';

class ApiClient {
  ApiClient(this._config) {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  final AppConfig _config;
  final HttpClient _httpClient = HttpClient();

  Future<AuthStartResult> startAuth({
    required String login,
    required String deviceId,
  }) async {
    final data = await _sendJson(
      method: 'POST',
      path: '/auth/start',
      body: {'login': login, 'device_id': deviceId},
    );
    return AuthStartResult(
      challengeId: data['challenge_id'] as String,
      method: data['method'] as String,
      deliveryHint: data['delivery_hint'] as String?,
      magicLink: data['magic_link'] as String?,
    );
  }

  Future<AuthVerifyResult> verifyAuth({
    required String challengeId,
    required String code,
    required String deviceId,
  }) async {
    final data = await _sendJson(
      method: 'POST',
      path: '/auth/verify',
      body: {
        'challenge_id': challengeId,
        'code': code,
        'device_id': deviceId,
      },
    );
    return AuthVerifyResult(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      expiresIn: data['expires_in'] as int,
    );
  }

  Future<AuthVerifyResult> refreshToken(String refreshToken) async {
    final data = await _sendJson(
      method: 'POST',
      path: '/auth/refresh',
      body: {'refresh_token': refreshToken},
    );
    return AuthVerifyResult(
      accessToken: data['access_token'] as String,
      refreshToken: refreshToken,
      expiresIn: data['expires_in'] as int,
    );
  }

  Future<MeResponse> getMe(String accessToken) async {
    final data = await _sendJson(
      method: 'GET',
      path: '/me',
      accessToken: accessToken,
    );
    return MeResponse(
      userId: data['user_id'] as String,
      username: data['username'] as String,
      authProvider: data['auth_provider'] as String,
      marzbanUsername: data['marzban_username'] as String?,
      marzbanLinkStatus: (data['marzban_link_status'] as String?) ?? 'pending',
    );
  }

  Future<MeResponse> linkMarzbanUser({
    required String accessToken,
    required String marzbanUsername,
  }) async {
    final data = await _sendJson(
      method: 'POST',
      path: '/me/marzban/link',
      accessToken: accessToken,
      body: {'marzban_username': marzbanUsername},
    );
    return MeResponse(
      userId: '',
      username: '',
      authProvider: '',
      marzbanUsername: data['marzban_username'] as String?,
      marzbanLinkStatus: (data['marzban_link_status'] as String?) ?? 'pending',
    );
  }

  Future<SubscriptionResponse> getSubscription(String accessToken) async {
    final data = await _sendJson(
      method: 'GET',
      path: '/subscription',
      accessToken: accessToken,
    );
    return SubscriptionResponse(
      isActive: data['is_active'] as bool,
      expireAtUnix: data['expire_at_unix'] as int?,
      daysLeft: data['days_left'] as int,
    );
  }

  Future<List<ConfigItem>> getConfigs(String accessToken) async {
    final data = await _sendJson(
      method: 'GET',
      path: '/configs',
      accessToken: accessToken,
    );
    final items = data['items'] as List<dynamic>;
    return items
        .map(
          (item) => ConfigItem(
            protocol: item['protocol'] as String,
            label: item['label'] as String,
            value: item['value'] as String,
          ),
        )
        .toList();
  }

  Future<String> fetchVpnRuntimeConfig({
    required String accessToken,
    required String url,
  }) async {
    try {
      final request = await _httpClient.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
      final response = await request.close().timeout(const Duration(seconds: 20));
      final rawBody = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException.fromResponse(
          statusCode: response.statusCode,
          rawBody: rawBody,
        );
      }
      final trimmed = rawBody.trim();
      if (trimmed.isEmpty) {
        throw const ApiException('Runtime config response is empty.');
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map<String, dynamic>) {
          throw const ApiException('Runtime config is not a sing-box JSON object.');
        }
      } on FormatException {
        final snippet = trimmed.substring(0, trimmed.length > 180 ? 180 : trimmed.length);
        final hint = trimmed.contains('://')
            ? 'Runtime config looks like subscription links, not sing-box JSON.'
            : 'Runtime config is not valid JSON.';
        throw ApiException('$hint Snippet: $snippet');
      }
      return trimmed;
    } on TimeoutException {
      throw const ApiException('Runtime config request timed out.');
    } on SocketException {
      throw const ApiException('Cannot reach runtime config URL.');
    }
  }

  Future<void> createSupportRequest({
    required String accessToken,
    required String subject,
    required String message,
  }) async {
    await _sendJson(
      method: 'POST',
      path: '/support/request',
      accessToken: accessToken,
      body: {'subject': subject, 'message': message},
    );
  }

  Future<void> logout({
    required String accessToken,
    String? refreshToken,
  }) async {
    await _sendJson(
      method: 'POST',
      path: '/auth/logout',
      accessToken: accessToken,
      body: {
        if (refreshToken != null) 'refresh_token': refreshToken,
      },
    );
  }

  Future<void> logoutAll({required String accessToken}) async {
    await _sendJson(
      method: 'POST',
      path: '/auth/logout-all',
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> _sendJson({
    required String method,
    required String path,
    String? accessToken,
    Map<String, dynamic>? body,
  }) async {
    try {
      final request = await _openRequest(method: method, path: path);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (accessToken != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
      }
      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(const Duration(seconds: 20));
      final rawBody = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException.fromResponse(
          statusCode: response.statusCode,
          rawBody: rawBody,
        );
      }
      if (rawBody.isEmpty) {
        return <String, dynamic>{};
      }
      return jsonDecode(rawBody) as Map<String, dynamic>;
    } on TimeoutException {
      throw const ApiException('Request timed out. Check API URL and backend status.');
    } on SocketException {
      throw const ApiException('Cannot reach backend. Check API URL and backend status.');
    }
  }

  Future<HttpClientRequest> _openRequest({
    required String method,
    required String path,
  }) {
    final uri = Uri.parse('${_config.apiBaseUrl}$path');
    switch (method) {
      case 'GET':
        return _httpClient.getUrl(uri);
      case 'POST':
        return _httpClient.postUrl(uri);
      default:
        throw UnsupportedError('Unsupported method: $method');
    }
  }
}

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.details,
    this.code,
    this.requestId,
    this.fieldErrors,
  });

  final String message;
  final int? statusCode;
  final String? details;
  final String? code;
  final String? requestId;
  final List<FieldError>? fieldErrors;

  factory ApiException.fromResponse({
    required int statusCode,
    required String rawBody,
  }) {
    try {
      final decoded = jsonDecode(rawBody) as Map<String, dynamic>;
      final details = decoded['details'];
      return ApiException(
        (decoded['message'] as String?) ?? 'Request failed',
        statusCode: statusCode,
        details: rawBody,
        code: decoded['code'] as String?,
        requestId: decoded['request_id'] as String?,
        fieldErrors: details is List<dynamic>
            ? details
                .map(
                  (item) => FieldError(
                    field: item['field'] as String? ?? 'unknown',
                    message: item['message'] as String? ?? 'Invalid value',
                  ),
                )
                .toList()
            : null,
      );
    } catch (_) {
      return ApiException(
        'Request failed',
        statusCode: statusCode,
        details: rawBody,
      );
    }
  }

  @override
  String toString() {
    if (fieldErrors != null && fieldErrors!.isNotEmpty) {
      return '${fieldErrors!.first.field}: ${fieldErrors!.first.message}';
    }
    if (requestId != null && requestId!.isNotEmpty) {
      return '$message [request $requestId]';
    }
    return message;
  }
}

class FieldError {
  const FieldError({
    required this.field,
    required this.message,
  });

  final String field;
  final String message;
}
