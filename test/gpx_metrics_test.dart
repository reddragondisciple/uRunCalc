import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/gap_model.dart';
import 'package:ultra_run_calc/features/gpx/gpx_parser.dart';
import 'package:ultra_run_calc/features/gpx/gpx_track.dart';
import 'package:ultra_run_calc/features/gpx/track_metrics.dart';

/// Старая реализация: отдельный проход по всем точкам на каждый сегмент.
/// Оставлена в тесте как эталон для проверки однопроходной версии.
List<SegmentStats> _legacyComputeSegments(
  TrackMetrics metrics,
  List<double> boundaries,
) {
  final result = <SegmentStats>[];
  for (var s = 0; s + 1 < boundaries.length; s++) {
    result.add(_legacySegmentStats(metrics, boundaries[s], boundaries[s + 1]));
  }
  return result;
}

SegmentStats _legacySegmentStats(TrackMetrics metrics, double from, double to) {
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
  var covered = 0.0;
  var movingM = 0.0;

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
      movingM += overlap;
      continue;
    }
    final grade = dEle / overlap;
    final ds3 = math.sqrt(overlap * overlap + dEle * dEle);
    movingM += ds3 * gapFactor(grade);
  }

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

/// Синтетический трек: шаг по широте меняется, высота — «пила».
GpxTrack _syntheticTrack(
  int points, {
  bool elevation = true,
  bool duplicates = false,
}) {
  final lats = Float64List(points);
  final lons = Float64List(points);
  final eles = Float64List(points);
  var lat = 56.0;
  var ele = 200.0;
  for (var i = 0; i < points; i++) {
    if (i > 0 && !(duplicates && i % 13 == 0)) {
      lat += 0.00008 + (i % 5) * 0.00003;
    }
    lats[i] = lat;
    lons[i] = 38.0;
    ele += ((i * 17) % 23 - 11) * 0.7;
    eles[i] = elevation ? ele : double.nan;
  }
  return GpxTrack(
    lats: lats,
    lons: lons,
    eles: eles,
    segmentStarts: const [0],
    waypoints: const [],
    droppedPoints: 0,
  );
}

/// Неубывающие границы, иногда за пределами трека.
List<double> _randomBoundaries(math.Random random, double total, int count) {
  final values = [
    for (var i = 0; i < count; i++) (random.nextDouble() * 1.1 - 0.05) * total,
  ]..sort();
  return values;
}

void _expectSegmentsEqual(
  List<SegmentStats> actual,
  List<SegmentStats> expected, {
  required String reason,
}) {
  expect(actual.length, expected.length, reason: reason);
  for (var i = 0; i < expected.length; i++) {
    final a = actual[i];
    final e = expected[i];
    expect(a.lengthM, e.lengthM, reason: '$reason, сегмент $i: длина');
    expect(a.ascentM, e.ascentM, reason: '$reason, сегмент $i: набор');
    expect(a.descentM, e.descentM, reason: '$reason, сегмент $i: сброс');
    expect(a.gapFactor, e.gapFactor, reason: '$reason, сегмент $i: GAP');
  }
}

