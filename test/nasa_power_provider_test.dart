import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ultra_run_calc/features/pace/environment_data.dart';
import 'package:ultra_run_calc/features/pace/environment_sampling.dart';
import 'package:ultra_run_calc/features/pace/factor_profile.dart';
import 'package:ultra_run_calc/features/pace/nasa_power_provider.dart';
import 'package:ultra_run_calc/features/pace/weather_provider.dart';

WeatherQuery _query(DateTime time) => WeatherQuery(
  point: const WeatherSamplePoint(
    index: 0,
    distanceM: 1200,
    lat: 56.43,
    lon: 40.42,
    elevationM: 130,
  ),
  timeUtc: time,
);

String _dailyBody() => jsonEncode({
  'properties': {
    'parameter': {
      'T2M': {'20260722': 16.0, '20260723': -1.5, '20260724': 18.5},
      'RH2M': {'20260724': 82.0},
      'WS2M': {'20260724': 3.0},
      'PRECTOTCORR': {'20260724': 2.4},
      'GWETTOP': {'20260724': 0.41},
      'GWETROOT': {'20260724': 0.37},
    },
  },
});

String _climatologyBody() => jsonEncode({
  'properties': {
    'parameter': {
      'T2M': {'JUL': 19.1, 'SEP': 11.4},
      'RH2M': {'JUL': 79.6, 'SEP': 82.7},
      'WS2M': {'JUL': 2.5, 'SEP': 3.1},
      'PRECTOTCORR': {'JUL': 2.4, 'SEP': 2.0},
      'GWETTOP': {'JUL': 0.65, 'SEP': 0.60},
      'GWETROOT': {'JUL': 0.61, 'SEP': 0.58},
    },
  },
});

void main() {
  test('историческая погода: суточные данные и средние за 5 дней', () async {
    late Uri requested;
    final provider = NasaPowerProvider(
      now: () => DateTime.utc(2026, 7, 30),
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(_dailyBody(), 200);
      }),
    );

    final result = await provider.fetch(
      queries: [_query(DateTime.utc(2026, 7, 24, 9))],
      profile: FactorProfile.defaults(),
    );

    expect(requested.path, contains('/temporal/daily/point'));
    expect(requested.queryParameters['start'], '20260718');
    expect(requested.queryParameters['end'], '20260724');
    expect(result.mode, WeatherMode.historical);
    expect(result.hasWeatherBand, isTrue);
    final sample = result.samples.single;
    expect(sample.tempC, 18.5);
    // Среднее по 22–24 июля: (16.0 − 1.5 + 18.5) / 3.
    expect(sample.avgTemp5C, closeTo(11.0, 0.001));
    expect(sample.frozenDays, 1);
    expect(sample.humidityPct, 82);
    expect(sample.windKmh, closeTo(10.8, 0.001));
    expect(sample.precipMm, 2.4);
    expect(sample.soilMoistureTop, 0.41);
    expect(sample.soilMoistureEff, closeTo(0.39, 0.001));
    expect(sample.freezingLevelM, greaterThan(130));
    expect(result.warning, contains('NASA POWER'));
  });

  test(
    'климатические нормы: месячное значение и нет полосы прогноза',
    () async {
      late Uri requested;
      final provider = NasaPowerProvider(
        now: () => DateTime.utc(2026, 7, 24),
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(_climatologyBody(), 200);
        }),
      );

      final result = await provider.fetch(
        queries: [_query(DateTime.utc(2026, 9, 15, 9))],
        profile: FactorProfile.defaults(),
      );

      expect(requested.path, contains('/temporal/climatology/point'));
      expect(result.mode, WeatherMode.normals);
      expect(result.hasWeatherBand, isFalse);
      expect(result.samples.single.tempC, 11.4);
      expect(result.samples.single.soilMoistureTop, 0.60);
    },
  );

  test('прогноз не подменяется климатологией', () async {
    var calls = 0;
    final provider = NasaPowerProvider(
      now: () => DateTime.utc(2026, 7, 24),
      client: MockClient((_) async {
        calls++;
        return http.Response(_dailyBody(), 200);
      }),
    );

    await expectLater(
      provider.fetch(
        queries: [_query(DateTime.utc(2026, 7, 25, 9))],
        profile: FactorProfile.defaults(),
      ),
      throwsA(isA<WeatherException>()),
    );
    expect(calls, 0);
  });
}
