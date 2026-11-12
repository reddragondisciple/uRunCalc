import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/pace/environment_data.dart';
import 'package:ultra_run_calc/features/pace/environment_sampling.dart';
import 'package:ultra_run_calc/features/pace/factor_profile.dart';
import 'package:ultra_run_calc/features/pace/osm_provider.dart';

List<TrackSamplePoint> _points({int count = 5, double lat0 = 56}) => [
  for (var i = 0; i < count; i++)
    TrackSamplePoint(
      index: i,
      distanceM: i * 100.0,
      lat: lat0 + i * 0.0001,
      lon: 40,
      elevationM: 150,
    ),
];

List<OsmPoint> _line(List<TrackSamplePoint> points) => [
  for (final point in points) OsmPoint(point.lat, point.lon),
];

OsmFeature _road(
  List<TrackSamplePoint> points, {
  Map<String, String> tags = const {'highway': 'path'},
}) {
  return OsmFeature(id: 1, tags: tags, geometry: _line(points));
}

OsmFeature _area({required String key, required String value, int id = 2}) {
  return OsmFeature(
    id: id,
    tags: {key: value},
    geometry: const [
      OsmPoint(55.999, 39.999),
      OsmPoint(55.999, 40.001),
      OsmPoint(56.001, 40.001),
      OsmPoint(56.001, 39.999),
      OsmPoint(55.999, 39.999),
    ],
  );
}

void main() {
  final profile = FactorProfile.defaults();

  test('explicit surface wins over a forest polygon', () {
    final points = _points();
    final result = buildOsmSurfaceResult(
      points: points,
      data: OsmData(
        features: [
          _road(points, tags: {'highway': 'path', 'surface': 'asphalt'}),
          _area(key: 'natural', value: 'wood'),
        ],
      ),
      profile: profile,
    );

    expect(result.runs.first.type, SurfaceType.asphalt);
    expect(result.runs.first.surfaceSource, 'surface');
  });

  test('forest refines an untagged path to ground', () {
    final points = _points();
    final result = buildOsmSurfaceResult(
      points: points,
      data: OsmData(
        features: [
          _road(points),
          _area(key: 'natural', value: 'wood'),
        ],
      ),
      profile: profile,
    );

    expect(result.runs.first.type, SurfaceType.ground);
    expect(result.runs.first.surfaceSource, 'landuse');
    expect(result.runs.first.confidence, closeTo(0.5, 0.001));
  });

  test('meadow refines an untagged path to grass', () {
    final points = _points();
    final result = buildOsmSurfaceResult(
      points: points,
      data: OsmData(
        features: [
          _road(points),
          _area(key: 'landuse', value: 'meadow'),
        ],
      ),
      profile: profile,
    );

    expect(result.runs.first.type, SurfaceType.grass);
  });

  test('a major road stays asphalt even inside a forest', () {
    final points = _points();
    final result = buildOsmSurfaceResult(
      points: points,
      data: OsmData(
        features: [
          _road(points, tags: {'highway': 'primary'}),
          _area(key: 'natural', value: 'wood'),
        ],
      ),
      profile: profile,
    );

    expect(result.runs.first.type, SurfaceType.asphalt);
  });

  test('no OSM data stays unknown with zero coverage', () {
    final points = _points();
    final result = buildOsmSurfaceResult(
      points: points,
      data: const OsmData(),
      profile: profile,
    );

    expect(result.runs.first.type, SurfaceType.unknown);
    expect(result.coverage, 0);
  });

  test('wetland polygon becomes a bog run', () {
    final points = _points();
    final result = buildOsmSurfaceResult(
      points: points,
      data: OsmData(
        features: [
          _road(points),
          _area(key: 'natural', value: 'wetland'),
        ],
      ),
      profile: profile,
    );

    expect(result.runs.first.isBog, isTrue);
    expect(result.runs.first.bogKind, 'pathInWetland');
    expect(result.runs.first.bogFactor, closeTo(1.25, 0.001));
  });

  test('ford=yes is a confirmed ford', () {
    final points = _points();
    final result = buildOsmSurfaceResult(
      points: points,
      data: OsmData(
        features: [
          _road(points, tags: {'highway': 'path', 'ford': 'yes'}),
        ],
      ),
      profile: profile,
    );

    expect(result.fords, isNotEmpty);
    expect(result.fords.first.confirmed, isTrue);
  });

  test('a waterway crossing without a bridge is a possible ford', () {
    final points = _points();
    final result = buildOsmSurfaceResult(
      points: points,
      data: OsmData(
        features: [
          _road(points),
          const OsmFeature(
            id: 3,
            tags: {'waterway': 'stream'},
            geometry: [OsmPoint(56.0002, 39.999), OsmPoint(56.0002, 40.001)],
          ),
        ],
      ),
      profile: profile,
    );

    expect(result.fords, isNotEmpty);
    expect(result.fords.first.confirmed, isFalse);
  });
}
