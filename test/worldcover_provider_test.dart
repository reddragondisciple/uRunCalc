import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/pace/environment_data.dart';
import 'package:ultra_run_calc/features/pace/environment_sampling.dart';
import 'package:ultra_run_calc/features/pace/raster_coverage.dart';
import 'package:ultra_run_calc/features/pace/worldcover_provider.dart';

TrackSamplePoint _point(double lat, double lon, {int index = 0}) {
  return TrackSamplePoint(
    index: index,
    distanceM: index * 100.0,
    lat: lat,
    lon: lon,
    elevationM: 150,
  );
}

/// Подменяет COG-читатель: тесты не ходят в сеть и не декодируют TIFF.
class _FakeTileReader implements WorldCoverTileReader {
  _FakeTileReader(this.handler);

  final Future<List<int?>> Function(String tile, List<TrackSamplePoint> points)
  handler;
  final List<String> calls = [];

  @override
  Future<List<int?>> readTile({
    required String tile,
    required List<TrackSamplePoint> points,
  }) {
    calls.add(tile);
    return handler(tile, points);
  }
}

void main() {
  test('tile names use the south-west 3-degree corner', () {
    expect(
      worldCoverTileName(56, 40),
      'ESA_WorldCover_10m_2021_v200_N54E039_Map.tif',
    );
    expect(
      worldCoverTileName(57, 42),
      'ESA_WorldCover_10m_2021_v200_N57E042_Map.tif',
    );
    expect(
      worldCoverTileName(0, 0),
      'ESA_WorldCover_10m_2021_v200_N00E000_Map.tif',
    );
    expect(
      worldCoverTileName(-1.5, -1.5),
      'ESA_WorldCover_10m_2021_v200_S03W003_Map.tif',
    );
    expect(
      worldCoverTileName(-0.1, 0.1),
      'ESA_WorldCover_10m_2021_v200_S03E000_Map.tif',
    );
  });

  test('WorldCover codes map to the expected surface classes', () {
    expect(WorldCoverClass.fromCode(10), WorldCoverClass.tree);
    expect(WorldCoverClass.fromCode(20), WorldCoverClass.shrub);
    expect(WorldCoverClass.fromCode(30), WorldCoverClass.grass);
    expect(WorldCoverClass.fromCode(40), WorldCoverClass.cropland);
    expect(WorldCoverClass.fromCode(50), WorldCoverClass.builtUp);
    expect(WorldCoverClass.fromCode(60), WorldCoverClass.bare);
    expect(WorldCoverClass.fromCode(70), WorldCoverClass.snowIce);
    expect(WorldCoverClass.fromCode(80), WorldCoverClass.water);
    expect(WorldCoverClass.fromCode(90), WorldCoverClass.wetland);
    expect(WorldCoverClass.fromCode(95), WorldCoverClass.mangrove);
    expect(WorldCoverClass.fromCode(100), WorldCoverClass.moss);
    expect(WorldCoverClass.fromCode(999), isNull);
    expect(WorldCoverClass.fromCode(null), isNull);
  });

  test('water has no candidate and wetland carries a weak bog hint', () {
    expect(WorldCoverClass.water.toCandidate(), isNull);

    final grass = WorldCoverClass.grass.toCandidate()!;
    expect(grass.type, SurfaceType.grass);
    expect(grass.weight, closeTo(worldCoverWeight, 0.001));
    expect(grass.source, 'worldcover');
    expect(grass.bogKind, isNull);
    expect(grass.bogConfidence, 0);

    final wetland = WorldCoverClass.wetland.toCandidate()!;
    expect(wetland.type, SurfaceType.grass);
    expect(wetland.bogKind, 'worldCoverWetland');
    expect(wetland.bogConfidence, closeTo(0.5, 0.001));

    final mangrove = WorldCoverClass.mangrove.toCandidate()!;
    expect(mangrove.type, SurfaceType.ground);
    expect(mangrove.bogKind, 'worldCoverWetland');
  });

  test('provider groups points by tile and aligns candidates', () async {
    final reader = _FakeTileReader((tile, points) async {
      if (tile.contains('N54E039')) return [30, 80];
      return [10];
    });
    final provider = WorldCoverProvider(reader: reader);
    final points = [
      _point(56.0, 40.0, index: 0),
      _point(56.1, 40.1, index: 1),
      _point(58.0, 42.0, index: 2),
    ];

    final result = await provider.sample(points: points);

    expect(reader.calls.toSet(), {
      'ESA_WorldCover_10m_2021_v200_N54E039_Map.tif',
      'ESA_WorldCover_10m_2021_v200_N57E042_Map.tif',
    });
    expect(result.warning, isNull);
    expect(result.candidates[0]!.type, SurfaceType.grass);
    expect(result.candidates[1], isNull);
    expect(result.candidates[2]!.type, SurfaceType.ground);
  });

  test('provider caches candidates and null water results', () async {
    var calls = 0;
    final reader = _FakeTileReader((tile, points) async {
      calls++;
      return [80];
    });
    final provider = WorldCoverProvider(reader: reader);
    final points = [_point(56.0, 40.0)];

    final first = await provider.sample(points: points);
    final second = await provider.sample(points: points);

    expect(calls, 1);
    expect(first.candidates.single, isNull);
    expect(second.candidates.single, isNull);
  });

  test('duplicate points in one call share a tile request', () async {
    var calls = 0;
    final reader = _FakeTileReader((tile, points) async {
      calls++;
      expect(points, hasLength(2));
      return [30, 30];
    });
    final provider = WorldCoverProvider(reader: reader);

    final result = await provider.sample(
      points: [_point(56.0, 40.0), _point(56.0, 40.0, index: 1)],
    );

    expect(calls, 1);
    expect(result.candidates[0]!.type, SurfaceType.grass);
    expect(result.candidates[1]!.type, SurfaceType.grass);
  });

  test('a failing tile warns and keeps other tiles working', () async {
    final reader = _FakeTileReader((tile, points) async {
      if (tile.contains('N54E039')) {
        throw const RasterCoverageException('нет сети');
      }
      return [30];
    });
    final provider = WorldCoverProvider(reader: reader);

    final result = await provider.sample(
      points: [_point(56.0, 40.0, index: 0), _point(58.0, 42.0, index: 1)],
    );

    expect(result.warning, contains('WorldCover'));
    expect(result.candidates[0], isNull);
    expect(result.candidates[1]!.type, SurfaceType.grass);
  });

  test('a failed tile is retried on the next call', () async {
    var calls = 0;
    final reader = _FakeTileReader((tile, points) async {
      calls++;
      if (calls == 1) throw const RasterCoverageException('нет сети');
      return [30];
    });
    final provider = WorldCoverProvider(reader: reader);
    final points = [_point(56.0, 40.0)];

    final first = await provider.sample(points: points);
    final second = await provider.sample(points: points);

    expect(first.candidates.single, isNull);
    expect(second.candidates.single!.type, SurfaceType.grass);
    expect(calls, 2);
  });

  test('missing codes in a tile response become null candidates', () async {
    final reader = _FakeTileReader((tile, points) async => [30]);
    final provider = WorldCoverProvider(reader: reader);

    final result = await provider.sample(
      points: [_point(56.0, 40.0, index: 0), _point(56.1, 40.1, index: 1)],
    );

    expect(result.candidates[0]!.type, SurfaceType.grass);
    expect(result.candidates[1], isNull);
  });

  test('empty input never touches the reader', () async {
    final reader = _FakeTileReader((tile, points) async {
      fail('reader must not be called');
    });
    final provider = WorldCoverProvider(reader: reader);

    final result = await provider.sample(points: const []);

    expect(result.candidates, isEmpty);
    expect(reader.calls, isEmpty);
  });

  test('noop provider returns aligned nulls', () async {
    const provider = NoopRasterCoverageProvider();

    final result = await provider.sample(
      points: [_point(56.0, 40.0, index: 0), _point(56.1, 40.1, index: 1)],
    );

    expect(result.candidates, [null, null]);
  });
}
