/// ESA WorldCover 10 м: чтение классов поверхности из COG по HTTP Range.
///
/// Один тайл — 3°×3°, около 67 МБ. Поэтому не скачиваем его целиком: берём
/// только обзорный уровень (≈74 м/пиксель) и Range-запросы к нужным плиткам.
/// Явный `surface` OSM этот источник не перекрывает (§6.6).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:tiff/tiff.dart';

import 'environment_data.dart';
import 'environment_sampling.dart';
import 'raster_coverage.dart';

const String _defaultBaseUrl =
    'https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/';

/// Вес WorldCover из §6.6.
const double worldCoverWeight = 0.40;

/// Уверенность болотного признака WorldCover из §6.5.
const double worldCoverBogConfidence = 0.5;

/// Классы ESA WorldCover, которые понимаем.
enum WorldCoverClass {
  tree(10, SurfaceType.ground),
  shrub(20, SurfaceType.ground),
  grass(30, SurfaceType.grass),
  cropland(40, SurfaceType.dirt),
  builtUp(50, SurfaceType.pavingStones),
  bare(60, SurfaceType.ground),
  snowIce(70, SurfaceType.ground),
  water(80, null),
  wetland(90, SurfaceType.grass, 'worldCoverWetland'),
  mangrove(95, SurfaceType.ground, 'worldCoverWetland'),
  moss(100, SurfaceType.ground);

  const WorldCoverClass(this.code, this.surface, [this.bogKind]);

  final int code;

  /// `null` — вода: растр не должен назначать брод или покрытие.
  final SurfaceType? surface;
  final String? bogKind;

  static WorldCoverClass? fromCode(int? code) {
    if (code == null) return null;
    for (final value in values) {
      if (value.code == code) return value;
    }
    return null;
  }

  RasterCandidate? toCandidate() {
    final surface = this.surface;
    if (surface == null) return null;
    return RasterCandidate(
      type: surface,
      weight: worldCoverWeight,
      source: 'worldcover',
      bogKind: bogKind,
      bogConfidence: bogKind == null ? 0 : worldCoverBogConfidence,
    );
  }
}

/// Имя COG-тайла WorldCover для координаты.
///
/// Тайлы нарезаны по 3° и названы по юго-западному углу:
/// `N54E039` покрывает 54…57° с. ш. и 39…42° в. д.
String worldCoverTileName(double lat, double lon) {
  final latOrigin = (lat / 3).floor() * 3;
  final lonOrigin = (lon / 3).floor() * 3;
  final latPart = latOrigin >= 0
      ? 'N${latOrigin.toString().padLeft(2, '0')}'
      : 'S${(-latOrigin).toString().padLeft(2, '0')}';
  final lonPart = lonOrigin >= 0
      ? 'E${lonOrigin.toString().padLeft(3, '0')}'
      : 'W${(-lonOrigin).toString().padLeft(3, '0')}';
  return 'ESA_WorldCover_10m_2021_v200_$latPart${lonPart}_Map.tif';
}

/// Читает коды WorldCover для точек одного тайла.
///
/// Отдельный интерфейс нужен, чтобы тесты не ходили в сеть и не декодировали
/// настоящий COG.
abstract class WorldCoverTileReader {
  Future<List<int?>> readTile({
    required String tile,
    required List<TrackSamplePoint> points,
  });
}

/// Провайдер WorldCover с кэшем точек: итерации погоды не перечитывают растр.
class WorldCoverProvider implements RasterCoverageProvider {
  WorldCoverProvider({
    WorldCoverTileReader? reader,
    this.totalBudget = const Duration(seconds: 15),
  }) : _reader = reader ?? CogWorldCoverTileReader();

  final WorldCoverTileReader _reader;

  /// Общий лимит на все тайлы. Растр — необязательное уточнение: если сеть
  /// медленная, лучше быстро вернуть OSM и предупреждение, чем ждать минуты.
  final Duration totalBudget;

  /// Ключ — округлённые координаты (~11 м), значение — кандидат или `null`.
  /// `null` кэшируется намеренно: в воде/за пределами тайла растра нет.
  final Map<String, RasterCandidate?> _cache = {};

  @override
  Future<RasterCoverageResult> sample({
    required List<TrackSamplePoint> points,
  }) async {
    if (points.isEmpty) {
      return const RasterCoverageResult(candidates: []);
    }

    final candidates = List<RasterCandidate?>.filled(points.length, null);
    final pending = <String, List<int>>{};
    for (var i = 0; i < points.length; i++) {
      final key = _pointKey(points[i]);
      if (_cache.containsKey(key)) {
        candidates[i] = _cache[key];
        continue;
      }
      final tile = worldCoverTileName(points[i].lat, points[i].lon);
      pending.putIfAbsent(tile, () => []).add(i);
    }

    String? warning;
    final deadline = DateTime.now().add(totalBudget);
    for (final entry in pending.entries) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        warning ??= 'WorldCover: лимит времени, часть точек без растра';
        break;
      }
      final indices = entry.value;
      try {
        final codes = await _reader
            .readTile(
              tile: entry.key,
              points: [for (final i in indices) points[i]],
            )
            .timeout(remaining);
        for (var j = 0; j < indices.length; j++) {
          final candidate = WorldCoverClass.fromCode(
            j < codes.length ? codes[j] : null,
          )?.toCandidate();
          candidates[indices[j]] = candidate;
          _cache[_pointKey(points[indices[j]])] = candidate;
        }
      } on TimeoutException {
        warning ??= 'WorldCover: лимит времени, часть точек без растра';
      } catch (error) {
        // Сеть/декодер не должны ронять весь расчёт: остаётся OSM.
        warning ??= 'WorldCover недоступен: покрытие уточнено только по OSM';
      }
    }

    return RasterCoverageResult(candidates: candidates, warning: warning);
  }

  static String _pointKey(TrackSamplePoint point) =>
      '${point.lat.toStringAsFixed(4)},${point.lon.toStringAsFixed(4)}';
}

