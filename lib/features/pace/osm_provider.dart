/// OSM / Overpass: покрытие, болота, броды и урбанизация.
///
/// Сеть и разбор ответа изолированы здесь. Классификация точек — чистые
/// функции, поэтому её можно тестировать без Overpass.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'environment_data.dart';
import 'environment_sampling.dart';
import 'factor_profile.dart';
import 'raster_coverage.dart';

/// Точка геометрии OSM.
class OsmPoint {
  const OsmPoint(this.lat, this.lon);

  final double lat;
  final double lon;
}

/// Way или area из Overpass.
class OsmFeature {
  const OsmFeature({
    required this.id,
    required this.tags,
    required this.geometry,
  });

  final int id;
  final Map<String, String> tags;
  final List<OsmPoint> geometry;

  bool get isClosed =>
      geometry.length > 3 &&
      geometry.first.lat == geometry.last.lat &&
      geometry.first.lon == geometry.last.lon;
}

/// Точка `place=...`.
class OsmPlace {
  const OsmPlace({required this.tags, required this.lat, required this.lon});

  final Map<String, String> tags;
  final double lat;
  final double lon;
}

/// Всё, что нужно из OSM для одного трека.
class OsmData {
  const OsmData({
    this.features = const [],
    this.places = const [],
    this.warning,
  });

  final List<OsmFeature> features;
  final List<OsmPlace> places;
  final String? warning;
}

/// Контракт OSM-провайдера.
abstract class OsmProvider {
  Future<OsmData> fetch({required List<TrackSamplePoint> points});
}

/// Overpass с несколькими зеркалами и повторами.
class OverpassOsmProvider implements OsmProvider {
  OverpassOsmProvider({
    http.Client? client,
    List<String>? endpoints,
    this.timeout = const Duration(seconds: 25),
    this.totalBudget = const Duration(seconds: 45),
  }) : _client = client ?? http.Client(),
       endpoints =
           endpoints ??
           const [
             'https://overpass.osm.ch/api/interpreter',
             'https://overpass.private.coffee/api/interpreter',
             'https://overpass-api.de/api/interpreter',
             'https://overpass.kumi.systems/api/interpreter',
           ];

  final http.Client _client;
  final List<String> endpoints;

  /// Таймаут одного запроса к зеркалу.
  final Duration timeout;

  /// Общий лимит на все зеркала: при недоступной сети расчёт не должен
  /// висеть минутами. Лучше вернуть грунт и предупреждение.
  final Duration totalBudget;

  @override
  Future<OsmData> fetch({required List<TrackSamplePoint> points}) async {
    if (points.length < 2) return const OsmData();

    final bbox = _bbox(points);
    final query = _buildQuery(bbox);
    final body = await _request(query);
    return _parse(body);
  }

  String _buildQuery(String bbox) {
    return '''
[out:json][timeout:25];
(
  way["highway"]($bbox);
  way["natural"~"wetland|bog|marsh|swamp|wood|scrub|grassland|heath|sand|bare_rock|scree|shingle"]($bbox);
  way["surface"="peat"]($bbox);
  way["landuse"~"peat_extraction|residential|commercial|industrial|retail|meadow|forest|farmland|orchard|vineyard|grass"]($bbox);
  way["waterway"~"river|stream|ditch"]($bbox);
  node["place"~"city|town|village|hamlet"]($bbox);
);
out tags geom;
''';
  }

