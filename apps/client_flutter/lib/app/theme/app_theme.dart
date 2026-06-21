import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF4F46E5),
    brightness: Brightness.light,
    appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF4F46E5),
    brightness: Brightness.dark,
    appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
  );
}
