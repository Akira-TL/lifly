import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:flutter/material.dart';

ThemePackageColorMode resolveThemeColorMode(
  ThemePackageColorMode requested,
  Set<ThemePackageColorMode> supported,
) {
  if (supported.contains(requested)) return requested;

  if (requested == ThemePackageColorMode.system &&
      supported.containsAll({
        ThemePackageColorMode.light,
        ThemePackageColorMode.dark,
      })) {
    return ThemePackageColorMode.system;
  }
  if (requested == ThemePackageColorMode.oled &&
      supported.contains(ThemePackageColorMode.dark)) {
    return ThemePackageColorMode.dark;
  }
  if (requested == ThemePackageColorMode.highContrast) {
    if (supported.contains(ThemePackageColorMode.light)) {
      return ThemePackageColorMode.light;
    }
    if (supported.contains(ThemePackageColorMode.dark)) {
      return ThemePackageColorMode.dark;
    }
  }

  if (supported.contains(ThemePackageColorMode.system) ||
      supported.containsAll({
        ThemePackageColorMode.light,
        ThemePackageColorMode.dark,
      })) {
    return ThemePackageColorMode.system;
  }
  if (supported.contains(ThemePackageColorMode.light)) {
    return ThemePackageColorMode.light;
  }
  if (supported.contains(ThemePackageColorMode.dark)) {
    return ThemePackageColorMode.dark;
  }
  if (supported.contains(ThemePackageColorMode.oled)) {
    return ThemePackageColorMode.oled;
  }
  return ThemePackageColorMode.highContrast;
}

ThemeMode materialThemeMode(ThemePackageColorMode colorMode) {
  return switch (colorMode) {
    ThemePackageColorMode.system => ThemeMode.system,
    ThemePackageColorMode.light => ThemeMode.light,
    ThemePackageColorMode.dark || ThemePackageColorMode.oled => ThemeMode.dark,
    ThemePackageColorMode.highContrast => ThemeMode.system,
  };
}