  Future<String> _request(String query) async {
    Object? lastError;
    final deadline = DateTime.now().add(totalBudget);
    for (final endpoint in endpoints) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      try {
        final response = await _client
            .post(
              Uri.parse(endpoint),
              headers: const {
                'User-Agent': 'uRunCalc/2.0 (non-commercial)',
                'Content-Type': 'application/x-www-form-urlencoded',
              },
              body: {'data': query},
            )
            .timeout(remaining < timeout ? remaining : timeout);
        if (response.statusCode == 200) return response.body;
        lastError = OsmException(
          'Overpass $endpoint вернул ${response.statusCode}',
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw OsmException('Overpass недоступен: $lastError');
  }

  OsmData _parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const OsmException('Overpass вернул не JSON');
    final elements = decoded['elements'];
    if (elements is! List) {
      throw const OsmException('В ответе Overpass нет elements');
    }

    final features = <OsmFeature>[];
    final places = <OsmPlace>[];
    for (final raw in elements) {
      if (raw is! Map) continue;
      final tags = _tags(raw['tags']);
      final type = raw['type'];
      if (type == 'node') {
        final lat = _double(raw['lat']);
        final lon = _double(raw['lon']);
        if (lat != null && lon != null && tags['place'] != null) {
          places.add(OsmPlace(tags: tags, lat: lat, lon: lon));
        }
        continue;
      }
      final geometryRaw = raw['geometry'];
      if (geometryRaw is! List) continue;
      final geometry = <OsmPoint>[];
      for (final point in geometryRaw) {
        if (point is! Map) continue;
        final lat = _double(point['lat']);
        final lon = _double(point['lon']);
        if (lat != null && lon != null) geometry.add(OsmPoint(lat, lon));
      }
      if (geometry.length < 2) continue;
      features.add(
        OsmFeature(
          id: _double(raw['id'])?.round() ?? 0,
          tags: tags,
          geometry: geometry,
        ),
      );
    }
    return OsmData(features: features, places: places);
  }

  static Map<String, String> _tags(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value != null) result[key] = '$value';
    }
    return result;
  }

  static double? _double(dynamic value) {
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String _bbox(List<TrackSamplePoint> points) {
    var minLat = points.first.lat;
    var maxLat = points.first.lat;
    var minLon = points.first.lon;
    var maxLon = points.first.lon;
    for (final point in points) {
      minLat = math.min(minLat, point.lat);
      maxLat = math.max(maxLat, point.lat);
      minLon = math.min(minLon, point.lon);
      maxLon = math.max(maxLon, point.lon);
    }
    const margin = 0.02;
    return '${(minLat - margin).toStringAsFixed(5)},'
        '${(minLon - margin).toStringAsFixed(5)},'
        '${(maxLat + margin).toStringAsFixed(5)},'
        '${(maxLon + margin).toStringAsFixed(5)}';
  }
}

/// Результат классификации OSM.
class OsmSurfaceResult {
  const OsmSurfaceResult({
    required this.runs,
    required this.settlements,
    required this.fords,
    required this.coverage,
    this.rasterCoverage = 0,
  });

  final List<SurfaceRun> runs;
  final List<SettlementRun> settlements;
  final List<Ford> fords;

  /// Доля точек, для которых нашёлся путь OSM.
  final double coverage;

  /// Доля точек, где тип покрытия уточнён растром.
  final double rasterCoverage;
}

/// Строит участки покрытия, населённые пункты и броды по точкам трека.
OsmSurfaceResult buildOsmSurfaceResult({
  required List<TrackSamplePoint> points,
  required OsmData data,
  required FactorProfile profile,
  List<RasterCandidate?> rasterSamples = const [],
}) {
  if (points.isEmpty) {
    return const OsmSurfaceResult(
      runs: [],
      settlements: [],
      fords: [],
      coverage: 0,
    );
  }

  final indexed = [
    for (final feature in data.features) _IndexedFeature(feature),
  ];
  final info = [
    for (var i = 0; i < points.length; i++)
      _classifyPoint(
        points[i],
        indexed,
        data.places,
        profile,
        i < rasterSamples.length ? rasterSamples[i] : null,
      ),
  ];
  final runs = <SurfaceRun>[];
  final settlements = <SettlementRun>[];
  final fords = <Ford>[];

  var groupStart = 0;
  for (var i = 1; i <= points.length; i++) {
    final atEnd = i == points.length;
    final same = !atEnd && info[i].groupKey == info[groupStart].groupKey;
    if (!atEnd && same) continue;

    final startM = points[groupStart].distanceM;
    final endM = atEnd
        ? points.last.distanceM
        : math.max(startM, points[i].distanceM);
    final first = info[groupStart];
    if (endM > startM) {
      runs.add(
        SurfaceRun(
          startM: startM,
          endM: endM,
          type: first.type,
          wetness: Wetness.dry,
          confidence: first.confidence,
          isBog: first.bogKind != null,
          bogKind: first.bogKind,
          bogFactor: first.bogFactor,
          bogConfidence: first.bogConfidence,
          surfaceSource: first.source,
          urbanity: first.urbanity,
          roadClass: first.roadClass,
          isFord: first.ford,
        ),
      );
      settlements.add(
        SettlementRun(
          startM: startM,
          endM: endM,
          context: first.context,
          urbanity: first.urbanity,
          confidence: first.settlementConfidence,
        ),
      );
      if (first.ford) {
        if (fords.isEmpty ||
            (first.distanceM - fords.last.distanceM).abs() > 100) {
          fords.add(
            Ford(
              distanceM: (startM + endM) / 2,
              confirmed: first.fordConfirmed,
            ),
          );
        }
      }
    }
    groupStart = i;
  }

  final coverage = info.where((i) => i.hasRoad).length / info.length;
  final rasterCoverage = info.where((i) => i.fromRaster).length / info.length;
  return OsmSurfaceResult(
    runs: runs,
    settlements: settlements,
    fords: fords,
    coverage: coverage,
    rasterCoverage: rasterCoverage,
  );
}

