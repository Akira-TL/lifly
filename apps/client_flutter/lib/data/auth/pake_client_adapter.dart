import 'dart:convert';

import 'package:client_flutter/data/auth/opaque_client_helper_platform.dart';

typedef OpaqueClientHelperInvoker =
    Future<Map<String, dynamic>> Function(
      String helperPath,
      Map<String, Object?> request,
    );

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

PakeClientAdapter defaultPakeClientAdapter() {
  final helperPath = opaqueClientHelperPathFromEnvironment();
  if (helperPath == null) return const UnavailableOpaqueClientAdapter();
  return JsonHelperOpaqueClientAdapter(helperPath: helperPath);
}

class JsonHelperOpaqueClientAdapter implements PakeClientAdapter {
  final String helperPath;
  final OpaqueClientHelperInvoker _invokeHelper;
  final Map<String, String> _passwordByClientState = <String, String>{};

  JsonHelperOpaqueClientAdapter({
    required this.helperPath,
    OpaqueClientHelperInvoker? invokeHelper,
  }) : _invokeHelper = invokeHelper ?? invokeOpaqueClientHelper;

  @override
  String get protocol => 'opaque-rfc9807';

  @override
  int get protocolVersion => 1;

  @override
  Future<PakeClientStart> startRegistration({required String password}) =>
      _start('client_registration_start', password);

  @override
  Future<PakeClientFinish> finishRegistration({
    required String clientState,
    required String serverResponse,
  }) => _finish(
    'client_registration_finish',
    clientState: clientState,
    serverResponse: serverResponse,
  );

  @override
  Future<PakeClientStart> startLogin({required String password}) =>
      _start('client_login_start', password);

  @override
  Future<PakeClientFinish> finishLogin({
    required String clientState,
    required String serverResponse,
  }) => _finish(
    'client_login_finish',
    clientState: clientState,
    serverResponse: serverResponse,
  );

  Future<PakeClientStart> _start(String operation, String password) async {
    if (password.isEmpty) {
      throw const PakeClientUnavailable('OPAQUE password must not be empty');
    }
    final result = await _invoke(operation, {'password': password});
    final clientState = _requiredString(result, 'client_state');
    _passwordByClientState[clientState] = password;
    return PakeClientStart(
      clientRequest: _requiredString(result, 'client_request'),
      clientState: clientState,
    );
  }

  Future<PakeClientFinish> _finish(
    String operation, {
    required String clientState,
    required String serverResponse,
  }) async {
    final password = _passwordByClientState.remove(clientState);
    if (password == null) {
      throw const PakeClientUnavailable(
        'OPAQUE client state is missing or was already consumed',
      );
    }
    final result = await _invoke(operation, {
      'client_state': clientState,
      'server_response': serverResponse,
      'password': password,
    });
    final exportKey = _requiredString(result, 'export_key');
    try {
      return PakeClientFinish(
        clientMessage: _requiredString(result, 'client_message'),
        exportKey: base64Url.decode(_padBase64(exportKey)),
      );
    } on FormatException {
      throw const PakeClientUnavailable(
        'OPAQUE helper returned invalid export key',
      );
    }
  }

  Future<Map<String, dynamic>> _invoke(
    String operation,
    Map<String, Object?> payload,
  ) async {
    try {
      final result = await _invokeHelper(helperPath, {
        'protocol': protocol,
        'protocol_version': protocolVersion,
        'operation': operation,
        ...payload,
      });
      return result;
    } on PakeClientUnavailable {
      rethrow;
    } catch (_) {
      throw const PakeClientUnavailable(
        'OPAQUE client helper execution failed',
      );
    }
  }

  String _requiredString(Map<String, dynamic> value, String key) {
    final item = value[key];
    if (item is! String || item.isEmpty) {
      throw PakeClientUnavailable('OPAQUE helper omitted $key');
    }
    return item;
  }

  String _padBase64(String value) {
    final padding = (4 - value.length % 4) % 4;
    return '$value${List<String>.filled(padding, '=').join()}';
  }
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
