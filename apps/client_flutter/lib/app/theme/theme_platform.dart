import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:flutter/foundation.dart';

ThemeTargetPlatform currentThemeTargetPlatform() {
  if (kIsWeb) return ThemeTargetPlatform.web;

  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => ThemeTargetPlatform.phone,
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => ThemeTargetPlatform.desktop,
  };
}
