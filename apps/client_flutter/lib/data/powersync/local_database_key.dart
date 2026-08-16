abstract interface class LocalDatabaseKeyProvider {
  Future<String> loadOrCreateKey();
}

class FixedLocalDatabaseKeyProvider implements LocalDatabaseKeyProvider {
  final String key;

  const FixedLocalDatabaseKeyProvider(this.key);

  @override
  Future<String> loadOrCreateKey() async {
    if (key.isEmpty) {
      throw StateError('Local database encryption key must not be empty');
    }
    return key;
  }
}

class LocalDatabaseKeyUnavailable implements LocalDatabaseKeyProvider {
  const LocalDatabaseKeyUnavailable();

  @override
  Future<String> loadOrCreateKey() {
    throw StateError(
      'Encrypted local database requires an explicit LocalDatabaseKeyProvider',
    );
  }
}
