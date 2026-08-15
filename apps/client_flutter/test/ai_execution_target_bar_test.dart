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
  testWidgets('compute failure UI never silently selects Cloud AI', (
    tester,
  ) async {
    var target = AiExecutionTarget.computeNode;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: AiExecutionTargetBar(
              target: target,
              computeNodes: [_desktop()],
              selectedComputeNodeId: 'desktop-1',
              computeStatusText: 'Desktop 离线；加密任务会等待，不会自动转 Cloud AI',
              onTargetChanged: (value) => setState(() => target = value),
              onComputeNodeChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('不会自动转 Cloud AI'), findsOneWidget);
    expect(target, AiExecutionTarget.computeNode);

    await tester.tap(find.text('Cloud AI'));
    await tester.pump();
    expect(target, AiExecutionTarget.cloudAi);
  });
}
