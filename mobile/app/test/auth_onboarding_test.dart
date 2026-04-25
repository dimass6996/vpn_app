import 'package:arbuz_vpn_app/src/core/config/app_config.dart';
import 'package:arbuz_vpn_app/src/core/network/api_client.dart';
import 'package:arbuz_vpn_app/src/core/storage/session_repository.dart';
import 'package:arbuz_vpn_app/src/features/app_shell/app_controller.dart';
import 'package:arbuz_vpn_app/src/features/app_shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows onboarding auth copy after restartAuth', (tester) async {
    final controller = AppController(
      config: const AppConfig(),
      apiClient: _FakeApiClient(),
      sessionStore: _FakeSessionStore(),
    );
    await controller.restartAuth();

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('Request access code'), findsOneWidget);
    expect(find.text('OTP sign-in'), findsOneWidget);
    expect(find.text('Request OTP'), findsOneWidget);
  });
}

class _FakeSessionStore implements SessionRepository {
  PersistedSession _session = const PersistedSession();

  @override
  Future<PersistedSession> load() async => _session;

  @override
  Future<void> save(PersistedSession session) async {
    _session = session;
  }

  @override
  Future<void> clear() async {
    _session = const PersistedSession();
  }
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(const AppConfig());
}
