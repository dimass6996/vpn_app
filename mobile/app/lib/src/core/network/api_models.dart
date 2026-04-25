class AuthStartResult {
  const AuthStartResult({
    required this.challengeId,
    required this.method,
    this.deliveryHint,
    this.magicLink,
  });

  final String challengeId;
  final String method;
  final String? deliveryHint;
  final String? magicLink;
}

class AuthVerifyResult {
  const AuthVerifyResult({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
}

class MeResponse {
  const MeResponse({
    required this.userId,
    required this.username,
    required this.authProvider,
  });

  final String userId;
  final String username;
  final String authProvider;
}

class SubscriptionResponse {
  const SubscriptionResponse({
    required this.isActive,
    required this.expireAtUnix,
    required this.daysLeft,
  });

  final bool isActive;
  final int? expireAtUnix;
  final int daysLeft;
}

class ConfigItem {
  const ConfigItem({
    required this.protocol,
    required this.label,
    required this.value,
  });

  final String protocol;
  final String label;
  final String value;
}
