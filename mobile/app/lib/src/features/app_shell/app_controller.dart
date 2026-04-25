import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_models.dart';
import '../../core/storage/session_repository.dart';
import '../../core/storage/session_store.dart';
import '../../core/vpn/platform_channel_vpn_engine.dart';
import '../../core/vpn/vpn_engine.dart';

enum AuthStage { bootstrapping, onboarding, codeVerification, authenticated }
enum StatusTone { neutral, success, warning, error }

class AppController extends ChangeNotifier {
  AppController({
    required AppConfig config,
    ApiClient? apiClient,
    SessionRepository? sessionStore,
    VpnEngine? vpnEngine,
  })  : _config = config,
        _apiClient = apiClient ?? ApiClient(config),
        _sessionStore = sessionStore ?? SessionStore(),
        _vpnEngine = vpnEngine ?? ResilientVpnEngine();

  final AppConfig _config;
  final ApiClient _apiClient;
  final SessionRepository _sessionStore;
  final VpnEngine _vpnEngine;
  PersistedSession _persistedSession = const PersistedSession();

  AuthStage _authStage = AuthStage.bootstrapping;
  bool _isLoading = false;
  int _selectedTab = 0;
  String _statusMessage = 'Enter Telegram username to request OTP.';
  StatusTone _statusTone = StatusTone.neutral;
  String _login = '';
  final String _deviceId = 'flutter-dev-simulator';
  String? _lastDeliveryHint;
  String? _lastMagicLink;
  VpnRuntimeState _vpnState = const VpnRuntimeState.disconnected();
  VpnCoreStatus _coreStatus = const VpnCoreStatus.unavailable();
  Timer? _runtimeSyncTimer;
  MeResponse? _me;
  SubscriptionResponse? _subscription;
  List<ConfigItem> _configs = const [];

  AuthStage get authStage => _authStage;
  bool get isLoading => _isLoading;
  int get selectedTab => _selectedTab;
  String get statusMessage => _statusMessage;
  StatusTone get statusTone => _statusTone;
  String get login => _login;
  String? get lastDeliveryHint => _lastDeliveryHint;
  String? get lastMagicLink => _lastMagicLink;
  bool get vpnEnabled => _vpnState.connected;
  MeResponse? get me => _me;
  SubscriptionResponse? get subscription => _subscription;
  List<ConfigItem> get configs => _configs;
  String get otpInputHint => _config.otpInputHint;
  VpnCoreStatus get coreStatus => _coreStatus;
  bool get runtimeProcessAlive => _coreStatus.runtimeProcessAlive;
  int? get runtimeHeartbeatAgeSeconds {
    final last = _coreStatus.runtimeLastUpdateMs;
    if (last == null || last <= 0) {
      return null;
    }
    final ageMs = DateTime.now().millisecondsSinceEpoch - last;
    if (ageMs < 0) {
      return 0;
    }
    return ageMs ~/ 1000;
  }
  bool get runtimeHeartbeatStale {
    final age = runtimeHeartbeatAgeSeconds;
    if (age == null) {
      return false;
    }
    return age > 12;
  }

  bool get canToggleVpn => (_subscription?.isActive == true) && runtimeConfigLink.isNotEmpty;
  String get primarySubscriptionLink =>
      _firstConfigValueByProtocol(const ['subscription']) ??
      (_configs.isNotEmpty ? _configs.first.value : '');
  String get runtimeConfigLink =>
      _firstConfigValueByProtocol(const ['sing-box-subscription', 'subscription']) ?? '';
  String get activeProtocol =>
      _vpnState.connected
          ? _vpnState.protocol
          : (_firstConfigByProtocol(const ['sing-box-subscription', 'subscription'])
                  ?.protocol
                  .toUpperCase() ??
              'N/A');
  String get activeLocation => _vpnState.connected ? _vpnState.location : 'Not connected';
  String get vpnRuntimeDetails => _vpnState.details ?? 'No runtime details';
  String get activeEndpointHost {
    if (_vpnState.connected && _vpnState.location.trim().isNotEmpty) {
      return _vpnState.location;
    }
    if (_configs.isNotEmpty) {
      final parsed = Uri.tryParse(_configs.first.value);
      if (parsed != null && parsed.hasAuthority && parsed.host.isNotEmpty) {
        return parsed.host;
      }
    }
    final api = Uri.tryParse(_config.apiBaseUrl);
    if (api != null && api.host.isNotEmpty) {
      return api.host;
    }
    return 'unknown';
  }

