import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/auth/secure_secret_store.dart';

abstract interface class AuthSessionStore {
  Future<AuthSession?> read();

  Future<String?> readAccessToken();

  Future<void> write(AuthSession session);

  Future<void> clear();
}

class SecureAuthSessionStore extends ChangeNotifier
    implements AuthSessionStore {
  static const _sessionKey = 'lifly.auth.session.v1';

  final SecretStore _secrets;

  SecureAuthSessionStore(this._secrets);

  @override
  Future<AuthSession?> read() async {
    final encoded = await _secrets.read(_sessionKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw const FormatException('Expected session object');
      }
      return AuthSession.fromJson(decoded.cast<String, dynamic>());
    } on Object {
      await clear();
      return null;
    }
  }

  @override
  Future<String?> readAccessToken() async => (await read())?.accessToken;

  @override
  Future<void> write(AuthSession session) async {
    await _secrets.write(_sessionKey, jsonEncode(session.toJson()));
    notifyListeners();
  }

  @override
  Future<void> clear() async {
    await _secrets.delete(_sessionKey);
    notifyListeners();
  }
}
