import 'dart:ui' show lerpDouble;

import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:flutter/material.dart';

@immutable
class ThemePlatformProfile extends ThemeExtension<ThemePlatformProfile> {
  final ThemeTargetPlatform platform;
  final ThemeLayoutVariant layoutVariant;
  final double visualDensityAdjustment;
  final double minimumInteractiveDimension;
  final double focusRingWidth;
  final bool hoverEnabled;
  final bool keyboardNavigation;

  const ThemePlatformProfile({
    required this.platform,
    required this.layoutVariant,
    required this.visualDensityAdjustment,
    required this.minimumInteractiveDimension,
    required this.focusRingWidth,
    required this.hoverEnabled,
    required this.keyboardNavigation,
  });

  factory ThemePlatformProfile.defaults(ThemeTargetPlatform platform) {
    return switch (platform) {
      ThemeTargetPlatform.web => const ThemePlatformProfile(
        platform: ThemeTargetPlatform.web,
        layoutVariant: ThemeLayoutVariant.dashboard,
        visualDensityAdjustment: -0.5,
        minimumInteractiveDimension: 40,
        focusRingWidth: 2,
        hoverEnabled: true,
        keyboardNavigation: true,
      ),
      ThemeTargetPlatform.phone => const ThemePlatformProfile(
        platform: ThemeTargetPlatform.phone,
        layoutVariant: ThemeLayoutVariant.balanced,
        visualDensityAdjustment: 0,
        minimumInteractiveDimension: 48,
        focusRingWidth: 2,
        hoverEnabled: false,
        keyboardNavigation: false,
      ),
      ThemeTargetPlatform.desktop => const ThemePlatformProfile(
        platform: ThemeTargetPlatform.desktop,
        layoutVariant: ThemeLayoutVariant.compact,
        visualDensityAdjustment: -1,
        minimumInteractiveDimension: 40,
        focusRingWidth: 2,
        hoverEnabled: true,
        keyboardNavigation: true,
      ),
    };
  }

  factory ThemePlatformProfile.resolve(
    ThemeTargetPlatform platform,
    ThemePlatformOverride? override,
  ) {
    final defaults = ThemePlatformProfile.defaults(platform);
    final requestedMinimum =
        override?.minimumInteractiveDimension ??
        defaults.minimumInteractiveDimension;
    return defaults.copyWith(
      layoutVariant: override?.layoutVariant,
      visualDensityAdjustment: override?.visualDensityAdjustment,
      minimumInteractiveDimension: platform == ThemeTargetPlatform.phone
          ? requestedMinimum.clamp(48, 64).toDouble()
          : requestedMinimum,
      focusRingWidth: override?.focusRingWidth,
      hoverEnabled: override?.hoverEnabled,
      keyboardNavigation: override?.keyboardNavigation,
    );
  }

  @override
  ThemePlatformProfile copyWith({
    ThemeLayoutVariant? layoutVariant,
    double? visualDensityAdjustment,
    double? minimumInteractiveDimension,
    double? focusRingWidth,
    bool? hoverEnabled,
    bool? keyboardNavigation,
  }) {
    return ThemePlatformProfile(
      platform: platform,
      layoutVariant: layoutVariant ?? this.layoutVariant,
      visualDensityAdjustment:
          visualDensityAdjustment ?? this.visualDensityAdjustment,
      minimumInteractiveDimension:
          minimumInteractiveDimension ?? this.minimumInteractiveDimension,
      focusRingWidth: focusRingWidth ?? this.focusRingWidth,
      hoverEnabled: hoverEnabled ?? this.hoverEnabled,
      keyboardNavigation: keyboardNavigation ?? this.keyboardNavigation,
    );
  }

  @override
  ThemePlatformProfile lerp(covariant ThemePlatformProfile? other, double t) {
    if (other == null || other.platform != platform) return this;
    return ThemePlatformProfile(
      platform: platform,
      layoutVariant: t < 0.5 ? layoutVariant : other.layoutVariant,
      visualDensityAdjustment: lerpDouble(
        visualDensityAdjustment,
        other.visualDensityAdjustment,
        t,
      )!,
      minimumInteractiveDimension: lerpDouble(
        minimumInteractiveDimension,
        other.minimumInteractiveDimension,
        t,
      )!,
      focusRingWidth: lerpDouble(focusRingWidth, other.focusRingWidth, t)!,
      hoverEnabled: t < 0.5 ? hoverEnabled : other.hoverEnabled,
      keyboardNavigation: t < 0.5
          ? keyboardNavigation
          : other.keyboardNavigation,
    );
  }
}