/// Читает WorldCover из COG на S3 через HTTP Range.
class CogWorldCoverTileReader implements WorldCoverTileReader {
  CogWorldCoverTileReader({
    http.Client? client,
    this.baseUrl = _defaultBaseUrl,
    this.targetPageWidth = 4500,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  /// 4500 px на 3° — это ≈74 м/пиксель. Для 30-метровых точек трека
  /// достаточно, а Range-запросы остаются небольшими.
  final int targetPageWidth;
  final Duration timeout;

  @override
  Future<List<int?>> readTile({
    required String tile,
    required List<TrackSamplePoint> points,
  }) async {
    if (points.isEmpty) return const [];
    final uri = Uri.parse('$baseUrl$tile');
    final source = await _openSource(uri);
    final document = await TiffDecoder.decodeAsync(source);
    try {
      final images = document.images;
      if (images.isEmpty) return List<int?>.filled(points.length, null);
      final full = images.first;
      final page = _pickPage(images);
      final pageWidth = page.metadata.width;
      final pageHeight = page.metadata.height;
      final geo = full.metadata.geoTiff;
      final scale = geo?.modelPixelScale;
      final tiepoint = geo != null && geo.modelTiepoints.isNotEmpty
          ? geo.modelTiepoints.first
          : null;

      final latOrigin = (points.first.lat / 3).floor() * 3.0;
      final lonOrigin = (points.first.lon / 3).floor() * 3.0;

      final xs = <int>[];
      final ys = <int>[];
      for (final point in points) {
        final double fullX;
        final double fullY;
        if (scale != null && tiepoint != null) {
          fullX = tiepoint.rasterX + (point.lon - tiepoint.modelX) / scale[0];
          fullY = tiepoint.rasterY - (point.lat - tiepoint.modelY) / scale[1];
        } else {
          fullX = (point.lon - lonOrigin) / 3 * full.metadata.width;
          fullY = (latOrigin + 3 - point.lat) / 3 * full.metadata.height;
        }
        final x = (fullX * pageWidth / full.metadata.width).floor();
        final y = (fullY * pageHeight / full.metadata.height).floor();
        xs.add(x.clamp(0, pageWidth - 1).toInt());
        ys.add(y.clamp(0, pageHeight - 1).toInt());
      }

      final minX = xs.reduce((a, b) => a < b ? a : b);
      final maxX = xs.reduce((a, b) => a > b ? a : b);
      final minY = ys.reduce((a, b) => a < b ? a : b);
      final maxY = ys.reduce((a, b) => a > b ? a : b);
      final region = TiffRegion(
        x: minX,
        y: minY,
        width: maxX - minX + 1,
        height: maxY - minY + 1,
      );
      final raster = await page.decodeRegionAsync(region);

      return [
        for (var i = 0; i < points.length; i++)
          raster.sampleAt(xs[i] - minX, ys[i] - minY, 0).toInt(),
      ];
    } finally {
      document.close();
    }
  }

  TiffImage _pickPage(List<TiffImage> images) {
    if (images.length == 1) return images.first;
    TiffImage? best;
    for (final image in images.skip(1)) {
      final width = image.metadata.width;
      if (width <= targetPageWidth &&
          (best == null || width > best.metadata.width)) {
        best = image;
      }
    }
    return best ?? images.last;
  }

  Future<TiffAsyncByteSource> _openSource(Uri uri) async {
    int? length;
    try {
      final head = await _client.head(uri).timeout(timeout);
      if (head.statusCode >= 200 && head.statusCode < 300) {
        length = int.tryParse(head.headers['content-length'] ?? '');
      }
    } catch (_) {
      // Некоторые серверы не любят HEAD — ниже пробуем Range.
    }
    if (length == null || length <= 0) {
      final probe = await _client
          .get(uri, headers: const {'Range': 'bytes=0-0'})
          .timeout(timeout);
      final range = probe.headers['content-range'];
      length = int.tryParse(range?.split('/').last ?? '');
    }
    if (length == null || length <= 0) {
      throw const RasterCoverageException(
        'WorldCover: не удалось узнать размер тайла',
      );
    }

    return TiffAsyncByteSource.fromCallback(length, (offset, count) async {
      if (count <= 0) return Uint8List(0);
      final response = await _client
          .get(uri, headers: {'Range': 'bytes=$offset-${offset + count - 1}'})
          .timeout(timeout);
      if (response.statusCode != 206) {
        throw RasterCoverageException(
          'WorldCover: Range вернул ${response.statusCode}',
        );
      }
      return response.bodyBytes;
    });
  }
}
