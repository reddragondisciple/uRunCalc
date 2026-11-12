/// Отбор точек для погодных запросов (docs/environment-conditions.md §9).
///
/// Сетка Open-Meteo грубее шага, поэтому 20 км базового шага достаточно;
/// дополнительные точки нужны для высоты, времени суток, покрытия и бродов.
library;

import 'dart:math' as math;

import '../gpx/parsed_track.dart';
import 'environment_data.dart';

/// Точка трека, для которой запрашивается погода.
class WeatherSamplePoint {
  const WeatherSamplePoint({
    required this.index,
    required this.distanceM,
    required this.lat,
    required this.lon,
    required this.elevationM,
  });

  final int index;

  /// Расстояние от старта таблицы, м (с учётом `startOffsetM`).
  final double distanceM;
  final double lat;
  final double lon;
  final double elevationM;
}

/// Точка трека для классификации покрытия.
class TrackSamplePoint {
  const TrackSamplePoint({
    required this.index,
    required this.distanceM,
    required this.lat,
    required this.lon,
    required this.elevationM,
  });

  final int index;
  final double distanceM;
  final double lat;
  final double lon;
  final double elevationM;
}

/// Базовый шаг, м.
const double weatherBaseStepM = 20000;

/// Лимит точек: 50 на 100 км.
const int weatherMaxPointsPer100Km = 50;

/// Отбирает точки погоды по треку.
///
/// Всегда входят старт и финиш, базовые точки через [baseStepM], середины
/// однородных участков покрытия, границы участков длиннее 2 км, локальные
/// вершины/днища и броды. Результат отсортирован по дистанции и ужат до
/// лимита [maxPointsPer100Km].
List<WeatherSamplePoint> selectWeatherPoints(
  ParsedTrack parsed, {
  List<SurfaceRun> surfaceRuns = const [],
  List<Ford> fords = const [],
  double baseStepM = weatherBaseStepM,
  int maxPointsPer100Km = weatherMaxPointsPer100Km,
}) {
  final track = parsed.track;
  if (track.length < 2) return const [];
  final cum = parsed.metrics.cumDist2d;
  final total = cum.last;
  if (total <= 0) return const [];

  final chosen = <double>{0, total};

  // Базовый шаг.
  if (baseStepM > 0) {
    for (var d = baseStepM; d < total; d += baseStepM) {
      chosen.add(d);
    }
  }

  // Вершины и днища: сглаженный профиль с шагом ~200 м, затем смена знака
  // уклона с перепадом больше 20 м. Середины длинных подъёмов, спусков и
  // плато между ними дают погоду в середине однородного участка высоты.
  final elevation = _elevationSamples(parsed);
  if (elevation.length >= 3) {
    final turning = _elevationTurningPoints(elevation);
    chosen.addAll(turning);
    final stops = [0.0, ...turning, total]..sort();
    for (var i = 1; i < stops.length; i++) {
      final length = stops[i] - stops[i - 1];
      if (length >= 2000) chosen.add((stops[i] + stops[i - 1]) / 2);
    }
  }

  // Участки покрытия: середина и, для длинных, границы.
  for (final run in surfaceRuns) {
    final length = run.endM - run.startM;
    if (length <= 0) continue;
    if (length >= 1000) {
      chosen.add((run.startM + run.endM) / 2);
    }
    if (length >= 2000) {
      chosen.add(run.startM);
      chosen.add(run.endM);
    }
  }

  // Броды.
  for (final ford in fords) {
    chosen.add(ford.distanceM);
  }

  final sorted = chosen.map((d) => d.clamp(0.0, total).toDouble()).toList()
    ..sort();

  // Склеиваем близкие точки: на сетке 5–8 км они всё равно попадут в одну
  // ячейку. Старт и финиш сохраняем всегда.
  final merged = <double>[];
  for (final d in sorted) {
    if (merged.isEmpty || d - merged.last >= 500 || d == total) {
      merged.add(d);
    }
  }

  final maxPoints = math.max(2, (total / 100000 * maxPointsPer100Km).ceil());
  final limited = merged.length <= maxPoints
      ? merged
      : _thinEvenly(merged, maxPoints);

  return [for (final d in limited) _pointAt(parsed, _nearestIndex(cum, d), d)];
}

