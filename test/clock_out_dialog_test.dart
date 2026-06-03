import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chs_companion/features/shifts/clock_out_dialog.dart';

Future<int?> _open(WidgetTester tester) async {
  int? result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showClockOutSignupsDialog(context);
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

ElevatedButton _clockOutButton(WidgetTester tester) =>
    tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Clock out'),
    );

void main() {
  testWidgets('Clock out button is disabled until a valid integer is entered',
      (tester) async {
    await _open(tester);
    expect(_clockOutButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    expect(_clockOutButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '5');
    await tester.pump();
    expect(_clockOutButton(tester).onPressed, isNotNull);
  });

  testWidgets('Zero is a valid entry and is returned', (tester) async {
    int? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              captured = await showClockOutSignupsDialog(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '0');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Clock out'));
    await tester.pumpAndSettle();

    expect(captured, 0);
  });

  testWidgets('Cancel returns null', (tester) async {
    int? captured = 999;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              captured = await showClockOutSignupsDialog(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(captured, isNull);
  });
}
