import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/pace/environment_data.dart';
import 'package:ultra_run_calc/features/pace/environment_sampling.dart';
import 'package:ultra_run_calc/features/pace/factor_profile.dart';
import 'package:ultra_run_calc/features/pace/weather_fallback_provider.dart';
import 'package:ultra_run_calc/features/pace/weather_provider.dart';

class _FailingWeather implements WeatherProvider {
  int calls = 0;

  @override
  Future<WeatherFetchResult> fetch({
    required List<WeatherQuery> queries,
    required FactorProfile profile,
  }) async {
    calls++;
    throw const WeatherException('Open-Meteo недоступен');
  }
}

class _EmptyWeather implements WeatherProvider {
  int calls = 0;

  @override
  Future<WeatherFetchResult> fetch({
    required List<WeatherQuery> queries,
    required FactorProfile profile,
  }) async {
    calls++;
    return const WeatherFetchResult(
      samples: [],
      mode: WeatherMode.historical,
      hasWeatherBand: false,
    );
  }
}

class _FakeWeather implements WeatherProvider {
  _FakeWeather(this.mode);

  final WeatherMode mode;
  int calls = 0;

  @override
  Future<WeatherFetchResult> fetch({
    required List<WeatherQuery> queries,
    required FactorProfile profile,
  }) async {
    calls++;
    return WeatherFetchResult(
      samples: [
        WeatherSample(
          distanceM: queries.first.point.distanceM,
          timeUtc: queries.first.timeUtc,
          lat: queries.first.point.lat,
          lon: queries.first.point.lon,
          elevationM: queries.first.point.elevationM,
          tempC: 12,
          apparentC: 12,
          humidityPct: 70,
          precipMm: 0,
          rainMm: 0,
          et0Mm: 0,
          windKmh: 0,
          snowfallCm: 0,
          snowDepthM: 0,
          soilMoistureTop: 0.3,
          soilMoistureDeep: 0.3,
          soilMoistureEff: 0.3,
          freezingLevelM: 2000,
          mode: mode,
          avgTemp5C: 12,
          frozenDays: 0,
        ),
      ],
      mode: mode,
      hasWeatherBand: mode != WeatherMode.normals,
    );
  }
}

WeatherQuery _query(DateTime time) => WeatherQuery(
  point: const WeatherSamplePoint(
    index: 0,
    distanceM: 1000,
    lat: 56,
    lon: 40,
    elevationM: 120,
  ),
  timeUtc: time,
);

void main() {
  final now = DateTime.utc(2026, 7, 24);

  test('история: при ошибке Open-Meteo используется NASA POWER', () async {
    final primary = _FailingWeather();
    final fallback = _FakeWeather(WeatherMode.historical);
    final provider = FallbackWeatherProvider(
      primary: primary,
      fallback: fallback,
      now: () => now,
    );

    final result = await provider.fetch(
      queries: [_query(DateTime.utc(2025, 7, 24))],
      profile: FactorProfile.defaults(),
    );

    expect(primary.calls, 1);
    expect(fallback.calls, 1);
    expect(result.samples, hasLength(1));
    expect(result.warning, contains('NASA POWER'));
  });

  test('прогноз: резервный источник не используется', () async {
    final primary = _FailingWeather();
    final fallback = _FakeWeather(WeatherMode.forecast);
    final provider = FallbackWeatherProvider(
      primary: primary,
      fallback: fallback,
      now: () => now,
    );

    await expectLater(
      provider.fetch(
        queries: [_query(DateTime.utc(2026, 7, 25))],
        profile: FactorProfile.defaults(),
      ),
      throwsA(isA<WeatherException>()),
    );
    expect(fallback.calls, 0);
  });

  test('нормы: пустой ответ Open-Meteo тоже уходит в резерв', () async {
    final primary = _EmptyWeather();
    final fallback = _FakeWeather(WeatherMode.normals);
    final provider = FallbackWeatherProvider(
      primary: primary,
      fallback: fallback,
      now: () => now,
    );

    final result = await provider.fetch(
      queries: [_query(DateTime.utc(2026, 9, 15))],
      profile: FactorProfile.defaults(),
    );

    expect(primary.calls, 1);
    expect(fallback.calls, 1);
    expect(result.mode, WeatherMode.normals);
    expect(result.hasWeatherBand, isFalse);
  });

  test('основной источник ответил — резерв не вызывается', () async {
    final primary = _FakeWeather(WeatherMode.historical);
    final fallback = _FailingWeather();
    final provider = FallbackWeatherProvider(
      primary: primary,
      fallback: fallback,
      now: () => now,
    );

    final result = await provider.fetch(
      queries: [_query(DateTime.utc(2025, 7, 24))],
      profile: FactorProfile.defaults(),
    );

    expect(primary.calls, 1);
    expect(fallback.calls, 0);
    expect(result.samples, hasLength(1));
  });
}
