import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/calculator/calculator_display.dart';
import 'package:ultra_run_calc/features/calculator/calculator_keypad.dart';
import 'package:ultra_run_calc/features/calculator/calculator_mode.dart';
import 'package:ultra_run_calc/features/calculator/calculator_mode_bar.dart';
import 'package:ultra_run_calc/features/pace/pace_cells.dart';
import 'package:ultra_run_calc/features/pace/pace_keyboard.dart';

void main() {
  testWidgets('calculator keypad reports pressed keys', (tester) async {
    final pressed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalculatorKeypad(
            keys: const ['1', '2', '=', ''],
            columns: 2,
            onPressed: pressed.add,
            onClearHistory: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('key_1')));
    await tester.tap(find.byKey(const ValueKey('key_=')));

    expect(pressed, ['1', '=']);
  });

  testWidgets('calculator display selects the original history entry', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalculatorDisplay(
            history: const ['1+2 = 3', '4+5 = 9'],
            onHistorySelected: (index) => selected = index,
            currentValue: const Text('42'),
          ),
        ),
      ),
    );

    expect(find.text('42'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('history-0')));

    expect(selected, 1);
  });

  testWidgets('mode bar shows current mode and reports a new one', (
    tester,
  ) async {
    CalculatorMode? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalculatorModeBar(
            current: CalculatorMode.ultra,
            onSelected: (mode) => selected = mode,
          ),
        ),
      ),
    );

    expect(find.text('Ultra'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mode-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pace'));
    await tester.pumpAndSettle();

    expect(selected, CalculatorMode.pace);
  });

  testWidgets('pace keyboard reports key and clear actions', (tester) async {
    final keys = <String>[];
    var cleared = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: PaceKeyboard(
              compact: false,
              tableLayout: false,
              isUltra: false,
              onKey: keys.add,
              onClear: () => cleared++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('pace-key-1')));
    await tester.longPress(find.byKey(const ValueKey('pace-key-⌫')));

    expect(keys, ['1']);
    expect(cleared, 1);
  });

  testWidgets('pace keyboard confirms with OK and swaps reset with ±', (
    tester,
  ) async {
    final keys = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: PaceKeyboard(
              compact: false,
              tableLayout: false,
              isUltra: false,
              onKey: keys.add,
              onClear: () {},
            ),
          ),
        ),
      ),
    );

    final zero = find.byKey(const ValueKey('pace-key-0'));
    final sign = find.byKey(const ValueKey('pace-key-±'));
    final reset = find.byKey(const ValueKey('pace-key-Сброс'));
    final ok = find.byKey(const ValueKey('pace-key-ОК'));
    expect(zero, findsOneWidget);
    expect(sign, findsOneWidget);
    expect(reset, findsOneWidget);
    expect(ok, findsOneWidget);
    expect(find.byKey(const ValueKey('pace-key-00')), findsNothing);

    // ± стоит в ряду 7–8–9, «Сброс» — в нижнем ряду рядом с ОК.
    expect(
      tester.getCenter(sign).dy,
      tester.getCenter(find.byKey(const ValueKey('pace-key-9'))).dy,
    );
    expect(tester.getCenter(reset).dy, tester.getCenter(zero).dy);
    expect(tester.getCenter(zero).dx, lessThan(tester.getCenter(reset).dx));
    expect(tester.getCenter(reset).dx, lessThan(tester.getCenter(ok).dx));

    await tester.tap(sign);
    await tester.tap(reset);
    expect(keys, ['±', 'Сброс']);
  });

  testWidgets('ultra keyboard keeps OK instead of ±', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: PaceKeyboard(
              compact: false,
              tableLayout: false,
              isUltra: true,
              onKey: (_) {},
              onClear: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('pace-key-±')), findsNothing);
    expect(find.byKey(const ValueKey('pace-key-ОК')), findsOneWidget);
  });

  testWidgets('interactive cell shows text and handles taps', (tester) async {
    var taps = 0;
    final anchor = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 100,
              height: 40,
              child: PaceInteractiveCell(
                cellKey: 'cell',
                text: '7',
                focusAnchorKey: anchor,
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('7'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cell')));

    expect(taps, 1);
  });

  test('water spans color known drinks', () {
    final spans = waterSpans('вода пиво');

    expect(spans, hasLength(3));
    expect((spans[0] as TextSpan).style?.color, const Color(0xFF64B5F6));
    expect((spans[2] as TextSpan).style?.color, const Color(0xFFFFEB3B));
  });
}
