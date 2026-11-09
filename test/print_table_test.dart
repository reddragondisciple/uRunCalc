import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/elevation_profile.dart';
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
      activeTrack: 'Основной',
      elevationPairs: ['', '120-80', '340-210', '1800-1600'],
      totalAscent: '2260',
      totalDescent: '1890',
      elevationKms: [0, 11, 18.8, 109.5],
      profile: [
        ProfilePoint(km: 0, eleM: 100, gradeFraction: 0),
        ProfilePoint(km: 5, eleM: 220, gradeFraction: 0.04),
        ProfilePoint(km: 11, eleM: 180, gradeFraction: 0.07),
        ProfilePoint(km: 18.8, eleM: 400, gradeFraction: 0.16),
        ProfilePoint(km: 60, eleM: 300, gradeFraction: -0.03),
        ProfilePoint(km: 109.5, eleM: 120, gradeFraction: -0.01),
      ],
    );

    final portrait = await buildTablePdf(data, landscape: false);
    expect(portrait.length, greaterThan(1000));
    expect(String.fromCharCodes(portrait.take(4)), '%PDF');

    final landscape = await buildTablePdf(data, landscape: true);
    expect(landscape.length, greaterThan(1000));
    expect(String.fromCharCodes(landscape.take(4)), '%PDF');
  });

  test(
    'buildTablePdf splits many columns and draws an elevation chart',
    () async {
      final columns = ['Start', for (var i = 1; i <= 13; i++) '$i', 'Finish'];
      final count = columns.length;
      final distances = ['0', for (var i = 1; i < count; i++) '${i * 8}'];
      final data = PrintTableData(
        event: 'GRUT · T100',
        columns: columns,
        times: [for (var i = 0; i < count; i++) '05:${'$i'.padLeft(2, '0')}'],
        distances: distances,
        segmentPaces: ['PACE', for (var i = 1; i < count; i++) '11:30'],
        planTimes: [
          for (var i = 0; i < count; i++) '05:${'$i'.padLeft(2, '0')}',
        ],
        planPaces: ['PACE', for (var i = 1; i < count; i++) '11:45'],
        water: [for (var i = 0; i < count; i++) i.isEven ? '' : '500 мл'],
        food: [for (var i = 0; i < count; i++) i.isEven ? '' : 'гель'],
        limitTime: '18:00',
        limitPace: '9:51',
        plannedPace: '9:51',
        plannedTime: '18:00',
        activeTrack: 'Резервный',
        elevationPairs: [
          '',
          for (var i = 1; i < count; i++) '${100 + i * 10}-${80 + i * 5}',
        ],
        totalAscent: '2260',
        totalDescent: '1890',
        elevationKms: [
          for (final distance in distances) double.parse(distance),
        ],
        profile: [
          for (var i = 0; i <= 60; i++)
            ProfilePoint(
              km: i * 2,
              eleM: 300 + (i % 7) * 70,
              gradeFraction: (i % 5 - 2) * 0.04,
            ),
        ],
      );

      final landscape = await buildTablePdf(data, landscape: true);
      expect(String.fromCharCodes(landscape.take(4)), '%PDF');

      final portrait = await buildTablePdf(data, landscape: false);
      expect(String.fromCharCodes(portrait.take(4)), '%PDF');
    },
  );
}
