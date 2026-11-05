import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/checkpoint_matching.dart';
import 'package:ultra_run_calc/features/gpx/gpx_import.dart';
import 'package:ultra_run_calc/features/gpx/gpx_parser.dart';
import 'package:ultra_run_calc/features/gpx/parsed_track.dart';
import 'package:ultra_run_calc/features/gpx/track_metrics.dart';

/// Трек на меридиане: 1 градус широты ≈ 111.2 км, 0.001° ≈ 111 м.
String gpxWithStart(double startLat, {double trackStartLat = 56.0}) {
  final pts = StringBuffer();
  for (var i = 0; i <= 20; i++) {
    final lat = trackStartLat + i * 0.001;
    pts.writeln(
      '<trkpt lat="${lat.toStringAsFixed(6)}" lon="38.0"><ele>100</ele></trkpt>',
    );
  }
  return '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
  <wpt lat="${startLat.toStringAsFixed(6)}" lon="38.0"><name>Start</name></wpt>
  <trk><trkseg>$pts</trkseg></trk>
</gpx>''';
}

void main() {
  group('trackStartOffsetMeters', () {
    test('старт совпадает с началом трека — смещение около нуля', () {
      final track = parseGpx(gpxWithStart(56.0));
      expect(trackStartOffsetMeters(track), lessThan(10));
    });

    test(
      'трек начинается на ~330 м севернее старта — смещение больше порога',
      () {
        // Старт на 56.000, трек с 56.003 (≈ 333 м).
        final track = parseGpx(gpxWithStart(56.0, trackStartLat: 56.003));
        final offset = trackStartOffsetMeters(track)!;
        expect(offset, closeTo(333, 15));
        expect(startNeedsDecision(offset), isTrue);
      },
    );

    test('нет точки Start — вопрос не задаётся', () {
      final track = parseGpx(
        File('test/fixtures/no_ele.gpx').readAsStringSync(),
      );
      expect(trackStartOffsetMeters(track), isNull);
    });
  });

  group('отсчёт от точки Start', () {
    test('подводка сдвигает километры на расстояние до старта', () {
      final track = parseGpx(gpxWithStart(56.0, trackStartLat: 56.003));
      final metrics = computeTrackMetrics(track);
      final candidates = buildCandidates(track, metrics);
      final parsed = ParsedTrack(
        track: track,
        metrics: metrics,
        candidates: candidates,
        totalAscentM: 0,
        totalDescentM: 0,
      ).measuredFromStart();

      expect(parsed.startOffsetM, closeTo(333, 15));
      expect(
        parsed.lengthKm * 1000,
        closeTo(metrics.totalDistance2d + parsed.startOffsetM, 1),
      );
      final shifted = candidatesFromStart(parsed);
      expect(identical(shifted, candidates), isFalse);
    });

    test('трек со стартом сдвига не получает', () {
      final track = parseGpx(gpxWithStart(56.0));
      final metrics = computeTrackMetrics(track);
      final candidates = buildCandidates(track, metrics);
      final parsed = ParsedTrack(
        track: track,
        metrics: metrics,
        candidates: candidates,
        totalAscentM: 0,
        totalDescentM: 0,
      );
      expect(identical(candidatesFromStart(parsed), candidates), isTrue);
    });
  });

  group('реальные треки', () {
    for (final name in [
      'GRUT100 - T100.gpx',
      'MFU K40.gpx',
      'VR100.gpx',
      'WBU L120.gpx',
    ]) {
      test('$name: старт в начале трека, вопрос не нужен', () {
        final file = File(name);
        expect(file.existsSync(), isTrue, reason: 'трек должен лежать в корне');
        final track = parseGpx(file.readAsStringSync());
        final offset = trackStartOffsetMeters(track)!;
        expect(offset, lessThan(200));
        expect(startNeedsDecision(offset), isFalse);
      });
    }
  });
}
