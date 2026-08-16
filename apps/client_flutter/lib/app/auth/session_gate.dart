import 'package:client_flutter/app/auth/auth_location.dart';
import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/auth/account_runtime_state.dart';
import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:flutter/material.dart';

typedef SignedInBuilder = Widget Function(BuildContext, AuthSession);
typedef AccountRuntimeResolver = Future<AccountRuntimeState> Function();

class SessionGate extends StatelessWidget {
  final LiflyDataMode dataMode;
  final SecureAuthSessionStore sessionStore;
  final Listenable? runtimeListenable;
  final AccountRuntimeResolver resolveRuntime;
  final WidgetBuilder signedOutBuilder;
  final SignedInBuilder signedInBuilder;
  final WidgetBuilder localBuilder;

  const SessionGate({
    super.key,
    required this.dataMode,
    required this.sessionStore,
    this.runtimeListenable,
    required this.resolveRuntime,
    required this.signedOutBuilder,
    required this.signedInBuilder,
    required this.localBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (dataMode == LiflyDataMode.local) {
      return localBuilder(context);
    }
    return ListenableBuilder(
      listenable: runtimeListenable ?? sessionStore,
      builder: (context, _) => FutureBuilder<AccountRuntimeState>(
        future: resolveRuntime(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final runtime =
              snapshot.data ?? const AccountRuntimeState.signedOut();
          if (runtime.phase == AccountRuntimePhase.unlocking) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (!runtime.canEnterApp) {
            syncAuthBrowserLocation(signedIn: false);
            _resetNavigationToAuthRoot(context);
            return signedOutBuilder(context);
          }
          final session = runtime.session!;
          syncAuthBrowserLocation(signedIn: true);
          return signedInBuilder(context, session);
        },
      ),
    );
  }
}

void _resetNavigationToAuthRoot(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    final navigator = Navigator.maybeOf(context);
    if (navigator == null || !navigator.canPop()) return;
    navigator.popUntil((route) => route.isFirst);
  });
}
