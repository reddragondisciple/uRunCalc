/// Сборка окружения: OSM + погода + множители.
///
/// Сервис не знает о Flutter: провайдеры можно подменить в тестах, а результат
/// [EnvironmentData] уже готов для плана и графика.
library;

import 'dart:math' as math;

import '../gpx/parsed_track.dart';
import 'environment_data.dart';
import 'environment_factors.dart';
import 'environment_sampling.dart';
import 'factor_profile.dart';
import 'osm_provider.dart';
import 'weather_provider.dart';

/// Считает покрытие, погоду, снег и итоговые множители для трека.
class EnvironmentService {
  EnvironmentService({OsmProvider? osm, WeatherProvider? weather})
    : _osm = osm ?? OverpassOsmProvider(),
      _weather = weather ?? OpenMeteoProvider();

  final OsmProvider _osm;
  final WeatherProvider _weather;

  /// OSM не зависит от времени и погоды: при итерациях погоды и повторном
  /// включении галочек запрашиваем Overpass один раз на трек.
  String? _osmCacheKey;
  OsmSurfaceResult? _osmCache;

  Future<EnvironmentData> compute({
    required ParsedTrack parsed,
    required EnvironmentSettings settings,
    required FactorProfile profile,
    required double flatPaceSecPerKm,
    double Function(double distanceM)? movingSecAt,
  }) async {
    if (!settings.anyEnabled) {
      return EnvironmentData(settings: settings);
    }
    if (parsed.track.length < 2) {
      return EnvironmentData(
        settings: settings,
        warning: 'В треке меньше двух точек',
      );
    }

    final surfacePoints = sampleTrackPoints(parsed);
    var warning = <String>[];

    final cacheKey = _pointsKey(surfacePoints);
    OsmSurfaceResult osmResult;
    if (_osmCacheKey == cacheKey && _osmCache != null) {
      osmResult = _osmCache!;
    } else {
      OsmData osmData;
      var cacheable = true;
      try {
        osmData = await _osm.fetch(points: surfacePoints);
      } catch (error) {
        osmData = const OsmData();
        warning.add('OSM недоступен: покрытие считается грунтом');
        // Сетевую ошибку не кэшируем: следующий пересчёт попробует снова.
        cacheable = false;
      }

      osmResult = buildOsmSurfaceResult(
        points: surfacePoints,
        data: osmData,
        profile: profile,
      );
      if (cacheable) {
        _osmCacheKey = cacheKey;
        _osmCache = osmResult;
      }
    }

    var weatherSamples = <WeatherSample>[];
    var hasWeatherBand = false;
    if (settings.weatherEnabled) {
      final start = settings.startUtc;
      if (start == null) {
        warning.add('Не задано время старта: погода не загружена');
      } else {
        final points = selectWeatherPoints(
          parsed,
          surfaceRuns: osmResult.runs,
          fords: osmResult.fords,
        );
        final pace = flatPaceSecPerKm > 0 ? flatPaceSecPerKm : 360.0;
        final queries = [
          for (final point in points)
            WeatherQuery(
              point: point,
              timeUtc: start.add(
                Duration(
                  seconds:
                      (movingSecAt?.call(point.distanceM) ??
                              point.distanceM / 1000 * pace)
                          .round(),
                ),
              ),
            ),
        ];
        try {
          final result = await _weather.fetch(
            queries: queries,
            profile: profile,
          );
          weatherSamples = result.samples;
          hasWeatherBand = result.hasWeatherBand;
          if (result.warning != null) warning.add(result.warning!);
        } catch (error) {
          warning.add('Погода недоступна: множитель 1.00');
        }
      }
    }

    final runs = <SurfaceRun>[];
    final snowEstimates = <SnowEstimate>[];
    for (final run in osmResult.runs) {
      final weather = _nearestWeather(
        weatherSamples,
        (run.startM + run.endM) / 2,
      );
      final wetness = weather == null
          ? Wetness.dry
          : wetnessFromSoil(weather.soilMoistureEff, profile);
      final type = surfaceAfterMud(
        surface: run.type,
        wetness: wetness,
        tempC: weather?.tempC ?? 0,
      );
      final bog = run.isBog
          ? bogFactor(
              kind: run.bogKind ?? 'bog',
              snowDepthM: weather?.snowDepthM ?? 0,
              avgTemp5C: weather?.avgTemp5C ?? 0,
              frozenDays: weather?.frozenDays ?? 0,
              profile: profile,
              groomed: settings.groomedSnow,
            )
          : 1.0;

      final heat = weather == null
          ? 1.0
          : heatFactor(weather.apparentC, profile);
      final snow = weather == null
          ? 1.0
          : snowFactor(
              snowDepthM: weather.snowDepthM,
              tempC: weather.tempC,
              freshSnowCm: weather.snowfallCm,
              urbanity: run.urbanity,
              roadClass: run.roadClass,
              groomed: settings.groomedSnow,
              wetness: wetness,
              profile: profile,
            );
      final shoe = settings.shoesEnabled
          ? shoeFactor(
              shoe: settings.shoe,
              surface: type,
              wetness: wetness,
              profile: profile,
              isFord: run.isFord,
            )
          : 1.0;
      final surfacePart = settings.surfaceEnabled
          ? surfaceFactor(
              surface: type,
              wetness: wetness,
              profile: profile,
              isBog: run.isBog,
              bogFactor: bog,
            )
          : 1.0;
      final weatherPart = settings.weatherEnabled ? heat * snow : 1.0;
      final factor = clampDouble(
        surfacePart * weatherPart * shoe,
        profile.clampMin,
        profile.clampMax,
      );

      runs.add(
        SurfaceRun(
          startM: run.startM,
          endM: run.endM,
          type: type,
          wetness: wetness,
          confidence: run.confidence,
          isBog: run.isBog,
          bogKind: run.bogKind,
          bogFactor: bog,
          surfaceSource: run.surfaceSource,
          urbanity: run.urbanity,
          roadClass: run.roadClass,
          isFord: run.isFord,
          factor: factor,
          heatFactor: heat,
          snowFactor: snow,
          shoeFactor: shoe,
        ),
      );

      if (weather != null && settings.weatherEnabled) {
        snowEstimates.add(
          _snowEstimate(
            run: run,
            weather: weather,
            settings: settings,
            profile: profile,
          ),
        );
      }
    }

    if (weatherSamples.isEmpty && settings.weatherEnabled) {
      hasWeatherBand = false;
    }

    return EnvironmentData(
      settings: settings,
      weather: weatherSamples,
      surface: runs,
      settlements: osmResult.settlements,
      snow: snowEstimates,
      fords: osmResult.fords,
      surfaceCoverage: osmResult.coverage,
      hasForecast: hasWeatherBand,
      warning: warning.isEmpty ? null : warning.join('; '),
    );
  }

