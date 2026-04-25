import 'package:arbuz_vpn_app/src/core/config/app_config.dart';
import 'package:arbuz_vpn_app/src/core/network/api_client.dart';
import 'package:arbuz_vpn_app/src/core/network/api_models.dart';
import 'package:arbuz_vpn_app/src/core/storage/session_repository.dart';
import 'package:arbuz_vpn_app/src/core/vpn/vpn_engine.dart';
import 'package:arbuz_vpn_app/src/features/app_shell/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppController', () {
    test('initialize routes to onboarding when no session exists', () async {
      final sessionStore = InMemorySessionStore(const PersistedSession());
      final apiClient = FakeApiClient();
      final controller = AppController(
        config: const AppConfig(),
        apiClient: apiClient,
        sessionStore: sessionStore,
      );

      await controller.initialize();

      expect(controller.authStage, AuthStage.onboarding);
      expect(controller.statusTone, StatusTone.neutral);
      expect(controller.statusMessage, contains('Telegram username'));
    });

    test('initialize restores pending challenge and opens verification stage', () async {
      final sessionStore = InMemorySessionStore(
        const PersistedSession(challengeId: 'challenge-1'),
      );
      final apiClient = FakeApiClient();
      final controller = AppController(
        config: const AppConfig(),
        apiClient: apiClient,
        sessionStore: sessionStore,
      );

      await controller.initialize();

      expect(controller.authStage, AuthStage.codeVerification);
      expect(controller.statusTone, StatusTone.warning);
      expect(apiClient.getMeCalls, 0);
    });

    test('initialize restores authenticated dashboard from storage', () async {
      final sessionStore = InMemorySessionStore(
        const PersistedSession(accessToken: 'access-1', refreshToken: 'refresh-1'),
      );
      final apiClient = FakeApiClient();
      final controller = AppController(
        config: const AppConfig(),
        apiClient: apiClient,
        sessionStore: sessionStore,
      );

      await controller.initialize();

      expect(controller.authStage, AuthStage.authenticated);
      expect(controller.me?.userId, 'demo-user');
      expect(controller.subscription?.isActive, isTrue);
      expect(controller.configs, isNotEmpty);
      expect(apiClient.getMeCalls, 1);
      expect(apiClient.refreshTokenCalls, 0);
    });

    test('refreshes access token on 401 and retries protected request', () async {
      final sessionStore = InMemorySessionStore(
        const PersistedSession(accessToken: 'expired-access', refreshToken: 'refresh-1'),
      );
      final apiClient = FakeApiClient()
        ..failFirstMeWithUnauthorized = true
        ..nextAccessToken = 'new-access';
      final controller = AppController(
        config: const AppConfig(),
        apiClient: apiClient,
        sessionStore: sessionStore,
      );

      await controller.initialize();

      expect(controller.authStage, AuthStage.authenticated);
      expect(apiClient.refreshTokenCalls, 1);
      expect(apiClient.getMeCalls, 2);
      expect(sessionStore.current.accessToken, 'new-access');
      expect(sessionStore.current.refreshToken, 'refresh-1');
    });

    test('logout clears local session and dashboard state', () async {
      final sessionStore = InMemorySessionStore(
        const PersistedSession(accessToken: 'access-1', refreshToken: 'refresh-1'),
      );
      final apiClient = FakeApiClient();
      final controller = AppController(
        config: const AppConfig(),
        apiClient: apiClient,
        sessionStore: sessionStore,
      );
      await controller.initialize();

      await controller.logout();

      expect(controller.authStage, AuthStage.onboarding);
      expect(controller.me, isNull);
      expect(controller.configs, isEmpty);
      expect(sessionStore.current.hasSession, isFalse);
      expect(apiClient.logoutCalls, 1);
    });

    test('verifyAuthLink parses challenge and code and authenticates', () async {
      final sessionStore = InMemorySessionStore(const PersistedSession());
      final apiClient = FakeApiClient();
      final controller = AppController(
        config: const AppConfig(),
        apiClient: apiClient,
        sessionStore: sessionStore,
      );
      await controller.initialize();

      await controller.verifyAuthLink(
        'https://example.com/auth?challenge_id=challenge-42&code=123456',
      );

      expect(controller.authStage, AuthStage.authenticated);
      expect(apiClient.lastVerifyChallengeId, 'challenge-42');
      expect(apiClient.lastVerifyCode, '123456');
      expect(sessionStore.current.hasSession, isTrue);
    });

    test('toggleVpn uses vpn engine connect and disconnect', () async {
      final sessionStore = InMemorySessionStore(
        const PersistedSession(accessToken: 'access-1', refreshToken: 'refresh-1'),
      );
      final apiClient = FakeApiClient();
      final vpnEngine = FakeVpnEngine();
      final controller = AppController(
        config: const AppConfig(),
        apiClient: apiClient,
        sessionStore: sessionStore,
        vpnEngine: vpnEngine,
      );
      await controller.initialize();

      expect(controller.vpnEnabled, isFalse);
      await controller.toggleVpn();
      expect(controller.vpnEnabled, isTrue);
      expect(vpnEngine.connectCalls, 1);
      expect(vpnEngine.lastConnectUrl, 'https://example.com/sub?format=sing-box');
      expect(vpnEngine.lastConnectProtocol, 'sing-box-subscription');

      await controller.toggleVpn();
      expect(controller.vpnEnabled, isFalse);
      expect(vpnEngine.disconnectCalls, 1);
    });
  });
}

