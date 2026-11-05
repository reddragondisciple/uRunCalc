import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ultra_run_calc/core/app_strings.dart';
import 'package:ultra_run_calc/main.dart';

void useSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
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
  const landscape = Size(844, 390);
  const portrait = Size(390, 844);

  testWidgets('ландшафт 844×390: ряд подъём–спуск есть, без переполнения', (
    tester,
  ) async {
    useSize(tester, landscape);
    await pumpUltra(tester, mountain: true);
    expect(find.byKey(const ValueKey('pace-elevation-label')), findsOneWidget);
    expect(find.byKey(const ValueKey('pace-elevation-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('pace-elevation-total')), findsOneWidget);
    expect(find.text(AppStrings.paceRowElevation), findsOneWidget);
    expect(find.text(AppStrings.paceRowWater), findsOneWidget);
    expect(find.text(AppStrings.paceRowFood), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ландшафт без горного режима: ряда высот нет, подписи на месте', (
    tester,
  ) async {
    useSize(tester, landscape);
    await pumpUltra(tester, mountain: false);
    expect(find.byKey(const ValueKey('pace-elevation-label')), findsNothing);
    expect(find.text(AppStrings.paceRowElevation), findsNothing);
    expect(find.text(AppStrings.paceRowPlan), findsOneWidget);
    expect(find.text(AppStrings.paceRowFood), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'портрет без горного режима: подпись «План» стоит над клеткой плана',
    (tester) async {
      useSize(tester, portrait);
      await pumpUltra(tester, mountain: false);
      final label = tester.getRect(find.text(AppStrings.paceRowPlan));
      final planCell = tester.getRect(
        find.byKey(const ValueKey('pace-plan-time-1')),
      );
      expect(label.center.dy, lessThan(planCell.top));
      expect(planCell.top - label.center.dy, lessThan(planCell.height + 20));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('портрет с горным режимом: итог набора/сброса — отдельный ряд', (
    tester,
  ) async {
    useSize(tester, portrait);
    await pumpUltra(tester, mountain: true);
    final elevation = tester.getRect(
      find.byKey(const ValueKey('pace-elevation-1')),
    );
    final total = tester.getRect(
      find.byKey(const ValueKey('pace-elevation-total-up')),
    );
    expect(find.byKey(const ValueKey('pace-elevation-total')), findsNothing);
    expect(total.top, greaterThanOrEqualTo(elevation.bottom));
    expect(find.text(AppStrings.paceTotalAscentLine('—')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
