import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ShellPreferenceStore {
  Future<bool?> loadSidebarCollapsed();

  Future<void> saveSidebarCollapsed(bool collapsed);

  Future<int?> loadDestinationIndex();

  Future<void> saveDestinationIndex(int index);
}

class NoopShellPreferenceStore implements ShellPreferenceStore {
  const NoopShellPreferenceStore();

  @override
  Future<bool?> loadSidebarCollapsed() async => null;

  @override
  Future<void> saveSidebarCollapsed(bool collapsed) async {}

  @override
  Future<int?> loadDestinationIndex() async => null;

  @override
  Future<void> saveDestinationIndex(int index) async {}
}

class SharedPreferencesShellPreferenceStore implements ShellPreferenceStore {
  static const _sidebarCollapsedKey = 'lifly.shell.sidebar_collapsed';
  static const _destinationIndexKey = 'lifly.shell.destination_index';

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

  @override
  Future<int?> loadDestinationIndex() {
    return _preferences.getInt(_destinationIndexKey);
  }

  @override
  Future<void> saveDestinationIndex(int index) {
    return _preferences.setInt(_destinationIndexKey, index);
  }
}