  Future<void> initialize() async {
    await _guard(() async {
      _statusMessage = 'Restoring local session.';
      _persistedSession = await _sessionStore.load();
      _login = _persistedSession.login ?? '';

      if (_persistedSession.challengeId != null) {
        _authStage = AuthStage.codeVerification;
        _setStatus('Pending verification challenge restored.', StatusTone.warning);
        return;
      }
      if (!_persistedSession.hasSession) {
        _authStage = AuthStage.onboarding;
        _setStatus('Enter Telegram username to request OTP.', StatusTone.neutral);
        return;
      }

      _authStage = AuthStage.authenticated;
      _setStatus('Restored session from secure storage.', StatusTone.success);
      await _refreshDashboardInternal();
      _startRuntimeSync();
    });
  }

  Future<void> startAuth(String login) async {
    await _guard(() async {
      _login = login.trim();
      if (_login.length < 3) {
        throw const ApiException('Login must contain at least 3 characters.');
      }
      final result = await _apiClient.startAuth(login: _login, deviceId: _deviceId);
      _persistedSession = _persistedSession.copyWith(
        challengeId: result.challengeId,
        login: _login,
      );
      await _sessionStore.save(_persistedSession);
      _authStage = AuthStage.codeVerification;
      _lastDeliveryHint = result.deliveryHint;
      _lastMagicLink = result.magicLink;
      _setStatus(
        result.deliveryHint == null
            ? 'OTP requested via ${result.method}.'
            : 'OTP requested via ${result.method}. ${result.deliveryHint}',
        StatusTone.success,
      );
    });
  }

  Future<void> verifyAuth(String code) async {
    await _guard(() async {
      final challengeId = _persistedSession.challengeId;
      if (challengeId == null) {
        throw StateError('Missing auth challenge');
      }
      final normalizedCode = code.trim();
      if (normalizedCode.length < 4) {
        throw const ApiException('OTP code is too short.');
      }

      final result = await _apiClient.verifyAuth(
        challengeId: challengeId,
        code: normalizedCode,
        deviceId: _deviceId,
      );
      _persistedSession = PersistedSession(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        login: _login,
      );
      await _sessionStore.save(_persistedSession);
      _authStage = AuthStage.authenticated;
      _setStatus('Session active. Pulling profile and configs.', StatusTone.success);
      await _refreshDashboardInternal();
      _startRuntimeSync();
    });
  }

  Future<void> resendAuthCode() async {
    await _guard(() async {
      final login = (_persistedSession.login ?? _login).trim();
      if (login.isEmpty) {
        throw const ApiException('Missing login. Go back and enter login again.');
      }
      _login = login;
      final result = await _apiClient.startAuth(login: login, deviceId: _deviceId);
      _persistedSession = _persistedSession.copyWith(
        challengeId: result.challengeId,
        login: login,
      );
      await _sessionStore.save(_persistedSession);
      _authStage = AuthStage.codeVerification;
      _lastDeliveryHint = result.deliveryHint;
      _lastMagicLink = result.magicLink;
      _setStatus(
        result.deliveryHint == null
            ? 'New OTP requested via ${result.method}.'
            : 'New OTP requested via ${result.method}. ${result.deliveryHint}',
        StatusTone.success,
      );
    });
  }

  Future<void> refreshDashboard() async {
    await _guard(_refreshDashboardInternal);
  }

  Future<void> refreshVpnRuntimeStatus() async {
    await _guard(() async {
      _vpnState = await _vpnEngine.currentState();
      _coreStatus = await _vpnEngine.coreStatus();
      _setStatus('VPN runtime status updated.', StatusTone.neutral);
    });
  }

  Future<void> sendSupportRequest({
    required String subject,
    required String message,
  }) async {
    await _guard(() async {
      await _authorizedCall(
        (token) => _apiClient.createSupportRequest(
          accessToken: token,
          subject: subject,
          message: message,
        ),
      );
      _setStatus('Support request accepted.', StatusTone.success);
    });
  }

  void selectTab(int index) {
    _selectedTab = index.clamp(0, 1).toInt();
    notifyListeners();
  }

