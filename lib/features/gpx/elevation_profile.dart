/// Данные профиля высот для карты (docs/gpx-mountain-mode.md §8.3).
///
/// Чистая логика без Flutter: даунсемплинг, сглаженный уклон для цвета и
/// подсказка по точке. Высоты берутся сырыми; сглаживание касается только
/// цвета (окно [gradeWindowM]), D+/D− в таблице от него не зависят.
library;

import 'dart:math' as math;

import 'parsed_track.dart';

/// Окно сглаживания уклона для цвета, м (§8.3).
const double gradeWindowM = 100;

/// Точка профиля: километраж от старта (км) и высота (м).
class ProfilePoint {
  const ProfilePoint({
    required this.km,
    required this.eleM,
    required this.gradeFraction,
  });

  final double km;
  final double eleM;

  /// Уклон по окну [gradeWindowM], доля (0.05 = 5%). Знак сохраняем.
  final double gradeFraction;
}

/// Классы крутизны для цвета. Крутой спуск относится к последнему классу
/// по модулю уклона (§8.3: «крутой спуск тоже красный»).
enum GradeBand { flat, gentle, moderate, steep, extreme }

GradeBand gradeBand(double gradeFraction) {
  final g = gradeFraction.abs() * 100;
  if (g < 3) return GradeBand.flat;
  if (g < 6) return GradeBand.gentle;
  if (g < 10) return GradeBand.moderate;
  if (g < 15) return GradeBand.steep;
  return GradeBand.extreme;
}

/// Профиль трека с даунсемплингом до [maxPoints] точек.
///
/// Точки распределяются по бакетам равной 2D-длины. В каждом бакете
/// сохраняем минимум и максимум высоты (в порядке следования), чтобы пики
/// не сглаживались. Уклон считается по сырому треку в окне [gradeWindowM].
///
/// Для трека без высот возвращает пустой список.
List<ProfilePoint> buildElevationProfile(
  ParsedTrack parsed, {
  int maxPoints = 1000,
}) {
  final track = parsed.track;
  if (!track.hasElevation || track.length < 2 || maxPoints < 2) {
    return const [];
  }
  final metrics = parsed.metrics;
  final cum = metrics.cumDist2d;
  final total = cum.last;
  if (total <= 0) return const [];

  // Бакеты по расстоянию: не больше maxPoints/2 бакетов, в каждом min и max.
  final buckets = math.max(1, maxPoints ~/ 2);
  final bucketLen = total / buckets;
  final out = <ProfilePoint>[];

  var index = 0;
  for (var b = 0; b < buckets; b++) {
    final from = b * bucketLen;
    final to = (b + 1) * bucketLen;
    // Точки, попадающие в бакет (последний бакет включает конец трека).
    var minI = -1;
    var maxI = -1;
    while (index < track.length && (cum[index] < to || b == buckets - 1)) {
      if (cum[index] >= from) {
        if (minI < 0 || track.eles[index] < track.eles[minI]) minI = index;
        if (maxI < 0 || track.eles[index] > track.eles[maxI]) maxI = index;
      }
      index++;
    }
    if (minI < 0) continue;
    // Порядок следования: первым идёт тот, что раньше по треку.
    final ordered = minI <= maxI ? [minI, maxI] : [maxI, minI];
    for (final i in ordered.toSet()) {
      out.add(_pointAt(parsed, i));
    }
  }
  return out;
}

ProfilePoint _pointAt(ParsedTrack parsed, int index) {
  final metrics = parsed.metrics;
  final track = parsed.track;
  final cumM = metrics.cumDist2d[index];
  return ProfilePoint(
    km: parsed.distanceFromStartM(cumM) / 1000,
    eleM: track.eles[index],
    gradeFraction: _gradeAt(metrics.cumDist2d, track.eles, cumM),
  );
}

/// Уклон в точке `at` (м, 2D-путь) по окну [gradeWindowM]: разность высот
/// на краях окна, делённая на длину окна. У краёв трека окно обрезается.
double _gradeAt(List<double> cum, List<double> eles, double at) {
  final total = cum.last;
  final half = gradeWindowM / 2;
  final from = math.max(0.0, at - half);
  final to = math.min(total, at + half);
  if (to - from <= 0) return 0;
  final eFrom = _eleAt(cum, eles, from);
  final eTo = _eleAt(cum, eles, to);
  return (eTo - eFrom) / (to - from);
}

/// Высота на 2D-пути `at` линейной интерполяцией по точкам трека.
double _eleAt(List<double> cum, List<double> eles, double at) {
  var lo = 0;
  var hi = cum.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (cum[mid] < at) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if (lo == 0) return eles[0];
  final a = lo - 1;
  final span = cum[lo] - cum[a];
  if (span <= 0) return eles[lo];
  final t = (at - cum[a]) / span;
  return eles[a] + (eles[lo] - eles[a]) * t;
}

/// Ближайшая к километражу `km` точка профиля (для подсказки по тапу).
ProfilePoint? nearestProfilePoint(List<ProfilePoint> profile, double km) {
  if (profile.isEmpty) return null;
  var best = profile.first;
  var bestDelta = (best.km - km).abs();
  for (final p in profile) {
    final d = (p.km - km).abs();
    if (d < bestDelta) {
      best = p;
      bestDelta = d;
    }
  }
  return best;
}

/// Диапазон профиля (км), в который попадает хотя бы одна точка. Для
/// фокуса на сегменте.
({double from, double to})? profileRange(List<ProfilePoint> profile) {
  if (profile.isEmpty) return null;
  return (from: profile.first.km, to: profile.last.km);
}

/// Точки профиля внутри [fromKm..toKm] (включительно). Для фокуса на
/// сегменте без лишней работы при отрисовке.
List<ProfilePoint> profileBetween(
  List<ProfilePoint> profile,
  double fromKm,
  double toKm,
) {
  return [
    for (final p in profile)
      if (p.km >= fromKm && p.km <= toKm) p,
  ];
}
