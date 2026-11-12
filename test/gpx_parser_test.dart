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

    test('сохраняет время точек в epoch seconds UTC', () {
      const source = '''
<?xml version="1.0"?>
<gpx version="1.1" creator="test">
  <trk><trkseg>
    <trkpt lat="56.0" lon="38.0">
      <ele>100</ele><time>2026-07-24T19:03:33Z</time>
    </trkpt>
    <trkpt lat="56.0001" lon="38.0">
      <ele>101</ele><time>2026-07-24T19:04:03Z</time>
    </trkpt>
  </trkseg></trk>
</gpx>
''';
      final track = parseGpx(source);
      expect(track.hasTime, isTrue);
      final expected =
          DateTime.utc(2026, 7, 24, 19, 3, 33).millisecondsSinceEpoch / 1000.0;
      expect(track.timesSec[0], closeTo(expected, 0.001));
      expect(track.timesSec[1] - track.timesSec[0], closeTo(30, 0.001));
    });

    test('без time hasTime = false, значения NaN', () {
      final track = parseGpx(File('test/fixtures/hill.gpx').readAsStringSync());
      expect(track.hasTime, isFalse);
      expect(track.timesSec.every((t) => t.isNaN), isTrue);
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
      final file = File('test/fixtures/GRUT100 - T100.gpx');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'фикстура должна лежать в test/fixtures',
      );
      final track = parseGpx(file.readAsStringSync());
      expect(track.waypoints.length, 19);
      expect(track.hasElevation, isTrue);
    });
  });
}
