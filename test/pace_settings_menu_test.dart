import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/core/app_strings.dart';
import 'package:ultra_run_calc/features/pace/pace_settings_menu.dart';

Future<void> _pumpMenu(
  WidgetTester tester, {
  required PaceSettingsState state,
  required PaceSettingsActions actions,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('open-menu'),
              onPressed: () => PaceSettingsMenu.show(
                context,
                state: state,
                actions: actions,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-menu')));
  await tester.pumpAndSettle();
}

PaceSettingsActions _actions({
  VoidCallback? onSurface,
  VoidCallback? onWeather,
  VoidCallback? onShoes,
  VoidCallback? onFactors,
}) {
  return PaceSettingsActions(
    onColumns: () async {},
    onMountainChanged: (_) {},
    onImportGpx: () async {},
    onTrackSlot: () async {},
    onStopsModeChanged: (_) {},
    onSurface: () async {
      onSurface?.call();
    },
    onWeather: () async {
      onWeather?.call();
    },
    onShoes: () async {
      onShoes?.call();
    },
    onFactors: () async {
      onFactors?.call();
    },
  );
}

void main() {
  const state = PaceSettingsState(
    mountainMode: false,
    showStopsInPace: false,
    activeSlotLabel: 'Основной',
  );

  testWidgets('shows the three environment checkboxes unchecked', (
    tester,
  ) async {
    await _pumpMenu(tester, state: state, actions: _actions());

    expect(find.text(AppStrings.paceSettingsSurface), findsOneWidget);
    expect(find.text(AppStrings.paceSettingsWeather), findsOneWidget);
    expect(find.text(AppStrings.paceSettingsShoes), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsWidgets);
    expect(find.byIcon(Icons.check_box), findsNothing);
  });

  testWidgets('checked state comes from the table settings', (tester) async {
    await _pumpMenu(
      tester,
      state: const PaceSettingsState(
        mountainMode: false,
        showStopsInPace: false,
        activeSlotLabel: 'Основной',
        surfaceEnabled: true,
        weatherEnabled: true,
        shoesEnabled: true,
      ),
      actions: _actions(),
    );

    expect(find.byIcon(Icons.check_box), findsNWidgets(3));
  });

  testWidgets('tapping a checkbox calls its dialog action', (tester) async {
    var surface = false;
    var weather = false;
    var shoes = false;
    await _pumpMenu(
      tester,
      state: state,
      actions: _actions(
        onSurface: () => surface = true,
        onWeather: () => weather = true,
        onShoes: () => shoes = true,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('pace-settings-surface')));
    await tester.pumpAndSettle();
    expect(surface, isTrue);

    await tester.tap(find.byKey(const ValueKey('open-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pace-settings-weather')));
    await tester.pumpAndSettle();
    expect(weather, isTrue);

    await tester.tap(find.byKey(const ValueKey('open-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pace-settings-shoes')));
    await tester.pumpAndSettle();
    expect(shoes, isTrue);
  });

  testWidgets('coefficient editor opens from the gear menu', (tester) async {
    var factors = false;
    await _pumpMenu(
      tester,
      state: state,
      actions: _actions(onFactors: () => factors = true),
    );

    expect(find.text(AppStrings.paceSettingsFactors), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pace-settings-factors')));
    await tester.pumpAndSettle();

    expect(factors, isTrue);
  });
}