WeatherSamplePoint _pointAt(ParsedTrack parsed, int index, double distanceM) {
  final track = parsed.track;
  return WeatherSamplePoint(
    index: index,
    distanceM: parsed.distanceFromStartM(distanceM),
    lat: track.lats[index],
    lon: track.lons[index],
    elevationM: track.eles[index].isNaN ? 0 : track.eles[index],
  );
}

/// Индекс точки, ближайшей к расстоянию [distanceM] по 2D-пути.
int _nearestIndex(List<double> cum, double distanceM) {
  var lo = 0;
  var hi = cum.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (cum[mid] < distanceM) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if (lo == 0) return 0;
  final prev = lo - 1;
  return (cum[lo] - distanceM).abs() < (distanceM - cum[prev]).abs()
      ? lo
      : prev;
}

/// Точки профиля высоты с шагом около 200 м.
List<({double d, double e})> _elevationSamples(ParsedTrack parsed) {
  final track = parsed.track;
  if (!track.hasElevation) return const [];
  final cum = parsed.metrics.cumDist2d;
  final total = cum.last;
  if (total <= 0) return const [];

  const stepM = 200.0;
  final points = <({double d, double e})>[];
  var next = 0.0;
  for (var i = 0; i < track.length; i++) {
    if (cum[i] + 1e-6 >= next) {
      points.add((d: cum[i], e: track.eles[i]));
      next = cum[i] + stepM;
    }
  }
  return points;
}

/// Локальные вершины и днища с перепадом больше 20 м.
List<double> _elevationTurningPoints(List<({double d, double e})> points) {
  if (points.length < 3) return const [];
  final result = <double>[];
  for (var i = 1; i < points.length - 1; i++) {
    final prev = points[i - 1].e;
    final current = points[i].e;
    final next = points[i + 1].e;
    final isPeak = current > prev && current >= next;
    final isBottom = current < prev && current <= next;
    if (!isPeak && !isBottom) continue;
    // Перепад с ближайшей точкой того же знака должен быть заметным.
    var opposite = current;
    for (var j = i + 1; j < points.length; j++) {
      if ((isPeak && points[j].e < current) ||
          (isBottom && points[j].e > current)) {
        opposite = points[j].e;
        break;
      }
    }
    if ((current - opposite).abs() < 20) continue;
    result.add(points[i].d);
  }
  return result;
}

/// Равномерно прореживает список, сохраняя первый и последний элементы.
List<double> _thinEvenly(List<double> values, int maxPoints) {
  if (values.length <= maxPoints) return values;
  final result = <double>[values.first];
  final step = (values.length - 1) / (maxPoints - 1);
  for (var i = 1; i < maxPoints - 1; i++) {
    result.add(values[(i * step).round()]);
  }
  result.add(values.last);
  return result.toSet().toList()..sort();
}

/// Дедуплицирует точки по округлению координат. Для истории достаточно
/// ~0.05°; ответ провайдера всё равно может схлопнуть точки в одну ячейку.
List<WeatherSamplePoint> dedupeWeatherPointsByGrid(
  List<WeatherSamplePoint> points, {
  double gridDeg = 0.05,
}) {
  final seen = <String>{};
  final result = <WeatherSamplePoint>[];
  for (final point in points) {
    final key =
        '${(point.lat / gridDeg).round()}:${(point.lon / gridDeg).round()}';
    if (seen.add(key)) result.add(point);
  }
  return result;
}

/// Точки для классификации покрытия: примерно каждые [stepM] метров, но не
/// больше [maxPoints]. Для 40-километрового трека это ~1300 точек.
List<TrackSamplePoint> sampleTrackPoints(
  ParsedTrack parsed, {
  double stepM = 30,
  int maxPoints = 3000,
}) {
  final track = parsed.track;
  if (track.length < 2) return const [];
  final cum = parsed.metrics.cumDist2d;
  final total = cum.last;
  if (total <= 0) return const [];

  final effectiveStep = math.max(stepM, total / maxPoints);
  final result = <TrackSamplePoint>[];
  var next = 0.0;
  for (var i = 0; i < track.length; i++) {
    if (cum[i] + 1e-6 < next) continue;
    result.add(
      TrackSamplePoint(
        index: i,
        distanceM: parsed.distanceFromStartM(cum[i]),
        lat: track.lats[i],
        lon: track.lons[i],
        elevationM: track.eles[i].isNaN ? 0 : track.eles[i],
      ),
    );
    next = cum[i] + effectiveStep;
  }
  return result;
}
