import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/pace/pace_catalog.dart';
import 'package:ultra_run_calc/features/pace/pace_state_codec.dart';
import 'package:ultra_run_calc/features/pace/pace_state_controller.dart';
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

void main() {
  group('defaults', () {
    test('select the first built-in event and distance', () {
      final controller = PaceStateController.defaults();

      expect(controller.selectedEvent, 'GRUT');
      expect(controller.selectedDistance, 'T100');
      expect(controller.events.length, 2);
      expect(controller.currentDistance!.checkpoints, 6);
      expect(controller.stateLoaded, isFalse);
    });
  });

  group('current table', () {
    test('is stored under the selected event and distance', () {
      final controller = PaceStateController.defaults();

      controller.saveCurrent(table(firstTime: '0600'));

      expect(controller.tableFor('GRUT', 'T100')!.times.first, '0600');
      expect(controller.tableFor('GRUT', 'T80'), isNull);
      expect(controller.currentTable!.times.first, '0600');
    });

    test('is not stored without a distance', () {
      final controller = PaceStateController.defaults();
      controller.selectedDistance = PaceCatalog.noDistance;

      controller.saveCurrent(table(firstTime: '9999'));

      expect(controller.currentTable, isNull);
      expect(
        controller.encode(snapshot: table()).toString(),
        isNot(contains('9999')),
      );
    });

    test('the snapshot passed to encode overrides the stored table', () {
      final controller = PaceStateController.defaults();
      controller.saveCurrent(table(firstTime: '0100'));

      final encoded = controller.encode(snapshot: table(firstTime: '0200'));
      final tables = encoded['tables'] as Map<String, dynamic>;
      final grut = tables['GRUT'] as Map<String, dynamic>;

      expect((grut['T100'] as Map<String, dynamic>)['tableTimes'], [
        '0200',
        '',
        '',
      ]);
    });
  });

  test('select switches the current event and distance', () {
    final controller = PaceStateController.defaults();
    final madFox = controller.eventNamed(PaceCatalog.madFoxEvent);

    controller.select(madFox, madFox.distances.first);

    expect(controller.selectedEvent, PaceCatalog.madFoxEvent);
    expect(controller.selectedDistance, PaceCatalog.vrDistance);
    expect(controller.eventLabel, 'Mad Fox Ultra · VR');
  });

  test('apply replaces events, selection and tables', () {
    final controller = PaceStateController.defaults();
    controller.saveCurrent(table(firstTime: '0100'));

    final state = PaceStateCodec.decodeUltra(
      {
        'events': [
          {
            'name': 'Solo',
            'distances': [
              {'name': 'One', 'checkpoints': 4},
            ],
          },
        ],
        'selectedEvent': 'Solo',
        'selectedDistance': 'One',
        'tables': {
          'Solo': {'One': table(firstTime: '0900').toJson()},
        },
      },
      fallbackEvents: controller.events,
      fallbackEvent: controller.selectedEvent,
    );

    controller.apply(state);

    expect(controller.events.single.name, 'Solo');
    expect(controller.selectedEvent, 'Solo');
    expect(controller.selectedDistance, 'One');
    expect(controller.tableFor('Solo', 'One')!.times.first, '0900');
    expect(controller.tableFor('GRUT', 'T100'), isNull);
  });

  group('events', () {
    test('add rejects duplicates and accepts a new name', () {
      final controller = PaceStateController.defaults();

      expect(controller.addEvent('GRUT'), isFalse);
      expect(controller.events.length, 2);

      expect(controller.addEvent('New race'), isTrue);
      expect(controller.events.last.name, 'New race');
      expect(controller.events.last.distances, isEmpty);
    });

    test('remove refuses the last event', () {
      final controller = PaceStateController(
        events: [
          PaceEvent('Only', [PaceDistance('One', 3)]),
        ],
        selectedEvent: 'Only',
        selectedDistance: 'One',
      );

      expect(controller.removeEvent('Only'), isFalse);
      expect(controller.events.single.name, 'Only');
    });

    test('remove deletes the tables of that event only', () {
      final controller = PaceStateController.defaults();
      controller.saveCurrent(table(firstTime: '0100'));

      expect(controller.removeEvent('Mad Fox Ultra'), isTrue);

      expect(controller.events.map((event) => event.name), ['GRUT']);
      expect(controller.selectedEvent, 'GRUT');
      expect(controller.selectedDistance, 'T100');
      expect(controller.tableFor('GRUT', 'T100')!.times.first, '0100');
    });

    test('remove of the selected event falls back to the first one', () {
      final controller = PaceStateController.defaults();
      final madFox = controller.eventNamed(PaceCatalog.madFoxEvent);
      controller.select(madFox, madFox.distances.first);
      controller.saveCurrent(table(firstTime: '1600'));

      expect(controller.removeEvent(PaceCatalog.madFoxEvent), isTrue);

      expect(controller.selectedEvent, 'GRUT');
      expect(controller.selectedDistance, 'T100');
      expect(
        controller.tableFor(PaceCatalog.madFoxEvent, PaceCatalog.vrDistance),
        isNull,
      );
    });

    test('remove of an event without distances selects the placeholder', () {
      final controller = PaceStateController(
        events: [
          PaceEvent('Empty', []),
          PaceEvent('Full', [PaceDistance('One', 3)]),
        ],
        selectedEvent: 'Full',
        selectedDistance: 'One',
      );

      controller.removeEvent('Full');

      expect(controller.selectedEvent, 'Empty');
      expect(controller.selectedDistance, PaceCatalog.noDistance);
    });
  });

  group('distances', () {
    test('add rejects duplicates and accepts a new distance', () {
      final controller = PaceStateController.defaults();
      final grut = controller.eventNamed('GRUT');

      expect(controller.addDistance(grut, 'T100', 6), isFalse);
      expect(controller.addDistance(grut, 'T25', 2), isTrue);
      expect(grut.distances.last.name, 'T25');
      expect(grut.distances.last.checkpoints, 2);
    });

    test('remove refuses the last distance', () {
      final controller = PaceStateController(
        events: [
          PaceEvent('Race', [PaceDistance('One', 3)]),
        ],
        selectedEvent: 'Race',
        selectedDistance: 'One',
      );

      expect(
        controller.removeDistance(controller.events.single, 'One'),
        isFalse,
      );
      expect(controller.events.single.distances.single.name, 'One');
    });

    test('remove deletes only that table and keeps the selection', () {
      final controller = PaceStateController.defaults();
      final grut = controller.eventNamed('GRUT');
      final t100 = grut.distances.first;
      final t80 = grut.distances[1];
      controller.saveCurrent(table(firstTime: '0100'));

      expect(controller.removeDistance(grut, t80.name), isTrue);

      expect(controller.selectedEvent, 'GRUT');
      expect(controller.selectedDistance, 'T100');
      expect(controller.currentDistance, same(t100));
      expect(controller.tableFor('GRUT', 'T80'), isNull);
    });

    test('remove of the selected distance falls back to the first one', () {
      final controller = PaceStateController.defaults();
      final grut = controller.eventNamed('GRUT');
      controller.selectedDistance = 'T80';
      controller.saveCurrent(table(firstTime: '0700'));

      expect(controller.removeDistance(grut, 'T80'), isTrue);

      expect(controller.selectedDistance, 'T100');
      expect(controller.tableFor('GRUT', 'T80'), isNull);
    });
  });
}
