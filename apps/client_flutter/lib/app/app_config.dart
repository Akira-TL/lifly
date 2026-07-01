import 'package:client_flutter/app/data_mode.dart';

class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'LIFLY_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8310/api/v1',
  );

  static const String dataModeName = String.fromEnvironment(
    'LIFLY_DATA_MODE',
    defaultValue: 'api',
  );

  static LiflyDataMode get dataMode => LiflyDataMode.fromName(dataModeName);
}
