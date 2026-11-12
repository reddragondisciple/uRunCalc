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

/// Состояние одной дистанции с загруженным треком. Погода выключена, но
/// сохранённое время старта задано — диалог берёт дату именно из него.
Map<String, dynamic> _state({required DateTime startLocal}) => {
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
  'tables': {
    'GRUT': {
      'T100': {
        'columns': 6,
        'fitTable': true,
        'tableTimes': ['0800', '', '', '', '', ''],
        'tableDistances': ['0', '11', '18.8', '30', '70.2', '94'],
        'planTimes': List.filled(6, ''),
        'planPaces': List.filled(6, ''),
        'notes': List.filled(6, ''),
        'water': List.filled(6, ''),
        'food': List.filled(6, ''),
        'mountain': {
          'enabled': true,
          'tracks': {'active': 'primary', 'primary': _trackMeta()},
        },
        'environment': {
          'weatherEnabled': false,
          'startUtcMs': startLocal.toUtc().millisecondsSinceEpoch,
        },
      },
    },
  },
};

class _MemoryTrackStore implements TrackFileStore {
  _MemoryTrackStore(this.files);

  final Map<String, String> files;

  @override
  Future<String?> read({
    required String distanceKey,
    required String fileName,
  }) async => files['$distanceKey/$fileName'];

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
}

Future<void> _switchMode(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('mode-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _openWeatherDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('pace-settings-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('pace-settings-weather')));
  await tester.pumpAndSettle();
}

/// Полдень через [days] дней: дата в локальном времени стабильна независимо
/// от часового пояса тестового окружения.
DateTime _localNoonAfter(int days) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + days, 12);
}

void main() {
  setUp(() {
    debugParseTrackSynchronously = true;
  });

  tearDown(() {
    debugParseTrackSynchronously = false;
    debugTrackFileStoreOverride = null;
  });

  testWidgets('погода дальше горизонта показывает подсказку «нет прогноза»', (
    tester,
  ) async {
    usePhoneSize(tester);
    debugTrackFileStoreOverride = _MemoryTrackStore({
      _key('GRUT', 'T100'): File('test/fixtures/hill.gpx').readAsStringSync(),
    });

    await _pumpApp(tester, _state(startLocal: _localNoonAfter(30)));
    await _switchMode(tester, 'Ultra');
    await _openWeatherDialog(tester);

    expect(find.text(AppStrings.environmentWeatherTitle), findsOneWidget);
    expect(
      find.byKey(const ValueKey('environment-weather-date')),
      findsOneWidget,
    );
    expect(find.text(AppStrings.environmentNoForecastHint), findsOneWidget);
  });

  testWidgets('погода внутри горизонта не показывает подсказку', (
    tester,
  ) async {
    usePhoneSize(tester);
    debugTrackFileStoreOverride = _MemoryTrackStore({
      _key('GRUT', 'T100'): File('test/fixtures/hill.gpx').readAsStringSync(),
    });

    await _pumpApp(tester, _state(startLocal: _localNoonAfter(2)));
    await _switchMode(tester, 'Ultra');
    await _openWeatherDialog(tester);

    expect(
      find.byKey(const ValueKey('environment-weather-date')),
      findsOneWidget,
    );
    expect(find.text(AppStrings.environmentNoForecastHint), findsNothing);
  });
}