class _IndexedFeature {
  _IndexedFeature(this.feature) {
    if (feature.geometry.isEmpty) {
      empty = true;
      return;
    }
    var minLat = feature.geometry.first.lat;
    var maxLat = minLat;
    var minLon = feature.geometry.first.lon;
    var maxLon = minLon;
    for (final point in feature.geometry) {
      if (point.lat < minLat) minLat = point.lat;
      if (point.lat > maxLat) maxLat = point.lat;
      if (point.lon < minLon) minLon = point.lon;
      if (point.lon > maxLon) maxLon = point.lon;
    }
    this.minLat = minLat;
    this.maxLat = maxLat;
    this.minLon = minLon;
    this.maxLon = maxLon;
  }

  final OsmFeature feature;
  late final double minLat;
  late final double maxLat;
  late final double minLon;
  late final double maxLon;
  bool empty = false;

  /// Точка не дальше [marginM] от рамки. Быстрый отсев до точной геометрии:
  /// на длинном треке иначе перебираем тысячи чужих путей на каждую точку.
  bool near(double lat, double lon, double marginM) {
    if (empty) return false;
    final latMargin = marginM / 111320;
    final cosLat = math.max(0.05, math.cos(lat * math.pi / 180).abs());
    final lonMargin = marginM / (111320 * cosLat);
    return lat >= minLat - latMargin &&
        lat <= maxLat + latMargin &&
        lon >= minLon - lonMargin &&
        lon <= maxLon + lonMargin;
  }

  bool contains(double lat, double lon) {
    if (empty) return false;
    return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;
  }
}

class _PointInfo {
  _PointInfo({
    required this.distanceM,
    required this.type,
    required this.source,
    required this.confidence,
    required this.urbanity,
    required this.context,
    required this.settlementConfidence,
    required this.roadClass,
    required this.hasRoad,
    required this.ford,
    required this.fordConfirmed,
    this.fromRaster = false,
    this.bogKind,
    this.bogConfidence = 1.0,
  }) : bogFactor = 1.0;

  final double distanceM;
  final SurfaceType type;
  final String source;
  final double confidence;
  final double urbanity;
  final SettlementContext context;
  final double settlementConfidence;
  final RoadClass roadClass;
  final bool hasRoad;
  final bool ford;
  final bool fordConfirmed;
  final bool fromRaster;
  final String? bogKind;
  final double bogConfidence;
  double bogFactor;

  String get groupKey =>
      '${type.name}|$source|${bogKind ?? ''}|'
      '${bogConfidence.toStringAsFixed(2)}|$ford|'
      '${roadClass.name}|${context.name}';
}

