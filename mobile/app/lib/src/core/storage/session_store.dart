import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'session_repository.dart';

class SessionStore implements SessionRepository {
  SessionStore({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'arbuz_access_token';
  static const _refreshTokenKey = 'arbuz_refresh_token';
  static const _challengeIdKey = 'arbuz_challenge_id';
  static const _loginKey = 'arbuz_login';

  final FlutterSecureStorage _secureStorage;

  @override
  Future<PersistedSession> load() async {
    final values = await _secureStorage.readAll();
    return PersistedSession(
      accessToken: values[_accessTokenKey],
      refreshToken: values[_refreshTokenKey],
      challengeId: values[_challengeIdKey],
      login: values[_loginKey],
    );
  }

  @override
  Future<void> save(PersistedSession session) async {
    await _writeNullable(_accessTokenKey, session.accessToken);
    await _writeNullable(_refreshTokenKey, session.refreshToken);
    await _writeNullable(_challengeIdKey, session.challengeId);
    await _writeNullable(_loginKey, session.login);
  }

  @override
  Future<void> clear() async {
    await _secureStorage.deleteAll();
  }

  Future<void> _writeNullable(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _secureStorage.delete(key: key);
      return;
    }
    await _secureStorage.write(key: key, value: value);
  }
}
