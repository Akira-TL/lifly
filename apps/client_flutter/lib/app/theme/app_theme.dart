import 'package:client_flutter/app/theme/theme_snapshot.dart';
import 'package:flutter/material.dart';

class LiflyCoreTheme {
  static const familyId = 'lifly.core';

  static final ThemeSnapshot snapshot = ThemeSnapshot(
    familyId: familyId,
    displayName: 'Lifly Core',
    lightTheme: _build(Brightness.light),
    darkTheme: _build(Brightness.dark),
    themeMode: ThemeMode.system,
  );

  static ThemeData _build(Brightness brightness) => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF4F46E5),
    brightness: brightness,
    appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
  );
}
