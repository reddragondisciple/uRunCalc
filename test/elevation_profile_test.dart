import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/elevation_profile.dart';
import 'package:ultra_run_calc/features/gpx/gpx_parser.dart';
import 'package:ultra_run_calc/features/gpx/parsed_track.dart';
import 'package:ultra_run_calc/features/gpx/track_metrics.dart';

ParsedTrack _parsedFrom(String path) {
  final track = parseGpx(File(path).readAsStringSync());
  return ParsedTrack(
    track: track,
    metrics: computeTrackMetrics(track),
    candidates: const [],
    totalAscentM: 0,
    totalDescentM: 0,
  );
}

void main() {
  group('gradeBand', () {
    test('границы классов по модулю уклона', () {
      expect(gradeBand(0.0), GradeBand.flat);
      expect(gradeBand(0.029), GradeBand.flat);
      expect(gradeBand(0.03), GradeBand.gentle);
      expect(gradeBand(-0.06), GradeBand.moderate);
      expect(gradeBand(0.10), GradeBand.steep);
      expect(gradeBand(0.15), GradeBand.extreme);
    });

    test('крутой спуск относится к красному классу', () {
      expect(gradeBand(-0.20), GradeBand.extreme);
      expect(gradeBand(-0.20), gradeBand(0.20));
    });
  });

  group('buildElevationProfile', () {
    test('без высот профиля нет', () {
      final parsed = _parsedFrom('test/fixtures/no_ele.gpx');
      expect(buildElevationProfile(parsed), isEmpty);
    });

    test('на холме профиль покрывает всю дистанцию от 0 до конца', () {
      final parsed = _parsedFrom('test/fixtures/hill.gpx');
      final profile = buildElevationProfile(parsed, maxPoints: 200);
      expect(profile, isNotEmpty);
      expect(profile.length, lessThanOrEqualTo(200));
      expect(profile.first.km, closeTo(0, 0.01));
      expect(profile.last.km, closeTo(parsed.lengthKm, 0.01));
    });

    test('точки упорядочены по километражу', () {
      final parsed = _parsedFrom('test/fixtures/hill.gpx');
      final profile = buildElevationProfile(parsed, maxPoints: 200);
      for (var i = 1; i < profile.length; i++) {
        expect(profile[i].km, greaterThanOrEqualTo(profile[i - 1].km));
      }
    });

    test('даунсемплинг сохраняет максимум высоты (пик не теряется)', () {
      final parsed = _parsedFrom('test/fixtures/hill.gpx');
      final raw = parsed.track.eles.reduce((a, b) => a > b ? a : b);
      final profile = buildElevationProfile(parsed, maxPoints: 10);
      final top = profile.map((p) => p.eleM).reduce((a, b) => a > b ? a : b);
      expect(top, closeTo(raw, 0.01));
    });

    test('знак уклона: подъём положительный, спуск отрицательный', () {
      final parsed = _parsedFrom('test/fixtures/hill.gpx');
      final profile = buildElevationProfile(parsed, maxPoints: 400);
      final len = parsed.lengthKm;
      // Фикстура: 100 → 150 → 200 (плато) → 150 → 100 м. Подъём в первой
      // четверти, спуск в последней; на плато уклон честно равен нулю.
      final up = nearestProfilePoint(profile, len * 0.25)!;
      final down = nearestProfilePoint(profile, len * 0.75)!;
      expect(up.gradeFraction, greaterThan(0));
      expect(down.gradeFraction, lessThan(0));
    });

    test(
      'реальный GRUT: профиль от 0 до финиша, максимум в пределах трека',
      () {
        final file = File('GRUT100 - T100.gpx');
        if (!file.existsSync()) return;
        final parsed = _parsedFrom(file.path);
        final profile = buildElevationProfile(parsed, maxPoints: 800);
        expect(profile.length, lessThanOrEqualTo(800));
        expect(profile.last.km, closeTo(parsed.lengthKm, 0.05));
        final maxEle = profile
            .map((p) => p.eleM)
            .reduce((a, b) => a > b ? a : b);
        final rawMax = parsed.track.eles.reduce((a, b) => a > b ? a : b);
        expect(maxEle, closeTo(rawMax, 0.01));
      },
    );
  });

  group('profileBetween / nearestProfilePoint', () {
    test('диапазон фильтрует по километражу', () {
      final parsed = _parsedFrom('test/fixtures/hill.gpx');
      final profile = buildElevationProfile(parsed, maxPoints: 200);
      final mid = parsed.lengthKm / 2;
      final part = profileBetween(profile, 0, mid);
      expect(part, isNotEmpty);
      expect(part.every((p) => p.km <= mid), isTrue);
    });

    test('пустой профиль — null у ближайшей точки', () {
      expect(nearestProfilePoint(const [], 1), isNull);
    });
  });
}
