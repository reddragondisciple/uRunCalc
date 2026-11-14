import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/pace/environment_data.dart';
import 'package:ultra_run_calc/features/pace/factor_profile.dart';
import 'package:ultra_run_calc/features/pace/factor_profile_screen.dart';

void main() {
  testWidgets('editor saves an edited coefficient', (tester) async {
    final profile = FactorProfile.defaults();
    FactorProfile? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('open'),
                onPressed: () async {
                  saved = await Navigator.of(context).push<FactorProfile>(
                    MaterialPageRoute(
                      builder: (_) => FactorProfileScreen(profile: profile),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('factor-surface-dirt'));
    expect(field, findsOneWidget);
    await tester.enterText(field, '1.25');
    await tester.tap(find.byKey(const ValueKey('factors-save')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.surface[SurfaceType.dirt], 1.25);
    // Остальные коэффициенты сохраняются без изменений.
    expect(saved!.surface[SurfaceType.asphalt], 1.00);
  });

  testWidgets('reset restores default coefficients', (tester) async {
    final profile = FactorProfile.defaults();
    FactorProfile? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('open'),
                onPressed: () async {
                  saved = await Navigator.of(context).push<FactorProfile>(
                    MaterialPageRoute(
                      builder: (_) => FactorProfileScreen(profile: profile),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('factor-surface-dirt'));
    await tester.enterText(field, '1.60');
    await tester.tap(find.byKey(const ValueKey('factors-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('factors-save')));
    await tester.pumpAndSettle();

    expect(saved!.surface[SurfaceType.dirt], 1.10);
  });
}
