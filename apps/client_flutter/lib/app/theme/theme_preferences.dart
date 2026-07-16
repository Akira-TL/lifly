import 'package:client_flutter/app/theme/app_theme.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class ThemePreference {
  final String familyId;
  final ThemePackageColorMode colorMode;

  const ThemePreference({required this.familyId, required this.colorMode});

  static const core = ThemePreference(
    familyId: LiflyCoreTheme.familyId,
    colorMode: ThemePackageColorMode.system,
  );

  ThemePreference copyWith({
    String? familyId,
    ThemePackageColorMode? colorMode,
  }) {
    return ThemePreference(
      familyId: familyId ?? this.familyId,
      colorMode: colorMode ?? this.colorMode,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ThemePreference &&
        other.familyId == familyId &&
        other.colorMode == colorMode;
  }

  @override
  int get hashCode => Object.hash(familyId, colorMode);
}

abstract interface class ThemePreferenceStore {
  Future<ThemePreference?> load();

  Future<void> save(ThemePreference preference);
}

class SharedPreferencesThemePreferenceStore implements ThemePreferenceStore {
  static const _familyKey = 'lifly.theme.family_id';
  static const _colorModeKey = 'lifly.theme.color_mode';

  final SharedPreferencesAsync _preferences;

  SharedPreferencesThemePreferenceStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  @override
  Future<ThemePreference?> load() async {
    final familyId = await _preferences.getString(_familyKey);
    final colorModeName = await _preferences.getString(_colorModeKey);
    if (familyId == null && colorModeName == null) return null;

    return ThemePreference(
      familyId: familyId ?? LiflyCoreTheme.familyId,
      colorMode: ThemePackageColorMode.values.firstWhere(
        (mode) => mode.name == colorModeName,
        orElse: () => ThemePackageColorMode.system,
      ),
    );
  }

  @override
  Future<void> save(ThemePreference preference) async {
    await Future.wait<void>([
      _preferences.setString(_familyKey, preference.familyId),
      _preferences.setString(_colorModeKey, preference.colorMode.name),
    ]);
  }
}
