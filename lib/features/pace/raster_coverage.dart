/// Растровые источники покрытия — кандидаты для пробелов OSM (§6.6).
///
/// Растр никогда не перекрывает явный `surface` OSM: он только уточняет
/// участки, где тега нет. Провайдеры изолированы за интерфейсом, чтобы
/// подменить сеть в тестах и позже добавить MODIS/SoilGrids.
library;

import 'environment_data.dart';
import 'environment_sampling.dart';

/// Один растровый кандидат для точки трека.
class RasterCandidate {
  const RasterCandidate({
    required this.type,
    required this.weight,
    required this.source,
    this.bogKind,
    this.bogConfidence = 0,
  });

  /// Тип покрытия, который предлагает растр.
  final SurfaceType type;

  /// Вес источника из §6.6: WorldCover — 0.40, MODIS — 0.20 и т.д.
  final double weight;

  /// Имя источника для отладки и статистики: `worldcover`.
  final String source;

  /// Если растр видит wetland, здесь будет вид болота.
  final String? bogKind;

  /// Уверенность болотного признака (0..1). У OSM-болота — 1.0.
  final double bogConfidence;
}

/// Результат растрового сэмплирования: кандидаты выровнены по точкам.
class RasterCoverageResult {
  const RasterCoverageResult({required this.candidates, this.warning});

  final List<RasterCandidate?> candidates;
  final String? warning;
}

/// Контракт растрового источника покрытия.
abstract class RasterCoverageProvider {
  Future<RasterCoverageResult> sample({required List<TrackSamplePoint> points});
}

/// Заглушка для тестов и сборок без сети: растр ничего не уточняет.
class NoopRasterCoverageProvider implements RasterCoverageProvider {
  const NoopRasterCoverageProvider();

  @override
  Future<RasterCoverageResult> sample({
    required List<TrackSamplePoint> points,
  }) async {
    return RasterCoverageResult(
      candidates: List<RasterCandidate?>.filled(points.length, null),
    );
  }
}

/// Ошибка растрового источника: сеть, Range-запрос или декодирование COG.
class RasterCoverageException implements Exception {
  const RasterCoverageException(this.message);

  final String message;

  @override
  String toString() => 'RasterCoverageException: $message';
}