  Future<void> restartAuth() async {
    _persistedSession = _persistedSession.copyWith(clearChallengeId: true);
    await _sessionStore.save(_persistedSession);
    _authStage = AuthStage.onboarding;
    _lastDeliveryHint = null;
    _lastMagicLink = null;
    _setStatus('Enter Telegram username to request OTP.', StatusTone.neutral);
    notifyListeners();
  }

  Future<void> logout() async {
    final accessToken = _persistedSession.accessToken;
    final refreshToken = _persistedSession.refreshToken;
    if (accessToken != null) {
      try {
        await _apiClient.logout(
          accessToken: accessToken,
          refreshToken: refreshToken,
        );
      } catch (_) {
        // Local cleanup still matters even if the network call fails.
      }
    }
    await _sessionStore.clear();
    _persistedSession = const PersistedSession();
    _authStage = AuthStage.onboarding;
    _selectedTab = 0;
    _login = '';
    _me = null;
    _subscription = null;
    _configs = const [];
    _lastDeliveryHint = null;
    _lastMagicLink = null;
    _vpnState = const VpnRuntimeState.disconnected();
    _coreStatus = const VpnCoreStatus.unavailable();
    _stopRuntimeSync();
    _setStatus('Session cleared.', StatusTone.neutral);
    notifyListeners();
  }

  Future<void> toggleVpn() async {
    await _guard(() async {
      if (!canToggleVpn) {
        throw const ApiException(
          'VPN is unavailable. Subscription is inactive or config is missing.',
        );
      }
      final username = me?.username ?? (_login.isNotEmpty ? _login : 'user');
      if (_vpnState.connected) {
        _vpnState = await _vpnEngine.disconnect();
      } else {
        final runtimeLink = runtimeConfigLink;
        if (runtimeLink.isEmpty) {
          throw const ApiException('Runtime VPN config is missing.');
        }
        final protocol =
            _firstConfigByProtocol(const ['sing-box-subscription', 'subscription'])?.protocol ??
                'subscription';
        _vpnState = await _vpnEngine.connect(
          subscriptionUrl: runtimeLink,
          protocol: protocol,
          username: username,
        );
        _coreStatus = await _vpnEngine.coreStatus();
        if (!_vpnState.connected) {
          unawaited(_pollVpnState(durationMs: 6000));
        }
      }
      _setStatus(
        _vpnState.connected
            ? 'VPN tunnel enabled. Protocol: $activeProtocol, endpoint: $activeEndpointHost.'
            : (_vpnState.details ?? 'VPN tunnel disabled.'),
        _vpnState.connected ? StatusTone.success : StatusTone.warning,
      );
    });
  }

  Future<void> verifyAuthLink(String rawLink) async {
    await _guard(() async {
      final link = rawLink.trim();
      if (link.isEmpty) {
        throw const ApiException('Paste Telegram login link first.');
      }
      final parsed = Uri.tryParse(link);
      if (parsed == null) {
        throw const ApiException('Invalid login link format.');
      }
      final challengeId = parsed.queryParameters['challenge_id']?.trim() ?? '';
      final code = parsed.queryParameters['code']?.trim() ?? '';
      if (challengeId.isEmpty || code.isEmpty) {
        throw const ApiException('Login link is missing challenge_id or code.');
      }

      final result = await _apiClient.verifyAuth(
        challengeId: challengeId,
        code: code,
        deviceId: _deviceId,
      );
      _persistedSession = PersistedSession(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        login: _login,
      );
      await _sessionStore.save(_persistedSession);
      _authStage = AuthStage.authenticated;
      _setStatus('Signed in via Telegram link. Pulling profile and configs.', StatusTone.success);
      await _refreshDashboardInternal();
      _startRuntimeSync();
    });
  }

  Future<String> _ensureAccessToken() async {
    final accessToken = _persistedSession.accessToken;
    if (accessToken != null) {
      return accessToken;
    }
    final refreshToken = _persistedSession.refreshToken;
    if (refreshToken == null) {
      throw StateError('Not authenticated');
    }
    final refreshed = await _apiClient.refreshToken(refreshToken);
    _persistedSession = _persistedSession.copyWith(
      accessToken: refreshed.accessToken,
      clearChallengeId: true,
    );
    await _sessionStore.save(_persistedSession);
    return refreshed.accessToken;
  }

