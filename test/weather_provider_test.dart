import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ultra_run_calc/features/pace/environment_data.dart';
import 'package:ultra_run_calc/features/pace/environment_sampling.dart';
import 'package:ultra_run_calc/features/pace/factor_profile.dart';
import 'package:ultra_run_calc/features/pace/weather_provider.dart';

WeatherQuery _query(DateTime time) => WeatherQuery(
  point: const WeatherSamplePoint(
    index: 0,
    distanceM: 1234,
    lat: 56.5,
    lon: 40.2,
    elevationM: 180,
  ),
  timeUtc: time,
);

/// Ответ Open-Meteo с одной точкой и одним часом.
http.Client _mockClient(
  void Function(Uri uri)? onRequest, {
  String time = '2026-07-24T04:00',
}) {
  return MockClient((request) async {
    onRequest?.call(request.url);
    final item = {
      'hourly': {
        'time': [time],
        'temperature_2m': [12.0],
        'apparent_temperature': [11.0],
        'relative_humidity_2m': [80.0],
        'precipitation': [0.0],
        'rain': [0.0],
        'snowfall': [0.0],
        'wind_speed_10m': [5.0],
        'snow_depth': [0.0],
        'soil_moisture_0_to_7cm': [0.3],
        'soil_moisture_7_to_28cm': [0.3],
        'et0_fao_evapotranspiration': [0.0],
        'freezing_level_height': [3000.0],
      },
    };
    return http.Response(jsonEncode([item]), 200);
  });
}

void main() {
  group('beyondForecastWindow', () {
    final now = DateTime(2026, 7, 20, 23, 59);

    test('today and the 16th day are still a forecast', () {
      expect(beyondForecastWindow(DateTime(2026, 7, 20), now: now), isFalse);
      expect(beyondForecastWindow(DateTime(2026, 8, 5), now: now), isFalse);
      expect(
        beyondForecastWindow(DateTime(2026, 8, 5, 23, 59), now: now),
        isFalse,
      );
    });

    test('the 17th day is beyond the forecast', () {
      expect(beyondForecastWindow(DateTime(2026, 8, 6), now: now), isTrue);
    });

    test('past dates are never beyond the forecast', () {
      expect(beyondForecastWindow(DateTime(2026, 7, 1), now: now), isFalse);
    });
  });

  group('OpenMeteoProvider', () {
    final profile = FactorProfile.defaults();

    test('a near start uses the forecast host', () async {
      Uri? requested;
      final provider = OpenMeteoProvider(
        client: _mockClient((uri) => requested = uri),
        now: () => DateTime.utc(2026, 7, 20, 12),
      );

      final result = await provider.fetch(
        queries: [_query(DateTime.utc(2026, 7, 24, 4, 7))],
        profile: profile,
      );

      expect(result.mode, WeatherMode.forecast);
      expect(result.hasWeatherBand, isTrue);
      expect(result.samples, hasLength(1));
      expect(result.samples.first.distanceM, 1234);
      expect(result.samples.first.tempC, 12);
      expect(requested!.host, 'api.open-meteo.com');
      expect(requested!.path, '/v1/forecast');
      expect(requested!.queryParameters['start_date'], '2026-07-20');
      expect(requested!.queryParameters['end_date'], '2026-07-25');
    });

    test('the 16th day still uses the forecast host', () async {
      Uri? requested;
      final provider = OpenMeteoProvider(
        client: _mockClient((uri) => requested = uri),
        now: () => DateTime.utc(2026, 7, 20, 12),
      );

      final result = await provider.fetch(
        queries: [_query(DateTime.utc(2026, 8, 5, 23))],
        profile: profile,
      );

      expect(result.mode, WeatherMode.forecast);
      expect(requested!.path, '/v1/forecast');
    });

    test('a far start shifts one year back and hides the band', () async {
      Uri? requested;
      final provider = OpenMeteoProvider(
        client: _mockClient((uri) => requested = uri, time: '2025-08-20T04:00'),
        now: () => DateTime.utc(2026, 7, 20, 12),
      );

      final result = await provider.fetch(
        queries: [_query(DateTime.utc(2026, 8, 20, 4))],
        profile: profile,
      );

      expect(result.mode, WeatherMode.normals);
      expect(result.hasWeatherBand, isFalse);
      expect(result.warning, contains('нормы'));
      expect(requested!.path, '/v1/archive');
      expect(requested!.queryParameters['start_date'], '2025-08-16');
      expect(requested!.queryParameters['end_date'], '2025-08-21');
      // Нормы относятся к запрошенной дате, а не к прошлогодней.
      expect(result.samples.first.timeUtc, DateTime.utc(2026, 8, 20, 4));
    });

    test('a past start uses the archive and keeps the band', () async {
      Uri? requested;
      final provider = OpenMeteoProvider(
        client: _mockClient((uri) => requested = uri, time: '2026-07-10T04:00'),
        now: () => DateTime.utc(2026, 7, 20, 12),
      );

      final result = await provider.fetch(
        queries: [_query(DateTime.utc(2026, 7, 10, 4))],
        profile: profile,
      );

      expect(result.mode, WeatherMode.historical);
      expect(result.hasWeatherBand, isTrue);
      expect(requested!.path, '/v1/archive');
      expect(requested!.queryParameters['start_date'], '2026-07-06');
    });

    test('a non-200 response throws WeatherException', () async {
      final provider = OpenMeteoProvider(
        client: MockClient((_) async => http.Response('nope', 500)),
        now: () => DateTime.utc(2026, 7, 20, 12),
      );

      expect(
        () => provider.fetch(
          queries: [_query(DateTime.utc(2026, 7, 24, 4))],
          profile: profile,
        ),
        throwsA(isA<WeatherException>()),
      );
    });
  });
}
