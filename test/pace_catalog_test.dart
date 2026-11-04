import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/pace/pace_catalog.dart';

void main() {
  group('defaults', () {
    test('contain the built-in events and distances', () {
      final events = PaceCatalog.defaults();

      expect(events.map((event) => event.name), ['GRUT', 'Mad Fox Ultra']);
      expect(events.first.distances.map((distance) => distance.name), [
        'T100',
        'T80',
        'T50',
      ]);
      expect(events.last.distances.map((distance) => distance.name), [
        'VR',
        '50M',
        'K70',
        'K40',
      ]);
      expect(events.first.distances.first.checkpoints, 6);
      expect(events.last.distances.first.checkpoints, 9);
    });

    test('fill the known distances with start values', () {
      final events = PaceCatalog.defaults();

      final t100 = events.first.distances.first;
      expect(t100.defaultTimes, isNotEmpty);
      expect(t100.defaultDistances.first, '');
      expect(t100.defaultTimes.first, '0500');

      final vr = events.last.distances.first;
      expect(vr.defaultTimes, isNotEmpty);
      expect(vr.defaultDistances.first, '');
      expect(vr.defaultTimes.first, '1600');
    });

    test('return fresh mutable lists on every call', () {
      final first = PaceCatalog.defaults();
      final second = PaceCatalog.defaults();

      first.first.distances.add(PaceDistance('NEW', 3));

      expect(second.first.distances.map((distance) => distance.name), [
        'T100',
        'T80',
        'T50',
      ]);
    });
  });

  group('prepareDistanceDefaults', () {
    test('renames the legacy 100M distance and adds VR defaults', () {
      final events = [
        PaceEvent(PaceCatalog.madFoxEvent, [
          PaceDistance(PaceCatalog.legacyVrDistance, 9),
          PaceDistance('50M', 5),
        ]),
      ];

      PaceCatalog.prepareDistanceDefaults(events);

      expect(events.single.distances.map((distance) => distance.name), [
        PaceCatalog.vrDistance,
        '50M',
      ]);
      expect(events.single.distances.first.defaultTimes, isNotEmpty);
    });

    test('adds defaults to GRUT T100 when they are missing', () {
      final events = [
        PaceEvent('GRUT', [PaceDistance('T100', 6)]),
      ];

      PaceCatalog.prepareDistanceDefaults(events);

      expect(events.single.distances.first.defaultTimes.first, '0500');
      expect(events.single.distances.first.defaultDistances, isNotEmpty);
    });

    test('keeps already loaded defaults untouched', () {
      final events = [
        PaceEvent('GRUT', [
          PaceDistance(
            'T100',
            6,
            defaultTimes: ['0100'],
            defaultDistances: ['', '5'],
          ),
        ]),
      ];

      PaceCatalog.prepareDistanceDefaults(events);

      expect(events.single.distances.first.defaultTimes, ['0100']);
      expect(events.single.distances.first.defaultDistances, ['', '5']);
    });

    test('is idempotent', () {
      final events = PaceCatalog.defaults();

      PaceCatalog.prepareDistanceDefaults(events);
      PaceCatalog.prepareDistanceDefaults(events);

      expect(
        events.first.distances.first.defaultTimes,
        PaceCatalog.defaults().first.distances.first.defaultTimes,
      );
    });
  });

  test('findDistance returns a distance or null', () {
    final events = PaceCatalog.defaults();

    expect(
      PaceCatalog.findDistance(events, 'Mad Fox Ultra', 'VR')?.checkpoints,
      9,
    );
    expect(PaceCatalog.findDistance(events, 'GRUT', 'unknown'), isNull);
    expect(PaceCatalog.findDistance(events, 'unknown', 'T100'), isNull);
  });
}