_PointInfo _classifyPoint(
  TrackSamplePoint point,
  List<_IndexedFeature> features,
  List<OsmPlace> places,
  FactorProfile profile,
  RasterCandidate? raster,
) {
  final road = _nearestRoad(point, features);
  final tags = road?.feature.tags ?? const <String, String>{};
  final areaTags = _areaTags(point, features);
  final choice = _surfaceChoice(tags, areaTags: areaTags, raster: raster);
  final roadClass = _roadClass(tags['highway']);
  final urbanity = _urbanity(point, features, places, profile);
  final context = _contextFor(urbanity);
  final osmBogKind = _bogKind(point, features, road, tags);

  // Растровый wetland — только fallback: явный surface/tracktype и OSM-болото
  // всегда важнее. Для жёсткой дороги растр болото не назначает.
  final rasterBog =
      osmBogKind == null &&
          choice.source != 'surface' &&
          choice.source != 'tracktype' &&
          choice.source != 'highway'
      ? choice.bogKind
      : null;
  final bogKind = osmBogKind ?? rasterBog;
  final bogConfidence = osmBogKind != null
      ? 1.0
      : (rasterBog != null ? choice.bogConfidence : 0.0);
  final ford = _ford(point, features, tags);

  final info = _PointInfo(
    distanceM: point.distanceM,
    type: choice.type,
    source: choice.source,
    confidence: choice.confidence,
    urbanity: urbanity,
    context: context,
    settlementConfidence: _settlementConfidence(point, features, places),
    roadClass: roadClass,
    hasRoad: road != null,
    ford: ford != null,
    fordConfirmed: ford?.confirmed ?? false,
    fromRaster: choice.fromRaster,
    bogKind: bogKind,
    bogConfidence: bogConfidence,
  );
  if (bogKind != null) {
    info.bogFactor = profile.bog[bogKind] ?? 1.0;
  }
  return info;
}

class _SurfaceChoice {
  const _SurfaceChoice({
    required this.type,
    required this.source,
    required this.confidence,
    this.fromRaster = false,
    this.bogKind,
    this.bogConfidence = 0,
  });

  final SurfaceType type;
  final String source;
  final double confidence;
  final bool fromRaster;
  final String? bogKind;
  final double bogConfidence;
}

class _RoadMatch {
  const _RoadMatch(this.feature, this.distanceM);

  final OsmFeature feature;
  final double distanceM;
}

_RoadMatch? _nearestRoad(
  TrackSamplePoint point,
  List<_IndexedFeature> features, {
  double maxM = 40,
}) {
  _RoadMatch? best;
  for (final indexed in features) {
    final feature = indexed.feature;
    if (feature.tags['highway'] == null) continue;
    if (!indexed.near(point.lat, point.lon, maxM)) continue;
    final distance = _distanceToPolyline(
      point.lat,
      point.lon,
      feature.geometry,
    );
    if (distance > maxM) continue;
    if (best == null || distance < best.distanceM) {
      best = _RoadMatch(feature, distance);
    }
  }
  return best;
}

class _FordInfo {
  const _FordInfo({required this.confirmed});

  final bool confirmed;
}

_FordInfo? _ford(
  TrackSamplePoint point,
  List<_IndexedFeature> features,
  Map<String, String> tags,
) {
  if (tags['bridge'] != null || tags['tunnel'] != null) return null;
  if (tags['ford'] != null && tags['ford'] != 'no') {
    return const _FordInfo(confirmed: true);
  }
  if (tags['highway'] == 'ford') {
    return const _FordInfo(confirmed: true);
  }

  // Возможный брод: вода рядом, моста/тоннеля нет.
  for (final indexed in features) {
    final feature = indexed.feature;
    if (feature.tags['waterway'] == null) continue;
    if (!indexed.near(point.lat, point.lon, 15)) continue;
    final distance = _distanceToPolyline(
      point.lat,
      point.lon,
      feature.geometry,
    );
    if (distance <= 15) return const _FordInfo(confirmed: false);
  }
  return null;
}

String? _bogKind(
  TrackSamplePoint point,
  List<_IndexedFeature> features,
  _RoadMatch? road,
  Map<String, String> roadTags,
) {
  String? kind;
  for (final indexed in features) {
    final tags = indexed.feature.tags;
    if (!_isBogFeature(tags)) continue;
    if (!indexed.contains(point.lat, point.lon)) continue;
    if (!_insidePolygon(point.lat, point.lon, indexed.feature.geometry)) {
      continue;
    }
    kind = _bogKindFromTags(tags);
    if (kind != null) break;
  }

  if (kind == null) {
    // Ближайший путь уже найден в _classifyPoint: второй проход не нужен.
    final peatTags = road?.feature.tags;
    if (peatTags?['surface'] == 'peat') kind = 'peat';
    if (peatTags?['landuse'] == 'peat_extraction') kind = 'peatExtraction';
  }

  if (kind == null) return null;
  if (roadTags['highway'] == 'boardwalk' || roadTags['surface'] == 'wood') {
    return 'boardwalk';
  }
  if (roadTags['highway'] == 'path' && roadTags['surface'] == null) {
    return 'pathInWetland';
  }
  return kind;
}

