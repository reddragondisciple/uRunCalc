import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/pace/pace_catalog.dart';
import 'package:ultra_run_calc/features/pace/pace_state_codec.dart';
import 'package:ultra_run_calc/features/pace/pace_table_data.dart';

PaceTableData table({int columns = 3, String firstTime = '0500'}) {
  return PaceTableData(
    columns: columns,
    fitTable: true,
    times: [firstTime, '', ''],
    distances: ['0.00', '11', '20'],
    planTimes: ['', '', ''],
    planPaces: ['', '', ''],
    notes: ['', '', ''],
    water: ['', '', ''],
    food: ['', '', ''],
  );
}

final PaceEvent grutEvent = PaceEvent('GRUT', [
  PaceDistance('T100', 6),
  PaceDistance('T80', 6),
]);

final PaceEvent madFoxEvent = PaceEvent('Mad Fox Ultra', [
  PaceDistance('VR', 9),
  PaceDistance('50M', 5),
]);

Map<String, dynamic> ultraJson({
  List<Map<String, dynamic>>? events,
  String selectedEvent = 'GRUT',
  String selectedDistance = 'T100',
  Map<String, dynamic>? tables,
}) {
  return {
    'events':
        events ??
        [
          {
            'name': 'GRUT',
            'distances': [
              {'name': 'T100', 'checkpoints': 6},
              {'name': 'T80', 'checkpoints': 6},
            ],
          },
          {
            'name': 'Mad Fox Ultra',
            'distances': [
              {'name': 'VR', 'checkpoints': 9},
              {'name': '50M', 'checkpoints': 5},
            ],
          },
        ],
    'selectedEvent': selectedEvent,
    'selectedDistance': selectedDistance,
    'tables': tables ?? <String, dynamic>{},
  };
}

