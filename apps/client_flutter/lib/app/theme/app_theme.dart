import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_snapshot.dart';
import 'package:client_flutter/app/theme/theme_tokens.dart';
import 'package:flutter/material.dart';

class LiflyCoreTheme {
  static const familyId = 'lifly.core';

  static const tokens = ThemeTokenSet(
    light: ThemeModeTokens(
      colors: ThemeSemanticColors(
        primary: Color(0xFF4F46E5),
        onPrimary: Color(0xFFFFFFFF),
        secondary: Color(0xFF625B71),
        surface: Color(0xFFFFFBFF),
        onSurface: Color(0xFF1C1B1F),
        critical: Color(0xFFBA1A1A),
        warning: Color(0xFF8A5100),
        success: Color(0xFF216E39),
        info: Color(0xFF00639B),
        neutral: Color(0xFF605D66),
      ),
      typography: ThemeTypographyTokens(
        fontFamily: null,
        titleScale: 1,
        bodyScale: 1,
        labelScale: 1,
      ),
      spacing: ThemeSpacingTokens(page: 16, card: 16, inline: 8),
      radius: ThemeRadiusTokens(card: 12, control: 8),
      elevation: ThemeElevationTokens(card: 1),
      density: ThemeDensityTokens(visual: 0),
      motion: ThemeMotionTokens(
        enabled: true,
        fast: Duration(milliseconds: 120),
        normal: Duration(milliseconds: 200),
      ),
    ),
    dark: ThemeModeTokens(
      colors: ThemeSemanticColors(
        primary: Color(0xFFC4C0FF),
        onPrimary: Color(0xFF211A85),
        secondary: Color(0xFFCBC2DB),
        surface: Color(0xFF1C1B1F),
        onSurface: Color(0xFFE6E1E5),
        critical: Color(0xFFFFB4AB),
        warning: Color(0xFFFFB95F),
        success: Color(0xFF8DDAA5),
        info: Color(0xFF92CCFF),
        neutral: Color(0xFFCAC4D0),
      ),
      typography: ThemeTypographyTokens(
        fontFamily: null,
        titleScale: 1,
        bodyScale: 1,
        labelScale: 1,
      ),
      spacing: ThemeSpacingTokens(page: 16, card: 16, inline: 8),
      radius: ThemeRadiusTokens(card: 12, control: 8),
      elevation: ThemeElevationTokens(card: 1),
      density: ThemeDensityTokens(visual: 0),
      motion: ThemeMotionTokens(
        enabled: true,
        fast: Duration(milliseconds: 120),
        normal: Duration(milliseconds: 200),
      ),
    ),
  );

  static final ThemeSnapshot snapshot = ThemeSnapshot(
    familyId: familyId,
    displayName: 'Lifly Core',
    packageVersion: 'builtin',
    performanceClass: ThemePerformanceClass.core,
    colorMode: ThemePackageColorMode.system,
    tokens: tokens,
    lightTheme: tokens.buildTheme(Brightness.light),
    darkTheme: tokens.buildTheme(Brightness.dark),
    themeMode: ThemeMode.system,
  );
}