class InMemorySessionStore implements SessionRepository {
  InMemorySessionStore(this.current);

  PersistedSession current;

  @override
  Future<void> clear() async {
    current = const PersistedSession();
  }

  @override
  Future<PersistedSession> load() async {
    return current;
  }

  @override
  Future<void> save(PersistedSession session) async {
    current = session;
  }
}

class FakeApiClient extends ApiClient {
  FakeApiClient() : super(const AppConfig(apiBaseUrl: 'http://localhost:9999/api/v1'));

  int getMeCalls = 0;
  int refreshTokenCalls = 0;
  int logoutCalls = 0;
  String? lastVerifyChallengeId;
  String? lastVerifyCode;
  bool failFirstMeWithUnauthorized = false;
  String nextAccessToken = 'refreshed-access';

  @override
  Future<MeResponse> getMe(String accessToken) async {
    getMeCalls += 1;
    if (failFirstMeWithUnauthorized && getMeCalls == 1) {
      throw const ApiException('Invalid token', statusCode: 401);
    }
    return const MeResponse(
      userId: 'demo-user',
      username: 'demo-user',
      authProvider: 'otp',
    );
  }

  @override
  Future<SubscriptionResponse> getSubscription(String accessToken) async {
    return const SubscriptionResponse(
      isActive: true,
      expireAtUnix: 1777777777,
      daysLeft: 30,
    );
  }

  @override
  Future<List<ConfigItem>> getConfigs(String accessToken) async {
    return const [
      ConfigItem(
        protocol: 'sing-box-subscription',
        label: 'Sing-box profile',
        value: 'https://example.com/sub?format=sing-box',
      ),
      ConfigItem(
        protocol: 'subscription',
        label: 'Primary',
        value: 'https://example.com/sub',
      ),
    ];
  }

  @override
  Future<AuthVerifyResult> refreshToken(String refreshToken) async {
    refreshTokenCalls += 1;
    return AuthVerifyResult(
      accessToken: nextAccessToken,
      refreshToken: refreshToken,
      expiresIn: 900,
    );
  }

  @override
  Future<void> logout({required String accessToken, String? refreshToken}) async {
    logoutCalls += 1;
  }

  @override
  Future<AuthVerifyResult> verifyAuth({
    required String challengeId,
    required String code,
    required String deviceId,
  }) async {
    lastVerifyChallengeId = challengeId;
    lastVerifyCode = code;
    return const AuthVerifyResult(
      accessToken: 'access-from-link',
      refreshToken: 'refresh-from-link',
      expiresIn: 900,
    );
  }
}

class FakeVpnEngine implements VpnEngine {
  int connectCalls = 0;
  int disconnectCalls = 0;
  String? lastConnectUrl;
  String? lastConnectProtocol;
  VpnRuntimeState _state = const VpnRuntimeState.disconnected();

  @override
  Future<VpnRuntimeState> connect({
    required String subscriptionUrl,
    required String protocol,
    required String username,
  }) async {
    connectCalls += 1;
    lastConnectUrl = subscriptionUrl;
    lastConnectProtocol = protocol;
    _state = VpnRuntimeState(
      connected: true,
      protocol: protocol.toUpperCase(),
      location: 'fake-node',
      details: '$username:$subscriptionUrl',
    );
    return _state;
  }

  @override
  Future<VpnRuntimeState> currentState() async {
    return _state;
  }

  @override
  Future<VpnRuntimeState> disconnect() async {
    disconnectCalls += 1;
    _state = const VpnRuntimeState.disconnected();
    return _state;
  }

  @override
  Future<VpnCoreStatus> coreStatus() async {
    return const VpnCoreStatus(
      available: true,
      path: 'stub://test-core',
      details: 'test core',
    );
  }
}
