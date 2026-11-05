import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/checkpoint_matching.dart';
import 'package:ultra_run_calc/features/gpx/checkpoint_names.dart';
import 'package:ultra_run_calc/features/gpx/gpx_parser.dart';
import 'package:ultra_run_calc/features/gpx/gpx_track.dart';
import 'package:ultra_run_calc/features/gpx/track_metrics.dart';

void main() {
  group('normalizeCheckpointName', () {
    test('CP и СР дают одну метку', () {
      expect(normalizeCheckpointName('CP3').labels, ['CP3']);
      expect(normalizeCheckpointName('СР9').labels, ['CP9']);
    });

    test('CP2/5 — две метки', () {
      expect(normalizeCheckpointName('CP2/5').labels, ['CP2', 'CP5']);
    });

    test('Start/Finish — два ярлыка', () {
      expect(normalizeCheckpointName('Start/Finish').labels, [
        'START',
        'FINISH',
      ]);
    });

    test('CC start — старт, CC end — не ПП', () {
      expect(normalizeCheckpointName('CC start').labels, ['START']);
      expect(normalizeCheckpointName('CC end').labels, isEmpty);
    });

    test('суффикс в скобках и через дефис идёт в заметку, метка остаётся', () {
      final a = normalizeCheckpointName('CP3 (Заброска)');
      expect(a.labels, ['CP3']);
      expect(a.suffixNote, '(Заброска)');

      final b = normalizeCheckpointName('CP3-Вода');
      expect(b.labels, ['CP3']);
      expect(b.suffixNote, 'Вода');
    });

    test('не-ПП (MP, Брод, ToD) — kind other, без заметки', () {
      for (final name in ['MP1', 'Брод', 'ToD end', 'Понтон', 'MFU K40']) {
        final n = normalizeCheckpointName(name);
        expect(n.kind, CheckpointKind.other, reason: name);
        expect(n.labels, isEmpty, reason: name);
        expect(n.suffixNote, isEmpty, reason: name);
      }
    });
  });

  group('mergeNote', () {
    test('пустая заметка получает суффикс', () {
      expect(mergeNote('', 'Вода'), 'Вода');
    });

    test('непустая заметка дополняется через точку', () {
      expect(mergeNote('Гель', 'Вода'), 'Гель · Вода');
    });

    test('дубликат не дописывается повторно', () {
      expect(mergeNote('Гель · Вода', 'Вода'), 'Гель · Вода');
    });

    test('пустой суффикс не меняет заметку', () {
      expect(mergeNote('Гель', ''), 'Гель');
    });
  });

  group('matching на фикстуре', () {
    late GpxTrack track;
    late TrackMetrics metrics;

    setUp(() {
      track = parseGpx(File('test/fixtures/hill.gpx').readAsStringSync());
      metrics = computeTrackMetrics(track);
    });

    test('точка на треке даёт проходку, далёкая точка — нет', () {
      final cands = buildCandidates(track, metrics);
      final cp1 = cands.firstWhere((c) => c.rawName == 'CP1 (Заброска)');
      expect(cp1.onTrack, isTrue);
      expect(cp1.passes, isNotEmpty);
    });

    test('колонка получает ближайшую проходку по имени', () {
      final cands = buildCandidates(track, metrics);
      final sug = suggestColumns(
        columnLabels: const ['START', 'CP1', 'FINISH'],
        columnDistancesM: [
          0,
          metrics.totalDistance2d / 2,
          metrics.totalDistance2d,
        ],
        candidates: cands,
        trackLengthM: metrics.totalDistance2d,
      );
      expect(sug[1].candidate!.rawName, 'CP1 (Заброска)');
    });
  });

  group('matching на реальном GRUT T100', () {
    test('колонки совпадают с таблицей сравнения из переписки', () {
      final file = File('GRUT100 - T100.gpx');
      expect(file.existsSync(), isTrue, reason: 'трек должен лежать в корне');
      final track = parseGpx(file.readAsStringSync());
      final metrics = computeTrackMetrics(track);
      final cands = buildCandidates(track, metrics);

      const labels = [
        'START',
        'CP1',
        'CP2',
        'CP3',
        'CP4',
        'CP5',
        'CP6',
        'FINISH',
      ];
      const cols = [
        0.0,
        11000.0,
        18800.0,
        30000.0,
        70200.0,
        94000.0,
        102200.0,
        109500.0,
      ];
      final sug = suggestColumns(
        columnLabels: labels,
        columnDistancesM: cols,
        candidates: cands,
        trackLengthM: metrics.totalDistance2d,
      );

      double km(int i) => sug[i].pass!.distanceM / 1000;
      expect(km(0), closeTo(0.00, 0.01));
      expect(km(1), closeTo(10.84, 0.02));
      expect(km(2), closeTo(18.76, 0.02));
      expect(km(3), closeTo(30.09, 0.02));
      expect(km(4), closeTo(70.17, 0.02));
      expect(km(5), closeTo(94.00, 0.02));
      expect(km(6), closeTo(102.14, 0.02));
      expect(km(7), closeTo(109.31, 0.02));
      expect(sug.every((s) => s.checked), isTrue);
    });

    test('ToD end вне трека в радиусе 100 м — не автоподсказка', () {
      final track = parseGpx(File('GRUT100 - T100.gpx').readAsStringSync());
      final metrics = computeTrackMetrics(track);
      final tod = buildCandidates(
        track,
        metrics,
      ).firstWhere((c) => c.rawName == 'ToD end');
      expect(tod.passes.single.offsetFromTrackM, greaterThan(100));
    });
  });
}
