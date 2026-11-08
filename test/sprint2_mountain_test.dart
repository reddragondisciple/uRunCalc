import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ultra_run_calc/core/app_strings.dart';
import 'package:ultra_run_calc/features/gpx/track_store.dart';
import 'package:ultra_run_calc/main.dart';

import 'elevation_row_widget_test.dart' show usePhoneSize;

String _key(String event, String distance) =>
    '${trackDistanceKey(event, distance)}/primary.gpx';

Map<String, dynamic> _trackMeta() => {
  'relativePath': 'primary.gpx',
  'originalName': 'hill.gpx',
  'importedAtMs': 1,
  'points': 6,
  'lengthM': 1500,
  'ascentM': 50,
  'descentM': 50,
  'hasElevation': true,
  'offsetM': 0,
};

Map<String, dynamic> _table({
  bool mountain = false,
  Map<String, dynamic>? tracks,
  Map<String, dynamic>? anchor,
  String? start,
  int columns = 8,
}) {
  final times = List.filled(columns, '');
  if (start != null) times[0] = start;
  return {
    'columns': columns,
    'fitTable': true,
    'tableTimes': times,
    'tableDistances': [
      '0',
      '11',
      '18.8',
      '30',
      '70.2',
      '94',
      '102.2',
      '109.5',
    ].sublist(0, columns),
    'planTimes': List.filled(columns, ''),
    'planPaces': List.filled(columns, ''),
    'notes': List.filled(columns, ''),
    'water': List.filled(columns, ''),
    'food': List.filled(columns, ''),
    'mountain': {'enabled': mountain, 'tracks': ?tracks, 'anchor': ?anchor},
  };
}

Map<String, dynamic> _tracks() => {
  'active': 'primary',
  'primary': _trackMeta(),
};

Map<String, dynamic> _state({
  required List<Map<String, dynamic>> events,
  required String selectedDistance,
  required Map<String, Map<String, dynamic>> tables,
  String selectedEvent = 'GRUT',
}) => {
  'events': events,
  'selectedEvent': selectedEvent,
  'selectedDistance': selectedDistance,
  'tables': tables,
};

Map<String, dynamic> _oneDistanceState({
  bool mountain = true,
  Map<String, dynamic>? tracks,
  Map<String, dynamic>? anchor,
  String? start,
}) => _state(
  events: [
    {
      'name': 'GRUT',
      'distances': [
        {'name': 'T100', 'checkpoints': 6},
      ],
    },
  ],
  selectedDistance: 'T100',
  tables: {
    'GRUT': {
      'T100': _table(
        mountain: mountain,
        tracks: tracks,
        anchor: anchor,
        start: start,
      ),
    },
  },
);

Map<String, dynamic> _twoDistanceState() => _state(
  events: [
    {
      'name': 'GRUT',
      'distances': [
        {'name': 'T100', 'checkpoints': 6},
        {'name': 'T80', 'checkpoints': 4},
      ],
    },
  ],
  selectedDistance: 'T100',
  tables: {
    'GRUT': {
      'T100': _table(mountain: true, tracks: _tracks()),
      'T80': _table(mountain: true, tracks: _tracks(), columns: 6),
    },
  },
);

class _MemoryTrackStore implements TrackFileStore {
  _MemoryTrackStore(this.files);

  final Map<String, String> files;
  final List<String> reads = [];
  final Map<String, Completer<String?>> delayed = {};

  @override
  Future<String?> read({
    required String distanceKey,
    required String fileName,
  }) {
    final key = '$distanceKey/$fileName';
    reads.add(key);
    final pending = delayed.remove(key);
    if (pending != null) return pending.future;
    return Future.value(files[key]);
  }

  @override
  Future<void> write({
    required String distanceKey,
    required String fileName,
    required String content,
  }) async {
    files['$distanceKey/$fileName'] = content;
  }

  @override
  Future<void> deleteDistance(String distanceKey) async {
    files.removeWhere((key, _) => key.startsWith('$distanceKey/'));
  }

  @override
  Future<bool> exists({
    required String distanceKey,
    required String fileName,
  }) async => files.containsKey('$distanceKey/$fileName');
}

Future<void> _pumpApp(
  WidgetTester tester,
  Map<String, dynamic> state, {
  String mode = 'simple',
}) async {
  SharedPreferences.setMockInitialValues({
    'app_mode_v1': mode,
    'ultra_state_v1': jsonEncode(state),
  });
  await tester.pumpWidget(const CalculatorApp());
  await tester.pumpAndSettle();
}

