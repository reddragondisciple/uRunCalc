import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/core/app_strings.dart';
import 'package:ultra_run_calc/features/gpx/elevation_profile.dart';
import 'package:ultra_run_calc/features/pace/elevation_chart_view.dart';
import 'package:ultra_run_calc/features/pace/environment_data.dart';

/// Профиль 0–20 км: подъём, плато, спуск.
ElevationChartData _data({EnvironmentData? environment}) {
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
    environment: environment,
  );
}

EnvironmentData _environment() {
  return EnvironmentData(
    settings: const EnvironmentSettings(
      surfaceEnabled: true,
      weatherEnabled: true,
    ),
    weather: [
      WeatherSample(
        distanceM: 0,
        timeUtc: DateTime.utc(2026, 7, 24, 4),
        lat: 56,
        lon: 40,
        elevationM: 100,
        tempC: 18,
        apparentC: 17,
        humidityPct: 70,
        precipMm: 0,
        rainMm: 0,
        et0Mm: 0,
        windKmh: 5,
        snowfallCm: 0,
        snowDepthM: 0,
        soilMoistureTop: 0.3,
        soilMoistureDeep: 0.3,
        soilMoistureEff: 0.3,
        freezingLevelM: 3000,
        mode: WeatherMode.historical,
      ),
      WeatherSample(
        distanceM: 10000,
        timeUtc: DateTime.utc(2026, 7, 24, 5),
        lat: 56.1,
        lon: 40,
        elevationM: 200,
        tempC: 26,
        apparentC: 29,
        humidityPct: 70,
        precipMm: 0,
        rainMm: 0,
        et0Mm: 0,
        windKmh: 5,
        snowfallCm: 0,
        snowDepthM: 0,
        soilMoistureTop: 0.45,
        soilMoistureDeep: 0.45,
        soilMoistureEff: 0.45,
        freezingLevelM: 3000,
        mode: WeatherMode.historical,
      ),
    ],
    surface: const [
      SurfaceRun(
        startM: 0,
        endM: 5000,
        type: SurfaceType.asphalt,
        wetness: Wetness.dry,
        confidence: 1,
        factor: 1.0,
      ),
      SurfaceRun(
        startM: 5000,
        endM: 15000,
        type: SurfaceType.dirt,
        wetness: Wetness.saturated,
        confidence: 1,
        factor: 1.5,
      ),
      SurfaceRun(
        startM: 15000,
        endM: 20000,
        type: SurfaceType.mud,
        wetness: Wetness.bog,
        confidence: 1,
        isBog: true,
        bogKind: 'bog',
        factor: 1.8,
      ),
    ],
    fords: const [
      Ford(distanceM: 7000, confirmed: true),
      Ford(distanceM: 12000, confirmed: false),
    ],
    surfaceCoverage: 0.5,
    hasForecast: true,
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

    testWidgets('тап добавляет тип покрытия в подсказку', (tester) async {
      await _pumpHost(
        tester,
        size: portrait,
        data: _data(environment: _environment()),
      );

      await tester.tapAt(at(tester, 0.5)); // 10 км — грунт
      await settleTap(tester);

      final tooltip = tester.widget<Text>(
        find.byKey(const ValueKey('elevation-chart-touch')),
      );
      expect(tooltip.data, contains('10.00 км'));
      expect(tooltip.data, contains('Грунт'));
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

  group('слои окружения', () {
    testWidgets('карта с покрытием, бродами и погодой рисуется без ошибок', (
      tester,
    ) async {
      await _pumpHost(
        tester,
        size: portrait,
        data: _data(environment: _environment()),
      );

      expect(find.text(AppStrings.elevationChartTitle), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('в окне карты есть расшифровка долей покрытия', (tester) async {
      await _pumpHost(
        tester,
        size: portrait,
        data: _data(environment: _environment()),
      );

      expect(
        find.byKey(const ValueKey('elevation-chart-surface-legend')),
        findsOneWidget,
      );
      expect(find.text('Асфальт 25%'), findsOneWidget);
      expect(find.text('Грунт 50%'), findsOneWidget);
      expect(find.text('Грязь 25%'), findsOneWidget);
    });

    testWidgets('без окружения расшифровки покрытия нет', (tester) async {
      await _pumpHost(tester, size: portrait, data: _data());

      expect(
        find.byKey(const ValueKey('elevation-chart-surface-legend')),
        findsNothing,
      );
    });

    test('доли покрытия взвешены по длине и отсортированы', () {
      const environment = EnvironmentData(
        settings: EnvironmentSettings(surfaceEnabled: true),
        surface: [
          SurfaceRun(
            startM: 0,
            endM: 2000,
            type: SurfaceType.asphalt,
            wetness: Wetness.dry,
            confidence: 1,
          ),
          SurfaceRun(
            startM: 2000,
            endM: 9000,
            type: SurfaceType.dirt,
            wetness: Wetness.dry,
            confidence: 1,
          ),
          SurfaceRun(
            startM: 9000,
            endM: 9990,
            type: SurfaceType.mud,
            wetness: Wetness.bog,
            confidence: 1,
          ),
          SurfaceRun(
            startM: 9990,
            endM: 10000,
            type: SurfaceType.snowPacked,
            wetness: Wetness.dry,
            confidence: 1,
          ),
        ],
      );

      final shares = surfaceShares(environment);

      expect(shares.map((share) => share.type), [
        SurfaceType.dirt,
        SurfaceType.asphalt,
        SurfaceType.mud,
        SurfaceType.snowPacked,
      ]);
      expect(shares[0].percent, closeTo(70, 0.001));
      expect(shares[1].percent, closeTo(20, 0.001));
      expect(shares[2].percent, closeTo(9.9, 0.001));
      expect(shares[3].percent, closeTo(0.1, 0.001));
      expect(formatSurfacePercent(shares[3].percent), '<1%');
    });

    test('пустое окружение не даёт долей покрытия', () {
      expect(surfaceShares(null), isEmpty);
      expect(
        surfaceShares(const EnvironmentData(settings: EnvironmentSettings())),
        isEmpty,
      );
    });

    test('у каждого типа покрытия есть подпись', () {
      for (final type in SurfaceType.values) {
        expect(surfaceTypeLabel(type), isNotEmpty);
        expect(surfaceOverlayColor(type), isA<Color>());
      }
    });

    test('проценты покрытия читаются без ложной точности', () {
      expect(formatSurfacePercent(0), '0%');
      expect(formatSurfacePercent(0.4), '<1%');
      expect(formatSurfacePercent(9.6), '10%');
      expect(formatSurfacePercent(50), '50%');
      expect(formatSurfacePercent(100), '100%');
    });

    test('цвета покрытия, мокрости и погоды заданы для всех значений', () {
      for (final wetness in Wetness.values) {
        expect(wetnessOverlayColor(wetness), isA<Color>());
      }
      for (final temp in [-20.0, -8.0, 0.0, 10.0, 20.0, 30.0, 40.0]) {
        expect(apparentTemperatureColor(temp), isA<Color>());
      }
      // Холод и жара различаются заметно.
      expect(
        apparentTemperatureColor(-15),
        isNot(apparentTemperatureColor(35)),
      );
    });
  });
}
