import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/gap_model.dart';
import 'package:ultra_run_calc/features/gpx/gpx_parser.dart';
import 'package:ultra_run_calc/features/gpx/track_metrics.dart';

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
      final file = File('GRUT100 - T100.gpx');
      expect(file.existsSync(), isTrue, reason: 'трек должен лежать в корне');
      final metrics = computeTrackMetrics(parseGpx(file.readAsStringSync()));
      expect(metrics.totalDistance2d / 1000, closeTo(109.31, 0.05));
    });
  });
}