Future<void> _switchMode(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('mode-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _switchDistance(
  WidgetTester tester,
  String event,
  String distance,
) async {
  await tester.tap(find.byKey(const ValueKey('pace-event-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(event));
  await tester.pumpAndSettle();
  await tester.tap(find.text(distance));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey('pace-key-$key')));
  await tester.pump();
}

Future<void> _enterTime(
  WidgetTester tester,
  String fieldKey,
  String digits,
) async {
  await tester.ensureVisible(find.byKey(ValueKey(fieldKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(fieldKey)));
  await tester.pumpAndSettle();
  for (final char in digits.split('')) {
    await _tapKey(tester, char);
  }
}

Finder _textIn(String key, String text) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(text));

/// GPX с заданными высотами: набор/сброс легко отличить по итогу.
String _gpxWithElevations(List<int> elevations) {
  final points = StringBuffer();
  for (var i = 0; i < elevations.length; i++) {
    final lat = 56.0 + i * 0.0045;
    points.writeln(
      '<trkpt lat="${lat.toStringAsFixed(4)}" lon="38.0">'
      '<ele>${elevations[i]}</ele></trkpt>',
    );
  }
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">'
      '<trk><trkseg>$points</trkseg></trk></gpx>';
}

void main() {
  setUp(() {
    debugParseTrackSynchronously = true;
  });

  tearDown(() {
    debugParseTrackSynchronously = false;
    debugTrackFileStoreOverride = null;
    debugPaceStateLoaderOverride = null;
  });

  testWidgets(
    'смена дистанции во время чтения трека загружает актуальный трек',
    (tester) async {
      usePhoneSize(tester);

      final store = _MemoryTrackStore({
        _key('GRUT', 'T80'): _gpxWithElevations([300, 400, 500, 500, 400, 300]),
      });
      final pendingT100 = Completer<String?>();
      store.delayed[_key('GRUT', 'T100')] = pendingT100;
      debugTrackFileStoreOverride = store;

      await _pumpApp(tester, _twoDistanceState());
      await _switchMode(tester, 'Ultra');

      // Первый трек читается и «завис» — пользователь успевает переключиться.
      expect(store.reads, contains(_key('GRUT', 'T100')));
      await _switchDistance(tester, 'GRUT', 'T80');

      pendingT100.complete(File('test/fixtures/hill.gpx').readAsStringSync());
      await tester.pumpAndSettle();

      // Старый результат не применён, прочитан и показан трек T80 (набор 200).
      expect(store.reads, contains(_key('GRUT', 'T80')));
      expect(find.text(AppStrings.paceTotalAscentLine('200')), findsOneWidget);
      expect(find.text(AppStrings.paceTotalAscentLine('50')), findsNothing);
    },
  );

  testWidgets('включение горного режима подгружает трек и считает план', (
    tester,
  ) async {
    usePhoneSize(tester);
    final store = _MemoryTrackStore({
      _key('GRUT', 'T100'): File('test/fixtures/hill.gpx').readAsStringSync(),
    });
    debugTrackFileStoreOverride = store;

    await _pumpApp(
      tester,
      _oneDistanceState(
        mountain: false,
        tracks: _tracks(),
        anchor: {'kind': 'flat', 'flatPaceSec': 300.0},
        start: '0800',
      ),
    );
    await _switchMode(tester, 'Ultra');

    expect(find.byKey(const ValueKey('pace-elevation-label')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('pace-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pace-settings-mountain')));
    await tester.pumpAndSettle();

    // Трек подгрузился: ряд высот и D+ на месте.
    expect(find.byKey(const ValueKey('pace-elevation-label')), findsOneWidget);
    expect(find.text(AppStrings.paceTotalAscentLine('100')), findsOneWidget);
    // План пересчитан от плоского темпа 5:00/км.
    expect(_textIn('pace-plan-pace-1', '5:00'), findsOneWidget);
  });

  testWidgets('ручная правка времени плана не затирается пересчётом', (
    tester,
  ) async {
    usePhoneSize(tester);
    final store = _MemoryTrackStore({
      _key('GRUT', 'T100'): File('test/fixtures/hill.gpx').readAsStringSync(),
    });
    debugTrackFileStoreOverride = store;

    await _pumpApp(
      tester,
      _oneDistanceState(
        mountain: true,
        tracks: _tracks(),
        anchor: {'kind': 'flat', 'flatPaceSec': 300.0},
        start: '0800',
      ),
    );
    await _switchMode(tester, 'Ultra');
    await tester.pumpAndSettle();

    await _enterTime(tester, 'pace-plan-time-1', '0930');
    await _tapKey(tester, AppStrings.ok);
    await tester.pumpAndSettle();

    // Если бы пересчёт сработал, здесь было бы время из плана (08:08).
    expect(_textIn('pace-plan-time-1', '09:30'), findsOneWidget);
  });

  testWidgets('ввод до окончания загрузки состояния не затирается', (
    tester,
  ) async {
    usePhoneSize(tester);
    final pending = Completer<Map<String, dynamic>?>();
    debugPaceStateLoaderOverride = (key) =>
        key == 'ultra_state_v1' ? pending.future : Future.value(null);

    SharedPreferences.setMockInitialValues({'app_mode_v1': 'ultra'});
    await tester.pumpWidget(const CalculatorApp());
    await tester.pumpAndSettle();

    // Пользователь вводит старт, пока SharedPreferences ещё «думает».
    await _enterTime(tester, 'pace-table-time-0', '0800');

    pending.complete(_oneDistanceState(start: '1200'));
    await tester.pumpAndSettle();

    expect(_textIn('pace-table-time-0', '08:00'), findsOneWidget);
    expect(_textIn('pace-table-time-0', '12:00'), findsNothing);
  });

  testWidgets('удаление мероприятия удаляет его треки', (tester) async {
    usePhoneSize(tester);
    final store = _MemoryTrackStore({
      _key('Mad Fox Ultra', 'VR'): _gpxWithElevations([100, 200]),
    });
    debugTrackFileStoreOverride = store;

    await _pumpApp(
      tester,
      _state(
        events: [
          {
            'name': 'GRUT',
            'distances': [
              {'name': 'T100', 'checkpoints': 6},
            ],
          },
          {
            'name': 'Mad Fox Ultra',
            'distances': [
              {'name': 'VR', 'checkpoints': 6},
            ],
          },
        ],
        selectedDistance: 'T100',
        tables: {
          'GRUT': {'T100': _table()},
          'Mad Fox Ultra': {'VR': _table()},
        },
      ),
    );
    await _switchMode(tester, 'Ultra');

    await tester.tap(find.byKey(const ValueKey('pace-event-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.paceEventRemove));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mad Fox Ultra'));
    await tester.pumpAndSettle();

    expect(
      store.files.keys.where(
        (key) => key.startsWith('${trackDistanceKey('Mad Fox Ultra', 'VR')}/'),
      ),
      isEmpty,
    );
  });
}
