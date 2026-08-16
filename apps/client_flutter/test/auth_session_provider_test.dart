import 'package:client_flutter/data/auth/secure_secret_store.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _MemorySecrets implements SecretStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  testWidgets('auth session provider exposes a non-listenable store facade', (
    tester,
  ) async {
    final secureStore = SecureAuthSessionStore(_MemorySecrets());
    final facade = DelegatingAuthSessionStore(secureStore);

    await tester.pumpWidget(
      Provider<AuthSessionStore>.value(
        value: facade,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              final injected = context.read<AuthSessionStore>();
              return Text(injected.runtimeType.toString());
            },
          ),
        ),
      ),
    );

    expect(find.text('DelegatingAuthSessionStore'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
