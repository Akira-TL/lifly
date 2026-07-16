import 'package:client_flutter/app/startup/startup_metrics_stub.dart'
    if (dart.library.js_interop) 'package:client_flutter/app/startup/startup_metrics_web.dart'
    as implementation;

abstract final class StartupMetrics {
  static void markDartEntrypoint() {
    implementation.markStartupEvent('lifly-dart-entrypoint');
  }

  static void markFlutterFirstFrame() {
    implementation.markStartupEvent('lifly-flutter-first-frame');
  }

  static void markCoreUsable() {
    implementation.markCoreUsable();
  }

  static void markThemeActivated(String themeId) {
    implementation.markThemeActivated(themeId);
  }

  static void markThemeRestoreFailed(Object error) {
    implementation.markStartupEvent(
      'lifly-theme-restore-failed',
      detail: error.toString(),
    );
  }
}
