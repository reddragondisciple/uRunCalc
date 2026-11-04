import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/widgets/blinking_cursor.dart';

void main() {
  double opacity(WidgetTester tester) {
    return tester.widget<Opacity>(find.byType(Opacity)).opacity;
  }

  testWidgets('blinks twice a second while active', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BlinkingCursor()));

    expect(opacity(tester), 1);

    await tester.pump(const Duration(milliseconds: 500));
    expect(opacity(tester), 0);

    await tester.pump(const Duration(milliseconds: 500));
    expect(opacity(tester), 1);
  });

  testWidgets('stays visible when inactive', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: BlinkingCursor(active: false)),
    );

    await tester.pump(const Duration(seconds: 2));

    expect(opacity(tester), 1);
  });
}