  Future<T> _authorizedCall<T>(Future<T> Function(String accessToken) action) async {
    var accessToken = await _ensureAccessToken();
    try {
      return await action(accessToken);
    } on ApiException catch (error) {
      if (error.statusCode != 401) {
        rethrow;
      }
      _persistedSession = _persistedSession.copyWith(clearAccessToken: true);
      await _sessionStore.save(_persistedSession);
      accessToken = await _ensureAccessToken();
      return action(accessToken);
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    _isLoading = true;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      if (error is StateError && error.toString().contains('Not authenticated')) {
        await _sessionStore.clear();
        _persistedSession = const PersistedSession();
        _authStage = AuthStage.onboarding;
        _selectedTab = 0;
        _me = null;
        _subscription = null;
        _configs = const [];
        _stopRuntimeSync();
        _setStatus('Session expired. Please sign in again.', StatusTone.warning);
        return;
      }
      if (error is ApiException) {
        _setStatus(_humanizeApiError(error), StatusTone.error);
      } else {
        _setStatus(error.toString(), StatusTone.error);
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshDashboardInternal() async {
    final me = await _authorizedCall((token) => _apiClient.getMe(token));
    final subscription = await _authorizedCall((token) => _apiClient.getSubscription(token));
    final configs = await _authorizedCall((token) => _apiClient.getConfigs(token));
    _me = me;
    _subscription = subscription;
    _configs = configs;
    if (!canToggleVpn) {
      _vpnState = await _vpnEngine.disconnect();
    } else {
      _vpnState = await _vpnEngine.currentState();
    }
    _coreStatus = await _vpnEngine.coreStatus();
    _setStatus('Profile synced from BFF.', StatusTone.success);
  }

  void _setStatus(String message, StatusTone tone) {
    _statusMessage = message;
    _statusTone = tone;
  }

  String _humanizeApiError(ApiException error) {
    if (error.statusCode == 422 && error.fieldErrors != null && error.fieldErrors!.isNotEmpty) {
      final fieldError = error.fieldErrors!.first;
      return '${fieldError.field}: ${fieldError.message}';
    }
    if (error.statusCode == 401) {
      return 'Authorization failed. Please sign in again.';
    }
    if (error.statusCode == 429) {
      return 'Too many requests. Wait a moment and try again.';
    }
    if (error.statusCode != null && error.statusCode! >= 500) {
      return 'Server error. Try again shortly.';
    }
    return error.toString();
  }

  ConfigItem? _firstConfigByProtocol(List<String> protocols) {
    for (final protocol in protocols) {
      for (final item in _configs) {
        if (item.protocol == protocol) {
          return item;
        }
      }
    }
    return null;
  }

  String? _firstConfigValueByProtocol(List<String> protocols) {
    return _firstConfigByProtocol(protocols)?.value;
  }

  void _startRuntimeSync() {
    _runtimeSyncTimer?.cancel();
    _runtimeSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (_authStage != AuthStage.authenticated || _isLoading) {
        return;
      }
      try {
        final state = await _vpnEngine.currentState();
        final core = await _vpnEngine.coreStatus();
        final changed =
            state.connected != _vpnState.connected ||
            state.details != _vpnState.details ||
            core.runtimeProcessAlive != _coreStatus.runtimeProcessAlive ||
            core.details != _coreStatus.details ||
            core.available != _coreStatus.available;
        _vpnState = state;
        _coreStatus = core;
        if (changed) {
          notifyListeners();
        }
      } catch (_) {
        // Runtime sync is best-effort.
      }
    });
  }

  void _stopRuntimeSync() {
    _runtimeSyncTimer?.cancel();
    _runtimeSyncTimer = null;
  }

  Future<void> _pollVpnState({required int durationMs}) async {
    final deadline = DateTime.now().millisecondsSinceEpoch + durationMs;
    while (DateTime.now().millisecondsSinceEpoch < deadline) {
      await Future<void>.delayed(const Duration(milliseconds: 750));
      final state = await _vpnEngine.currentState();
      _vpnState = state;
      _coreStatus = await _vpnEngine.coreStatus();
      if (state.connected) {
        _setStatus(
          'VPN tunnel enabled. Protocol: $activeProtocol, endpoint: $activeEndpointHost.',
          StatusTone.success,
        );
        notifyListeners();
        return;
      }
      if ((state.details ?? '').contains('exited')) {
        _setStatus(state.details ?? 'VPN process exited unexpectedly.', StatusTone.error);
        notifyListeners();
        return;
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stopRuntimeSync();
    super.dispose();
  }
}
