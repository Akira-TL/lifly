import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_platform_profile.dart';
import 'package:flutter/material.dart';

class ThemeTokenSet {
  final ThemeModeTokens light;
  final ThemeModeTokens dark;

  const ThemeTokenSet({required this.light, required this.dark});

  factory ThemeTokenSet.fromJson(Map<String, dynamic> json) {
    return ThemeTokenSet(
      light: ThemeModeTokens.fromJson(_requiredMap(json, 'light')),
      dark: ThemeModeTokens.fromJson(_requiredMap(json, 'dark')),
    );
  }

  ThemeData buildTheme(
    Brightness brightness, {
    required ThemePlatformProfile platformProfile,
  }) {
    final tokens = brightness == Brightness.light ? light : dark;
    final density =
        (tokens.density.visual + platformProfile.visualDensityAdjustment)
            .clamp(-4, 4)
            .toDouble();
    final focusColor = tokens.colors.primary.withValues(alpha: 0.24);
    final hoverColor = platformProfile.hoverEnabled
        ? tokens.colors.primary.withValues(alpha: 0.08)
        : Colors.transparent;
    final minimumSize = Size.square(
      platformProfile.minimumInteractiveDimension,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: tokens.colors.primary,
            brightness: brightness,
          ).copyWith(
            primary: tokens.colors.primary,
            onPrimary: tokens.colors.onPrimary,
            secondary: tokens.colors.secondary,
            surface: tokens.colors.surface,
            onSurface: tokens.colors.onSurface,
            error: tokens.colors.critical,
          ),
      visualDensity: VisualDensity(horizontal: density, vertical: density),
      materialTapTargetSize:
          platformProfile.platform == ThemeTargetPlatform.phone
          ? MaterialTapTargetSize.padded
          : MaterialTapTargetSize.shrinkWrap,
      focusColor: focusColor,
      hoverColor: hoverColor,
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(minimumSize: WidgetStatePropertyAll(minimumSize)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(minimumSize: WidgetStatePropertyAll(minimumSize)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(minimumSize: WidgetStatePropertyAll(minimumSize)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(minimumSize: WidgetStatePropertyAll(minimumSize)),
      ),
      cardTheme: CardThemeData(
        elevation: tokens.elevation.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius.card),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radius.control),
        ),
      ),
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
    );

    return base.copyWith(
      extensions: [platformProfile],
      textTheme: _scaledTextTheme(base.textTheme, tokens.typography),
      pageTransitionsTheme: tokens.motion.enabled
          ? base.pageTransitionsTheme
          : const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: ReducedMotionPageTransitionsBuilder(),
                TargetPlatform.fuchsia: ReducedMotionPageTransitionsBuilder(),
                TargetPlatform.iOS: ReducedMotionPageTransitionsBuilder(),
                TargetPlatform.linux: ReducedMotionPageTransitionsBuilder(),
                TargetPlatform.macOS: ReducedMotionPageTransitionsBuilder(),
                TargetPlatform.windows: ReducedMotionPageTransitionsBuilder(),
              },
            ),
    );
  }
}

class ThemeModeTokens {
  final ThemeSemanticColors colors;
  final ThemeTypographyTokens typography;
  final ThemeSpacingTokens spacing;
  final ThemeRadiusTokens radius;
  final ThemeElevationTokens elevation;
  final ThemeDensityTokens density;
  final ThemeMotionTokens motion;

  const ThemeModeTokens({
    required this.colors,
    required this.typography,
    required this.spacing,
    required this.radius,
    required this.elevation,
    required this.density,
    required this.motion,
  });

