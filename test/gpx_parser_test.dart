import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/gpx_parser.dart';
import 'package:ultra_run_calc/features/gpx/gpx_track.dart';

void main() {
  group('parseGpx', () {
    test('склеивает несколько trkseg и запоминает границы', () {
      final track = parseGpx(File('test/fixtures/hill.gpx').readAsStringSync());
      expect(track.segmentStarts, [0, 3]);
      expect(track.hasElevation, isTrue);
      expect(track.waypoints.map((w) => w.name), ['Start', 'CP1 (Заброска)']);
    });

    test('пропускает дубликаты внутри сегмента', () {
      final track = parseGpx(File('test/fixtures/hill.gpx').readAsStringSync());
      // Четвёртая точка — дубликат третьей.
      expect(track.droppedPoints, 1);
      expect(track.length, 5);
    });

    test('без ele hasElevation = false', () {
      final track = parseGpx(
        File('test/fixtures/no_ele.gpx').readAsStringSync(),
      );
      expect(track.hasElevation, isFalse);
    });

    test('не GPX — ошибка', () {
      expect(
        () => parseGpx('<html></html>'),
        throwsA(isA<GpxFormatException>()),
      );
    });

    test('сломанный XML — ошибка', () {
      expect(() => parseGpx('<gpx>'), throwsA(isA<GpxFormatException>()));
    });

    test('реальный трек GRUT: 19 wpt и высоты', () {
      final file = File('GRUT100 - T100.gpx');
      expect(file.existsSync(), isTrue, reason: 'трек должен лежать в корне');
      final track = parseGpx(file.readAsStringSync());
      expect(track.waypoints.length, 19);
      expect(track.hasElevation, isTrue);
    });
  });
}
