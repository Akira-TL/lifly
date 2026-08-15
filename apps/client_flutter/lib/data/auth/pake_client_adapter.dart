class PakeClientUnavailable implements Exception {
  final String message;

  const PakeClientUnavailable([
    this.message =
        'OPAQUE client bridge is unavailable; plaintext-password fallback is disabled',
  ]);

  @override
  String toString() => 'PakeClientUnavailable: $message';
}

class PakeClientStart {
  final String clientRequest;
  final String clientState;

  const PakeClientStart({
    required this.clientRequest,
    required this.clientState,
  });
}

class PakeClientFinish {
  final String clientMessage;
  final List<int> exportKey;

  const PakeClientFinish({
    required this.clientMessage,
    required this.exportKey,
  });
}

abstract interface class PakeClientAdapter {
  String get protocol;

  int get protocolVersion;

  Future<PakeClientStart> startRegistration({required String password});

  Future<PakeClientFinish> finishRegistration({
    required String clientState,
    required String serverResponse,
  });

  Future<PakeClientStart> startLogin({required String password});

  Future<PakeClientFinish> finishLogin({
    required String clientState,
    required String serverResponse,
  });
}

class UnavailableOpaqueClientAdapter implements PakeClientAdapter {
  const UnavailableOpaqueClientAdapter();

  @override
  String get protocol => 'opaque-rfc9807';

  @override
  int get protocolVersion => 1;

  @override
  Future<PakeClientFinish> finishLogin({
    required String clientState,
    required String serverResponse,
  }) async => throw const PakeClientUnavailable();

  @override
  Future<PakeClientFinish> finishRegistration({
    required String clientState,
    required String serverResponse,
  }) async => throw const PakeClientUnavailable();

  @override
  Future<PakeClientStart> startLogin({required String password}) async =>
      throw const PakeClientUnavailable();

  @override
  Future<PakeClientStart> startRegistration({required String password}) async =>
      throw const PakeClientUnavailable();
}