  /// Ключ кэша OSM: трек и его координаты, без времени и погоды.
  static String _pointsKey(List<TrackSamplePoint> points) {
    if (points.isEmpty) return 'empty';
    final first = points.first;
    final last = points.last;
    return '${points.length}:'
        '${first.lat.toStringAsFixed(5)},${first.lon.toStringAsFixed(5)}:'
        '${last.lat.toStringAsFixed(5)},${last.lon.toStringAsFixed(5)}:'
        '${last.distanceM.round()}';
  }

  static WeatherSample? _nearestWeather(
    List<WeatherSample> samples,
    double distanceM,
  ) {
    if (samples.isEmpty) return null;
    var best = samples.first;
    var bestDelta = (best.distanceM - distanceM).abs();
    for (final sample in samples) {
      final delta = (sample.distanceM - distanceM).abs();
      if (delta < bestDelta) {
        best = sample;
        bestDelta = delta;
      }
    }
    return best;
  }

  SnowEstimate _snowEstimate({
    required SurfaceRun run,
    required WeatherSample weather,
    required EnvironmentSettings settings,
    required FactorProfile profile,
  }) {
    final clearance = clampDouble(
      1 - run.urbanity * 0.75,
      profile.settlement.minClearance,
      1.0,
    );
    final road = profile.roadClearance[run.roadClass] ?? 1.0;
    var effective = weather.snowDepthM * clearance * road;
    if (settings.groomedSnow) {
      effective = math.min(
        effective * profile.groomed.depthScale,
        profile.groomed.maxDepthScale * weather.snowDepthM,
      );
    }

    final probabilities = <SnowState, double>{};
    if (effective < profile.snow.thresholdM) {
      probabilities[SnowState.asphalt] = 1.0;
    } else if (weather.tempC > 1) {
      probabilities[SnowState.slush] = 1.0;
    } else if (weather.tempC > -1 && run.urbanity >= 0.3) {
      probabilities[SnowState.ice] = 0.6;
      probabilities[SnowState.packed] = 0.4;
    } else if (effective < profile.snowState.packedBelowM &&
        run.urbanity >= 0.3) {
      probabilities[SnowState.packed] = 0.8;
      probabilities[SnowState.loose] = 0.2;
    } else {
      probabilities[SnowState.loose] = 1.0;
    }
    if (settings.groomedSnow && probabilities.containsKey(SnowState.loose)) {
      final shift = math.min(
        profile.groomed.packedShift,
        probabilities[SnowState.loose] ?? 0,
      );
      probabilities[SnowState.loose] =
          (probabilities[SnowState.loose] ?? 0) - shift;
      probabilities[SnowState.packed] =
          (probabilities[SnowState.packed] ?? 0) + shift;
    }

    return SnowEstimate(
      startM: run.startM,
      endM: run.endM,
      effectiveDepthM: effective,
      probabilities: probabilities,
    );
  }
}
