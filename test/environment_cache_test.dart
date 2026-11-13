import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ultra_run_calc/features/pace/environment_cache.dart';
import 'package:ultra_run_calc/features/pace/environment_data.dart';

EnvironmentData _data({
  EnvironmentSettings settings = const EnvironmentSettings(
    surfaceEnabled: true,
  ),
}) {
  return EnvironmentData(
    settings: settings,
    weather: [
      WeatherSample(
        distanceM: 1200,
        timeUtc: DateTime.utc(2026, 7, 24, 4),
        lat: 56,
        lon: 40,
        elevationM: 180,
        tempC: 14.5,
        apparentC: 13.2,
        humidityPct: 81,
        precipMm: 0.2,
        rainMm: 0.2,
        et0Mm: 0.1,
        windKmh: 7,
        snowfallCm: 0,
        snowDepthM: 0,
        soilMoistureTop: 0.31,
        soilMoistureDeep: 0.28,
        soilMoistureEff: 0.3,
        freezingLevelM: 2800,
        mode: WeatherMode.forecast,
        avgTemp5C: 17.5,
        frozenDays: 0,
      ),
    ],
    surface: const [
      SurfaceRun(
        startM: 0,
        endM: 5000,
        type: SurfaceType.asphalt,
        wetness: Wetness.dry,
        confidence: 1,
        surfaceSource: 'surface',
        roadClass: RoadClass.pavedMajor,
        factor: 1,
      ),
      SurfaceRun(
        startM: 5000,
        endM: 9000,
        type: SurfaceType.ground,
        wetness: Wetness.wet,
        confidence: 0.7,
        isBog: true,
        bogKind: 'wetland',
        bogFactor: 1.2,
        bogConfidence: 0.5,
        surfaceSource: 'worldcover',
        urbanity: 0.1,
        roadClass: RoadClass.footway,
        factor: 1.3,
        heatFactor: 1.02,
        snowFactor: 1,
        shoeFactor: 1.05,
      ),
    ],
    settlements: const [
      SettlementRun(
        startM: 0,
        endM: 9000,
        context: SettlementContext.village,
        urbanity: 0.4,
        confidence: 0.8,
      ),
    ],
    snow: const [
      SnowEstimate(
        startM: 5000,
        endM: 9000,
        effectiveDepthM: 0.02,
        probabilities: {SnowState.packed: 0.8, SnowState.loose: 0.2},
      ),
    ],
    fords: const [
      Ford(distanceM: 6500, confirmed: true, widthM: 3),
      Ford(distanceM: 7500, confirmed: false),
    ],
    surfaceCoverage: 0.92,
    rasterCoverage: 0.48,
    hasForecast: true,
    warning: 'Тестовое предупреждение',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('EnvironmentData JSON', () {
    test('переживает сохранение и чтение без потерь', () {
      final original = _data();
      final restored = EnvironmentData.tryFromJson(original.toJson());

      expect(restored, isNotNull);
      expect(restored!.settings, original.settings);
      expect(restored.surfaceCoverage, closeTo(0.92, 0.0001));
      expect(restored.rasterCoverage, closeTo(0.48, 0.0001));
      expect(restored.hasForecast, isTrue);
      expect(restored.warning, original.warning);
      expect(restored.weather, hasLength(1));
      expect(restored.weather.single.timeUtc, DateTime.utc(2026, 7, 24, 4));
      expect(restored.weather.single.mode, WeatherMode.forecast);
      expect(restored.weather.single.avgTemp5C, closeTo(17.5, 0.0001));
      expect(restored.surface, hasLength(2));
      expect(restored.surface.last.type, SurfaceType.ground);
      expect(restored.surface.last.wetness, Wetness.wet);
      expect(restored.surface.last.isBog, isTrue);
      expect(restored.surface.last.bogConfidence, closeTo(0.5, 0.0001));
      expect(restored.surface.last.roadClass, RoadClass.footway);
      expect(restored.settlements.single.context, SettlementContext.village);
      expect(restored.snow.single.probabilities[SnowState.packed], 0.8);
      expect(restored.fords, hasLength(2));
      expect(restored.fords.first.widthM, 3);
    });

    test('повреждённые данные возвращают null', () {
      expect(EnvironmentData.tryFromJson(null), isNull);
      expect(EnvironmentData.tryFromJson({}), isNull);
      expect(EnvironmentData.tryFromJson({'settings': 42}), isNull);
    });

    test('пустой результат не считается сохранённым', () {
      expect(
        EnvironmentData(
          settings: const EnvironmentSettings(surfaceEnabled: true),
        ).hasContent,
        isFalse,
      );
      expect(_data().hasContent, isTrue);
    });
  });

  test('настройки сравниваются по значению', () {
    const a = EnvironmentSettings(
      surfaceEnabled: true,
      weatherEnabled: true,
      startUtc: null,
      shoe: ShoeKind.trail,
    );
    const b = EnvironmentSettings(
      surfaceEnabled: true,
      weatherEnabled: true,
      shoe: ShoeKind.trail,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const EnvironmentSettings(surfaceEnabled: true)));
  });

  group('EnvironmentCacheStore', () {
    test(
      'хранит данные по ключу трека и читает их после перезапуска',
      () async {
        final store = EnvironmentCacheStore(storageKey: 'test_cache');
        await store.write('GRUT/T100/primary/primary.gpx/1', _data());

        final reopened = EnvironmentCacheStore(storageKey: 'test_cache');
        final restored = await reopened.read('GRUT/T100/primary/primary.gpx/1');

        expect(restored, isNotNull);
        expect(restored!.surface, hasLength(2));
        expect(restored.weather, hasLength(1));
      },
    );

    test('пустой результат не кэшируется', () async {
      final store = EnvironmentCacheStore(storageKey: 'test_cache');
      await store.write(
        'empty',
        EnvironmentData(
          settings: const EnvironmentSettings(surfaceEnabled: true),
        ),
      );

      expect(await store.read('empty'), isNull);
    });

    test('вытесняет самую старую запись сверх лимита', () async {
      final store = EnvironmentCacheStore(
        storageKey: 'test_cache',
        maxEntries: 1,
      );
      await store.write('first', _data());
      await store.write('second', _data());

      expect(await store.read('first'), isNull);
      expect(await store.read('second'), isNotNull);
    });

    test('повреждённый JSON не роняет чтение', () async {
      SharedPreferences.setMockInitialValues({
        'test_cache': jsonEncode({'version': 1, 'entries': 'oops'}),
      });
      final store = EnvironmentCacheStore(storageKey: 'test_cache');

      expect(await store.read('any'), isNull);
    });
  });
}
