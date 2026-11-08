import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ultra_run_calc/core/app_strings.dart';
import 'package:ultra_run_calc/features/gpx/track_store.dart';
import 'package:ultra_run_calc/main.dart';

import 'elevation_row_widget_test.dart' show usePhoneSize;

/// Трек длиннее 100 км: 210 точек с шагом ~500 м.
///
/// Нужен, чтобы колонка ПП №5 (94 км) попадала внутрь трека и фокус окна
/// действительно отличался от «всей дистанции».
String _longGpx() {
  final points = StringBuffer();
  for (var i = 0; i < 210; i++) {
    final lat = 56.0 + i * 0.0045;
    final ele = 300 + (i * 37) % 200;
    points.writeln(
      '<trkpt lat="${lat.toStringAsFixed(4)}" lon="38.0">'
      '<ele>$ele</ele></trkpt>',
    );
  }
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">'
      '<trk><trkseg>$points</trkseg></trk></gpx>';
}

Map<String, dynamic> _trackMeta() => {
  'relativePath': 'primary.gpx',
  'originalName': 'long.gpx',
  'importedAtMs': 1,
  'points': 210,
  'lengthM': 104000,
  'ascentM': 5000,
  'descentM': 5000,
  'hasElevation': true,
  'offsetM': 0,
};

Map<String, dynamic> _tracks() => {
  'active': 'primary',
  'primary': _trackMeta(),
};

Map<String, dynamic> _table({
  bool mountain = true,
  bool withTrack = true,
  int columns = 8,
}) {
  const distances = ['0', '11', '18.8', '30', '70.2', '94', '102.2', '109.5'];
  return {
    'columns': columns,
    'fitTable': true,
    'tableTimes': List.filled(columns, ''),
    'tableDistances': distances.sublist(0, columns),
    'planTimes': List.filled(columns, ''),
    'planPaces': List.filled(columns, ''),
    'notes': List.filled(columns, ''),
    'water': List.filled(columns, ''),
    'food': List.filled(columns, ''),
    'mountain': {'enabled': mountain, if (withTrack) 'tracks': _tracks()},
  };
}

Map<String, dynamic> _state({
  bool mountain = true,
  bool withTrack = true,
  Map<String, dynamic>? tables,
}) => {
  'events': [
    {
      'name': 'GRUT',
      'distances': [
        {'name': 'T100', 'checkpoints': 6},
      ],
    },
  ],
  'selectedEvent': 'GRUT',
  'selectedDistance': 'T100',
  'tables':
      tables ??
      {
        'GRUT': {'T100': _table(mountain: mountain, withTrack: withTrack)},
      },
};

class _MemoryTrackStore implements TrackFileStore {
  _MemoryTrackStore(this.files);

  final Map<String, String> files;
  final List<String> reads = [];

  @override
  Future<String?> read({
    required String distanceKey,
    required String fileName,
  }) {
    reads.add('$distanceKey/$fileName');
    return Future.value(files['$distanceKey/$fileName']);
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

Future<void> _pumpApp(WidgetTester tester, Map<String, dynamic> state) async {
  SharedPreferences.setMockInitialValues({
    'app_mode_v1': 'simple',
    'ultra_state_v1': jsonEncode(state),
  });
  await tester.pumpWidget(const CalculatorApp());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('mode-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ultra').last);
  await tester.pumpAndSettle();
}

Future<void> _pumpWithTrack(
  WidgetTester tester, {
  Map<String, dynamic>? state,
  Size size = const Size(390, 844),
}) async {
  if (size == const Size(390, 844)) {
    usePhoneSize(tester);
  } else {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  debugTrackFileStoreOverride = _MemoryTrackStore({
    '${trackDistanceKey('GRUT', 'T100')}/primary.gpx': _longGpx(),
  });
  addTearDown(() => debugTrackFileStoreOverride = null);
  await _pumpApp(tester, state ?? _state());
}

final Finder _strip = find.byKey(const ValueKey('pace-elevation-chart-inline'));

void main() {
  setUp(() {
    debugParseTrackSynchronously = true;
  });

  tearDown(() {
    debugParseTrackSynchronously = false;
    debugTrackFileStoreOverride = null;
    debugPaceStateLoaderOverride = null;
  });

  testWidgets('левая половина ряда раскрывает и сворачивает полосу', (
    tester,
  ) async {
    await _pumpWithTrack(tester);

    expect(_strip, findsNothing);
    await tester.tap(find.byKey(const ValueKey('pace-elevation-1')));
    await tester.pumpAndSettle();
    expect(_strip, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pace-elevation-1')));
    await tester.pumpAndSettle();
    expect(_strip, findsNothing);
  });

  testWidgets('правая половина открывает окно с фокусом на сегменте', (
    tester,
  ) async {
    await _pumpWithTrack(tester);

    await tester.tap(find.byKey(const ValueKey('pace-elevation-5')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.elevationChartTitle), findsOneWidget);
    // Фокус на сегменте 70.2–94 км: появляется кнопка сброса на всю дистанцию.
    expect(find.byKey(const ValueKey('elevation-chart-reset')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('elevation-chart-close')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.elevationChartTitle), findsNothing);
  });

  testWidgets('служебная клетка в итоговом ряду раскрывает полосу', (
    tester,
  ) async {
    await _pumpWithTrack(tester);

    await tester.tap(find.byKey(const ValueKey('pace-elevation-toggle')));
    await tester.pumpAndSettle();
    expect(_strip, findsOneWidget);
  });

  testWidgets('без трека ряд не раскрывается, окно показывает заглушку', (
    tester,
  ) async {
    usePhoneSize(tester);
    await _pumpApp(tester, _state(withTrack: false));

    await tester.tap(find.byKey(const ValueKey('pace-elevation-1')));
    await tester.pumpAndSettle();
    expect(_strip, findsNothing);

    await tester.tap(find.byKey(const ValueKey('pace-elevation-5')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.elevationChartNoData), findsOneWidget);
  });

  testWidgets('в ландшафте полоса раскрывается без переполнения', (
    tester,
  ) async {
    await _pumpWithTrack(tester, size: const Size(844, 390));

    await tester.tap(find.byKey(const ValueKey('pace-elevation-1')));
    await tester.pumpAndSettle();

    expect(_strip, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('смена таблицы сворачивает полосу', (tester) async {
    usePhoneSize(tester);
    debugTrackFileStoreOverride = _MemoryTrackStore({
      '${trackDistanceKey('GRUT', 'T100')}/primary.gpx': _longGpx(),
      '${trackDistanceKey('GRUT', 'T80')}/primary.gpx': _longGpx(),
    });
    addTearDown(() => debugTrackFileStoreOverride = null);

    await _pumpApp(tester, {
      'events': [
        {
          'name': 'GRUT',
          'distances': [
            {'name': 'T100', 'checkpoints': 6},
            {'name': 'T80', 'checkpoints': 4},
          ],
        },
      ],
      'selectedEvent': 'GRUT',
      'selectedDistance': 'T100',
      'tables': {
        'GRUT': {'T100': _table(), 'T80': _table(columns: 6)},
      },
    });

    await tester.tap(find.byKey(const ValueKey('pace-elevation-1')));
    await tester.pumpAndSettle();
    expect(_strip, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pace-event-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GRUT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('T80'));
    await tester.pumpAndSettle();

    expect(_strip, findsNothing);
  });
}
