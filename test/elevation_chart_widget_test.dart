import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/core/app_strings.dart';
import 'package:ultra_run_calc/features/gpx/elevation_profile.dart';
import 'package:ultra_run_calc/features/pace/elevation_chart_view.dart';

/// Профиль 0–20 км: подъём, плато, спуск.
ElevationChartData _data() {
  final profile = <ProfilePoint>[
    for (var i = 0; i <= 40; i++)
      ProfilePoint(km: i * 0.5, eleM: 100 + i * 10.0, gradeFraction: 0.05),
  ];
  return ElevationChartData(
    profile: profile,
    markers: const [
      ElevationMarker(km: 0, label: 'Старт'),
      ElevationMarker(km: 10, label: 'CP1'),
      ElevationMarker(km: 20, label: 'Финиш'),
    ],
    totalAscentM: 400,
    totalDescentM: 0,
    boundariesKm: const [0, 10, 20],
  );
}

/// Экран с кнопкой, которая открывает карту с данными [data].
Future<void> _pumpHost(
  WidgetTester tester, {
  required Size size,
  required ElevationChartData data,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const ValueKey('open'),
              onPressed: () => showElevationChart(context, data),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
}

void main() {
  const portrait = Size(390, 844);
  const landscape = Size(844, 390);

  group('портрет (bottom sheet)', () {
    testWidgets('открывается bottom sheet с заголовком и холстом профиля', (
      tester,
    ) async {
      await _pumpHost(tester, size: portrait, data: _data());

      expect(find.text(AppStrings.elevationChartTitle), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('закрывается крестиком', (tester) async {
      await _pumpHost(tester, size: portrait, data: _data());

      await tester.tap(find.byKey(const ValueKey('elevation-chart-close')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.elevationChartTitle), findsNothing);
    });

    testWidgets('закрывается свайпом вниз', (tester) async {
      await _pumpHost(tester, size: portrait, data: _data());

      await tester.drag(
        find.text(AppStrings.elevationChartTitle),
        const Offset(0, 600),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.elevationChartTitle), findsNothing);
    });

    testWidgets('закрывается системной кнопкой «назад»', (tester) async {
      await _pumpHost(tester, size: portrait, data: _data());

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.maybePop();
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.elevationChartTitle), findsNothing);
    });

    testWidgets('без данных показывает «нет данных о высоте»', (tester) async {
      const empty = ElevationChartData(
        profile: [],
        markers: [],
        totalAscentM: 0,
        totalDescentM: 0,
        boundariesKm: [],
      );
      await _pumpHost(tester, size: portrait, data: empty);

      expect(find.text(AppStrings.elevationChartNoData), findsOneWidget);
    });
  });

  group('ландшафт (полноэкранный профиль)', () {
    testWidgets('открывается полноэкранно с заголовком', (tester) async {
      await _pumpHost(tester, size: landscape, data: _data());

      expect(find.text(AppStrings.elevationChartTitle), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('закрывается крестиком', (tester) async {
      await _pumpHost(tester, size: landscape, data: _data());

      await tester.tap(find.byKey(const ValueKey('elevation-chart-close')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.elevationChartTitle), findsNothing);
    });

    testWidgets('закрывается свайпом вниз', (tester) async {
      await _pumpHost(tester, size: landscape, data: _data());

      await tester.fling(
        find.text(AppStrings.elevationChartTitle),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.elevationChartTitle), findsNothing);
    });

    testWidgets('закрывается системной кнопкой «назад»', (tester) async {
      await _pumpHost(tester, size: landscape, data: _data());

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.maybePop();
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.elevationChartTitle), findsNothing);
    });
  });

  group('жесты карты (тап — подсказка, фокус — двойной тап / «Сегмент»)', () {
    Finder canvas() => find.byKey(const ValueKey('elevation-chart-canvas'));

    // Одиночный тап отдаётся только после окна двойного тапа.
    Future<void> settleTap(WidgetTester tester) =>
        tester.pump(const Duration(milliseconds: 400));

    Offset at(WidgetTester tester, double fx) =>
        tester.getTopLeft(canvas()) +
        Offset(
          tester.getSize(canvas()).width * fx,
          tester.getSize(canvas()).height / 2,
        );

    testWidgets('тап показывает подсказку с км, высотой и уклоном', (
      tester,
    ) async {
      await _pumpHost(tester, size: portrait, data: _data());

      await tester.tapAt(at(tester, 0.5));
      await settleTap(tester);

      expect(
        find.byKey(const ValueKey('elevation-chart-touch')),
        findsOneWidget,
      );
    });

    testWidgets('двойной тап фокусирует сегмент и показывает чип сброса', (
      tester,
    ) async {
      await _pumpHost(tester, size: portrait, data: _data());
      expect(find.byKey(const ValueKey('elevation-chart-reset')), findsNothing);

      final p = at(tester, 0.25); // ~5 км, сегмент 0–10
      await tester.tapAt(p);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(p);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('elevation-chart-reset')),
        findsOneWidget,
      );
    });

    testWidgets('кнопка «Сегмент» фокусирует сегмент по последнему тапу', (
      tester,
    ) async {
      await _pumpHost(tester, size: portrait, data: _data());
      final button = find.byKey(const ValueKey('elevation-chart-segment'));
      expect(tester.widget<TextButton>(button).onPressed, isNull);

      await tester.tapAt(at(tester, 0.75));
      await settleTap(tester);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('elevation-chart-reset')),
        findsOneWidget,
      );
    });

    testWidgets('чип «← вся дистанция» возвращает весь трек', (tester) async {
      await _pumpHost(tester, size: portrait, data: _data());

      final p = at(tester, 0.75);
      await tester.tapAt(p);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(p);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('elevation-chart-reset')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('elevation-chart-reset')), findsNothing);
    });
  });
}
