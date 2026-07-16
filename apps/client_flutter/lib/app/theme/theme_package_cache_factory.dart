import 'package:client_flutter/app/theme/theme_package_cache.dart';
import 'package:client_flutter/app/theme/theme_package_cache_shared_preferences.dart'
    if (dart.library.io) 'package:client_flutter/app/theme/theme_package_cache_io.dart'
    as implementation;

Future<ThemePackageCache> openDefaultThemePackageCache() {
  return implementation.createDefaultThemePackageCache();
}
