import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ultra_run_calc/core/app_strings.dart';
import 'package:ultra_run_calc/features/gpx/track_store.dart';
import 'package:ultra_run_calc/main.dart';

import 'elevation_row_widget_test.dart' show usePhoneSize;

/// In-memory хранилище: чтение синхронное по сути, без реального I/O.
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
    files.removeWhere((k, _) => k.startsWith('$distanceKey/'));
  }

  @override
  Future<bool> exists({
    required String distanceKey,
    required String fileName,
  }) async => files.containsKey('$distanceKey/$fileName');
}

Future<void> _pumpMountainUltra(WidgetTester tester) async {
  final table = {
    'columns': 8,
    'fitTable': true,
    'tableTimes': List.filled(8, ''),
    'tableDistances': ['0', '11', '18.8', '30', '70.2', '94', '102.2', '109.5'],
    'planTimes': List.filled(8, ''),
    'planPaces': List.filled(8, ''),
    'notes': List.filled(8, ''),
    'water': List.filled(8, ''),
    'food': List.filled(8, ''),
    'mountain': {
      'enabled': true,
      'tracks': {
        'active': 'primary',
        'primary': {
          'relativePath': 'primary.gpx',
          'originalName': 'hill.gpx',
          'importedAtMs': 1,
          'points': 6,
          'lengthM': 1000,
          'ascentM': 50,
          'descentM': 50,
          'hasElevation': true,
        },
      },
    },
  };
  SharedPreferences.setMockInitialValues({
    'app_mode_v1': 'simple',
    'ultra_state_v1': jsonEncode({
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
        'GRUT': {'T100': table},
      },
    }),
  });
  await tester.pumpWidget(const CalculatorApp());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('mode-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ultra').last);
  await tester.pumpAndSettle();
}

/// Тап по клавише пэда с прокруткой к ней (пэд в тестовом размере экрана
/// частично уходит под нижний край).
Future<void> tapPadKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey('pace-key-$key'));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ввод итогового времени с горным треком открывает диалог', (
    tester,
  ) async {
    usePhoneSize(tester);
    debugTrackFileStoreOverride = _MemoryTrackStore({
      '${trackDistanceKey('GRUT', 'T100')}/primary.gpx': File(
        'test/fixtures/hill.gpx',
      ).readAsStringSync(),
    });
    addTearDown(() => debugTrackFileStoreOverride = null);
    await _pumpMountainUltra(tester);

    // Старт таблицы: без него подтверждение итога не работает.
    await tester.tap(find.byKey(const ValueKey('pace-table-time-0')));
    await tester.pump();
    for (final key in ['0', '8', '0', '0']) {
      await tapPadKey(tester, key);
    }

    await tester.tap(find.byKey(const ValueKey('pace-overall-plan-time')));
    await tester.pump();
    for (final key in ['1', '2', '0', '0']) {
      await tapPadKey(tester, key);
    }
    await tapPadKey(tester, AppStrings.ok);
    await tester.pumpAndSettle();

    // Сначала подтверждение пересчёта, затем диалог режима.
    expect(find.text('Пересчитать план?'), findsOneWidget);
    await tester.tap(find.text('Пересчитать'));
    await tester.pumpAndSettle();

    expect(find.text('Как введён темп?'), findsOneWidget);
    // Предпросмотр строится из реального расчёта: итог после слова «Итого».
    expect(find.textContaining('Итого'), findsWidgets);
  });
}
