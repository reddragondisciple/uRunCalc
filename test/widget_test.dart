import 'dart:convert';

import 'package:ultra_run_calc/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpCalculator(
  WidgetTester tester, {
  bool seedUltraDefaults = false,
}) async {
  SharedPreferences.setMockInitialValues(
    seedUltraDefaults
        ? {}
        : {
            'ultra_state_v1': jsonEncode({
              'tables': {
                'GRUT': {
                  'T100': {'columns': 8, 'fitTable': true, 'seeded': true},
                },
              },
            }),
          },
  );
  await tester.pumpWidget(const CalculatorApp());
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey('key_$key')));
  await tester.pump();
}

Future<void> switchMode(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('mode-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> tapPaceKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey('pace-key-$key')));
  await tester.pump();
}

Future<void> tapTimeKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey('time-key-$key')));
  await tester.pump();
}

Future<void> enterTimeDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tapTimeKey(tester, digit);
  }
}

Future<void> tapField(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> enterPaceTime(
  WidgetTester tester,
  String key,
  String digits,
) async {
  await tapField(tester, find.byKey(ValueKey(key)));
  // Время вводится только цифрами: двоеточие подставляется автоматически.
  for (final char in digits.replaceAll(':', '').split('')) {
    await tapPaceKey(tester, char);
  }
}

Future<void> enterPaceValue(
  WidgetTester tester,
  String key,
  String digits,
) async {
  await tapField(tester, find.byKey(ValueKey(key)));
  for (final char in digits.split('')) {
    await tapPaceKey(tester, char);
  }
}

Color? paceCellColor(WidgetTester tester, String key, String text) {
  final widget = tester.widget<Text>(
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(text)),
  );
  return widget.style?.color;
}

int? paceCellBorderColor(WidgetTester tester, String key) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Container),
        )
        .first,
  );
  final decoration = container.decoration;
  if (decoration is! BoxDecoration) return null;
  return decoration.border?.top.color.toARGB32();
}

double? paceCellBorderWidth(WidgetTester tester, String key) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Container),
        )
        .first,
  );
  final decoration = container.decoration;
  if (decoration is! BoxDecoration) return null;
  return decoration.border?.top.width;
}

