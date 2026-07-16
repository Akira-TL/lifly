import 'package:client_flutter/app/theme/app_theme.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_preferences.dart';
import 'package:client_flutter/app/theme/theme_registry.dart';
import 'package:client_flutter/app/theme/theme_snapshot.dart';
import 'package:flutter/foundation.dart';

export 'package:client_flutter/app/theme/theme_snapshot.dart';

abstract interface class ThemeResolver {
  Future<ThemeSnapshot?> resolve();
}

class ThemeRuntime extends ChangeNotifier {
  final ThemeResolver? _resolver;
  final ThemeRegistry? _registry;
  final ThemePreferenceStore? _preferenceStore;
  final String? _appVersion;
  final ThemeTargetPlatform? _platform;

  late ThemeSnapshot _snapshot;
  ThemePreference _preference = ThemePreference.core;
  Object? _lastRestoreError;

  factory ThemeRuntime({
    required ThemeRegistry registry,
    required ThemePreferenceStore preferenceStore,
    required String appVersion,
    required ThemeTargetPlatform platform,
  }) {
    return ThemeRuntime._selection(
      registry,
      preferenceStore,
      appVersion,
      platform,
    );
  }

  factory ThemeRuntime.withResolver(ThemeResolver resolver) {
    return ThemeRuntime._resolver(resolver);
  }

  ThemeRuntime._selection(
    this._registry,
    this._preferenceStore,
    this._appVersion,
    this._platform,
  ) : _resolver = null {
    _snapshot = LiflyCoreTheme.snapshotFor(_platform!);
  }

  ThemeRuntime._resolver(this._resolver)
    : _registry = null,
      _preferenceStore = null,
      _appVersion = null,
      _platform = null {
    _snapshot = LiflyCoreTheme.snapshot;
  }

  ThemeSnapshot get snapshot => _snapshot;

  ThemePreference get preference => _preference;

  ThemePackageColorMode get resolvedColorMode => _snapshot.colorMode;

  List<InstalledThemeFamily> get installedThemes =>
      _registry?.installedThemes ?? const <InstalledThemeFamily>[];

  Object? get lastRestoreError => _lastRestoreError;

  Future<void> restore() async {
    if (_resolver != null) {
      await _restoreFromResolver();
      return;
    }

    try {
      final loaded = await _preferenceStore!.load() ?? ThemePreference.core;
      await _activatePreference(loaded, persist: false);
    } catch (error) {
      _preference = ThemePreference.core;
      _snapshot = LiflyCoreTheme.snapshotFor(_platform!);
      _lastRestoreError = error;
      notifyListeners();
    }
  }

  Future<void> selectFamily(String familyId) async {
    _requireSelectionMode();
    if (!_registry!.contains(familyId)) {
      throw ThemeSelectionException('Theme family is not installed: $familyId');
    }
    await _activatePreference(
      _preference.copyWith(familyId: familyId),
      persist: true,
    );
  }

  Future<void> selectColorMode(ThemePackageColorMode colorMode) async {
    _requireSelectionMode();
    await _activatePreference(
      _preference.copyWith(colorMode: colorMode),
      persist: true,
    );
  }

  Future<void> _restoreFromResolver() async {
    final resolver = _resolver!;
    try {
      final resolved = await resolver.resolve();
      _snapshot = resolved ?? LiflyCoreTheme.snapshot;
      _preference = ThemePreference(
        familyId: _snapshot.familyId,
        colorMode: _snapshot.colorMode,
      );
      _lastRestoreError = null;
    } catch (error) {
      _preference = ThemePreference.core;
      _snapshot = LiflyCoreTheme.snapshot;
      _lastRestoreError = error;
    }
    notifyListeners();
  }

  Future<void> _activatePreference(
    ThemePreference preference, {
    required bool persist,
  }) async {
    final previousPreference = _preference;
    final previousSnapshot = _snapshot;
    try {
      final resolved = await _registry!.resolve(
        preference: preference,
        appVersion: _appVersion!,
        platform: _platform!,
      );
      if (persist) {
        await _preferenceStore!.save(preference);
      }
      _preference = preference;
      _snapshot = resolved;
      _lastRestoreError = null;
      notifyListeners();
    } catch (error) {
      if (persist) {
        _preference = previousPreference;
        _snapshot = previousSnapshot;
        _lastRestoreError = error;
        rethrow;
      }
      _preference = ThemePreference(
        familyId: LiflyCoreTheme.familyId,
        colorMode: preference.colorMode,
      );
      final coreResolved = await _registry!.resolve(
        preference: _preference,
        appVersion: _appVersion!,
        platform: _platform!,
      );
      _snapshot = coreResolved;
      _lastRestoreError = error;
      notifyListeners();
    }
  }

  void _requireSelectionMode() {
    if (_registry == null || _preferenceStore == null) {
      throw const ThemeSelectionException(
        'Theme selection is unavailable for a resolver-only runtime',
      );
    }
  }
}

class ThemeSelectionException implements Exception {
  final String message;

  const ThemeSelectionException(this.message);

  @override
  String toString() => 'ThemeSelectionException: $message';
}
