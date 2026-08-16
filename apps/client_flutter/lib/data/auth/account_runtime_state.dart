import 'package:client_flutter/data/auth/auth_session.dart';

enum AccountRuntimePhase {
  signedOut('signed_out'),
  authenticatedLocked('authenticated_locked'),
  unlocking('unlocking'),
  ready('ready'),
  degraded('degraded');

  const AccountRuntimePhase(this.value);
  final String value;
}

class AccountRuntimeState {
  final AccountRuntimePhase phase;
  final AuthSession? session;
  final bool dataUnlocked;
  final String? detail;

  const AccountRuntimeState({
    required this.phase,
    required this.session,
    required this.dataUnlocked,
    this.detail,
  });

  const AccountRuntimeState.signedOut()
    : phase = AccountRuntimePhase.signedOut,
      session = null,
      dataUnlocked = false,
      detail = null;

  bool get canEnterApp =>
      session != null &&
      dataUnlocked &&
      (phase == AccountRuntimePhase.ready ||
          phase == AccountRuntimePhase.degraded);
}
