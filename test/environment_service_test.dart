import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/gpx_track.dart';
import 'package:ultra_run_calc/features/gpx/parsed_track.dart';
import 'package:ultra_run_calc/features/gpx/track_metrics.dart';
import 'package:ultra_run_calc/features/pace/environment_data.dart';
import 'package:ultra_run_calc/features/pace/environment_sampling.dart';
import 'package:ultra_run_calc/features/pace/environment_service.dart';
import 'package:ultra_run_calc/features/pace/factor_profile.dart';
import 'package:ultra_run_calc/features/pace/osm_provider.dart';
import 'package:ultra_run_calc/features/pace/weather_provider.dart';

ParsedTrack _track({int points = 10}) {
  final lats = Float64List(points);
  final lons = Float64List(points);
  final eles = Float64List(points);
  for (var i = 0; i < points; i++) {
    lats[i] = 56.0 + i * 0.001;
    lons[i] = 40.0;
    eles[i] = 150 + i.toDouble();
  }
  final track = GpxTrack(
    lats: lats,
    lons: lons,
    eles: eles,
    segmentStarts: const [0],
    waypoints: const [],
    droppedPoints: 0,
  );
  final metrics = computeTrackMetrics(track);
  final whole = computeSegments(metrics, [0, metrics.totalDistance2d]).single;
  return ParsedTrack(
    track: track,
    metrics: metrics,
    candidates: const [],
    totalAscentM: whole.ascentM,
    totalDescentM: whole.descentM,
  );
}

/// OSM, который рисует грунтовую тропу прямо по точкам трека.
class _TrackOsm implements OsmProvider {
  const _TrackOsm();

  @override
  Future<OsmData> fetch({required List<TrackSamplePoint> points}) async {
    return OsmData(
      features: [
        OsmFeature(
          id: 1,
          tags: const {'highway': 'path', 'surface': 'dirt'},
          geometry: [
            for (final point in points) OsmPoint(point.lat, point.lon),
          ],
        ),
      ],
    );
  }
}

class _FailingOsm implements OsmProvider {
  const _FailingOsm();

  @override
  Future<OsmData> fetch({required List<TrackSamplePoint> points}) async {
    throw const OsmException('нет сети');
  }
}

class _FakeWeather implements WeatherProvider {
  const _FakeWeather({
    this.samples = const [],
    this.mode = WeatherMode.historical,
    this.hasWeatherBand = true,
  });

  final List<WeatherSample> samples;
  final WeatherMode mode;
  final bool hasWeatherBand;

  @override
  Future<WeatherFetchResult> fetch({
    required List<WeatherQuery> queries,
    required FactorProfile profile,
  }) async {
    return WeatherFetchResult(
      samples: samples,
      mode: mode,
      hasWeatherBand: hasWeatherBand,
    );
  }
}

class _FailingWeather implements WeatherProvider {
  const _FailingWeather();

  @override
  Future<WeatherFetchResult> fetch({
    required List<WeatherQuery> queries,
    required FactorProfile profile,
  }) async {
    throw const WeatherException('нет сети');
  }
}

/// Считает вызовы Overpass: кэш должен схлопнуть повторный расчёт.
class _CountingOsm implements OsmProvider {
  int calls = 0;

  @override
  Future<OsmData> fetch({required List<TrackSamplePoint> points}) async {
    calls++;
    return OsmData(
      features: [
        OsmFeature(
          id: 1,
          tags: const {'highway': 'path', 'surface': 'dirt'},
          geometry: [
            for (final point in points) OsmPoint(point.lat, point.lon),
          ],
        ),
      ],
    );
  }
}

/// Запоминает запросы погоды, чтобы проверить времена прибытия.
class _RecordingWeather implements WeatherProvider {
  _RecordingWeather(this.samples);

  final List<WeatherSample> samples;
  List<WeatherQuery> queries = const [];

