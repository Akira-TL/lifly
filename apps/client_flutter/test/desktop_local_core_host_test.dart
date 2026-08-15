import 'package:client_flutter/data/local_core/desktop_local_core_host.dart';
import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop host exposes the frozen Agent4 health and memo seam', () async {
    final host = DesktopLocalCoreHost(
      FakeLocalCoreBridge(),
      userId: 'account-demo',
    );

    final health = await host.handle({
      'id': 1,
      'method': 'health',
      'input': null,
    });
    expect(health['id'], 1);
    expect(health['ok'], true);
    expect((health['result'] as Map)['status'], 'ok');

    final created = await host.handle({
      'id': 2,
      'method': 'memo_create',
      'input': {
        'type': 'memo',
        'title': 'Bridge memo',
        'content_markdown': 'from desktop stdio',
        'tags': ['bridge'],
      },
      'context': {
        'actorType': 'ai',
        'sourceChannel': 'local_mcp',
        'toolName': 'memo_create',
        'requestId': 'req-1',
      },
    });
    expect(created['ok'], true);
    final memo = created['result'] as Map;
    expect(memo['title'], 'Bridge memo');
    expect(memo['content_markdown'], 'from desktop stdio');
    expect(memo['revision'], 1);
  });

  test(
    'desktop host returns a structured error for unsupported methods',
    () async {
      final host = DesktopLocalCoreHost(FakeLocalCoreBridge());
      final response = await host.handle({
        'id': 7,
        'method': 'not_a_method',
        'input': const <String, Object?>{},
      });
      expect(response['id'], 7);
      expect(response['ok'], false);
      expect((response['error'] as Map)['code'], 'LOCAL_CORE_HOST_ERROR');
    },
  );
}
