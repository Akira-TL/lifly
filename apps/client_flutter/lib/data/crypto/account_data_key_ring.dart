import 'package:client_flutter/data/crypto/account_data_key.dart';

class AccountDataKeyRing {
  final Map<int, AccountDataKey> _keys = {};
  int _currentVersion;

  AccountDataKeyRing(AccountDataKey current)
    : _currentVersion = current.keyVersion {
    _keys[current.keyVersion] = current;
  }

  AccountDataKey get current => _keys[_currentVersion]!;

  AccountDataKey? keyForVersion(int keyVersion) => _keys[keyVersion];

  void add(AccountDataKey key, {bool makeCurrent = false}) {
    _keys[key.keyVersion] = key;
    if (makeCurrent) {
      _currentVersion = key.keyVersion;
    }
  }

  void makeCurrent(int keyVersion) {
    if (!_keys.containsKey(keyVersion)) {
      throw StateError('ADK version $keyVersion is not available');
    }
    _currentVersion = keyVersion;
  }
}