bool _isBogFeature(Map<String, String> tags) {
  final natural = tags['natural'];
  final landuse = tags['landuse'];
  final surface = tags['surface'];
  return natural == 'wetland' ||
      natural == 'bog' ||
      natural == 'marsh' ||
      natural == 'swamp' ||
      landuse == 'peat_extraction' ||
      surface == 'peat';
}

String? _bogKindFromTags(Map<String, String> tags) {
  final natural = tags['natural'];
  final wetland = tags['wetland'];
  if (natural == 'bog') return 'bog';
  if (natural == 'marsh') return 'marsh';
  if (natural == 'swamp') return 'swamp';
  if (tags['landuse'] == 'peat_extraction') return 'peatExtraction';
  if (tags['surface'] == 'peat') return 'peat';
  return switch (wetland) {
    'bog' => 'bog',
    'fen' => 'fen',
    'marsh' => 'marsh',
    'swamp' => 'swamp',
    'reedbed' => 'reedbed',
    'wet_meadow' => 'wetMeadow',
    _ => natural == 'wetland' ? 'fen' : null,
  };
}

double _urbanity(
  TrackSamplePoint point,
  List<_IndexedFeature> features,
  List<OsmPlace> places,
  FactorProfile profile,
) {
  var urbanity = 0.0;
  for (final indexed in features) {
    final landuse = indexed.feature.tags['landuse'];
    if (landuse == null) continue;
    if (!const {
      'residential',
      'commercial',
      'industrial',
      'retail',
    }.contains(landuse)) {
      continue;
    }
    if (!indexed.contains(point.lat, point.lon)) continue;
    if (_insidePolygon(point.lat, point.lon, indexed.feature.geometry)) {
      urbanity = 1.0;
      break;
    }
  }

  for (final place in places) {
    final type = place.tags['place'];
    if (type == null) continue;
    final context = switch (type) {
      'city' => SettlementContext.urban,
      'town' => SettlementContext.town,
      'village' => SettlementContext.village,
      'hamlet' => SettlementContext.village,
      _ => SettlementContext.rural,
    };
    if (context == SettlementContext.rural) continue;
    final radius = switch (context) {
      SettlementContext.urban => 5000.0,
      SettlementContext.town => 3000.0,
      SettlementContext.village => 1000.0,
      SettlementContext.rural => 0.0,
    };
    final distance = _meters(point.lat, point.lon, place.lat, place.lon);
    if (distance > radius) continue;
    final base = profile.settlement.urbanity[context] ?? 0;
    final value = base * (1 - 0.25 * distance / radius);
    urbanity = math.max(urbanity, value);
  }
  return urbanity.clamp(0.0, 1.0).toDouble();
}

double _settlementConfidence(
  TrackSamplePoint point,
  List<_IndexedFeature> features,
  List<OsmPlace> places,
) {
  for (final indexed in features) {
    if (indexed.feature.tags['landuse'] == null) continue;
    if (!indexed.contains(point.lat, point.lon)) continue;
    if (_insidePolygon(point.lat, point.lon, indexed.feature.geometry)) {
      return 1.0;
    }
  }
  for (final place in places) {
    if (place.tags['place'] != null) return 0.7;
  }
  return 0.2;
}

SettlementContext _contextFor(double urbanity) {
  if (urbanity >= 0.9) return SettlementContext.urban;
  if (urbanity >= 0.6) return SettlementContext.town;
  if (urbanity >= 0.3) return SettlementContext.village;
  return SettlementContext.rural;
}

RoadClass _roadClass(String? highway) {
  return switch (highway) {
    'motorway' ||
    'trunk' ||
    'primary' ||
    'secondary' ||
    'tertiary' => RoadClass.pavedMajor,
    'residential' || 'service' || 'unclassified' => RoadClass.pavedLocal,
    'footway' || 'cycleway' || 'pedestrian' || 'steps' => RoadClass.footway,
    _ => RoadClass.unpaved,
  };
}

