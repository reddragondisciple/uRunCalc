import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/pace/pace_table_data.dart';

void main() {
  PaceTableData sample() => PaceTableData(
    columns: 3,
    fitTable: true,
    times: ['0500', '0700', '0800'],
    distances: ['0.00', '10', '20'],
    planTimes: ['0500', '0730', '0800'],
    planPaces: ['', '0730', '0830'],
    notes: ['Start', '', 'Finish'],
    water: ['', '500 мл', ''],
    food: ['', 'гель', ''],
    boldColumns: [1],
  );

  test('survives a JSON round trip', () {
    final restored = PaceTableData.tryFromJson(sample().toJson());

    expect(restored, isNotNull);
    expect(restored!.columns, 3);
    expect(restored.fitTable, isTrue);
    expect(restored.times, ['0500', '0700', '0800']);
    expect(restored.planTimes, ['0500', '0730', '0800']);
    expect(restored.notes, ['Start', '', 'Finish']);
    expect(restored.boldColumns, [1]);
    expect(restored.seeded, isFalse);
  });

  test('lists are immutable after construction', () {
    final data = sample();

    expect(() => data.times[0] = '0900', throwsUnsupportedError);
    expect(() => data.boldColumns.add(2), throwsUnsupportedError);
  });

  test('normalizes JSON lists to the column count', () {
    final restored = PaceTableData.tryFromJson({
      'columns': 5,
      'tableTimes': ['0500'],
    });

    expect(restored!.times.length, 5);
    expect(restored.times.first, '0500');
    expect(restored.times.last, '');
  });

  test('rejects invalid columns and clamps large values', () {
    expect(PaceTableData.tryFromJson({'columns': 'x'}), isNull);

    final clamped = PaceTableData.tryFromJson({'columns': 100});
    expect(clamped!.columns, 20);
  });

  test('detects an empty table', () {
    final empty = PaceTableData.tryFromJson({'columns': 3});

    expect(empty!.isEmpty, isTrue);
    expect(sample().isEmpty, isFalse);
  });
}
