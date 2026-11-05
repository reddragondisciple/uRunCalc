import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ultra_run_calc/main.dart';

void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> pumpUltra(WidgetTester tester, {required bool mountain}) async {
  final table = {
    'columns': 8,
    'fitTable': true,
    'tableTimes': List.filled(8, ''),
    'tableDistances': ['0', '11', '18.8', '30', '70.2', '94', '102.2', '109.5'],
    'planTimes': List.filled(8, ''),
    'planPaces': List.filled(8, ''),
    'notes': List.filled(8, ''),
    'water': List.filled(8, ''),
    'food': List.filled(8, ''),
    'mountain': {'enabled': mountain},
  };
  SharedPreferences.setMockInitialValues({
    'app_mode_v1': 'simple',
    'ultra_state_v1': jsonEncode({
      'events': [
        {
          'name': 'GRUT',
          'distances': [
            {'name': 'T100', 'checkpoints': 6},
          ],
        },
      ],
      'selectedEvent': 'GRUT',
      'selectedDistance': 'T100',
      'tables': {
        'GRUT': {'T100': table},
      },
    }),
  });
  await tester.pumpWidget(const CalculatorApp());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('mode-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ultra').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ряд подъём–спуск не показывается в обычном режиме', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpUltra(tester, mountain: false);
    expect(find.byKey(const ValueKey('pace-elevation-label')), findsNothing);
  });

  testWidgets('в горном режиме ряд подъём–спуск есть, без трека — прочерки', (
    tester,
  ) async {
    usePhoneSize(tester);
    await pumpUltra(tester, mountain: true);
    expect(find.byKey(const ValueKey('pace-elevation-label')), findsOneWidget);
    expect(find.byKey(const ValueKey('pace-elevation-1')), findsOneWidget);
    expect(find.text('↑↓'), findsOneWidget);
  });
}