/// Выбирает покрытие по приоритетам §6.6.
///
/// Явный `surface` и `tracktype` всегда важнее растра. Растр уточняет
/// «мягкий» путь (лесная подстилка вместо абстрактного грунта) и заполняет
/// полные пробелы OSM, но не превращает тропу в асфальт.
_SurfaceChoice _surfaceChoice(
  Map<String, String> tags, {
  Map<String, String> areaTags = const {},
  RasterCandidate? raster,
}) {
  final explicit = _explicitSurface(tags['surface']);
  if (explicit != null) {
    return _SurfaceChoice(type: explicit, source: 'surface', confidence: 1.0);
  }

  final tracktype = _tracktypeSurface(tags['tracktype']);
  if (tracktype != null) {
    return _SurfaceChoice(
      type: tracktype,
      source: 'tracktype',
      confidence: 0.8,
    );
  }

  final highway = tags['highway'];
  final area = _areaSurface(areaTags);
  final rasterType = raster?.type;

  // Пробел OSM: дороги нет, поэтому растр может заполнить его любым
  // классом, включая застройку. Жёсткие дороги ниже это уже не разрешают.
  if (highway == null) {
    if (raster != null) {
      return _SurfaceChoice(
        type: raster.type,
        source: raster.source,
        confidence: raster.weight,
        fromRaster: true,
        bogKind: raster.bogKind,
        bogConfidence: raster.bogConfidence,
      );
    }
    if (area != null) {
      return _SurfaceChoice(type: area, source: 'landuse', confidence: 0.5);
    }
    return const _SurfaceChoice(
      type: SurfaceType.unknown,
      source: 'default',
      confidence: 0.3,
    );
  }

  final soft = _isSoftPath(highway);
  final rasterSoft = rasterType != null && _isSoftSurface(rasterType);

  if (!soft) {
    return _SurfaceChoice(
      type: _hardHighwaySurface(highway),
      source: 'highway',
      confidence: 0.6,
    );
  }

  if (rasterSoft) {
    return _SurfaceChoice(
      type: rasterType,
      source: raster!.source,
      confidence: raster.weight,
      fromRaster: true,
      bogKind: raster.bogKind,
      bogConfidence: raster.bogConfidence,
    );
  }
  if (area != null) {
    return _SurfaceChoice(type: area, source: 'landuse', confidence: 0.5);
  }
  return _SurfaceChoice(
    type: _softHighwaySurface(highway),
    source: 'highway',
    confidence: 0.6,
  );
}

SurfaceType? _explicitSurface(String? surface) => switch (surface) {
  'asphalt' => SurfaceType.asphalt,
  'concrete' || 'concrete:plates' || 'concrete:lanes' => SurfaceType.concrete,
  'paving_stones' || 'paving_stones:30' => SurfaceType.pavingStones,
  'compacted' || 'fine_gravel' => SurfaceType.compacted,
  'dirt' || 'earth' || 'unpaved' => SurfaceType.dirt,
  'ground' => SurfaceType.ground,
  'grass' => SurfaceType.grass,
  'sand' => SurfaceType.sand,
  'mud' => SurfaceType.mud,
  'wood' => SurfaceType.ground,
  _ => null,
};

SurfaceType? _tracktypeSurface(String? tracktype) => switch (tracktype) {
  'grade1' => SurfaceType.compacted,
  'grade2' || 'grade3' => SurfaceType.dirt,
  'grade4' || 'grade5' => SurfaceType.ground,
  _ => null,
};

SurfaceType _softHighwaySurface(String highway) => switch (highway) {
  'footway' ||
  'pedestrian' ||
  'cycleway' ||
  'steps' => SurfaceType.pavingStones,
  'boardwalk' => SurfaceType.ground,
  'path' || 'track' || 'bridleway' => SurfaceType.dirt,
  _ => SurfaceType.unknown,
};

SurfaceType _hardHighwaySurface(String highway) => switch (highway) {
  'service' || 'residential' => SurfaceType.compacted,
  'primary' ||
  'secondary' ||
  'tertiary' ||
  'trunk' ||
  'motorway' => SurfaceType.asphalt,
  _ => SurfaceType.unknown,
};

