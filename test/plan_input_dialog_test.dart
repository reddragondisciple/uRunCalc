import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/plan_math.dart';
import 'package:ultra_run_calc/features/pace/pace_gpx_import_ui.dart';

void main() {
  testWidgets(
    'диалог: по умолчанию «с поправкой», переключатель и предпросмотр',
    (tester) async {
      PlanInputChoice? result;
      final previews = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showPlanInputDialog(
                    context,
                    previewFor: (mode, stopsMin) {
                      final text = '${mode.name} $stopsMin';
                      previews.add(text);
                      return text;
                    },
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Как введён темп?'), findsOneWidget);
      expect(find.text('withAdjustment 0'), findsOneWidget);

      // Переключаем на «плоские».
      await tester.tap(find.text('Плоские данные'));
      await tester.pumpAndSettle();
      expect(find.text('flatData 0'), findsOneWidget);
      await tester.tap(find.text('Уже с поправкой на высоты'));
      await tester.pumpAndSettle();

      // Меняем стоянки.
      await tester.enterText(
        find.byKey(const ValueKey('plan-input-stops')),
        '45',
      );
      await tester.pumpAndSettle();
      expect(find.text('withAdjustment 45'), findsOneWidget);

      await tester.tap(find.text('Пересчитать'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.mode, PlanInputMode.withAdjustment);
      expect(result!.stopsMin, 45);
    },
  );

  testWidgets('отмена возвращает null', (tester) async {
    PlanInputChoice? result = const PlanInputChoice(
      mode: PlanInputMode.flatData,
      stopsMin: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showPlanInputDialog(
                  context,
                  previewFor: (_, _) => '',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
