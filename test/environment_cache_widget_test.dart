import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ultra_run_calc/features/gpx/track_store.dart';
import 'package:ultra_run_calc/features/pace/environment_data.dart';
import 'package:ultra_run_calc/features/pace/environment_sampling.dart';
import 'package:ultra_run_calc/features/pace/environment_service.dart';
import 'package:ultra_run_calc/features/pace/factor_profile.dart';
import 'package:ultra_run_calc/features/pace/osm_provider.dart';
import 'package:ultra_run_calc/features/pace/raster_coverage.dart';
import 'package:ultra_run_calc/features/pace/weather_provider.dart';
import 'package:ultra_run_calc/main.dart';

import 'elevation_row_widget_test.dart' show usePhoneSize;

class _CountingOsm implements OsmProvider {
  int calls = 0;

  @override
  Future<OsmData> fetch({required List<TrackSamplePoint> points}) async {
    calls++;
    return const OsmData();
  }
}

class _UnusedWeather implements WeatherProvider {
  @override
  Future<WeatherFetchResult> fetch({
    required List<WeatherQuery> queries,
    required FactorProfile profile,
  }) async {
    throw StateError('погода не должна запрашиваться');
  }
}

/// Растр даёт покрытие даже при пустом OSM — такого результата достаточно,
/// чтобы сохранить его в кэш.
class _GroundRaster implements RasterCoverageProvider {
  @override
  Future<RasterCoverageResult> sample({
    required List<TrackSamplePoint> points,
  }) async {
    return RasterCoverageResult(
      candidates: List<RasterCandidate?>.filled(
        points.length,
        const RasterCandidate(
          type: SurfaceType.ground,
          weight: 0.40,
          source: 'worldcover',
        ),
      ),
    );
  }
}

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

Map<String, dynamic> _state() => {
  'events': [
    {
      'name': 'GRUT',
      'distances': [
        {'name': 'T100', 'checkpoints': 6},
        {'name': 'T50', 'checkpoints': 4},
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
        'environment': {'surfaceEnabled': true},
      },
    },
  },
};

String _cacheKey() =>
    '${trackDistanceKey('GRUT', 'T100')}/primary/primary.gpx/1';

EnvironmentData _cachedEnvironment() => const EnvironmentData(
  settings: EnvironmentSettings(surfaceEnabled: true),
  surface: [
    SurfaceRun(
      startM: 0,
      endM: 1500,
      type: SurfaceType.asphalt,
      wetness: Wetness.dry,
      confidence: 1,
      factor: 1,
    ),
  ],
  surfaceCoverage: 1,
);

String _cacheJson() => jsonEncode({
  'version': 1,
  'entries': {
    _cacheKey(): {'savedAtMs': 1, 'data': _cachedEnvironment().toJson()},
  },
});

Future<void> _pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'app_mode_v1': 'simple',
    'ultra_state_v1': jsonEncode(_state()),
  });
  debugParseTrackSynchronously = true;
  debugTrackFileStoreOverride = _MemoryTrackStore({
    '${trackDistanceKey('GRUT', 'T100')}/primary.gpx': File(
      'test/fixtures/hill.gpx',
    ).readAsStringSync(),
  });
  await tester.pumpWidget(const CalculatorApp());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('mode-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ultra').last);
  await tester.pumpAndSettle();
}

Future<void> _switchDistance(WidgetTester tester, String distance) async {
  await tester.tap(find.byKey(const ValueKey('pace-event-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('GRUT').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(distance).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    debugParseTrackSynchronously = true;
  });

  tearDown(() {
    debugParseTrackSynchronously = false;
    debugTrackFileStoreOverride = null;
    debugEnvironmentServiceOverride = null;
  });

  testWidgets('сохранённое окружение восстанавливается без сети', (
    tester,
  ) async {
    final osm = _CountingOsm();
    debugEnvironmentServiceOverride = EnvironmentService(
      osm: osm,
      weather: _UnusedWeather(),
      raster: const NoopRasterCoverageProvider(),
    );
    usePhoneSize(tester);
    SharedPreferences.setMockInitialValues({
      'app_mode_v1': 'simple',
      'ultra_state_v1': jsonEncode(_state()),
      'environment_cache_v2': _cacheJson(),
    });

    debugTrackFileStoreOverride = _MemoryTrackStore({
      '${trackDistanceKey('GRUT', 'T100')}/primary.gpx': File(
        'test/fixtures/hill.gpx',
      ).readAsStringSync(),
    });
    await tester.pumpWidget(const CalculatorApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mode-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ultra').last);
    await tester.pumpAndSettle();

    expect(osm.calls, 0);
    expect(find.textContaining('Покрытие OSM: 100%'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pace-refresh-environment')),
      findsOneWidget,
    );
  });

  testWidgets('переключение дистанции не повторяет сетевой запрос', (
    tester,
  ) async {
    final osm = _CountingOsm();
    debugEnvironmentServiceOverride = EnvironmentService(
      osm: osm,
      weather: _UnusedWeather(),
      raster: _GroundRaster(),
    );
    usePhoneSize(tester);
    await _pumpApp(tester);

    expect(osm.calls, 1);
    expect(
      find.byKey(const ValueKey('pace-refresh-environment')),
      findsOneWidget,
    );

    await _switchDistance(tester, 'T50');
    await _switchDistance(tester, 'T100');

    // Второй запрос не нужен: результат сохранён и восстановлен из кэша.
    expect(osm.calls, 1);
  });
}
