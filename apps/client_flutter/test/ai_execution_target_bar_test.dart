import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/features/ai_capture/widgets/ai_execution_target_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceDescriptor _desktop() => DeviceDescriptor(
  deviceId: 'desktop-1',
  accountId: 'account-1',
  displayName: 'Desktop',
  platform: 'linux',
  publicKey: 'public-key',
  trustState: DeviceTrustState.trusted,
  capabilityReport: const DeviceCapabilityReport(
    capabilities: [DeviceCapability.localAi, DeviceCapability.localMcp],
  ),
  isDefaultComputeNode: true,
  lastSeenAt: DateTime.utc(2026, 8, 15, 11, 30),
);

void main() {
  testWidgets('web target bar only shows local computer and cloud AI', (
    tester,
  ) async {
    var target = AiExecutionTarget.computeNode;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiExecutionTargetBar(
            webMode: true,
            target: target,
            computeNodes: [_desktop()],
            selectedComputeNodeId: 'desktop-1',
            computeStatusText: 'Desktop 已就绪，不会自动切换到云端 AI。',
            onTargetChanged: (value) => target = value,
            onComputeNodeChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('当前处理'), findsNothing);
    expect(find.text('我的电脑'), findsOneWidget);
    expect(find.text('云端 AI'), findsOneWidget);
    expect(find.text('Cloud AI'), findsNothing);
    expect(find.textContaining('local_ai'), findsNothing);
    expect(find.textContaining('Trusted'), findsNothing);

    await tester.tap(find.text('云端 AI'));
    await tester.pump();
    expect(target, AiExecutionTarget.cloudAi);
  });

  testWidgets('empty compute list uses Chinese product copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiExecutionTargetBar(
            webMode: true,
            target: AiExecutionTarget.computeNode,
            computeNodes: const [],
            selectedComputeNodeId: null,
            computeStatusText: '没有可用的本地计算节点。',
            onTargetChanged: (_) {},
            onComputeNodeChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('没有可用的可信本地计算节点。'), findsOneWidget);
    expect(find.textContaining('local_ai'), findsNothing);
    expect(find.textContaining('Trusted'), findsNothing);
  });
}
