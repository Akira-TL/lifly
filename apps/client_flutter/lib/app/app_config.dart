class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'LIFLY_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8310/api/v1',
  );
}