/// Растр уточняет мягкий путь только мягкими классами.
bool _isSoftSurface(SurfaceType type) => switch (type) {
  SurfaceType.dirt ||
  SurfaceType.ground ||
  SurfaceType.grass ||
  SurfaceType.sand => true,
  _ => false,
};

/// Покрытие по полигону `natural`/`landuse` — приоритет 4 из §6.6.
SurfaceType? _areaSurface(Map<String, String> tags) {
  final natural = tags['natural'];
  final landuse = tags['landuse'];
  if (natural == 'wood' ||
      natural == 'scrub' ||
      natural == 'heath' ||
      landuse == 'forest') {
    return SurfaceType.ground;
  }
  if (natural == 'grassland' ||
      natural == 'meadow' ||
      landuse == 'meadow' ||
      landuse == 'grass') {
    return SurfaceType.grass;
  }
  if (landuse == 'farmland' || landuse == 'orchard' || landuse == 'vineyard') {
    return SurfaceType.dirt;
  }
  if (natural == 'sand' || natural == 'beach') return SurfaceType.sand;
  if (natural == 'bare_rock' || natural == 'scree' || natural == 'shingle') {
    return SurfaceType.ground;
  }
  return null;
}

bool _isSoftPath(String? highway) =>
    highway == null ||
    const {
      'path',
      'track',
      'footway',
      'cycleway',
      'bridleway',
      'pedestrian',
      'steps',
    }.contains(highway);

/// Теги полигона, внутри которого лежит точка. Первый подходящий.
Map<String, String> _areaTags(
  TrackSamplePoint point,
  List<_IndexedFeature> features,
) {
  for (final indexed in features) {
    final tags = indexed.feature.tags;
    if (tags['natural'] == null && tags['landuse'] == null) continue;
    if (!indexed.contains(point.lat, point.lon)) continue;
    if (_insidePolygon(point.lat, point.lon, indexed.feature.geometry)) {
      return tags;
    }
  }
  return const {};
}

bool _insidePolygon(double lat, double lon, List<OsmPoint> polygon) {
  if (polygon.length < 3) return false;
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final yi = polygon[i].lat;
    final xi = polygon[i].lon;
    final yj = polygon[j].lat;
    final xj = polygon[j].lon;
    final intersects =
        ((yi > lat) != (yj > lat)) &&
        (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi);
    if (intersects) inside = !inside;
  }
  return inside;
}

double _distanceToPolyline(double lat, double lon, List<OsmPoint> geometry) {
  var best = double.infinity;
  for (var i = 1; i < geometry.length; i++) {
    final distance = _distanceToSegment(
      lat,
      lon,
      geometry[i - 1].lat,
      geometry[i - 1].lon,
      geometry[i].lat,
      geometry[i].lon,
    );
    if (distance < best) best = distance;
  }
  return best;
}

/// Расстояние от точки до отрезка в метрах (локальная равнопромежуточная
/// проекция; для 40 м этого достаточно).
double _distanceToSegment(
  double lat,
  double lon,
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  final latRef = (lat1 + lat2) / 2 * math.pi / 180;
  final x = (lon - lon1) * math.cos(latRef);
  final y = lat - lat1;
  final dx = (lon2 - lon1) * math.cos(latRef);
  final dy = lat2 - lat1;
  final lengthSq = dx * dx + dy * dy;
  if (lengthSq <= 0) return _meters(lat, lon, lat1, lon1);
  final t = ((x * dx + y * dy) / lengthSq).clamp(0.0, 1.0);
  final px = dx * t;
  final py = dy * t;
  final ddx = x - px;
  final ddy = y - py;
  return math.sqrt(ddx * ddx + ddy * ddy) * 111320;
}

double _meters(double lat1, double lon1, double lat2, double lon2) {
  const earth = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final meanLat = (lat1 + lat2) / 2 * math.pi / 180;
  final x = dLon * math.cos(meanLat);
  return math.sqrt(dLat * dLat + x * x) * earth;
}

/// Ошибка Overpass.
class OsmException implements Exception {
  const OsmException(this.message);

  final String message;

  @override
  String toString() => message;
}