Future<void> switchEventDistance(
  WidgetTester tester,
  String event,
  String distance,
) async {
  await tester.tap(find.byKey(const ValueKey('pace-event-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(event));
  await tester.pumpAndSettle();
  await tester.tap(find.text(distance));
  await tester.pumpAndSettle();
}

void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder inCurrentDisplay(String text) {
  return find.descendant(
    of: find.byKey(const ValueKey('current-display')),
    matching: find.text(text),
  );
}

Finder inPreview(String text) {
  return find.descendant(
    of: find.byKey(const ValueKey('preview')),
    matching: find.textContaining(text),
  );
}

void main() {
  testWidgets('adds numbers', (tester) async {
    await pumpCalculator(tester);

    await tapKey(tester, '1');
    await tapKey(tester, '+');
    await tapKey(tester, '2');
    await tapKey(tester, '=');

    expect(inCurrentDisplay('3'), findsOneWidget);
  });

  testWidgets('shows a fraction and its decimal value for 1/3', (tester) async {
    await pumpCalculator(tester);

    await tapKey(tester, '1');
    await tapKey(tester, '÷');
    await tapKey(tester, '3');
    await tapKey(tester, '=');

    expect(inCurrentDisplay('1'), findsOneWidget);
    expect(inCurrentDisplay('3'), findsOneWidget);
    expect(inPreview('0.333'), findsOneWidget);
  });

  testWidgets('shows an exact decimal for 1/2', (tester) async {
    await pumpCalculator(tester);

    await tapKey(tester, '1');
    await tapKey(tester, '÷');
    await tapKey(tester, '2');
    await tapKey(tester, '=');

    expect(inCurrentDisplay('1'), findsOneWidget);
    expect(inCurrentDisplay('2'), findsOneWidget);
    expect(inPreview('= 0.5'), findsOneWidget);
  });

  testWidgets('allows only one unary minus after an operator', (tester) async {
    await pumpCalculator(tester);

    await tapKey(tester, '1');
    await tapKey(tester, '+');
    await tapKey(tester, '-');
    await tapKey(tester, '-');
    await tapKey(tester, '2');
    await tapKey(tester, '=');

    expect(inCurrentDisplay('−1'), findsOneWidget);
  });

  testWidgets('percent in addition uses the left operand as the base', (
    tester,
  ) async {
    await pumpCalculator(tester);

    await tapKey(tester, '2');
    await tapKey(tester, '0');
    await tapKey(tester, '0');
    await tapKey(tester, '+');
    await tapKey(tester, '1');
    await tapKey(tester, '0');
    await tapKey(tester, '%');
    await tapKey(tester, '=');

    expect(inCurrentDisplay('220'), findsOneWidget);
  });

  testWidgets('keypad keeps brackets together and delete at top right', (
    tester,
  ) async {
    await pumpCalculator(tester);

    final open = tester.getCenter(find.byKey(const ValueKey('key_(')));
    final close = tester.getCenter(find.byKey(const ValueKey('key_)')));
    final delete = tester.getCenter(find.byKey(const ValueKey('key_⌫')));
    final percent = tester.getCenter(find.byKey(const ValueKey('key_%')));
    final tripleZero = tester.getCenter(find.byKey(const ValueKey('key_000')));

    expect(open.dy, close.dy);
    expect(close.dy, delete.dy);
    expect(open.dx, lessThan(close.dx));
    expect(close.dx, lessThan(delete.dx));
    expect(percent.dy, lessThan(tripleZero.dy));
  });

  testWidgets('wraps a fraction in parentheses before a power', (tester) async {
    await pumpCalculator(tester);

    await tapKey(tester, '2');
    await tapKey(tester, '÷');
    await tapKey(tester, '3');
    await tapKey(tester, '^');

    expect(inCurrentDisplay('('), findsOneWidget);
    expect(inCurrentDisplay(')'), findsOneWidget);
    expect(inCurrentDisplay('2'), findsOneWidget);
    expect(inCurrentDisplay('3'), findsOneWidget);

    await tapKey(tester, '2');
    await tapKey(tester, '=');

    expect(inPreview('0.444'), findsOneWidget);
  });

  testWidgets('shows a specific division by zero error', (tester) async {
    await pumpCalculator(tester);

    await tapKey(tester, '1');
    await tapKey(tester, '÷');
    await tapKey(tester, '0');
    await tapKey(tester, '=');

    expect(find.text('Деление на ноль'), findsOneWidget);
  });

  testWidgets('backspace removes the last character', (tester) async {
    await pumpCalculator(tester);

    await tapKey(tester, '1');
    await tapKey(tester, '2');
    await tapKey(tester, '⌫');

    expect(inCurrentDisplay('1'), findsOneWidget);
    expect(inCurrentDisplay('2'), findsNothing);
  });

  testWidgets('square root works', (tester) async {
    await pumpCalculator(tester);

    await tapKey(tester, '√');
    await tapKey(tester, '9');
    await tapKey(tester, ')');
    await tapKey(tester, '=');

    expect(inCurrentDisplay('3'), findsOneWidget);
  });

  testWidgets('supports hardware keyboard', (tester) async {
    await pumpCalculator(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(inCurrentDisplay('12'), findsOneWidget);
  });

  testWidgets('portrait layout and nested fractions fit', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpCalculator(tester);

    await tapKey(tester, '1');
    await tapKey(tester, '÷');
    await tapKey(tester, '2');
    await tapKey(tester, '÷');
    await tapKey(tester, '3');

    expect(inCurrentDisplay('1'), findsOneWidget);
    expect(inCurrentDisplay('2'), findsOneWidget);
    expect(inCurrentDisplay('3'), findsOneWidget);
  });

  testWidgets('marks approximate results with the almost-equal sign', (
    tester,
  ) async {
    await pumpCalculator(tester);

    await tapKey(tester, '√');
    await tapKey(tester, '2');
    await tapKey(tester, ')');
    await tapKey(tester, '=');

    expect(inCurrentDisplay('≈ 1.414213562373095'), findsOneWidget);
  });

  testWidgets('uses scientific notation for huge results', (tester) async {
    await pumpCalculator(tester);

    await tapKey(tester, '2');
    await tapKey(tester, '^');
    await tapKey(tester, '1');
    await tapKey(tester, '0');
    await tapKey(tester, '0');
    await tapKey(tester, '=');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('current-display')),
        matching: find.textContaining('e+30'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('history appends its result to existing input', (tester) async {
    await pumpCalculator(tester);

    await tapKey(tester, '1');
    await tapKey(tester, '÷');
    await tapKey(tester, '3');
    await tapKey(tester, '=');

    // Начинаем новый ввод: результат из истории не должен его затирать.
    await tapKey(tester, '5');
    await tapKey(tester, '+');

    await tester.tap(find.byKey(const ValueKey('history-0')));
    await tester.pump();

    expect(inCurrentDisplay('5'), findsOneWidget);
    expect(inCurrentDisplay('+'), findsOneWidget);
    expect(inCurrentDisplay('1'), findsOneWidget);
    expect(inCurrentDisplay('3'), findsOneWidget);
    expect(inPreview('5.333'), findsOneWidget);
  });

  testWidgets('history replaces the field only when it is empty', (
    tester,
  ) async {
    await pumpCalculator(tester);

    await tapKey(tester, '1');
    await tapKey(tester, '÷');
    await tapKey(tester, '3');
    await tapKey(tester, '=');
    await tapKey(tester, 'C');

    await tester.tap(find.byKey(const ValueKey('history-0')));
    await tester.pump();

    expect(inCurrentDisplay('1'), findsOneWidget);
    expect(inCurrentDisplay('3'), findsOneWidget);
  });

  testWidgets('history entry can be reused', (tester) async {
    await pumpCalculator(tester);

    await tapKey(tester, '1');
    await tapKey(tester, '+');
    await tapKey(tester, '2');
    await tapKey(tester, '=');

    await tester.tap(find.byKey(const ValueKey('history-0')));
    await tester.pump();

    expect(inCurrentDisplay('1'), findsOneWidget);
    expect(inCurrentDisplay('+'), findsOneWidget);
    expect(inCurrentDisplay('2'), findsOneWidget);
  });

  testWidgets('engineering mode shows functions and computes factorial', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Engineering');

    expect(find.byKey(const ValueKey('key_sin')), findsOneWidget);
    expect(find.byKey(const ValueKey('key_π')), findsOneWidget);
    expect(find.byKey(const ValueKey('key_angle')), findsOneWidget);
    expect(find.byKey(const ValueKey('key_Ans')), findsOneWidget);

    await tapKey(tester, '5');
    await tapKey(tester, 'n!');
    await tapKey(tester, '=');

    expect(inCurrentDisplay('120'), findsOneWidget);

    await tapKey(tester, 'angle');
    expect(find.text('RAD'), findsOneWidget);
  });

  testWidgets('pace mode computes pace from distance and time', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Pace');

    expect(find.byKey(const ValueKey('pace-calc-pace')), findsOneWidget);
    expect(find.byKey(const ValueKey('pace-table-time-0')), findsNothing);

    // Дистанция 5 км, время 25 минут -> темп 5:00 на километр.
    await tapPaceKey(tester, '5');
    await tapField(tester, find.byKey(const ValueKey('pace-time-minutes')));
    await tapPaceKey(tester, '2');
    await tapPaceKey(tester, '5');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-pace-min')),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-pace-sec')),
        matching: find.text('00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('pace table computes segment and overall pace', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await tapField(tester, find.byKey(const ValueKey('pace-table-time-0')));
    for (final key in ['0', '8', '0', '0']) {
      await tapPaceKey(tester, key);
    }

    await tapField(tester, find.byKey(const ValueKey('pace-table-time-1')));
    for (final key in ['0', '8', '3', '0']) {
      await tapPaceKey(tester, key);
    }

    await tapField(tester, find.byKey(const ValueKey('pace-table-distance-1')));
    await tapPaceKey(tester, '1');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-pace-1')),
        matching: find.text('30:00'),
      ),
      findsOneWidget,
    );

    final summary = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('pace-overall')),
        matching: find.byType(Text),
      ),
    );
    expect(summary.data, 'Темп в лимит - 30:00');
  });

  testWidgets('simple mode uses larger keypad and display fonts', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);

    final display = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('current-display')),
        matching: find.text('0'),
      ),
    );
    expect(display.style?.fontSize, 37);
    expect(display.style?.fontWeight, FontWeight.w600);

    final key = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('key_1')),
        matching: find.text('1'),
      ),
    );
    expect(key.style?.fontSize, 30);
  });

  testWidgets('history rows keep the same font size', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);

    await tapKey(tester, '1');
    await tapKey(tester, '=');
    await tapKey(tester, '2');
    await tapKey(tester, '=');

    final texts = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('history')),
        matching: find.byType(Text),
      ),
    );
    expect(texts.length, greaterThanOrEqualTo(2));
    for (final text in texts) {
      expect(text.style?.fontSize, 18);
    }
  });

  testWidgets(
    'engineering keypad has no triple zero and keeps zero bottom left',
    (tester) async {
      usePhoneSize(tester);
      await pumpCalculator(tester);
      await switchMode(tester, 'Engineering');

      expect(find.byKey(const ValueKey('key_000')), findsNothing);

      final zero = tester.getCenter(find.byKey(const ValueKey('key_0')));
      final dot = tester.getCenter(find.byKey(const ValueKey('key_.')));
      final inverse = tester.getCenter(find.byKey(const ValueKey('key_1/x')));
      final equals = tester.getCenter(find.byKey(const ValueKey('key_=')));

      expect(zero.dy, dot.dy);
      expect(dot.dy, inverse.dy);
      expect(inverse.dy, equals.dy);
      expect(zero.dx, lessThan(dot.dx));
      expect(dot.dx, lessThan(inverse.dx));
      expect(inverse.dx, lessThan(equals.dx));
    },
  );

  testWidgets('pace toolbar selects events and resizes columns', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    expect(find.byKey(const ValueKey('pace-event-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('pace-columns-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('pace-lock-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('pace-scale-button')), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('pace-event-button'))).width,
      greaterThan(
        tester
                .getSize(find.byKey(const ValueKey('pace-columns-button')))
                .width *
            2,
      ),
    );
    expect(find.text('GRUT · T100'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pace-event-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mad Fox Ultra'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VR'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pace-table-time-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('pace-table-time-11')), findsNothing);
    expect(find.byKey(const ValueKey('pace-scale-button')), findsOneWidget);
    expect(find.text('Mad Fox Ultra · VR'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pace-columns-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pace-columns-minus')));
    await tester.pump();
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pace-table-time-9')), findsOneWidget);
    expect(find.byKey(const ValueKey('pace-table-time-10')), findsNothing);
  });

  testWidgets('pace adds a custom event and distance', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await tester.tap(find.byKey(const ValueKey('pace-event-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ Добавить мероприятие'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Мой забег');
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pace-event-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мой забег'));
    await tester.pumpAndSettle();
    expect(find.text('Нет дистанций'), findsOneWidget);

    await tester.tap(find.text('+ Добавить дистанцию'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '10K');
    await tester.enterText(fields.at(1), '2');
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pace-event-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мой забег'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10K'));
    await tester.pumpAndSettle();

    expect(find.text('Мой забег · 10K'), findsOneWidget);
    expect(find.byKey(const ValueKey('pace-table-time-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('pace-table-time-4')), findsNothing);
  });

  testWidgets('pace scale toggle changes the table cell width', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await tester.tap(find.byKey(const ValueKey('pace-columns-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pace-columns-plus')));
    await tester.pump();
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();

    final fittedWidth = tester
        .getSize(find.byKey(const ValueKey('pace-table-time-0')))
        .width;
    expect(fittedWidth, lessThan(52));

    await tester.tap(find.byKey(const ValueKey('pace-scale-button')));
    await tester.pump();

    final fixedWidth = tester
        .getSize(find.byKey(const ValueKey('pace-table-time-0')))
        .width;
    expect(fixedWidth, closeTo(51, 1));
  });

  testWidgets('pace notes, water and food accept text', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await tapField(tester, find.byKey(const ValueKey('pace-note-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Лес');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    await tapField(tester, find.byKey(const ValueKey('pace-water-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '500 мл');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    await tapField(tester, find.byKey(const ValueKey('pace-food-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'гель');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Лес'), findsOneWidget);
    expect(find.textContaining('500 мл', findRichText: true), findsOneWidget);
    expect(find.textContaining('гель'), findsOneWidget);
  });

  testWidgets('pace plan time and planned pace stay in sync', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await tapField(tester, find.byKey(const ValueKey('pace-table-distance-1')));
    await tapPaceKey(tester, '1');
    await tapField(tester, find.byKey(const ValueKey('pace-table-distance-2')));
    await tapPaceKey(tester, '2');

    await tapField(tester, find.byKey(const ValueKey('pace-plan-time-0')));
    for (final key in ['0', '8', '0', '0']) {
      await tapPaceKey(tester, key);
    }
    await tapField(tester, find.byKey(const ValueKey('pace-plan-time-1')));
    for (final key in ['0', '9', '0', '0']) {
      await tapPaceKey(tester, key);
    }

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-plan-pace-1')),
        matching: find.text('60:00'),
      ),
      findsOneWidget,
    );

    await tapField(tester, find.byKey(const ValueKey('pace-plan-pace-2')));
    for (final key in ['3', '0', '0', '0']) {
      await tapPaceKey(tester, key);
    }

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-plan-time-2')),
        matching: find.text('09:30'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('pace empty time cell rewrites 00:00 from the left', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await tapField(tester, find.byKey(const ValueKey('pace-table-time-0')));
    await tapPaceKey(tester, '0');
    await tapPaceKey(tester, '7');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-time-0')),
        matching: find.text('07:00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('pace landscape shows only the table and keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    expect(find.byKey(const ValueKey('pace-calc-pace')), findsNothing);
    expect(find.byKey(const ValueKey('pace-event-button')), findsNothing);
    expect(find.byKey(const ValueKey('mode-button')), findsNothing);
    expect(find.byKey(const ValueKey('pace-table-time-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('pace-food-0')), findsOneWidget);

    // Клавиатура выезжает только после нажатия на поле ввода.
    expect(find.byKey(const ValueKey('pace-key-1')), findsNothing);
    await tapField(tester, find.byKey(const ValueKey('pace-table-time-0')));

    expect(find.byKey(const ValueKey('pace-key-1')), findsOneWidget);

    final tableRight = tester
        .getTopRight(find.byKey(const ValueKey('pace-table-time-7')))
        .dx;
    final keyboardLeft = tester
        .getTopLeft(find.byKey(const ValueKey('pace-key-1')))
        .dx;
    expect(tableRight, lessThanOrEqualTo(keyboardLeft + 0.5));

    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('pace-food-0'))).dy,
      lessThanOrEqualTo(390),
    );

    expect(find.byKey(const ValueKey('pace-key-.')), findsOneWidget);
    expect(find.byKey(const ValueKey('pace-key-⌫')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('pace-key-.'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('pace-key-1'))).dy),
    );
  });

  testWidgets('pace calculator landscape keeps the mode bar', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpCalculator(tester);
    await switchMode(tester, 'Pace');

    expect(find.byKey(const ValueKey('mode-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('pace-calc-pace')), findsOneWidget);
    expect(find.byKey(const ValueKey('pace-table-time-0')), findsNothing);
  });

  testWidgets('time mode computes a difference between date-times', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Time');

    await tapField(tester, find.byKey(const ValueKey('time-0-date')));
    await enterTimeDigits(tester, '01102026');
    await tapField(tester, find.byKey(const ValueKey('time-0-hours')));
    await enterTimeDigits(tester, '10');

    await tapField(tester, find.byKey(const ValueKey('time-1-date')));
    await enterTimeDigits(tester, '01102026');
    await tapField(tester, find.byKey(const ValueKey('time-1-hours')));
    await enterTimeDigits(tester, '12');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('time-2-hours')),
        matching: find.text('02'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('time mode adds and subtracts durations from a date', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Time');

    await tester.tap(find.byKey(const ValueKey('time-tab-add')));
    await tester.pump();

    await tapField(tester, find.byKey(const ValueKey('time-0-date')));
    await enterTimeDigits(tester, '01102026');
    await tapField(tester, find.byKey(const ValueKey('time-0-hours')));
    await enterTimeDigits(tester, '10');

    await tapField(tester, find.byKey(const ValueKey('time-1-hours')));
    await enterTimeDigits(tester, '2');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('time-2-date')),
        matching: find.text('01.10.2026'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('time-2-hours')),
        matching: find.text('12'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('time-op-sub')));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('time-2-hours')),
        matching: find.text('08'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('time mode carries the result date across midnight', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Time');

    await tester.tap(find.byKey(const ValueKey('time-tab-add')));
    await tester.pump();

    await tapField(tester, find.byKey(const ValueKey('time-0-date')));
    await enterTimeDigits(tester, '31122026');
    await tapField(tester, find.byKey(const ValueKey('time-0-hours')));
    await enterTimeDigits(tester, '23');
    await tapField(tester, find.byKey(const ValueKey('time-0-minutes')));
    await enterTimeDigits(tester, '30');

    await tapField(tester, find.byKey(const ValueKey('time-1-hours')));
    await enterTimeDigits(tester, '1');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('time-2-date')),
        matching: find.text('01.01.2027'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('time-2-hours')),
        matching: find.text('00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('time-2-minutes')),
        matching: find.text('30'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('time converter shows totals', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Time');

    await tester.tap(find.byKey(const ValueKey('time-tab-converter')));
    await tester.pump();

    await tapField(tester, find.byKey(const ValueKey('time-0-days')));
    await tapTimeKey(tester, '1');

    expect(find.text('24'), findsOneWidget);
    expect(find.text('1440'), findsOneWidget);
    expect(find.text('86400'), findsOneWidget);
  });

  testWidgets('all modes fit a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpCalculator(tester);

    await switchMode(tester, 'Engineering');
    expect(find.byKey(const ValueKey('key_sin')), findsOneWidget);

    await switchMode(tester, 'Pace');
    expect(find.byKey(const ValueKey('pace-calc-pace')), findsOneWidget);

    await switchMode(tester, 'Ultra');
    expect(find.byKey(const ValueKey('pace-table-time-0')), findsOneWidget);

    await switchMode(tester, 'Time');
    expect(find.byKey(const ValueKey('time-tab-difference')), findsOneWidget);
  });

  testWidgets('pace treats a smaller time as the next day', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await enterPaceTime(tester, 'pace-table-time-0', '23:00');
    await enterPaceTime(tester, 'pace-table-time-1', '01:00');
    await enterPaceValue(tester, 'pace-table-distance-1', '1');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-pace-1')),
        matching: find.text('120:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-overall')),
        matching: find.text('Темп в лимит - 120:00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('pace keeps segment pace green and highlights planned paces', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await enterPaceTime(tester, 'pace-table-time-0', '08:00');
    await enterPaceTime(tester, 'pace-table-time-1', '08:30');
    await enterPaceTime(tester, 'pace-table-time-2', '08:50');
    await enterPaceTime(tester, 'pace-table-time-3', '09:15');
    await enterPaceValue(tester, 'pace-table-distance-1', '1');
    await enterPaceValue(tester, 'pace-table-distance-2', '2');
    await enterPaceValue(tester, 'pace-table-distance-3', '3');

    // Ряд «Темп сегмента» всегда зелёный, без подсветки быстрейшего.
    const segmentColor = Color(0xFF4CAF50);
    expect(paceCellColor(tester, 'pace-table-pace-2', '20:00'), segmentColor);
    expect(paceCellColor(tester, 'pace-table-pace-3', '25:00'), segmentColor);
    expect(paceCellColor(tester, 'pace-table-pace-1', '30:00'), segmentColor);

    await enterPaceTime(tester, 'pace-plan-time-0', '08:00');
    await enterPaceTime(tester, 'pace-plan-time-1', '08:30');
    await enterPaceTime(tester, 'pace-plan-time-2', '08:50');
    await enterPaceTime(tester, 'pace-plan-time-3', '09:15');

    expect(paceCellColor(tester, 'pace-plan-pace-2', '20:00'), Colors.red);
    expect(paceCellColor(tester, 'pace-plan-pace-3', '25:00'), Colors.amber);
    expect(paceCellColor(tester, 'pace-plan-pace-1', '30:00'), Colors.white);
  });

  testWidgets('pace shows the overall planned pace', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await enterPaceTime(tester, 'pace-plan-time-0', '08:00');
    await enterPaceTime(tester, 'pace-plan-time-1', '09:00');
    await enterPaceTime(tester, 'pace-plan-time-2', '10:00');
    await enterPaceValue(tester, 'pace-table-distance-1', '2');
    await enterPaceValue(tester, 'pace-table-distance-2', '4');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-overall-plan')),
        matching: find.text('Итоговый плановый темп - 30:00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('pace data survives an app restart', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await enterPaceTime(tester, 'pace-table-time-0', '08:00');
    await enterPaceValue(tester, 'pace-table-distance-1', '1');
    await enterPaceTime(tester, 'pace-plan-time-0', '08:00');
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const CalculatorApp());
    await tester.pumpAndSettle();
    await switchMode(tester, 'Ultra');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-time-0')),
        matching: find.text('08:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-distance-1')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-plan-time-0')),
        matching: find.text('08:00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ultra keeps a separate table for every distance', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await enterPaceTime(tester, 'pace-table-time-0', '08:00');
    await enterPaceValue(tester, 'pace-table-distance-1', '1');

    await switchEventDistance(tester, 'Mad Fox Ultra', '50M');
    expect(find.text('Mad Fox Ultra · 50M'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-time-0')),
        matching: find.text('08:00'),
      ),
      findsNothing,
    );

    await enterPaceTime(tester, 'pace-table-time-0', '09:00');
    await enterPaceValue(tester, 'pace-table-distance-1', '2');

    await switchEventDistance(tester, 'GRUT', 'T100');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-time-0')),
        matching: find.text('08:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-distance-1')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );

    await switchEventDistance(tester, 'Mad Fox Ultra', '50M');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-time-0')),
        matching: find.text('09:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-distance-1')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const CalculatorApp());
    await tester.pumpAndSettle();
    await switchMode(tester, 'Ultra');

    expect(find.text('Mad Fox Ultra · 50M'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-time-0')),
        matching: find.text('09:00'),
      ),
      findsOneWidget,
    );

    await switchEventDistance(tester, 'GRUT', 'T100');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-time-0')),
        matching: find.text('08:00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ultra colours borders after input finishes', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    const darkGreen = Color(0xFF1B5E20);

    await enterPaceTime(tester, 'pace-table-time-0', '23:00');
    await enterPaceTime(tester, 'pace-table-time-1', '23:30');
    await enterPaceTime(tester, 'pace-table-time-2', '01:00');

    // Пока ввод не завершён, новый день ещё не зафиксирован.
    expect(
      paceCellBorderColor(tester, 'pace-table-time-2'),
      isNot(darkGreen.toARGB32()),
    );

    // Завершаем ввод, перейдя в соседнее поле.
    await tapField(tester, find.byKey(const ValueKey('pace-table-time-3')));

    expect(
      paceCellBorderColor(tester, 'pace-table-time-2'),
      darkGreen.toARGB32(),
    );
    expect(
      paceCellBorderColor(tester, 'pace-table-distance-2'),
      darkGreen.toARGB32(),
    );
    expect(
      paceCellBorderColor(tester, 'pace-table-pace-2'),
      darkGreen.toARGB32(),
    );
    expect(paceCellBorderColor(tester, 'pace-water-2'), darkGreen.toARGB32());
    expect(paceCellBorderColor(tester, 'pace-food-2'), darkGreen.toARGB32());
    expect(paceCellBorderColor(tester, 'pace-note-2'), darkGreen.toARGB32());

    // План проверяется отдельно по плановому времени.
    expect(
      paceCellBorderColor(tester, 'pace-plan-time-2'),
      isNot(darkGreen.toARGB32()),
    );

    await enterPaceTime(tester, 'pace-plan-time-0', '23:00');
    await enterPaceTime(tester, 'pace-plan-time-1', '23:30');
    await enterPaceTime(tester, 'pace-plan-time-2', '01:00');
    await tapField(tester, find.byKey(const ValueKey('pace-plan-time-3')));

    expect(
      paceCellBorderColor(tester, 'pace-plan-time-2'),
      darkGreen.toARGB32(),
    );
    expect(
      paceCellBorderColor(tester, 'pace-plan-pace-2'),
      darkGreen.toARGB32(),
    );

    // Следующий новый день — синий.
    await enterPaceTime(tester, 'pace-table-time-3', '00:30');
    await tapField(tester, find.byKey(const ValueKey('pace-table-time-0')));
    expect(
      paceCellBorderColor(tester, 'pace-table-distance-3'),
      Colors.blue.toARGB32(),
    );
  });

  testWidgets('pace calculator data survives an app restart', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Pace');

    await tapPaceKey(tester, '5');
    await tapField(tester, find.byKey(const ValueKey('pace-time-minutes')));
    await tapPaceKey(tester, '2');
    await tapPaceKey(tester, '5');
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const CalculatorApp());
    await tester.pumpAndSettle();
    await switchMode(tester, 'Pace');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-distance')),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-time-minutes')),
        matching: find.text('25'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'ultra keyboard appears on tap, hides outside and commits by OK',
    (tester) async {
      usePhoneSize(tester);
      await pumpCalculator(tester);
      await switchMode(tester, 'Ultra');

      expect(find.byKey(const ValueKey('pace-key-1')), findsNothing);

      await tapField(tester, find.byKey(const ValueKey('pace-table-time-0')));
      expect(find.byKey(const ValueKey('pace-key-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('pace-key-ОК')), findsOneWidget);
      expect(find.byKey(const ValueKey('pace-key-00')), findsNothing);

      for (final key in ['0', '8', '0', '0']) {
        await tapPaceKey(tester, key);
      }
      await tapPaceKey(tester, 'ОК');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pace-key-1')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('pace-table-time-0')),
          matching: find.text('08:00'),
        ),
        findsOneWidget,
      );

      await tapField(tester, find.byKey(const ValueKey('pace-table-time-1')));
      expect(find.byKey(const ValueKey('pace-key-1')), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('pace-table-pace-0')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pace-table-pace-0')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pace-key-1')), findsNothing);
    },
  );

  testWidgets('ultra portrait summary shows total time and editable plan', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await enterPaceTime(tester, 'pace-table-time-0', '23:00');
    await enterPaceTime(tester, 'pace-table-time-1', '01:00');
    await enterPaceValue(tester, 'pace-table-distance-1', '10');
    await tapField(tester, find.byKey(const ValueKey('pace-table-time-2')));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-overall-time')),
        matching: find.text('Общее время - 02:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-overall')),
        matching: find.text('Темп в лимит - 12:00'),
      ),
      findsOneWidget,
    );

    await enterPaceTime(tester, 'pace-plan-time-0', '08:00');

    await tester.ensureVisible(find.byKey(const ValueKey('pace-overall-plan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pace-overall-plan')));
    await tester.pumpAndSettle();
    for (final key in ['0', '6', '0', '0']) {
      await tapPaceKey(tester, key);
    }
    await tapPaceKey(tester, 'ОК');
    await tester.pumpAndSettle();

    // Пересчёт плана требует подтверждения.
    expect(find.text('Пересчитать план?'), findsOneWidget);
    await tester.tap(find.text('Пересчитать'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-overall-plan')),
        matching: find.text('Итоговый плановый темп - 6:00'),
      ),
      findsOneWidget,
    );
    // Время в итоговой строке — длительность, а не время суток финиша.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-overall-plan-time')),
        matching: find.text('Итоговое плановое время - 01:00'),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('pace-overall-plan-time')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pace-overall-plan-time')));
    await tester.pumpAndSettle();
    for (final key in ['1', '0', '0', '0']) {
      await tapPaceKey(tester, key);
    }
    await tapPaceKey(tester, 'ОК');
    await tester.pumpAndSettle();
    expect(find.text('Пересчитать план?'), findsOneWidget);
    await tester.tap(find.text('Пересчитать'));
    await tester.pumpAndSettle();

    // 10 часов на 10 км дают средний темп 60:00.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-overall-plan')),
        matching: find.text('Итоговый плановый темп - 60:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-overall-plan-time')),
        matching: find.text('Итоговое плановое время - 10:00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ultra landscape shows the bold Total column with hints', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    expect(find.byKey(const ValueKey('pace-total-header')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-total-header')),
        matching: find.text('Total'),
      ),
      findsOneWidget,
    );

    await enterPaceTime(tester, 'pace-table-time-0', '08:00');
    await enterPaceTime(tester, 'pace-table-time-1', '09:00');
    await enterPaceValue(tester, 'pace-table-distance-1', '10');
    await tapField(tester, find.byKey(const ValueKey('pace-table-time-2')));
    await tapPaceKey(tester, 'ОК');
    await tester.pumpAndSettle();

    final totalTime = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('pace-total-time')),
        matching: find.text('01:00'),
      ),
    );
    expect(totalTime.style?.fontWeight, FontWeight.bold);

    await tester.tap(find.byKey(const ValueKey('pace-total-time')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Общее время по данным строки «Лимит»: сумма переходов от старта '
        'до последнего заполненного пункта.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
  });

  testWidgets('ultra lock makes every field read-only and persists', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await enterPaceTime(tester, 'pace-table-time-0', '08:00');
    await tapField(tester, find.byKey(const ValueKey('pace-table-time-1')));

    await tester.tap(find.byKey(const ValueKey('pace-lock-button')));
    await tester.pumpAndSettle();
    expect(find.text('Фиксация'), findsOneWidget);
    await tester.tap(find.text('Зафиксировать все'));
    await tester.pumpAndSettle();
    expect(find.text('Зафиксировать введённые значения?'), findsOneWidget);
    await tester.tap(find.text('Зафиксировать'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-lock-button')),
        matching: find.text('Замок'),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('pace-table-time-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pace-key-1')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-time-0')),
        matching: find.text('08:00'),
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const CalculatorApp());
    await tester.pumpAndSettle();
    await switchMode(tester, 'Ultra');

    await tester.tap(find.byKey(const ValueKey('pace-table-time-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pace-key-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('pace-lock-button')));
    await tester.pumpAndSettle();
    expect(find.text('Фиксация'), findsOneWidget);
    await tester.tap(find.text('Разблокировать все'));
    await tester.pumpAndSettle();
    expect(find.text('Снять фиксацию?'), findsOneWidget);
    await tester.tap(find.text('Снять'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pace-table-time-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pace-key-1')), findsOneWidget);
  });

  testWidgets('ultra water words are coloured and rows are tall', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await tapField(tester, find.byKey(const ValueKey('pace-water-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      'кола 200 вода 500 пиво 100 ягер 50',
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    final rich = tester.widget<RichText>(
      find
          .descendant(
            of: find.byKey(const ValueKey('pace-water-text-0')),
            matching: find.byType(RichText),
          )
          .first,
    );
    final span = rich.text as TextSpan;
    final colors = <Color?>[];
    void collect(InlineSpan node) {
      if (node is! TextSpan) return;
      if (node.text != null && node.text!.trim().isNotEmpty) {
        colors.add(node.style?.color);
      }
      for (final child in node.children ?? const <InlineSpan>[]) {
        collect(child);
      }
    }

    collect(span);
    colors.removeWhere((color) => color == null || color == Colors.white);
    expect(colors, [
      const Color(0xFFD2A679),
      const Color(0xFF64B5F6),
      const Color(0xFFFFEB3B),
      const Color(0xFF81C784),
    ]);

    final waterText = tester.widget<Text>(
      find
          .descendant(
            of: find.byKey(const ValueKey('pace-water-text-0')),
            matching: find.byType(Text),
          )
          .first,
    );
    expect(waterText.maxLines, greaterThanOrEqualTo(8));
    expect(
      tester.getSize(find.byKey(const ValueKey('pace-water-0'))).height,
      greaterThanOrEqualTo(100),
    );
  });

  testWidgets('ultra keyboard keeps the focused field visible', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    final field = find.byKey(const ValueKey('pace-plan-pace-7'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();

    final fieldBottom = tester.getBottomLeft(field).dy;
    final keyboardTop = tester
        .getTopLeft(find.byKey(const ValueKey('pace-key-1')))
        .dy;
    expect(fieldBottom, lessThanOrEqualTo(keyboardTop + 0.5));
  });

  testWidgets('ultra fills new GRUT T100 and Mad Fox VR tables', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester, seedUltraDefaults: true);
    await switchMode(tester, 'Ultra');

    expect(find.text('GRUT · T100'), findsOneWidget);
    const grutTimes = [
      '05:00',
      '07:00',
      '08:00',
      '10:00',
      '17:00',
      '20:35',
      '22:00',
      '23:00',
    ];
    for (var index = 0; index < grutTimes.length; index++) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('pace-table-time-$index')),
          matching: find.text(grutTimes[index]),
        ),
        findsOneWidget,
      );
    }
    const grutDistances = [
      '0.00',
      '11',
      '18.8',
      '30',
      '70.2',
      '94',
      '102.2',
      '109.5',
    ];
    for (var index = 0; index < grutDistances.length; index++) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('pace-table-distance-$index')),
          matching: find.text(grutDistances[index]),
        ),
        findsOneWidget,
      );
    }

    await switchEventDistance(tester, 'Mad Fox Ultra', 'VR');
    expect(find.text('Mad Fox Ultra · VR'), findsOneWidget);

    const vrTimes = [
      '16:00',
      '21:00',
      '23:50',
      '03:00',
      '06:40',
      '09:30',
      '12:45',
      '15:00',
      '17:30',
      '19:00',
      '22:00',
    ];
    for (var index = 0; index < vrTimes.length; index++) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('pace-table-time-$index')),
          matching: find.text(vrTimes[index]),
        ),
        findsOneWidget,
      );
    }
    const vrDistances = [
      '0.00',
      '20.3',
      '32.2',
      '47.3',
      '72',
      '90.7',
      '111.2',
      '125.8',
      '139.6',
      '148.5',
      '165.2',
    ];
    for (var index = 0; index < vrDistances.length; index++) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('pace-table-distance-$index')),
          matching: find.text(vrDistances[index]),
        ),
        findsOneWidget,
      );
    }

    expect(
      paceCellBorderColor(tester, 'pace-table-time-3'),
      const Color(0xFF1B5E20).toARGB32(),
    );
  });

  testWidgets('ultra shows distance precision exactly as entered', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await enterPaceValue(tester, 'pace-table-distance-1', '20');
    await enterPaceValue(tester, 'pace-table-distance-2', '20.3');
    await enterPaceValue(tester, 'pace-table-distance-3', '20.35');
    await tapField(tester, find.byKey(const ValueKey('pace-table-distance-4')));
    await tapPaceKey(tester, 'ОК');
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-distance-1')),
        matching: find.text('20'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-distance-2')),
        matching: find.text('20.3'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-distance-3')),
        matching: find.text('20.35'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ultra landscape puts totals into data rows', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    expect(find.text('Общее время'), findsNothing);
    expect(find.text('Темп в лимит'), findsNothing);
    expect(find.text('Итоговый плановый темп'), findsNothing);
    expect(find.text('Итоговое плановое время'), findsNothing);

    await enterPaceTime(tester, 'pace-table-time-0', '08:00');
    await enterPaceTime(tester, 'pace-table-time-1', '09:00');
    await enterPaceValue(tester, 'pace-table-distance-1', '10');
    await tapField(tester, find.byKey(const ValueKey('pace-table-time-2')));
    await tapPaceKey(tester, 'ОК');
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-total-time')),
        matching: find.text('01:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-total-pace')),
        matching: find.text('6:00'),
      ),
      findsOneWidget,
    );

    expect(
      tester.getCenter(find.byKey(const ValueKey('pace-total-time'))).dy,
      closeTo(
        tester.getCenter(find.byKey(const ValueKey('pace-table-time-0'))).dy,
        1,
      ),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('pace-total-pace'))).dy,
      closeTo(
        tester.getCenter(find.byKey(const ValueKey('pace-table-pace-1'))).dy,
        1,
      ),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('pace-total-plan-pace'))).dy,
      closeTo(
        tester.getCenter(find.byKey(const ValueKey('pace-plan-pace-1'))).dy,
        1,
      ),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('pace-total-plan-time'))).dy,
      closeTo(
        tester.getCenter(find.byKey(const ValueKey('pace-plan-time-0'))).dy,
        1,
      ),
    );

    // Плановые итоги вводятся с клавиатуры, а не показывают подсказку.
    await tester.tap(find.byKey(const ValueKey('pace-total-plan-pace')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pace-key-1')), findsOneWidget);
    for (final key in ['0', '6', '0', '0']) {
      await tapPaceKey(tester, key);
    }
    await tapPaceKey(tester, 'ОК');
    await tester.pumpAndSettle();
    expect(find.text('Пересчитать план?'), findsOneWidget);
    await tester.tap(find.text('Пересчитать'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-total-plan-pace')),
        matching: find.text('6:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-total-plan-time')),
        matching: find.text('01:00'),
      ),
      findsOneWidget,
    );

    // Долгое нажатие по-прежнему показывает пояснение.
    await tester.longPress(find.byKey(const ValueKey('pace-total-plan-pace')));
    await tester.pumpAndSettle();
    expect(find.text('Итоговый плановый темп'), findsOneWidget);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
  });

  testWidgets('legacy 100M distance migrates to VR without losing data', (
    tester,
  ) async {
    usePhoneSize(tester);
    SharedPreferences.setMockInitialValues({
      'ultra_state_v1': jsonEncode({
        'events': [
          {
            'name': 'Mad Fox Ultra',
            'distances': [
              {'name': '100M', 'checkpoints': 9},
              {'name': '50M', 'checkpoints': 5},
            ],
          },
          {
            'name': 'GRUT',
            'distances': [
              {'name': 'T100', 'checkpoints': 6},
            ],
          },
        ],
        'selectedEvent': 'Mad Fox Ultra',
        'selectedDistance': '100M',
        'tables': {
          'Mad Fox Ultra': {
            '100M': {
              'columns': 11,
              'fitTable': true,
              'tableTimes': [
                '1600',
                '2100',
                '2350',
                '0300',
                '0640',
                '0930',
                '1245',
                '1500',
                '1730',
                '1900',
                '2200',
              ],
            },
          },
        },
      }),
    });
    await tester.pumpWidget(const CalculatorApp());
    await tester.pumpAndSettle();
    await switchMode(tester, 'Ultra');

    expect(find.text('Mad Fox Ultra · VR'), findsOneWidget);
    expect(find.byKey(const ValueKey('pace-table-time-10')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-time-0')),
        matching: find.text('16:00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('last selected mode is restored after restart', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Time');

    expect(find.byKey(const ValueKey('time-1-hours')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const CalculatorApp());
    await tester.pumpAndSettle();

    expect(find.text('Time'), findsOneWidget);
    expect(find.byKey(const ValueKey('time-1-hours')), findsOneWidget);
  });

  testWidgets('legacy empty table receives seeded defaults once', (
    tester,
  ) async {
    usePhoneSize(tester);
    SharedPreferences.setMockInitialValues({
      'ultra_state_v1': jsonEncode({
        'tables': {
          'GRUT': {
            'T100': {'columns': 8, 'fitTable': true},
          },
        },
      }),
    });
    await tester.pumpWidget(const CalculatorApp());
    await tester.pumpAndSettle();
    await switchMode(tester, 'Ultra');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-time-0')),
        matching: find.text('05:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-distance-1')),
        matching: find.text('11'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('seeded table cleared by the user stays empty', (tester) async {
    usePhoneSize(tester);
    SharedPreferences.setMockInitialValues({
      'ultra_state_v1': jsonEncode({
        'tables': {
          'GRUT': {
            'T100': {'columns': 8, 'fitTable': true, 'seeded': true},
          },
        },
      }),
    });
    await tester.pumpWidget(const CalculatorApp());
    await tester.pumpAndSettle();
    await switchMode(tester, 'Ultra');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-time-0')),
        matching: find.text('00:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-distance-1')),
        matching: find.text(''),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ultra portrait hides row names and enlarges notes', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    expect(find.text('ПП / заметки'), findsNothing);
    expect(find.text('Лимит'), findsNothing);
    expect(find.text('Расстояние, км'), findsNothing);
    expect(find.text('Темп сегмента'), findsNothing);

    final noteHeight = tester
        .getSize(find.byKey(const ValueKey('pace-note-0')))
        .height;
    final timeHeight = tester
        .getSize(find.byKey(const ValueKey('pace-table-time-0')))
        .height;
    expect(noteHeight, closeTo(timeHeight * 2, 1));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-distance-0')),
        matching: find.text('0.00'),
      ),
      findsOneWidget,
    );

    Future<double> noteFontSize(String text) async {
      await tapField(tester, find.byKey(const ValueKey('pace-note-0')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), text);
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      final widget = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('pace-note-0')),
          matching: find.text(text),
        ),
      );
      return widget.style!.fontSize!;
    }

    final shortSize = await noteFontSize('Лес');
    final longSize = await noteFontSize('Очень длинная заметка');
    expect(shortSize, greaterThan(longSize));
    expect(shortSize, greaterThan(18));
  });

  testWidgets('ultra portrait fits a seven-letter note word', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await tapField(tester, find.byKey(const ValueKey('pace-note-0')));
    await tester.enterText(find.byType(TextFormField), 'Заправка');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    final cellRect = tester.getRect(find.byKey(const ValueKey('pace-note-0')));
    final textRect = tester.getRect(find.text('Заправка'));
    expect(textRect.width, lessThanOrEqualTo(cellRect.width + 0.5));
    expect(textRect.height, lessThanOrEqualTo(cellRect.height + 0.5));
  });

  testWidgets('ultra portrait uses PACE cells and water/food placeholders', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-table-pace-0')),
        matching: find.text('PACE'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-plan-pace-0')),
        matching: find.text('PACE'),
      ),
      findsOneWidget,
    );

    // Подписи рядов убраны, вместо них — подсказки в первых клетках.
    expect(find.text('Плановый темп'), findsNothing);
    expect(find.text('Вода'), findsOneWidget);
    expect(find.text('Еда'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-water-0')),
        matching: find.text('Вода'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-food-0')),
        matching: find.text('Еда'),
      ),
      findsOneWidget,
    );

    await tapField(tester, find.byKey(const ValueKey('pace-water-0')));
    await tester.enterText(find.byType(TextFormField), '500 мл');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    // После ввода подсказка исчезает.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-water-0')),
        matching: find.text('Вода'),
      ),
      findsNothing,
    );
    expect(find.textContaining('500 мл', findRichText: true), findsOneWidget);
  });

  testWidgets('ultra water text overflows into empty neighbouring cells', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await tapField(tester, find.byKey(const ValueKey('pace-water-0')));
    await tester.enterText(find.byType(TextFormField), 'кола 200 вода 500');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    final cellWidth = tester
        .getSize(find.byKey(const ValueKey('pace-water-0')))
        .width;
    final overlayWidth = tester
        .getSize(find.byKey(const ValueKey('pace-water-text-0')))
        .width;
    expect(overlayWidth, greaterThan(cellWidth * 1.5));

    // Заполненная соседняя клетка останавливает перетекание.
    await tapField(tester, find.byKey(const ValueKey('pace-water-1')));
    await tester.enterText(find.byType(TextFormField), 'изотоник');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('pace-water-text-0'))).width,
      closeTo(cellWidth, 1),
    );
  });

  testWidgets('ultra water editor preserves line breaks', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await tapField(tester, find.byKey(const ValueKey('pace-water-0')));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.maxLines, greaterThan(1));

    await tester.enterText(find.byType(TextFormField), 'вода\n500 мл');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('вода\n500 мл', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('ultra long press toggles bold borders for the whole column', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    const columnKeys = [
      'pace-note-0',
      'pace-table-time-0',
      'pace-table-distance-0',
      'pace-table-pace-0',
      'pace-plan-time-0',
      'pace-plan-pace-0',
      'pace-water-0',
      'pace-food-0',
    ];

    for (final key in columnKeys) {
      expect(paceCellBorderWidth(tester, key), 1);
    }

    await tester.longPress(find.byKey(const ValueKey('pace-note-0')));
    await tester.pumpAndSettle();

    // Ячейки заметок/воды/еды рисуют рамку 2.5, ячейки таблицы — 3.0.
    const thinBoldKeys = {'pace-note-0', 'pace-water-0', 'pace-food-0'};
    for (final key in columnKeys) {
      expect(
        paceCellBorderWidth(tester, key),
        thinBoldKeys.contains(key) ? 2.5 : 3.0,
      );
    }
    // Соседняя колонка остаётся обычной.
    expect(paceCellBorderWidth(tester, 'pace-table-time-1'), 1);

    await tester.longPress(find.byKey(const ValueKey('pace-note-0')));
    await tester.pumpAndSettle();

    for (final key in columnKeys) {
      expect(paceCellBorderWidth(tester, key), 1);
    }
  });

  testWidgets('ultra landscape long press also toggles bold borders', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await tester.longPress(find.byKey(const ValueKey('pace-note-0')));
    await tester.pumpAndSettle();

    expect(paceCellBorderWidth(tester, 'pace-note-0'), 2.5);
    expect(paceCellBorderWidth(tester, 'pace-table-time-0'), 3.0);
    expect(paceCellBorderWidth(tester, 'pace-water-0'), 2.5);
    expect(paceCellBorderWidth(tester, 'pace-food-0'), 2.5);
  });

  testWidgets('planned time uses limit start and writes plan paces', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await enterPaceTime(tester, 'pace-table-time-0', '06:00');
    await enterPaceTime(tester, 'pace-table-time-1', '07:00');
    await enterPaceValue(tester, 'pace-table-distance-1', '10');
    await tapField(tester, find.byKey(const ValueKey('pace-table-time-2')));

    await tester.ensureVisible(
      find.byKey(const ValueKey('pace-overall-plan-time')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pace-overall-plan-time')));
    await tester.pumpAndSettle();
    for (final key in ['1', '0', '0', '0']) {
      await tapPaceKey(tester, key);
    }
    await tapPaceKey(tester, 'ОК');
    await tester.pumpAndSettle();

    // Планового старта нет — берём старт из ряда «Лимит».
    expect(find.textContaining('ряда «Лимит»'), findsOneWidget);
    await tester.tap(find.text('Пересчитать'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-plan-time-0')),
        matching: find.text('06:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-overall-plan-time')),
        matching: find.text('Итоговое плановое время - 10:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-overall-plan')),
        matching: find.text('Итоговый плановый темп - 60:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-plan-pace-1')),
        matching: find.text('60:00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('planned time keeps an explicitly entered plan start', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await enterPaceTime(tester, 'pace-table-time-0', '06:00');
    await enterPaceValue(tester, 'pace-table-distance-1', '10');
    await enterPaceTime(tester, 'pace-plan-time-0', '08:00');
    await tapField(tester, find.byKey(const ValueKey('pace-table-time-1')));

    await tester.ensureVisible(
      find.byKey(const ValueKey('pace-overall-plan-time')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pace-overall-plan-time')));
    await tester.pumpAndSettle();
    for (final key in ['1', '2', '0', '0']) {
      await tapPaceKey(tester, key);
    }
    await tapPaceKey(tester, 'ОК');
    await tester.pumpAndSettle();

    expect(find.textContaining('кроме времени старта'), findsOneWidget);
    await tester.tap(find.text('Пересчитать'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-plan-time-0')),
        matching: find.text('08:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-overall-plan-time')),
        matching: find.text('Итоговое плановое время - 12:00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('time input is not limited by character count', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Time');

    await tester.tap(find.byKey(const ValueKey('time-tab-converter')));
    await tester.pump();

    await tapField(tester, find.byKey(const ValueKey('time-0-minutes')));
    await enterTimeDigits(tester, '1000');
    expect(find.text('1000'), findsWidgets);
    // 1000 минут = 16.67 часа — значение участвует в расчёте.
    expect(find.text('16.67'), findsOneWidget);

    // Очищаем минуты и проверяем 500 часов отдельно.
    await tester.longPress(find.byKey(const ValueKey('time-key-⌫')));
    await tester.pumpAndSettle();
    await tapField(tester, find.byKey(const ValueKey('time-0-hours')));
    await enterTimeDigits(tester, '500');
    expect(find.text('500'), findsWidgets);
  });

  testWidgets('plan times wrap across midnight', (tester) async {
    usePhoneSize(tester);
    await pumpCalculator(tester);
    await switchMode(tester, 'Ultra');

    await enterPaceTime(tester, 'pace-table-time-0', '23:00');
    await enterPaceValue(tester, 'pace-table-distance-1', '10');
    await enterPaceTime(tester, 'pace-plan-time-0', '23:00');
    await tapField(tester, find.byKey(const ValueKey('pace-table-time-1')));

    await tester.ensureVisible(find.byKey(const ValueKey('pace-overall-plan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pace-overall-plan')));
    await tester.pumpAndSettle();
    for (final key in ['0', '6', '0', '0']) {
      await tapPaceKey(tester, key);
    }
    await tapPaceKey(tester, 'ОК');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Пересчитать'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-plan-time-1')),
        matching: find.text('00:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pace-overall-plan-time')),
        matching: find.text('Итоговое плановое время - 01:00'),
      ),
      findsOneWidget,
    );
  });
}
