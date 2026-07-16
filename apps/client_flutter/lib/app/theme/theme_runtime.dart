import 'package:client_flutter/app/theme/app_theme.dart';
import 'package:client_flutter/app/theme/theme_snapshot.dart';
import 'package:flutter/foundation.dart';

export 'package:client_flutter/app/theme/theme_snapshot.dart';

abstract interface class ThemeResolver {
  Future<ThemeSnapshot?> resolve();
}

class ThemeRuntime extends ChangeNotifier {
  final ThemeResolver? _resolver;

  ThemeSnapshot _snapshot = LiflyCoreTheme.snapshot;
  Object? _lastRestoreError;

  ThemeRuntime({this._resolver});

  ThemeSnapshot get snapshot => _snapshot;

  Object? get lastRestoreError => _lastRestoreError;

  Future<void> restore() async {
    try {
      final resolved = await _resolver?.resolve();
      _snapshot = resolved ?? LiflyCoreTheme.snapshot;
      _lastRestoreError = null;
    } catch (error) {
      _snapshot = LiflyCoreTheme.snapshot;
      _lastRestoreError = error;
    }
    notifyListeners();
  }
}