  @override
  Future<WeatherFetchResult> fetch({
    required List<WeatherQuery> queries,
    required FactorProfile profile,
  }) async {
    this.queries = queries;
    return WeatherFetchResult(
      samples: samples,
      mode: WeatherMode.historical,
      hasWeatherBand: true,
    );
  }
}

WeatherSample _sample({
  double temp = 15,
  double apparent = 15,
  double soil = 0.45,
  double snowDepth = 0,
  double snowfall = 0,
  WeatherMode mode = WeatherMode.historical,
}) {
  return WeatherSample(
    distanceM: 0,
    timeUtc: DateTime.utc(2026, 7, 24, 4, 7),
    lat: 56,
    lon: 40,
    elevationM: 150,
    tempC: temp,
    apparentC: apparent,
    humidityPct: 70,
    precipMm: 0,
    rainMm: 0,
    et0Mm: 0,
    windKmh: 5,
    snowfallCm: snowfall,
    snowDepthM: snowDepth,
    soilMoistureTop: soil,
    soilMoistureDeep: soil,
    soilMoistureEff: soil,
    freezingLevelM: 3000,
    mode: mode,
  );
}

void main() {
  final profile = FactorProfile.defaults();

  test('surface only: dirt is 1.10, no weather band', () async {
    final data =
        await EnvironmentService(
          osm: const _TrackOsm(),
          weather: const _FakeWeather(),
        ).compute(
          parsed: _track(),
          settings: const EnvironmentSettings(surfaceEnabled: true),
          profile: profile,
          flatPaceSecPerKm: 360,
        );

    expect(data.surface, isNotEmpty);
    expect(data.surface.every((run) => run.type == SurfaceType.dirt), isTrue);
    expect(data.surface.first.factor, closeTo(1.10, 0.001));
    expect(data.surface.first.wetness, Wetness.dry);
    expect(data.hasForecast, isFalse);
    expect(data.surfaceCoverage, closeTo(1.0, 0.001));
  });

  test('saturated dirt becomes mud and adds the road shoe factor', () async {
    final data =
        await EnvironmentService(
          osm: const _TrackOsm(),
          weather: _FakeWeather(samples: [_sample(soil: 0.45)]),
        ).compute(
          parsed: _track(),
          settings: EnvironmentSettings(
            surfaceEnabled: true,
            weatherEnabled: true,
            shoesEnabled: true,
            shoe: ShoeKind.road,
            startUtc: DateTime.utc(2026, 7, 24, 4, 7),
          ),
          profile: profile,
          flatPaceSecPerKm: 360,
        );

    final run = data.surface.first;
    expect(run.wetness, Wetness.saturated);
    expect(run.type, SurfaceType.mud);
    expect(run.shoeFactor, closeTo(1.35, 0.001));
    // 1.45 × 1.20 × 1.35 выходит за верхний предел и зажимается в 2.00.
    expect(run.factor, closeTo(2.0, 0.001));
  });

  test('heat uses apparent temperature', () async {
    final hot =
        await EnvironmentService(
          osm: const _TrackOsm(),
          weather: _FakeWeather(samples: [_sample(apparent: 35)]),
        ).compute(
          parsed: _track(),
          settings: EnvironmentSettings(
            weatherEnabled: true,
            startUtc: DateTime.utc(2026, 7, 24, 4, 7),
          ),
          profile: profile,
          flatPaceSecPerKm: 360,
        );

    expect(hot.surface.first.heatFactor, closeTo(1.20, 0.001));
    expect(hot.hasForecast, isTrue);
  });

  test('normals hide the weather band', () async {
    final data =
        await EnvironmentService(
          osm: const _TrackOsm(),
          weather: _FakeWeather(
            samples: [_sample(mode: WeatherMode.normals)],
            mode: WeatherMode.normals,
            hasWeatherBand: false,
          ),
        ).compute(
          parsed: _track(),
          settings: EnvironmentSettings(
            weatherEnabled: true,
            startUtc: DateTime.utc(2030, 7, 24, 4, 7),
          ),
          profile: profile,
          flatPaceSecPerKm: 360,
        );

    expect(data.hasForecast, isFalse);
  });

  test('OSM failure falls back to dirt without throwing', () async {
    final data =
        await EnvironmentService(
          osm: const _FailingOsm(),
          weather: const _FakeWeather(),
        ).compute(
          parsed: _track(),
          settings: const EnvironmentSettings(surfaceEnabled: true),
          profile: profile,
          flatPaceSecPerKm: 360,
        );

    expect(data.surface, isNotEmpty);
    expect(data.surface.every((run) => run.type == SurfaceType.dirt), isTrue);
    expect(data.surfaceCoverage, 0);
    expect(data.warning, contains('OSM'));
  });

  test('weather failure keeps the surface factor and warns', () async {
    final data =
        await EnvironmentService(
          osm: const _TrackOsm(),
          weather: const _FailingWeather(),
        ).compute(
          parsed: _track(),
          settings: EnvironmentSettings(
            surfaceEnabled: true,
            weatherEnabled: true,
            startUtc: DateTime.utc(2026, 7, 24, 4, 7),
          ),
          profile: profile,
          flatPaceSecPerKm: 360,
        );

    expect(data.surface.first.factor, closeTo(1.10, 0.001));
    expect(data.hasForecast, isFalse);
    expect(data.warning, contains('Погода'));
  });

  test('weather without a start time is skipped with a warning', () async {
    final data =
        await EnvironmentService(
          osm: const _TrackOsm(),
          weather: _FakeWeather(samples: [_sample()]),
        ).compute(
          parsed: _track(),
          settings: const EnvironmentSettings(weatherEnabled: true),
          profile: profile,
          flatPaceSecPerKm: 360,
        );

    expect(data.weather, isEmpty);
    expect(data.hasForecast, isFalse);
    expect(data.warning, contains('время старта'));
  });

  test('factorBetween weights runs by length', () async {
    final data =
        await EnvironmentService(
          osm: const _TrackOsm(),
          weather: _FakeWeather(samples: [_sample(soil: 0.45)]),
        ).compute(
          parsed: _track(),
          settings: const EnvironmentSettings(surfaceEnabled: true),
          profile: profile,
          flatPaceSecPerKm: 360,
        );

    final total = data.surface.last.endM;
    expect(
      data.factorBetween(0, total),
      closeTo(data.surface.first.factor, 0.001),
    );
    expect(data.factorAt(total / 2), closeTo(data.surface.first.factor, 0.001));
  });

  test('movingSecAt sets the weather time for each sample point', () async {
    final start = DateTime.utc(2026, 7, 24, 4, 7);
    final weather = _RecordingWeather([_sample()]);
    await EnvironmentService(osm: const _TrackOsm(), weather: weather).compute(
      parsed: _track(),
      settings: EnvironmentSettings(weatherEnabled: true, startUtc: start),
      profile: profile,
      flatPaceSecPerKm: 360,
      movingSecAt: (distanceM) => 100 + distanceM / 10,
    );

    expect(weather.queries, isNotEmpty);
    for (final query in weather.queries) {
      expect(
        query.timeUtc,
        start.add(
          Duration(seconds: (100 + query.point.distanceM / 10).round()),
        ),
      );
    }
  });

  test('OSM is fetched once and reused for the same track', () async {
    final osm = _CountingOsm();
    final service = EnvironmentService(osm: osm, weather: const _FakeWeather());
    final parsed = _track();

    await service.compute(
      parsed: parsed,
      settings: const EnvironmentSettings(surfaceEnabled: true),
      profile: profile,
      flatPaceSecPerKm: 360,
    );
    await service.compute(
      parsed: parsed,
      settings: const EnvironmentSettings(surfaceEnabled: true),
      profile: profile,
      flatPaceSecPerKm: 360,
    );

    expect(osm.calls, 1);
  });
}
