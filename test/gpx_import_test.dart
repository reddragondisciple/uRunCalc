import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/checkpoint_matching.dart';
import 'package:ultra_run_calc/features/gpx/checkpoint_names.dart';
import 'package:ultra_run_calc/features/gpx/gpx_import.dart';

/// Подсказка-заглушка: только проходка и кандидат с суффиксом.
ColumnSuggestion suggestion({
  required int column,
  required double km,
  String suffix = '',
}) {
  final candidate = CheckpointCandidate(
    rawName: 'x',
    name: CheckpointName(
      labels: const [],
      suffixNote: suffix,
      kind: CheckpointKind.numbered,
    ),
    passes: const [],
    onTrack: true,
  );
  return ColumnSuggestion(
    column: column,
    candidate: candidate,
    pass: TrackPass(index: 0, distanceM: km * 1000, offsetFromTrackM: 0),
    checked: true,
  );
}

void main() {
  group('startNeedsDecision', () {
    test('старт дальше 200 м спрашиваем', () {
      expect(startNeedsDecision(250), isTrue);
      expect(startNeedsDecision(-250), isTrue);
      expect(startNeedsDecision(150), isFalse);
    });
  });

  group('формат километров', () {
    test('целые без дробной части, иначе до сотых', () {
      expect(formatKm(109.0), '109');
      expect(formatKm(109.31), '109.31');
      expect(formatKm(40.2004), '40.2');
    });
  });

  group('режим «только финиш»', () {
    test('меняется только финиш, промежуточные ПП не трогаются', () {
      final result = applyGpxImport(
        mode: GpxImportMode.finishOnly,
        distances: const [
          '0',
          '11',
          '18.8',
          '30',
          '70.2',
          '94',
          '102.2',
          '109.5',
        ],
        notes: const ['', '', '', '', '', '', '', ''],
        finishKm: 109.31,
      );
      expect(result.ok, isTrue);
      expect(result.distances.sublist(0, 7), [
        '0',
        '11',
        '18.8',
        '30',
        '70.2',
        '94',
        '102.2',
      ]);
      expect(result.distances.last, '109.31');
      expect(result.changedColumns, [7]);
    });

    test('финиш раньше последнего ПП — отказ', () {
      final result = applyGpxImport(
        mode: GpxImportMode.finishOnly,
        distances: const ['0', '11', '20', '30'],
        notes: const ['', '', '', ''],
        finishKm: 19,
      );
      expect(result.ok, isFalse);
      expect(result.error, GpxImportError.finishBeforeLastCheckpoint);
    });
  });

  group('режим «финиш + чекпойнты»', () {
    test('применяет только отмеченные колонки', () {
      final result = applyGpxImport(
        mode: GpxImportMode.checkpoints,
        distances: const ['0', '11', '18.8', '30', '109.5'],
        notes: const ['', '', '', '', ''],
        finishKm: 109.31,
        choices: [
          ColumnChoice(column: 1, pass: suggestion(column: 1, km: 10.84)),
          // CP3 не отмечен: колонка 3 не меняется.
          ColumnChoice(column: 2, pass: null),
        ],
      );
      expect(result.ok, isTrue);
      expect(result.distances[1], '10.84');
      expect(result.distances[2], '18.8');
      expect(result.distances[3], '30');
    });

    test('суффикс кандидата дописывается в заметку колонки', () {
      final result = applyGpxImport(
        mode: GpxImportMode.checkpoints,
        distances: const ['0', '11', '30'],
        notes: const ['', 'Гель', ''],
        finishKm: 30,
        choices: [
          ColumnChoice(
            column: 1,
            pass: suggestion(column: 1, km: 10.84, suffix: 'Вода'),
          ),
        ],
      );
      expect(result.notes[1], 'Гель · Вода');
    });

    test('финиш привязывается к концу трека, даже если не выбран', () {
      final result = applyGpxImport(
        mode: GpxImportMode.checkpoints,
        distances: const ['0', '11', '109.5'],
        notes: const ['', '', ''],
        finishKm: 109.31,
      );
      expect(result.distances.last, '109.31');
    });

    test('результат с убывающими расстояниями отклоняется', () {
      final result = applyGpxImport(
        mode: GpxImportMode.checkpoints,
        distances: const ['0', '11', '30'],
        notes: const ['', '', ''],
        finishKm: 30,
        choices: [ColumnChoice(column: 1, pass: suggestion(column: 1, km: 40))],
      );
      expect(result.ok, isFalse);
      expect(result.error, GpxImportError.nonMonotonicDistances);
    });
  });
}
