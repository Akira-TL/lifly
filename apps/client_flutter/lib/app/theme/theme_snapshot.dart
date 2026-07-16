import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_tokens.dart';
import 'package:flutter/material.dart';

@immutable
class ThemeSnapshot {
  final String familyId;
  final String displayName;
  final String packageVersion;
  final ThemePerformanceClass performanceClass;
  final ThemeTokenSet tokens;
  final ThemeData lightTheme;
  final ThemeData darkTheme;
  final ThemeMode themeMode;

  const ThemeSnapshot({
    required this.familyId,
    required this.displayName,
    required this.packageVersion,
    required this.performanceClass,
    required this.tokens,
    required this.lightTheme,
    required this.darkTheme,
    required this.themeMode,
  });
}
