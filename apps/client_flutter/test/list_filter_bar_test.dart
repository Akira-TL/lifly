import 'package:client_flutter/shared/widgets/list_filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile filters keep at least a 48px touch target', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListFilterBar(
            options: const [
              ListFilterOption(label: '全部', value: null),
              ListFilterOption(label: '进行中', value: 'doing'),
            ],
            selectedValue: null,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final allButton = find.widgetWithText(TextButton, '全部');
    final doingButton = find.widgetWithText(TextButton, '进行中');
    expect(allButton, findsOneWidget);
    expect(doingButton, findsOneWidget);
    expect(tester.getSize(allButton).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(doingButton).height, greaterThanOrEqualTo(48));
  });

  testWidgets('desktop filters also preserve a 48px touch target', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListFilterBar(
            options: const [ListFilterOption(label: '全部', value: null)],
            selectedValue: null,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final button = find.widgetWithText(TextButton, '全部');
    expect(button, findsOneWidget);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
  });
}