  factory ThemeModeTokens.fromJson(Map<String, dynamic> json) {
    return ThemeModeTokens(
      colors: ThemeSemanticColors.fromJson(_requiredMap(json, 'colors')),
      typography: ThemeTypographyTokens.fromJson(
        _requiredMap(json, 'typography'),
      ),
      spacing: ThemeSpacingTokens.fromJson(_requiredMap(json, 'spacing')),
      radius: ThemeRadiusTokens.fromJson(_requiredMap(json, 'radius')),
      elevation: ThemeElevationTokens.fromJson(_requiredMap(json, 'elevation')),
      density: ThemeDensityTokens.fromJson(_requiredMap(json, 'density')),
      motion: ThemeMotionTokens.fromJson(_requiredMap(json, 'motion')),
    );
  }
}

class ThemeSemanticColors {
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color surface;
  final Color onSurface;
  final Color critical;
  final Color warning;
  final Color success;
  final Color info;
  final Color neutral;

  const ThemeSemanticColors({
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.surface,
    required this.onSurface,
    required this.critical,
    required this.warning,
    required this.success,
    required this.info,
    required this.neutral,
  });

  factory ThemeSemanticColors.fromJson(Map<String, dynamic> json) {
    return ThemeSemanticColors(
      primary: _parseColor(json, 'primary'),
      onPrimary: _parseColor(json, 'on_primary'),
      secondary: _parseColor(json, 'secondary'),
      surface: _parseColor(json, 'surface'),
      onSurface: _parseColor(json, 'on_surface'),
      critical: _parseColor(json, 'critical'),
      warning: _parseColor(json, 'warning'),
      success: _parseColor(json, 'success'),
      info: _parseColor(json, 'info'),
      neutral: _parseColor(json, 'neutral'),
    );
  }
}

class ThemeTypographyTokens {
  final String? fontFamily;
  final double titleScale;
  final double bodyScale;
  final double labelScale;

  const ThemeTypographyTokens({
    required this.fontFamily,
    required this.titleScale,
    required this.bodyScale,
    required this.labelScale,
  });

  factory ThemeTypographyTokens.fromJson(Map<String, dynamic> json) {
    final fontFamily = json['font_family'];
    if (fontFamily != null && fontFamily is! String) {
      throw const ThemeTokenFormatException('font_family must be a string');
    }
    return ThemeTypographyTokens(
      fontFamily: fontFamily as String?,
      titleScale: _rangedDouble(json, 'title_scale', 0.8, 1.5),
      bodyScale: _rangedDouble(json, 'body_scale', 0.8, 1.5),
      labelScale: _rangedDouble(json, 'label_scale', 0.8, 1.5),
    );
  }
}

class ThemeSpacingTokens {
  final double page;
  final double card;
  final double inline;

  const ThemeSpacingTokens({
    required this.page,
    required this.card,
    required this.inline,
  });

  factory ThemeSpacingTokens.fromJson(Map<String, dynamic> json) {
    return ThemeSpacingTokens(
      page: _rangedDouble(json, 'page', 0, 64),
      card: _rangedDouble(json, 'card', 0, 48),
      inline: _rangedDouble(json, 'inline', 0, 32),
    );
  }
}

class ThemeRadiusTokens {
  final double card;
  final double control;

  const ThemeRadiusTokens({required this.card, required this.control});

  factory ThemeRadiusTokens.fromJson(Map<String, dynamic> json) {
    return ThemeRadiusTokens(
      card: _rangedDouble(json, 'card', 0, 40),
      control: _rangedDouble(json, 'control', 0, 32),
    );
  }
}

class ThemeElevationTokens {
  final double card;

  const ThemeElevationTokens({required this.card});

  factory ThemeElevationTokens.fromJson(Map<String, dynamic> json) {
    return ThemeElevationTokens(card: _rangedDouble(json, 'card', 0, 24));
  }
}

class ThemeDensityTokens {
  final double visual;

  const ThemeDensityTokens({required this.visual});

  factory ThemeDensityTokens.fromJson(Map<String, dynamic> json) {
    return ThemeDensityTokens(visual: _rangedDouble(json, 'visual', -4, 4));
  }
}

class ThemeMotionTokens {
  final bool enabled;
  final Duration fast;
  final Duration normal;

  const ThemeMotionTokens({
    required this.enabled,
    required this.fast,
    required this.normal,
  });

