import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/print_table.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildTablePdf produces portrait and landscape documents', () async {
    const data = PrintTableData(
      event: 'GRUT · T100',
      columns: ['Start', '1', '2', 'Finish'],
      times: ['05:00', '07:00', '08:00', '23:00'],
      distances: ['0.00', '11', '18.8', '109.5'],
      segmentPaces: ['PACE', '10:54', '12:48', '15:30'],
      planTimes: ['05:00', '07:00', '08:00', '23:00'],
      planPaces: ['PACE', '10:54', '12:48', '15:30'],
      water: ['', '500 мл', '1 л', ''],
      food: ['', 'гель', 'батончик', ''],
      limitTime: '18:00',
      limitPace: '9:51',
      plannedPace: '9:51',
      plannedTime: '18:00',
      boldColumns: [2],
      dayIndexes: [0, 1, 2, 3],
    );

    final portrait = await buildTablePdf(data, landscape: false);
    expect(portrait.length, greaterThan(1000));
    expect(String.fromCharCodes(portrait.take(4)), '%PDF');

    final landscape = await buildTablePdf(data, landscape: true);
    expect(landscape.length, greaterThan(1000));
    expect(String.fromCharCodes(landscape.take(4)), '%PDF');
  });
}
