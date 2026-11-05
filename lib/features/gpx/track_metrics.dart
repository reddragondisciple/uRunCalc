import 'dart:math' as math;

import 'gap_model.dart';
import 'gpx_parser.dart';
import 'gpx_track.dart';

/// Интервалы короче этого (2D, м) не учитываем в расчёте уклона и времени.
const double minIntervalMeters = 0.5;

/// Итог по одному сегменту между границами колонок.
class SegmentStats {
  const SegmentStats({
    required this.lengthM,
    required this.ascentM,
    required this.descentM,
    required this.gapFactor,
  });

  /// 2D-длина сегмента, м.
  final double lengthM;
  final double ascentM;
  final double descentM;

  /// Отношение ходового времени по GAP к времени по плоскому темпу.
  /// `1`, если высот нет или сегмент вне трека.
  final double gapFactor;
}

/// Накопленные метрики трека: `cumDist2d[i]` — 2D-путь от старта до точки `i`.
class TrackMetrics {
  TrackMetrics({
    required this.track,
    required this.cumDist2d,
    required this.cumDist3d,
  });

  final GpxTrack track;
  final List<double> cumDist2d;
  final List<double> cumDist3d;

  double get totalDistance2d => cumDist2d.last;
  double get totalDistance3d => cumDist3d.last;

  /// Точка трека ближе всего к `km` по 2D-пути (индекс).
  int indexAtDistance(double meters) {
    var lo = 0;
    var hi = cumDist2d.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (cumDist2d[mid] < meters) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

/// Считает накопленные 2D- и 3D-пути.
///
/// 3D-шаг ограничиваем уклоном 100%: одиночные выбросы высоты не должны
/// раздувать расстояние.
TrackMetrics computeTrackMetrics(GpxTrack track) {
  final n = track.length;
  final cum2 = List<double>.filled(n, 0);
  final cum3 = List<double>.filled(n, 0);
  final hasEle = track.hasElevation;

  for (var i = 1; i < n; i++) {
    final ds2 = haversineMeters(
      track.lats[i - 1],
      track.lons[i - 1],
      track.lats[i],
      track.lons[i],
    );
    cum2[i] = cum2[i - 1] + ds2;

    var dEle = hasEle ? track.eles[i] - track.eles[i - 1] : 0.0;
    if (ds2 > 0 && dEle.abs() / ds2 > 1.0) {
      dEle = dEle.sign * ds2;
    }
    final ds3 = math.sqrt(ds2 * ds2 + dEle * dEle);
    cum3[i] = cum3[i - 1] + ds3;
  }

  return TrackMetrics(track: track, cumDist2d: cum2, cumDist3d: cum3);
}

/// Считает статистику сегментов по границам в метрах 2D-пути.
///
/// `boundaries` — неубывающие границы: `[0, b1, ..., bN]`. Интервалы,
/// пересекающие границу, делятся пропорционально.
List<SegmentStats> computeSegments(
  TrackMetrics metrics,
  List<double> boundaries,
) {
  final result = <SegmentStats>[];
  for (var s = 0; s + 1 < boundaries.length; s++) {
    result.add(_segmentStats(metrics, boundaries[s], boundaries[s + 1]));
  }
  return result;
}

SegmentStats _segmentStats(TrackMetrics metrics, double from, double to) {
  final track = metrics.track;
  final cum = metrics.cumDist2d;
  final length = math.max(0.0, to - from);
  const flat = 1.0;

  if (length <= 0 || !track.hasElevation || track.length < 2) {
    return SegmentStats(
      lengthM: length,
      ascentM: 0,
      descentM: 0,
      gapFactor: flat,
    );
  }

  var ascent = 0.0;
  var descent = 0.0;
  var covered = 0.0; // 2D-длина, покрытая треком внутри сегмента
  var movingM = 0.0; // путь по GAP: ds3 * k для каждого интервала

  for (var i = 1; i < track.length; i++) {
    final a = cum[i - 1];
    final b = cum[i];
    final overlap = math.min(b, to) - math.max(a, from);
    if (overlap <= 0 || b <= a) continue;

    final share = overlap / (b - a);
    final dEle = (track.eles[i] - track.eles[i - 1]) * share;
    if (dEle > 0) ascent += dEle;
    if (dEle < 0) descent -= dEle;

    covered += overlap;
    if (overlap < minIntervalMeters) {
      movingM += overlap; // короткий кусок считаем плоским
      continue;
    }
    final grade = dEle / overlap;
    final ds3 = math.sqrt(overlap * overlap + dEle * dEle);
    movingM += ds3 * gapFactor(grade);
  }

  // Трек не покрывает сегмент полностью (колонка за пределами трека):
  // по §5.1 фактор 1, а не усреднённый по части.
  if (covered < length * 0.99) {
    return SegmentStats(
      lengthM: length,
      ascentM: ascent,
      descentM: descent,
      gapFactor: flat,
    );
  }

  return SegmentStats(
    lengthM: length,
    ascentM: ascent,
    descentM: descent,
    gapFactor: movingM / length,
  );
}
