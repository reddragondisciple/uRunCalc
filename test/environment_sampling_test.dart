import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/gpx_track.dart';
import 'package:ultra_run_calc/features/gpx/parsed_track.dart';
import 'package:ultra_run_calc/features/gpx/track_metrics.dart';
import 'package:ultra_run_calc/features/pace/environment_data.dart';
import 'package:ultra_run_calc/features/pace/environment_sampling.dart';

ParsedTrack _track({
  int points = 50,
  double stepDeg = 0.009,
  double Function(int index)? elevation,
}) {
  final lats = Float64List(points);
  final lons = Float64List(points);
  final eles = Float64List(points);
  for (var i = 0; i < points; i++) {
    lats[i] = 56.0 + i * stepDeg;
    lons[i] = 40.0;
    // Волна высоты: вершины и днища примерно каждые 10 км.
    eles[i] = elevation?.call(i) ?? 150 + 40 * math.sin(i / 5);
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

void main() {
  group('selectWeatherPoints', () {
    test('always includes start and finish', () {
      final points = selectWeatherPoints(_track());

      expect(points.first.distanceM, 0);
      expect(points.last.distanceM, closeTo(48000, 2000));
    });

    test('adds base points about every 20 km', () {
      final points = selectWeatherPoints(_track());
      final distances = points.map((p) => p.distanceM).toList();

      expect(
        distances.any((d) => (d - 20000).abs() < 2000),
        isTrue,
        reason: 'нет точки около 20 км',
      );
      expect(
        distances.any((d) => (d - 40000).abs() < 2000),
        isTrue,
        reason: 'нет точки около 40 км',
      );
    });

    test('adds surface run boundaries and midpoints', () {
      final points = selectWeatherPoints(
        _track(),
        surfaceRuns: const [
          SurfaceRun(
            startM: 5000,
            endM: 12000,
            type: SurfaceType.dirt,
            wetness: Wetness.wet,
            confidence: 0.8,
          ),
        ],
      );
      final distances = points.map((p) => p.distanceM).toList();

      expect(distances.any((d) => (d - 5000).abs() < 1000), isTrue);
      expect(distances.any((d) => (d - 8500).abs() < 1000), isTrue);
      expect(distances.any((d) => (d - 12000).abs() < 1000), isTrue);
    });

    test('adds the midpoint of a long homogeneous climb', () {
      final points = selectWeatherPoints(
        _track(points: 50, elevation: (i) => 100 + i * 20.0),
      );

      // Ровный подъём ~48 км: середина около 24 км, базовые 20 и 40 км её
      // не заменяют.
      expect(
        points.any((p) => (p.distanceM - 24000).abs() < 2000),
        isTrue,
        reason: 'нет точки в середине подъёма',
      );
    });

    test('adds fords', () {
      final points = selectWeatherPoints(
        _track(),
        fords: const [Ford(distanceM: 7777, confirmed: true)],
      );

      expect(points.any((p) => (p.distanceM - 7777).abs() < 1000), isTrue);
    });

    test('respects 50 points per 100 km', () {
      final points = selectWeatherPoints(_track(points: 200, stepDeg: 0.009));

      // ~179 км → не больше 90 точек.
      expect(points.length, lessThanOrEqualTo(90));
    });

    test('handles a track shorter than the base step', () {
      final points = selectWeatherPoints(_track(points: 5, stepDeg: 0.002));

      expect(points.length, 2);
      expect(points.first.distanceM, 0);
    });
  });

  group('dedupeWeatherPointsByGrid', () {
    test('keeps one point per 0.05° cell', () {
      final points = [
        const WeatherSamplePoint(
          index: 0,
          distanceM: 0,
          lat: 56.000,
          lon: 40.000,
          elevationM: 100,
        ),
        const WeatherSamplePoint(
          index: 1,
          distanceM: 1000,
          lat: 56.001,
          lon: 40.001,
          elevationM: 101,
        ),
        const WeatherSamplePoint(
          index: 2,
          distanceM: 5000,
          lat: 56.100,
          lon: 40.100,
          elevationM: 110,
        ),
      ];

      final deduped = dedupeWeatherPointsByGrid(points);

      expect(deduped.length, 2);
      expect(deduped.first.index, 0);
      expect(deduped.last.index, 2);
    });
  });
}
