import 'package:flutter/material.dart';

@immutable
class LiflySemanticColors extends ThemeExtension<LiflySemanticColors> {
  final Color critical;
  final Color warning;
  final Color success;
  final Color info;
  final Color neutral;

  const LiflySemanticColors({
    required this.critical,
    required this.warning,
    required this.success,
    required this.info,
    required this.neutral,
  });

  factory LiflySemanticColors.fallback(ColorScheme colorScheme) {
    return LiflySemanticColors(
      critical: colorScheme.error,
      warning: colorScheme.secondary,
      success: colorScheme.tertiary,
      info: colorScheme.primary,
      neutral: colorScheme.onSurfaceVariant,
    );
  }

  @override
  LiflySemanticColors copyWith({
    Color? critical,
    Color? warning,
    Color? success,
    Color? info,
    Color? neutral,
  }) {
    return LiflySemanticColors(
      critical: critical ?? this.critical,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      info: info ?? this.info,
      neutral: neutral ?? this.neutral,
    );
  }

  @override
  LiflySemanticColors lerp(
    covariant LiflySemanticColors? other,
    double t,
  ) {
    if (other == null) return this;
    return LiflySemanticColors(
      critical: Color.lerp(critical, other.critical, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      info: Color.lerp(info, other.info, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
    );
  }
}

extension LiflySemanticTheme on ThemeData {
  LiflySemanticColors get semanticColors =>
      extension<LiflySemanticColors>() ??
      LiflySemanticColors.fallback(colorScheme);
}
