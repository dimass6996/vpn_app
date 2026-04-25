class AppConfig {
  const AppConfig({
    this.apiBaseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://194.50.94.81:8001/api/v1',
    ),
    this.otpInputHint = '',
  });

  final String apiBaseUrl;
  final String otpInputHint;
}
