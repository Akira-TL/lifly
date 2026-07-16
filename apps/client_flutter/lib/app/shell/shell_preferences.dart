import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ShellPreferenceStore {
  Future<bool?> loadSidebarCollapsed();

  Future<void> saveSidebarCollapsed(bool collapsed);
}

class NoopShellPreferenceStore implements ShellPreferenceStore {
  const NoopShellPreferenceStore();

  @override
  Future<bool?> loadSidebarCollapsed() async => null;

  @override
  Future<void> saveSidebarCollapsed(bool collapsed) async {}
}

class SharedPreferencesShellPreferenceStore implements ShellPreferenceStore {
  static const _sidebarCollapsedKey = 'lifly.shell.sidebar_collapsed';

  final SharedPreferencesAsync _preferences;

  SharedPreferencesShellPreferenceStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  @override
  Future<bool?> loadSidebarCollapsed() {
    return _preferences.getBool(_sidebarCollapsedKey);
  }

  @override
  Future<void> saveSidebarCollapsed(bool collapsed) {
    return _preferences.setBool(_sidebarCollapsedKey, collapsed);
  }
}
