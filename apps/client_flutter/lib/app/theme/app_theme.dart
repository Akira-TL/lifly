import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_platform_profile.dart';
import 'package:client_flutter/app/theme/theme_snapshot.dart';
import 'package:client_flutter/app/theme/theme_tokens.dart';
import 'package:flutter/material.dart';

class LiflyCoreTheme {
  static const familyId = 'lifly.core';

  static const tokens = ThemeTokenSet(
    light: ThemeModeTokens(
      colors: ThemeSemanticColors(
        primary: Color(0xFF225D45),
        onPrimary: Color(0xFFFFFFFF),
        secondary: Color(0xFF58675D),
        surface: Color(0xFFFBFBF8),
        onSurface: Color(0xFF20241F),
        critical: Color(0xFFA83D35),
        warning: Color(0xFF9A6717),
        success: Color(0xFF2F7052),
        info: Color(0xFF397296),
        neutral: Color(0xFF6F766E),
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
        primary: Color(0xFF91D2B0),
        onPrimary: Color(0xFF073925),
        secondary: Color(0xFFB9C9BE),
        surface: Color(0xFF171B18),
        onSurface: Color(0xFFE4E9E4),
        critical: Color(0xFFFFB4AB),
        warning: Color(0xFFFFC46C),
        success: Color(0xFF8FD5A9),
        info: Color(0xFF93CCF2),
        neutral: Color(0xFFBFC8C0),
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

  static final Map<ThemeTargetPlatform, ThemeSnapshot> _snapshots = {
    for (final platform in ThemeTargetPlatform.values)
      platform: _buildSnapshot(platform),
  };

  static ThemeSnapshot get snapshot => snapshotFor(ThemeTargetPlatform.web);

  static ThemeSnapshot snapshotFor(ThemeTargetPlatform platform) {
    return _snapshots[platform]!;
  }

  static ThemeSnapshot _buildSnapshot(ThemeTargetPlatform platform) {
    final profile = ThemePlatformProfile.defaults(platform);
    return ThemeSnapshot(
      familyId: familyId,
      displayName: 'Lifly Core',
      packageVersion: 'builtin',
      performanceClass: ThemePerformanceClass.core,
      colorMode: ThemePackageColorMode.system,
      platformProfile: profile,
      tokens: tokens,
      lightTheme: tokens.buildTheme(Brightness.light, platformProfile: profile),
      darkTheme: tokens.buildTheme(Brightness.dark, platformProfile: profile),
      themeMode: ThemeMode.system,
    );
  }
}
