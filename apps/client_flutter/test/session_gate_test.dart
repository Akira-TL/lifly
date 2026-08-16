import 'package:client_flutter/app/auth/session_gate.dart';
import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/auth/account_runtime_state.dart';
import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/auth/secure_secret_store.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySecrets implements SecretStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

AuthSession _session() => AuthSession(
  account: const AccountProfile(
    accountId: 'account-1',
    phoneE164: '+8613800138000',
    displayName: 'Akira',
    accountStatus: 'active',
    plan: 'demo',
  ),
  device: const DeviceDescriptor(
    deviceId: 'web-1',
    accountId: 'account-1',
    displayName: 'Lifly web',
    platform: 'web',
    publicKey: 'public-key',
    trustState: DeviceTrustState.trusted,
    capabilityReport: DeviceCapabilityReport(),
    isDefaultComputeNode: false,
  ),
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: DateTime.utc(2026, 8, 16, 14),
  refreshExpiresAt: DateTime.utc(2026, 9, 16, 14),
);

Future<AccountRuntimeState> _runtimeFromSessions(
  SecureAuthSessionStore sessions,
) async {
  final session = await sessions.read();
  if (session == null) return const AccountRuntimeState.signedOut();
  return AccountRuntimeState(
    phase: AccountRuntimePhase.ready,
    session: session,
    dataUnlocked: true,
  );
}

Widget _app(SecureAuthSessionStore sessions, LiflyDataMode mode) => MaterialApp(
  home: SessionGate(
    dataMode: mode,
    sessionStore: sessions,
    resolveRuntime: () => _runtimeFromSessions(sessions),
    signedOutBuilder: (_) => const Text('SIGNED_OUT'),
    signedInBuilder: (_, session) =>
        Text('SIGNED_IN:${session.account.phoneE164}'),
    localBuilder: (_) => const Text('LOCAL_SHELL'),
  ),
);

void main() {
  testWidgets('api mode gates shell until Account runtime is ready', (
    tester,
  ) async {
    final sessions = SecureAuthSessionStore(_MemorySecrets());
    await tester.pumpWidget(_app(sessions, LiflyDataMode.api));
    await tester.pumpAndSettle();
    expect(find.text('SIGNED_OUT'), findsOneWidget);

    await sessions.write(_session());
    await tester.pumpAndSettle();
    expect(find.text('SIGNED_IN:+8613800138000'), findsOneWidget);

    await sessions.clear();
    await tester.pumpAndSettle();
    expect(find.text('SIGNED_OUT'), findsOneWidget);
  });

  testWidgets('authenticated but locked runtime never builds business shell', (
    tester,
  ) async {
    final sessions = SecureAuthSessionStore(_MemorySecrets());
    await sessions.write(_session());
    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(
          dataMode: LiflyDataMode.api,
          sessionStore: sessions,
          resolveRuntime: () async => AccountRuntimeState(
            phase: AccountRuntimePhase.authenticatedLocked,
            session: _session(),
            dataUnlocked: false,
          ),
          signedOutBuilder: (_) => const Text('LOCKED_AUTH_ROOT'),
          signedInBuilder: (_, _) => const Text('SIGNED_IN'),
          localBuilder: (_) => const Text('LOCAL_SHELL'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('LOCKED_AUTH_ROOT'), findsOneWidget);
    expect(find.text('SIGNED_IN'), findsNothing);
  });

  testWidgets('degraded but unlocked runtime remains locally usable', (
    tester,
  ) async {
    final sessions = SecureAuthSessionStore(_MemorySecrets());
    await sessions.write(_session());
    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(
          dataMode: LiflyDataMode.api,
          sessionStore: sessions,
          resolveRuntime: () async => AccountRuntimeState(
            phase: AccountRuntimePhase.degraded,
            session: _session(),
            dataUnlocked: true,
            detail: 'PowerSync offline',
          ),
          signedOutBuilder: (_) => const Text('SIGNED_OUT'),
          signedInBuilder: (_, _) => const Text('LOCAL_DATA_READY'),
          localBuilder: (_) => const Text('LOCAL_SHELL'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('LOCAL_DATA_READY'), findsOneWidget);
  });

  testWidgets(
    'signing out clears pushed business routes and reveals auth root',
    (tester) async {
      final sessions = SecureAuthSessionStore(_MemorySecrets());
      await sessions.write(_session());
      await tester.pumpWidget(_app(sessions, LiflyDataMode.api));
      await tester.pumpAndSettle();
      final context = tester.element(find.textContaining('SIGNED_IN:'));
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('PUSHED_SETTINGS')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PUSHED_SETTINGS'), findsOneWidget);

      await sessions.clear();
      await tester.pumpAndSettle();
      expect(find.text('PUSHED_SETTINGS'), findsNothing);
      expect(find.text('SIGNED_OUT'), findsOneWidget);
    },
  );

  testWidgets('local mode remains usable without an account session', (
    tester,
  ) async {
    final sessions = SecureAuthSessionStore(_MemorySecrets());
    await tester.pumpWidget(_app(sessions, LiflyDataMode.local));
    await tester.pumpAndSettle();
    expect(find.text('LOCAL_SHELL'), findsOneWidget);
  });
}
