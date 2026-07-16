import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_tokens.dart';
import 'package:flutter/material.dart';

@immutable
class ThemeSnapshot {
  final String familyId;
  final String displayName;
  final String packageVersion;
  final ThemePerformanceClass performanceClass;
  final ThemePackageColorMode colorMode;
  final ThemeTokenSet tokens;
  final ThemeData lightTheme;
  final ThemeData darkTheme;
  final ThemeMode themeMode;

  const ThemeSnapshot({
    required this.familyId,
    required this.displayName,
    required this.packageVersion,
    required this.performanceClass,
    required this.colorMode,
    required this.tokens,
    required this.lightTheme,
    required this.darkTheme,
    required this.themeMode,
  });

  ThemeSnapshot copyWith({
    ThemePackageColorMode? colorMode,
    ThemeMode? themeMode,
  }) {
    return ThemeSnapshot(
      familyId: familyId,
      displayName: displayName,
      packageVersion: packageVersion,
      performanceClass: performanceClass,
      colorMode: colorMode ?? this.colorMode,
      tokens: tokens,
      lightTheme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}
