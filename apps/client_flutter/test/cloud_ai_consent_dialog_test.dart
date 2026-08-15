import 'package:client_flutter/features/ai_capture/widgets/cloud_ai_consent_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Cloud AI send stays disabled until model and one-time consent exist',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showCloudAiConsentDialog(
                  context,
                  inputText: '记录今晚八点买牛奶',
                  selectedAssetCount: 2,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('历史会话：不发送'), findsOneWidget);
      expect(find.textContaining('附件：2 个，不发送'), findsOneWidget);
      var confirm = tester.widget<FilledButton>(
        find.byKey(const Key('cloud_ai_consent_confirm')),
      );
      expect(confirm.onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('cloud_ai_model')),
        'demo-model',
      );
      await tester.tap(find.byKey(const Key('cloud_ai_once_consent')));
      await tester.pump();

      confirm = tester.widget<FilledButton>(
        find.byKey(const Key('cloud_ai_consent_confirm')),
      );
      expect(confirm.onPressed, isNotNull);
    },
  );
}
