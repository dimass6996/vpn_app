class PersistedSession {
  const PersistedSession({
    this.accessToken,
    this.refreshToken,
    this.challengeId,
    this.login,
  });

  final String? accessToken;
  final String? refreshToken;
  final String? challengeId;
  final String? login;

  bool get hasSession => accessToken != null && refreshToken != null;

  PersistedSession copyWith({
    String? accessToken,
    String? refreshToken,
    String? challengeId,
    String? login,
    bool clearAccessToken = false,
    bool clearRefreshToken = false,
    bool clearChallengeId = false,
    bool clearLogin = false,
  }) {
    return PersistedSession(
      accessToken: clearAccessToken ? null : (accessToken ?? this.accessToken),
      refreshToken: clearRefreshToken ? null : (refreshToken ?? this.refreshToken),
      challengeId: clearChallengeId ? null : (challengeId ?? this.challengeId),
      login: clearLogin ? null : (login ?? this.login),
    );
  }
}

abstract class SessionRepository {
  Future<PersistedSession> load();
  Future<void> save(PersistedSession session);
  Future<void> clear();
}
