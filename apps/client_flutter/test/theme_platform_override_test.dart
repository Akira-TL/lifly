import 'package:client_flutter/app/shell/shell_layout_policy.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_package_resolver.dart';
import 'package:client_flutter/app/theme/theme_platform_profile.dart';
import 'package:client_flutter/app/theme/theme_tokens.dart';
import 'package:client_flutter/app/theme/themes/lifly_test_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ThemePackage _package() => ThemePackage.fromJson(liflyTestThemePackageJson);

void main() {
  test(
    'theme package resolves controlled profiles for every platform',
    () async {
      final package = _package();

      final web = await ThemePackageResolver(
        package: package,
        appVersion: '0.8.0',
        platform: ThemeTargetPlatform.web,
      ).resolve();
      final phone = await ThemePackageResolver(
        package: package,
        appVersion: '0.8.0',
        platform: ThemeTargetPlatform.phone,
      ).resolve();
      final desktop = await ThemePackageResolver(
        package: package,
        appVersion: '0.8.0',
        platform: ThemeTargetPlatform.desktop,
      ).resolve();

      expect(web.platformProfile.layoutVariant, ThemeLayoutVariant.dashboard);
      expect(web.platformProfile.hoverEnabled, isTrue);
      expect(web.platformProfile.keyboardNavigation, isTrue);
      expect(web.platformProfile.focusRingWidth, 2);

      expect(phone.platformProfile.layoutVariant, ThemeLayoutVariant.balanced);
      expect(phone.platformProfile.minimumInteractiveDimension, 48);
      expect(phone.platformProfile.hoverEnabled, isFalse);

      expect(desktop.platformProfile.layoutVariant, ThemeLayoutVariant.compact);
      expect(desktop.platformProfile.visualDensityAdjustment, -1);
      expect(desktop.platformProfile.keyboardNavigation, isTrue);
    },
  );

  test(
    'platform profile shapes density, focus, hover and touch behavior',
    () async {
      final package = _package();
      final phone = await ThemePackageResolver(
        package: package,
        appVersion: '0.8.0',
        platform: ThemeTargetPlatform.phone,
      ).resolve();
      final web = await ThemePackageResolver(
        package: package,
        appVersion: '0.8.0',
        platform: ThemeTargetPlatform.web,
      ).resolve();

      expect(
        phone.lightTheme.materialTapTargetSize,
        MaterialTapTargetSize.padded,
      );
      expect(
        phone.lightTheme.iconButtonTheme.style?.minimumSize?.resolve({}),
        const Size(48, 48),
      );
      expect(web.lightTheme.hoverColor.a, greaterThan(0));
      expect(web.lightTheme.focusColor.a, greaterThan(0));
      expect(
        web.lightTheme.extension<ThemePlatformProfile>(),
        web.platformProfile,
      );
    },
  );

  test('layout variants only change approved shell presentation', () {
    final compact = ShellLayoutPolicy.resolve(
      width: 1440,
      profile: ThemePlatformProfile.defaults(
        ThemeTargetPlatform.desktop,
      ).copyWith(layoutVariant: ThemeLayoutVariant.compact),
    );
    final balanced = ShellLayoutPolicy.resolve(
      width: 1440,
      profile: ThemePlatformProfile.defaults(
        ThemeTargetPlatform.web,
      ).copyWith(layoutVariant: ThemeLayoutVariant.balanced),
    );
    final dashboard = ShellLayoutPolicy.resolve(
      width: 1440,
      profile: ThemePlatformProfile.defaults(
        ThemeTargetPlatform.web,
      ).copyWith(layoutVariant: ThemeLayoutVariant.dashboard),
    );

    expect(compact.useNavigationRail, isTrue);
    expect(compact.railExtended, isFalse);
    expect(compact.railLabelType, NavigationRailLabelType.none);
    expect(balanced.railLabelType, NavigationRailLabelType.all);
    expect(dashboard.railExtended, isTrue);
    expect(dashboard.railMinimumExtendedWidth, 218);
  });

  test('reduced motion overrides a theme that enables transitions', () async {
    final snapshot = await ThemePackageResolver(
      package: _package(),
      appVersion: '0.8.0',
      platform: ThemeTargetPlatform.web,
    ).resolve();

    final reduced = themeWithReducedMotion(snapshot.lightTheme);

    expect(
      reduced.pageTransitionsTheme.builders.values,
      everyElement(isA<ReducedMotionPageTransitionsBuilder>()),
    );
    expect(snapshot.tokens.light.colors.critical, isNotNull);
    expect(snapshot.tokens.light.colors.warning, isNotNull);
  });
}
