import 'package:client_flutter/data/ai/ai_provider.dart';
import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/features/ai_capture/data/external_ai_action_committer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'local committer writes exact candidate through Local Core and undo',
    () async {
      final bridge = FakeLocalCoreBridge();
      final sessions = _SessionStore(_localSession());
      final committer = LocalCoreExternalAiActionCommitter(
        bridge: bridge,
        sessions: sessions,
      );
      const action = MemoCreateCandidateAction(
        memoType: 'memo',
        contentMarkdown: 'private local candidate',
        confidence: 0.93,
        rawText: 'private model text',
      );

      final committed = await committer.commit(action);
      expect(committed.entityType, 'memo');
      expect(committed.undoToken, isNotEmpty);

      final memos = await bridge.searchMemos({
        'q': 'private local candidate',
        'limit': 20,
      }, LocalCoreContext.flutterUser(userId: 'account-local'));
      expect(memos.single.contentMarkdown, 'private local candidate');

      final undone = await committer.undo(committed.undoToken);
      expect(undone.undone, 1);
    },
  );
}

class _SessionStore implements AuthSessionStore {
  _SessionStore(this.session);
  AuthSession? session;

  @override
  Future<void> clear() async => session = null;

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<String?> readAccessToken() async => session?.accessToken;

  @override
  Future<void> write(AuthSession value) async => session = value;
}

AuthSession _localSession() => AuthSession(
  account: const AccountProfile(
    accountId: 'account-local',
    phoneE164: '+8613800138000',
    displayName: null,
    accountStatus: 'active',
    plan: 'demo',
  ),
  device: const DeviceDescriptor(
    deviceId: 'device-local',
    accountId: 'account-local',
    displayName: 'Local',
    platform: 'linux',
    publicKey: 'public-key',
    trustState: DeviceTrustState.trusted,
    capabilityReport: DeviceCapabilityReport(),
    isDefaultComputeNode: false,
  ),
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: DateTime.utc(2026, 8, 16),
  refreshExpiresAt: DateTime.utc(2026, 9, 15),
);