void main() {
  group('minetti / gapFactor', () {
    test('на плоском k = 1', () {
      expect(gapFactor(0), closeTo(1.0, 1e-9));
    });

    test('подъём +5% медленнее, спуск −5% быстрее', () {
      expect(gapFactor(0.05), closeTo(1.30, 0.02));
      expect(gapFactor(-0.05), closeTo(0.76, 0.02));
    });

    test('спуск не быстрее 0.70', () {
      expect(gapFactor(-0.10), closeTo(0.70, 1e-9));
      expect(gapFactor(-0.25), 0.70);
    });

    test('уклон обрезается до ±25%', () {
      expect(gapFactor(0.5), gapFactor(0.25));
      expect(gapFactor(-0.5), gapFactor(-0.25));
    });
  });

  group('computeTrackMetrics / computeSegments', () {
    test('на фикстуре D+ и D− сегментов', () {
      final track = parseGpx(File('test/fixtures/hill.gpx').readAsStringSync());
      final metrics = computeTrackMetrics(track);
      final total = metrics.totalDistance2d;
      final segs = computeSegments(metrics, [0, total]);
      expect(segs.length, 1);
      // Подъём 100 м, спуск 100 м на фикстуре (200 → 100 через 150).
      expect(segs.first.ascentM, closeTo(100, 0.5));
      expect(segs.first.descentM, closeTo(100, 0.5));
    });

    test('граница внутри интервала делит перепад пропорционально', () {
      final track = parseGpx(File('test/fixtures/hill.gpx').readAsStringSync());
      final metrics = computeTrackMetrics(track);
      final mid = metrics.totalDistance2d / 2;
      final segs = computeSegments(metrics, [0, mid, metrics.totalDistance2d]);
      expect(segs[0].ascentM + segs[1].ascentM, closeTo(100, 0.5));
      expect(segs[0].ascentM, greaterThan(0));
    });

    test('колонка за пределами трека даёт gapFactor = 1', () {
      final track = parseGpx(File('test/fixtures/hill.gpx').readAsStringSync());
      final metrics = computeTrackMetrics(track);
      final beyond = metrics.totalDistance2d + 5000;
      final segs = computeSegments(metrics, [
        0,
        metrics.totalDistance2d,
        beyond,
      ]);
      expect(segs.last.gapFactor, 1.0);
    });

    test('без высот gapFactor = 1 везде', () {
      final track = parseGpx(
        File('test/fixtures/no_ele.gpx').readAsStringSync(),
      );
      final metrics = computeTrackMetrics(track);
      final segs = computeSegments(metrics, [0, metrics.totalDistance2d]);
      expect(segs.single.gapFactor, 1.0);
      expect(segs.single.ascentM, 0);
    });

    test('реальный трек: 2D-длина GRUT ≈ 109.3 км', () {
      final file = File('test/fixtures/GRUT100 - T100.gpx');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'фикстура должна лежать в test/fixtures',
      );
      final metrics = computeTrackMetrics(parseGpx(file.readAsStringSync()));
      expect(metrics.totalDistance2d / 1000, closeTo(109.31, 0.05));
    });

    test('повторяющиеся границы дают нулевой сегмент', () {
      final track = parseGpx(File('test/fixtures/hill.gpx').readAsStringSync());
      final metrics = computeTrackMetrics(track);
      final total = metrics.totalDistance2d;
      final segs = computeSegments(metrics, [0, total / 2, total / 2, total]);

      expect(segs.length, 3);
      expect(segs[1].lengthM, 0);
      expect(segs[1].ascentM, 0);
      expect(segs[1].descentM, 0);
      expect(segs[1].gapFactor, 1.0);
      expect(segs[0].ascentM + segs[2].ascentM, closeTo(100, 0.5));
    });
  });

  group('computeSegments: однопроходная версия', () {
    test('совпадает со старой реализацией на случайных границах', () {
      final random = math.Random(20261108);
      final tracks = <GpxTrack>[
        _syntheticTrack(120),
        _syntheticTrack(80, duplicates: true),
        _syntheticTrack(60, elevation: false),
        parseGpx(File('test/fixtures/hill.gpx').readAsStringSync()),
        parseGpx(File('test/fixtures/GRUT100 - T100.gpx').readAsStringSync()),
      ];

      for (final track in tracks) {
        final metrics = computeTrackMetrics(track);
        for (var round = 0; round < 25; round++) {
          final boundaries = _randomBoundaries(
            random,
            metrics.totalDistance2d,
            2 + random.nextInt(9),
          );
          _expectSegmentsEqual(
            computeSegments(metrics, boundaries),
            _legacyComputeSegments(metrics, boundaries),
            reason: 'точек ${track.length}, раунд $round',
          );
        }
      }
    });

    test('пустой список границ и одна граница дают пустой результат', () {
      final metrics = computeTrackMetrics(_syntheticTrack(10));
      expect(computeSegments(metrics, const []), isEmpty);
      expect(computeSegments(metrics, const [0]), isEmpty);
    });
  });
}
