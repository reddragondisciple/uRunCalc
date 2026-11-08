import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/track_parse.dart';
import 'package:ultra_run_calc/features/gpx/track_parse_async.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final content = File('test/fixtures/hill.gpx').readAsStringSync();

  tearDown(() {
    debugParseTrackSynchronously = false;
  });

  test('разбор в изоляте совпадает с синхронным', () async {
    debugParseTrackSynchronously = false;

    final sync = parseTrackContent(content: content);
    final async = await parseTrackFileAsync(
      PickedTrackFile(name: 'hill.gpx', content: content),
    );

    expect(sync.error, isNull);
    expect(async.error, isNull);
    final expected = sync.parsed!;
    final actual = async.parsed!;
    expect(actual.track.length, expected.track.length);
    expect(actual.metrics.totalDistance2d, expected.metrics.totalDistance2d);
    expect(actual.metrics.totalDistance3d, expected.metrics.totalDistance3d);
    expect(actual.totalAscentM, expected.totalAscentM);
    expect(actual.totalDescentM, expected.totalDescentM);
    expect(actual.candidates.length, expected.candidates.length);
  });

  test('withCandidates: false пропускает поиск ПП, но считает итоги', () async {
    debugParseTrackSynchronously = true;

    final withCandidates = parseTrackContent(content: content);
    final withoutCandidates = await parseTrackFileAsync(
      PickedTrackFile(name: 'hill.gpx', content: content),
      withCandidates: false,
    );

    expect(withCandidates.parsed!.candidates, isNotEmpty);
    expect(withoutCandidates.parsed!.candidates, isEmpty);
    expect(
      withoutCandidates.parsed!.totalAscentM,
      withCandidates.parsed!.totalAscentM,
    );
    expect(
      withoutCandidates.parsed!.metrics.totalDistance2d,
      withCandidates.parsed!.metrics.totalDistance2d,
    );
  });

  test('битый GPX возвращает текст ошибки, а не исключение', () {
    final result = parseTrackContent(content: '<not-gpx/>');
    expect(result.parsed, isNull);
    expect(result.error, isNotNull);
  });
}
