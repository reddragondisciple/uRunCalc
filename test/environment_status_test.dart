import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/core/app_strings.dart';
import 'package:ultra_run_calc/features/calculator/calculator_mode.dart';
import 'package:ultra_run_calc/features/calculator/calculator_mode_bar.dart';
import 'package:ultra_run_calc/features/pace/environment_status.dart';

void main() {
  test('status text shows time and adds the date for older data', () {
    expect(AppStrings.environmentUpdatedLabel(9, 5), 'обновлено 09:05');
    expect(
      AppStrings.environmentUpdatedLabel(9, 5, day: 3, month: 7),
      'обновлено 3.07 09:05',
    );
  });

  testWidgets('environment status sits right of the mode button', (
    tester,
  ) async {
    final controller = EnvironmentStatusController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalculatorModeBar(
            current: CalculatorMode.pace,
            onSelected: (_) {},
            environmentStatus: controller,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('environment-status')), findsNothing);

    controller.update(text: 'обновлено 09:05 · Покрытие OSM: 100%');
    await tester.pump();

    final status = find.byKey(const ValueKey('environment-status'));
    expect(status, findsOneWidget);
    expect(
      tester.getTopLeft(status).dx,
      greaterThan(
        tester.getTopLeft(find.byKey(const ValueKey('mode-button'))).dx,
      ),
    );
    expect(find.textContaining('обновлено 09:05'), findsOneWidget);
  });

  testWidgets('loading status replaces the text', (tester) async {
    final controller = EnvironmentStatusController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalculatorModeBar(
            current: CalculatorMode.ultra,
            onSelected: (_) {},
            environmentStatus: controller,
          ),
        ),
      ),
    );

    controller.update(loading: true);
    await tester.pump();

    expect(find.text(AppStrings.environmentLoading), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  test('clear removes the status and has no loading state', () {
    final controller = EnvironmentStatusController();
    addTearDown(controller.dispose);

    controller.update(text: 'обновлено 09:05');
    expect(controller.isEmpty, isFalse);

    controller.clear();
    expect(controller.isEmpty, isTrue);
    expect(controller.text, isNull);
    expect(controller.loading, isFalse);
  });
}
