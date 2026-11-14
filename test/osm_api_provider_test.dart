import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ultra_run_calc/features/pace/environment_sampling.dart';
import 'package:ultra_run_calc/features/pace/osm_provider.dart';

List<TrackSamplePoint> _points({int count = 3}) => [
  for (var i = 0; i < count; i++)
    TrackSamplePoint(
      index: i,
      distanceM: i * 100.0,
      lat: 56.43 + i * 0.001,
      lon: 40.42 + i * 0.001,
      elevationM: 120,
    ),
];

String _mapXml() => '''
<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6" generator="openstreetmap-cgimap">
  <node id="1" lat="56.4300" lon="40.4200"/>
  <node id="2" lat="56.4310" lon="40.4210"/>
  <node id="3" lat="56.4320" lon="40.4220"/>
  <node id="10" lat="56.4305" lon="40.4205">
    <tag k="place" v="village"/>
    <tag k="name" v="Тестово"/>
  </node>
  <way id="100">
    <nd ref="1"/>
    <nd ref="2"/>
    <nd ref="3"/>
    <tag k="highway" v="track"/>
    <tag k="surface" v="dirt"/>
  </way>
  <way id="101">
    <nd ref="1"/>
    <nd ref="2"/>
    <tag k="natural" v="wetland"/>
    <tag k="wetland" v="bog"/>
  </way>
</osm>
''';

class _FakeOsm implements OsmProvider {
  _FakeOsm({this.data, this.error});

  final OsmData? data;
  final Object? error;
  int calls = 0;

  @override
  Future<OsmData> fetch({required List<TrackSamplePoint> points}) async {
    calls++;
    if (error != null) throw error!;
    return data ?? const OsmData();
  }
}

void main() {
  group('OsmApiProvider', () {
    test('разбирает узлы, пути и place из XML', () async {
      final provider = OsmApiProvider(
        client: MockClient((request) async {
          return http.Response(
            _mapXml(),
            200,
            headers: const {'content-type': 'application/xml; charset=utf-8'},
          );
        }),
      );

      final data = await provider.fetch(points: _points());

      expect(data.features, hasLength(2));
      final road = data.features.firstWhere((f) => f.id == 100);
      expect(road.tags['surface'], 'dirt');
      expect(road.geometry, hasLength(3));
      expect(road.geometry.first.lat, closeTo(56.43, 1e-9));
      expect(road.geometry.last.lon, closeTo(40.422, 1e-9));
      expect(data.places.single.tags['place'], 'village');
      expect(data.warning, isNull);
    });

    test('bbox для OSM API идёт в порядке lon,lat', () async {
      late Uri requested;
      final provider = OsmApiProvider(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            _mapXml(),
            200,
            headers: const {'content-type': 'application/xml; charset=utf-8'},
          );
        }),
      );

      await provider.fetch(points: _points());

      final bbox = requested.queryParameters['bbox']!;
      final parts = bbox.split(',').map(double.parse).toList();
      expect(parts, hasLength(4));
      // left/bottom/right/top: сначала долгота, потом широта.
      expect(parts[0], lessThan(parts[2]));
      expect(parts[1], lessThan(parts[3]));
      expect(parts[0], closeTo(40.40, 0.001));
      expect(parts[1], closeTo(56.41, 0.001));
    });

    test('слишком большая область не запрашивается', () async {
      var calls = 0;
      final provider = OsmApiProvider(
        client: MockClient((_) async {
          calls++;
          return http.Response(_mapXml(), 200);
        }),
        maxAreaDeg2: 0.0001,
      );

      await expectLater(
        provider.fetch(points: _points()),
        throwsA(isA<OsmException>()),
      );
      expect(calls, 0);
    });

    test('не 200 — OsmException', () async {
      final provider = OsmApiProvider(
        client: MockClient((_) async => http.Response('nope', 400)),
      );

      await expectLater(
        provider.fetch(points: _points()),
        throwsA(isA<OsmException>()),
      );
    });

    test('пустая карта даёт предупреждение', () async {
      final provider = OsmApiProvider(
        client: MockClient(
          (_) async => http.Response('<osm version="0.6"></osm>', 200),
        ),
      );

      final data = await provider.fetch(points: _points());
      expect(data.warning, contains('не вернул объектов'));
    });
  });

  group('FallbackOsmProvider', () {
    test('использует резерв, когда Overpass упал', () async {
      final primary = _FakeOsm(error: const OsmException('нет сети'));
      final fallback = _FakeOsm(
        data: const OsmData(
          features: [
            OsmFeature(
              id: 1,
              tags: {'highway': 'path'},
              geometry: [OsmPoint(56.43, 40.42), OsmPoint(56.44, 40.43)],
            ),
          ],
        ),
      );
      final provider = FallbackOsmProvider(
        primary: primary,
        fallback: fallback,
      );

      final data = await provider.fetch(points: _points());
      expect(primary.calls, 1);
      expect(fallback.calls, 1);
      expect(data.features, hasLength(1));
    });

    test('использует резерв, когда Overpass вернул пусто', () async {
      final primary = _FakeOsm(
        data: const OsmData(warning: 'OSM не вернул объектов'),
      );
      final fallback = _FakeOsm(
        data: const OsmData(
          places: [
            OsmPlace(tags: {'place': 'town'}, lat: 56.43, lon: 40.42),
          ],
        ),
      );
      final provider = FallbackOsmProvider(
        primary: primary,
        fallback: fallback,
      );

      final data = await provider.fetch(points: _points());
      expect(fallback.calls, 1);
      expect(data.places, hasLength(1));
    });

    test('основной ответил — резерв не вызывается', () async {
      final primary = _FakeOsm(
        data: const OsmData(
          features: [
            OsmFeature(
              id: 1,
              tags: {'highway': 'path'},
              geometry: [OsmPoint(56.43, 40.42), OsmPoint(56.44, 40.43)],
            ),
          ],
        ),
      );
      final fallback = _FakeOsm(error: const OsmException('не должен'));
      final provider = FallbackOsmProvider(
        primary: primary,
        fallback: fallback,
      );

      final data = await provider.fetch(points: _points());
      expect(fallback.calls, 0);
      expect(data.features, hasLength(1));
    });

    test('оба пусты — остаётся предупреждение основного', () async {
      final primary = _FakeOsm(data: const OsmData(warning: 'Overpass пуст'));
      final fallback = _FakeOsm(data: const OsmData(warning: 'OSM API пуст'));
      final provider = FallbackOsmProvider(
        primary: primary,
        fallback: fallback,
      );

      final data = await provider.fetch(points: _points());
      expect(data.warning, 'Overpass пуст');
    });

    test('оба упали — OsmException с обеими причинами', () async {
      final primary = _FakeOsm(error: const OsmException('таймаут'));
      final fallback = _FakeOsm(error: const OsmException('HTTP 400'));
      final provider = FallbackOsmProvider(
        primary: primary,
        fallback: fallback,
      );

      await expectLater(
        provider.fetch(points: _points()),
        throwsA(
          isA<OsmException>().having(
            (e) => e.message,
            'message',
            allOf(contains('таймаут'), contains('HTTP 400')),
          ),
        ),
      );
    });
  });
}