  factory ThemeMotionTokens.fromJson(Map<String, dynamic> json) {
    final enabled = json['enabled'];
    if (enabled is! bool) {
      throw const ThemeTokenFormatException('motion.enabled must be a bool');
    }
    return ThemeMotionTokens(
      enabled: enabled,
      fast: Duration(milliseconds: _rangedInt(json, 'fast_ms', 0, 1000)),
      normal: Duration(milliseconds: _rangedInt(json, 'normal_ms', 0, 2000)),
    );
  }
}

class ThemeTokenFormatException implements Exception {
  final String message;

  const ThemeTokenFormatException(this.message);

  @override
  String toString() => 'ThemeTokenFormatException: $message';
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map) {
    throw ThemeTokenFormatException('$key must be an object');
  }
  return value.cast<String, dynamic>();
}

Color _parseColor(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw is! String || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(raw)) {
    throw ThemeTokenFormatException('$key must be a #RRGGBB color');
  }
  return Color(0xFF000000 | int.parse(raw.substring(1), radix: 16));
}

double _rangedDouble(
  Map<String, dynamic> json,
  String key,
  double minimum,
  double maximum,
) {
  final raw = json[key];
  if (raw is! num) {
    throw ThemeTokenFormatException('$key must be a number');
  }
  final value = raw.toDouble();
  if (value < minimum || value > maximum) {
    throw ThemeTokenFormatException(
      '$key must be between $minimum and $maximum',
    );
  }
  return value;
}

int _rangedInt(
  Map<String, dynamic> json,
  String key,
  int minimum,
  int maximum,
) {
  final raw = json[key];
  if (raw is! int || raw < minimum || raw > maximum) {
    throw ThemeTokenFormatException(
      '$key must be an integer between $minimum and $maximum',
    );
  }
  return raw;
}

TextTheme _scaledTextTheme(TextTheme source, ThemeTypographyTokens typography) {
  TextStyle? scale(TextStyle? style, double factor) {
    if (style == null) return null;
    return style.copyWith(
      fontFamily: typography.fontFamily,
      fontSize: style.fontSize == null ? null : style.fontSize! * factor,
    );
  }

  return source.copyWith(
    displayLarge: scale(source.displayLarge, typography.titleScale),
    displayMedium: scale(source.displayMedium, typography.titleScale),
    displaySmall: scale(source.displaySmall, typography.titleScale),
    headlineLarge: scale(source.headlineLarge, typography.titleScale),
    headlineMedium: scale(source.headlineMedium, typography.titleScale),
    headlineSmall: scale(source.headlineSmall, typography.titleScale),
    titleLarge: scale(source.titleLarge, typography.titleScale),
    titleMedium: scale(source.titleMedium, typography.titleScale),
    titleSmall: scale(source.titleSmall, typography.titleScale),
    bodyLarge: scale(source.bodyLarge, typography.bodyScale),
    bodyMedium: scale(source.bodyMedium, typography.bodyScale),
    bodySmall: scale(source.bodySmall, typography.bodyScale),
    labelLarge: scale(source.labelLarge, typography.labelScale),
    labelMedium: scale(source.labelMedium, typography.labelScale),
    labelSmall: scale(source.labelSmall, typography.labelScale),
  );
}

ThemeData themeWithReducedMotion(ThemeData theme) {
  return theme.copyWith(
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ReducedMotionPageTransitionsBuilder(),
        TargetPlatform.fuchsia: ReducedMotionPageTransitionsBuilder(),
        TargetPlatform.iOS: ReducedMotionPageTransitionsBuilder(),
        TargetPlatform.linux: ReducedMotionPageTransitionsBuilder(),
        TargetPlatform.macOS: ReducedMotionPageTransitionsBuilder(),
        TargetPlatform.windows: ReducedMotionPageTransitionsBuilder(),
      },
    ),
  );
}

class ReducedMotionPageTransitionsBuilder extends PageTransitionsBuilder {
  const ReducedMotionPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
