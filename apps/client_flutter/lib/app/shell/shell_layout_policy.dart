import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_platform_profile.dart';
import 'package:flutter/material.dart';

@immutable
class ShellLayoutPolicy {
  static const railBreakpoint = 900.0;

  final bool useNavigationRail;
  final bool railExtended;
  final NavigationRailLabelType railLabelType;
  final double railMinimumWidth;
  final double railMinimumExtendedWidth;
  final double mobileNavigationHeight;

  const ShellLayoutPolicy({
    required this.useNavigationRail,
    required this.railExtended,
    required this.railLabelType,
    required this.railMinimumWidth,
    required this.railMinimumExtendedWidth,
    required this.mobileNavigationHeight,
  });

  factory ShellLayoutPolicy.resolve({
    required double width,
    required ThemePlatformProfile profile,
  }) {
    final useRail = width >= railBreakpoint;
    final variant = profile.layoutVariant;
    return ShellLayoutPolicy(
      useNavigationRail: useRail,
      railExtended: useRail && variant == ThemeLayoutVariant.dashboard,
      railLabelType:
          variant == ThemeLayoutVariant.compact ||
              variant == ThemeLayoutVariant.dashboard
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      railMinimumWidth: variant == ThemeLayoutVariant.compact ? 64 : 80,
      railMinimumExtendedWidth: variant == ThemeLayoutVariant.dashboard
          ? 220
          : 200,
      mobileNavigationHeight: profile.minimumInteractiveDimension + 36,
    );
  }
}
