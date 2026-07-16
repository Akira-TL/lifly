import 'package:flutter/material.dart';

@immutable
class ThemeSnapshot {
  final String familyId;
  final String displayName;
  final ThemeData lightTheme;
  final ThemeData darkTheme;
  final ThemeMode themeMode;

  const ThemeSnapshot({
    required this.familyId,
    required this.displayName,
    required this.lightTheme,
    required this.darkTheme,
    required this.themeMode,
  });
}
