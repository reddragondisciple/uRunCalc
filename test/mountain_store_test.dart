import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/track_store.dart';
import 'package:ultra_run_calc/features/pace/mountain_data.dart';
import 'package:ultra_run_calc/features/pace/pace_catalog.dart';
import 'package:ultra_run_calc/features/pace/pace_state_controller.dart';
import 'package:ultra_run_calc/features/pace/pace_table_data.dart';

void main() {
  group('MountainData / PaceTableData JSON', () {
    PaceTableData base({MountainData mountain = MountainData.empty}) {
      return PaceTableData(
        columns: 3,
        fitTable: true,
        times: const ['0500', '', ''],
        distances: const ['0', '11', '20'],
        planTimes: const ['', '', ''],
        planPaces: const ['', '', ''],
        notes: const ['', '', ''],
        water: const ['', '', ''],
        food: const ['', '', ''],
        mountain: mountain,
      );
    }

    test('старая таблица без поля mountain читается как обычный режим', () {
      final json = base().toJson()..remove('mountain');
      final restored = PaceTableData.tryFromJson(json)!;
      expect(restored.mountain.enabled, isFalse);
      expect(restored.mountain.tracks.primary, isNull);
      expect(restored.mountain.anchor, isNull);
    });

    test('горные данные переживают сохранение и загрузку', () {
      final mountain = MountainData(
        enabled: true,
        stopsSec: const [0, 600, 0],
        anchor: const PlanAnchor.targetTime(43200),
        tracks: const TrackSlots(
          active: 'backup',
          primary: TrackMeta(
            relativePath: 'primary.gpx',
            originalName: 'GRUT100 - T100.gpx',
            importedAtMs: 1762257600000,
            points: 2290,
            lengthM: 109308.4,
            ascentM: 934.1,
            descentM: 934.1,
            hasElevation: true,
          ),
          backup: TrackMeta(
            relativePath: 'backup.gpx',
            originalName: 'backup.gpx',
            importedAtMs: 1,
            points: 10,
            lengthM: 1,
            ascentM: 0,
            descentM: 0,
            hasElevation: false,
            offsetM: 120,
          ),
        ),
        manualAscent: const [null, 140, null],
        manualDescent: const [null, 60, null],
        showStopsInPace: true,
      );

      final restored = PaceTableData.tryFromJson(
        base(mountain: mountain).toJson(),
      )!.mountain;

      expect(restored.enabled, isTrue);
      expect(restored.stopsSec, [0, 600, 0]);
      expect(restored.anchor!.kind, PlanAnchorKind.targetTime);
      expect(restored.anchor!.targetTotalSec, 43200);
      expect(restored.tracks.active, 'backup');
      expect(restored.tracks.primary!.relativePath, 'primary.gpx');
      expect(restored.tracks.backup!.offsetM, 120);
      expect(restored.manualAscent, [null, 140, null]);
      expect(restored.manualDescent, [null, 60, null]);
      expect(restored.showStopsInPace, isTrue);
    });

    test('испорченные типы не роняют загрузку', () {
      final json = base().toJson()
        ..['mountain'] = {
          'enabled': 'yes',
          'stopsSec': ['x', 5],
          'anchor': {'kind': 'unknown'},
          'tracks': {'active': 'weird', 'primary': 42},
        };
      final mountain = PaceTableData.tryFromJson(json)!.mountain;
      expect(mountain.enabled, isFalse);
      expect(mountain.anchor, isNull);
      expect(mountain.tracks.active, 'primary');
      expect(mountain.tracks.primary, isNull);
      expect(mountain.stopsSec.length, 3);
    });

    test('подводка (offsetM) переживает сохранение таблицы', () {
      final mountain = MountainData(
        enabled: true,
        tracks: const TrackSlots(
          primary: TrackMeta(
            relativePath: 'primary.gpx',
            originalName: 'track.gpx',
            importedAtMs: 1,
            points: 10,
            lengthM: 1000,
            ascentM: 0,
            descentM: 0,
            hasElevation: true,
            offsetM: 333.5,
          ),
        ),
      );
      final restored = PaceTableData.tryFromJson(
        base(mountain: mountain).toJson(),
      )!.mountain;
      expect(restored.tracks.primary!.offsetM, closeTo(333.5, 1e-9));
    });

    test('PlanAnchor.flat сохраняет плоский темп', () {
      final json = const PlanAnchor.flat(360).toJson();
      final restored = PlanAnchor.tryFromJson(json)!;
      expect(restored.kind, PlanAnchorKind.flat);
      expect(restored.flatPaceSec, 360);
    });
  });

  group('trackDistanceKey', () {
    test('стабилен и 16 hex-символов', () {
      final key = trackDistanceKey('GRUT', 'T100');
      expect(key, hasLength(16));
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(key), isTrue);
      expect(trackDistanceKey('GRUT', 'T100'), key);
    });

    test('разные дистанции дают разные ключи', () {
      expect(
        trackDistanceKey('GRUT', 'T100'),
        isNot(trackDistanceKey('GRUT', 'T80')),
      );
      // Разделитель важен: «AB»+«C» не равно «A»+«BC».
      expect(trackDistanceKey('AB', 'C'), isNot(trackDistanceKey('A', 'BC')));
    });
  });

  group('DirectoryTrackFileStore', () {
    late Directory temp;
    late DirectoryTrackFileStore store;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('track_store_test');
      store = DirectoryTrackFileStore(temp);
    });

    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('запись и чтение слота', () async {
      await store.write(
        distanceKey: 'abc',
        fileName: 'primary.gpx',
        content: '<gpx/>',
      );
      expect(
        await store.read(distanceKey: 'abc', fileName: 'primary.gpx'),
        '<gpx/>',
      );
      expect(
        await store.exists(distanceKey: 'abc', fileName: 'primary.gpx'),
        isTrue,
      );
    });

    test('повторная запись перезаписывает файл без .tmp', () async {
      await store.write(
        distanceKey: 'abc',
        fileName: 'primary.gpx',
        content: '1',
      );
      await store.write(
        distanceKey: 'abc',
        fileName: 'primary.gpx',
        content: '2',
      );
      expect(
        await store.read(distanceKey: 'abc', fileName: 'primary.gpx'),
        '2',
      );
      final leftovers = temp
          .listSync(recursive: true)
          .where((e) => e.path.endsWith('.tmp'));
      expect(leftovers, isEmpty);
    });

    test('слоты независимы', () async {
      await store.write(
        distanceKey: 'abc',
        fileName: 'primary.gpx',
        content: 'P',
      );
      await store.write(
        distanceKey: 'abc',
        fileName: 'backup.gpx',
        content: 'B',
      );
      expect(
        await store.read(distanceKey: 'abc', fileName: 'primary.gpx'),
        'P',
      );
      expect(await store.read(distanceKey: 'abc', fileName: 'backup.gpx'), 'B');
    });

    test('отсутствующий файл — null, а не ошибка', () async {
      expect(
        await store.read(distanceKey: 'zzz', fileName: 'primary.gpx'),
        isNull,
      );
    });

    test('удаление дистанции удаляет оба слота и не трогает другие', () async {
      await store.write(
        distanceKey: 'abc',
        fileName: 'primary.gpx',
        content: 'P',
      );
      await store.write(
        distanceKey: 'abc',
        fileName: 'backup.gpx',
        content: 'B',
      );
      await store.write(
        distanceKey: 'other',
        fileName: 'primary.gpx',
        content: 'O',
      );

      await store.deleteDistance('abc');

      expect(
        await store.exists(distanceKey: 'abc', fileName: 'primary.gpx'),
        isFalse,
      );
      expect(
        await store.exists(distanceKey: 'abc', fileName: 'backup.gpx'),
        isFalse,
      );
      expect(
        await store.read(distanceKey: 'other', fileName: 'primary.gpx'),
        'O',
      );
    });

    test('удаление несуществующей дистанции не ошибка', () async {
      await store.deleteDistance('none');
    });
  });

  group('PaceStateController: удаление дистанции', () {
    test('запоминает удалённую дистанцию и отдаёт её один раз', () {
      final event = PaceEvent('GRUT', [
        PaceDistance('T100', 6),
        PaceDistance('T80', 6),
      ]);
      final controller = PaceStateController(
        events: [event],
        selectedEvent: 'GRUT',
        selectedDistance: 'T100',
      );

      expect(controller.removeDistance(event, 'T80'), isTrue);
      expect(controller.takeRemovedDistances(), [('GRUT', 'T80')]);
      expect(controller.takeRemovedDistances(), isEmpty);
    });

    test('последнюю дистанцию удалить нельзя, список не меняется', () {
      final event = PaceEvent('GRUT', [PaceDistance('T100', 6)]);
      final controller = PaceStateController(
        events: [event],
        selectedEvent: 'GRUT',
        selectedDistance: 'T100',
      );

      expect(controller.removeDistance(event, 'T100'), isFalse);
      expect(controller.takeRemovedDistances(), isEmpty);
    });
  });
}