void main() {
  group('PaceCalculatorState', () {
    test('survives a JSON round trip', () {
      const state = PaceCalculatorState(
        calc: 'time',
        distance: '42.2',
        paceMinutes: '4',
        paceSeconds: '30',
        days: '1',
        hours: '02',
        minutes: '03',
        seconds: '04',
      );

      final restored = PaceStateCodec.decodeCalculator(
        PaceStateCodec.encodeCalculator(state),
      );

      expect(restored.toJson(), state.toJson());
    });

    test('replaces non-string values with empty strings', () {
      final restored = PaceStateCodec.decodeCalculator({
        'calc': 7,
        'distance': null,
        'minutes': ['05'],
        'hours': '01',
      });

      expect(restored.calc, '');
      expect(restored.distance, '');
      expect(restored.minutes, '');
      expect(restored.hours, '01');
    });
  });

  group('encodeUltra', () {
    test('stores events without their default tables', () {
      final encoded = PaceStateCodec.encodeUltra(
        events: [grutEvent, madFoxEvent],
        selectedEvent: 'Mad Fox Ultra',
        selectedDistance: 'VR',
        tables: {},
        currentTable: table(firstTime: '2200'),
      );

      expect(encoded['selectedEvent'], 'Mad Fox Ultra');
      expect(encoded['selectedDistance'], 'VR');
      expect(encoded['events'], [
        {
          'name': 'GRUT',
          'distances': [
            {'name': 'T100', 'checkpoints': 6},
            {'name': 'T80', 'checkpoints': 6},
          ],
        },
        {
          'name': 'Mad Fox Ultra',
          'distances': [
            {'name': 'VR', 'checkpoints': 9},
            {'name': '50M', 'checkpoints': 5},
          ],
        },
      ]);
      final tables = encoded['tables'] as Map<String, dynamic>;
      final madFox = tables['Mad Fox Ultra'] as Map<String, dynamic>;
      expect((madFox['VR'] as Map<String, dynamic>)['tableTimes'], [
        '2200',
        '',
        '',
      ]);
    });

    test('the current table overrides an older snapshot', () {
      final encoded = PaceStateCodec.encodeUltra(
        events: [grutEvent],
        selectedEvent: 'GRUT',
        selectedDistance: 'T100',
        tables: {
          PaceStateCodec.tableKey('GRUT', 'T100'): table(firstTime: '0100'),
        },
        currentTable: table(firstTime: '0200'),
      );

      final tables = encoded['tables'] as Map<String, dynamic>;
      final grut = tables['GRUT'] as Map<String, dynamic>;
      expect((grut['T100'] as Map<String, dynamic>)['tableTimes'], [
        '0200',
        '',
        '',
      ]);
    });

    test('does not store the current table when no distance is selected', () {
      final encoded = PaceStateCodec.encodeUltra(
        events: [grutEvent],
        selectedEvent: 'GRUT',
        selectedDistance: '—',
        tables: {},
        currentTable: table(),
      );

      expect(encoded['tables'], isEmpty);
    });

    test('skips table keys without an event separator', () {
      final encoded = PaceStateCodec.encodeUltra(
        events: [grutEvent],
        selectedEvent: 'GRUT',
        selectedDistance: 'T100',
        tables: {'broken-key': table()},
      );

      expect(encoded['tables'], isEmpty);
    });
  });

  group('decodeUltra', () {
    test('restores events, selection and tables', () {
      final encoded = PaceStateCodec.encodeUltra(
        events: [grutEvent, madFoxEvent],
        selectedEvent: 'Mad Fox Ultra',
        selectedDistance: 'VR',
        tables: {
          PaceStateCodec.tableKey('GRUT', 'T80'): table(firstTime: '0600'),
        },
        currentTable: table(firstTime: '2200'),
      );

      final restored = PaceStateCodec.decodeUltra(
        encoded,
        fallbackEvents: [grutEvent],
        fallbackEvent: 'GRUT',
      );

      expect(restored.selectedEvent, 'Mad Fox Ultra');
      expect(restored.selectedDistance, 'VR');
      expect(restored.events.map((event) => event.name), [
        'GRUT',
        'Mad Fox Ultra',
      ]);
      expect(
        restored.tables[PaceStateCodec.tableKey('GRUT', 'T80')]!.times.first,
        '0600',
      );
      expect(
        restored
            .tables[PaceStateCodec.tableKey('Mad Fox Ultra', 'VR')]!
            .times
            .first,
        '2200',
      );
    });

    test('keeps fallback events when stored events are missing', () {
      final restored = PaceStateCodec.decodeUltra(
        {'tables': <String, dynamic>{}},
        fallbackEvents: [grutEvent],
        fallbackEvent: 'GRUT',
      );

      expect(restored.events.single.name, 'GRUT');
      expect(restored.selectedEvent, 'GRUT');
      expect(restored.selectedDistance, 'T100');
    });

    test('ignores an unknown stored event and distance', () {
      final restored = PaceStateCodec.decodeUltra(
        ultraJson(selectedEvent: 'Unknown', selectedDistance: 'Unknown'),
        fallbackEvents: [grutEvent],
        fallbackEvent: 'GRUT',
      );

      expect(restored.selectedEvent, 'GRUT');
      expect(restored.selectedDistance, 'T100');
    });

    test('selects an empty distance placeholder for an event without them', () {
      final restored = PaceStateCodec.decodeUltra(
        ultraJson(
          events: [
            {'name': 'Solo', 'distances': <Map<String, dynamic>>[]},
          ],
          selectedEvent: 'Solo',
        ),
        fallbackEvents: [grutEvent],
        fallbackEvent: 'GRUT',
      );

      expect(restored.selectedEvent, 'Solo');
      expect(restored.selectedDistance, '—');
    });

    test('migrates the legacy 100M distance to VR', () {
      final restored = PaceStateCodec.decodeUltra(
        ultraJson(
          events: [
            {
              'name': 'Mad Fox Ultra',
              'distances': [
                {'name': '100M', 'checkpoints': 9},
                {'name': '50M', 'checkpoints': 5},
              ],
            },
          ],
          selectedEvent: 'Mad Fox Ultra',
          selectedDistance: '100M',
          tables: {
            'Mad Fox Ultra': {'100M': table(firstTime: '1600').toJson()},
          },
        ),
        fallbackEvents: [grutEvent],
        fallbackEvent: 'GRUT',
      );

      expect(
        restored.events.single.distances.map((distance) => distance.name),
        ['VR', '50M'],
      );
      expect(restored.selectedEvent, 'Mad Fox Ultra');
      expect(restored.selectedDistance, 'VR');
      expect(
        restored
            .tables[PaceStateCodec.tableKey('Mad Fox Ultra', 'VR')]!
            .times
            .first,
        '1600',
      );
      expect(
        restored.tables.containsKey(
          PaceStateCodec.tableKey('Mad Fox Ultra', '100M'),
        ),
        isFalse,
      );
    });

    test('keeps the first table when both 100M and VR are stored', () {
      final restored = PaceStateCodec.decodeUltra(
        ultraJson(
          events: [
            {
              'name': 'Mad Fox Ultra',
              'distances': [
                {'name': 'VR', 'checkpoints': 9},
              ],
            },
          ],
          selectedEvent: 'Mad Fox Ultra',
          selectedDistance: 'VR',
          tables: {
            'Mad Fox Ultra': {
              '100M': table(firstTime: '0100').toJson(),
              'VR': table(firstTime: '0200').toJson(),
            },
          },
        ),
        fallbackEvents: [grutEvent],
        fallbackEvent: 'GRUT',
      );

      expect(
        restored
            .tables[PaceStateCodec.tableKey('Mad Fox Ultra', 'VR')]!
            .times
            .first,
        '0100',
      );
    });

    test('clamps checkpoints to the table limits', () {
      final restored = PaceStateCodec.decodeUltra(
        ultraJson(
          events: [
            {
              'name': 'GRUT',
              'distances': [
                {'name': 'T100', 'checkpoints': 0},
                {'name': 'T80', 'checkpoints': 999},
              ],
            },
          ],
        ),
        fallbackEvents: [grutEvent],
        fallbackEvent: 'GRUT',
      );

      expect(
        restored.events.single.distances.map(
          (distance) => distance.checkpoints,
        ),
        [1, PaceStateCodec.maxColumns - 2],
      );
    });

    test('skips malformed events and distances', () {
      final restored = PaceStateCodec.decodeUltra(
        ultraJson(
          events: [
            {'name': '', 'distances': <Map<String, dynamic>>[]},
            {
              'name': 'GRUT',
              'distances': [
                {'name': 'T100', 'checkpoints': '6'},
                {'name': '', 'checkpoints': 6},
                {'name': 'T80', 'checkpoints': 5},
              ],
            },
          ],
        ),
        fallbackEvents: [grutEvent],
        fallbackEvent: 'GRUT',
      );

      expect(restored.events.single.name, 'GRUT');
      expect(
        restored.events.single.distances.map((distance) => distance.name),
        ['T80'],
      );
    });

    test('restores a legacy table stored at the top level', () {
      final restored = PaceStateCodec.decodeUltra(
        {
          ...ultraJson(selectedDistance: 'T80'),
          'columns': 3,
          'fitTable': true,
          'tableTimes': ['0900', '', ''],
        },
        fallbackEvents: [grutEvent],
        fallbackEvent: 'GRUT',
      );

      expect(
        restored.tables[PaceStateCodec.tableKey('GRUT', 'T80')]!.times.first,
        '0900',
      );
    });

    test('skips invalid tables but keeps valid ones', () {
      final restored = PaceStateCodec.decodeUltra(
        ultraJson(
          tables: {
            'GRUT': {
              'T100': {'columns': 'x'},
              'T80': {'columns': 4},
            },
          },
        ),
        fallbackEvents: [grutEvent],
        fallbackEvent: 'GRUT',
      );

      expect(restored.tables.keys, [PaceStateCodec.tableKey('GRUT', 'T80')]);
    });
  });
}
