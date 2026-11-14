import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ultra_run_calc/features/pace/environment_sampling.dart';
import 'package:ultra_run_calc/features/pace/osm_provider.dart';

void main() {
  test('default endpoints do not use country-only extracts', () {
    final provider = OverpassOsmProvider();
    expect(
      provider.endpoints,
      isNot(contains('https://overpass.osm.ch/api/interpreter')),
    );
  });

  test('empty Overpass result is reported instead of silent 0%', () async {
    final provider = OverpassOsmProvider(
      client: MockClient((_) async => http.Response('{"elements":[]}', 200)),
    );
    const points = [
      TrackSamplePoint(
        index: 0,
        distanceM: 0,
        lat: 56,
        lon: 40,
        elevationM: 150,
      ),
      TrackSamplePoint(
        index: 1,
        distanceM: 100,
        lat: 56.01,
        lon: 40,
        elevationM: 150,
      ),
    ];

    final data = await provider.fetch(points: points);
    expect(data.warning, contains('не вернул объектов'));
  });

  test('Overpass respects the total budget instead of hanging', () async {
    final provider = OverpassOsmProvider(
      client: MockClient((_) => Completer<http.Response>().future),
      endpoints: const ['https://a.invalid', 'https://b.invalid'],
      timeout: const Duration(milliseconds: 30),
      totalBudget: const Duration(milliseconds: 50),
    );
    const points = [
      TrackSamplePoint(
        index: 0,
        distanceM: 0,
        lat: 56,
        lon: 40,
        elevationM: 150,
      ),
      TrackSamplePoint(
        index: 1,
        distanceM: 100,
        lat: 56.01,
        lon: 40,
        elevationM: 150,
      ),
    ];

    final watch = Stopwatch()..start();
    await expectLater(
      provider.fetch(points: points),
      throwsA(isA<OsmException>()),
    );
    expect(watch.elapsedMilliseconds, lessThan(500));
  });
}
