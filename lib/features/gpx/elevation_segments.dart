import 'dart:math' as math;

import 'parsed_track.dart';
import 'plan_math.dart';
import 'track_metrics.dart';

/// Набор и сброс по сегментам таблицы (docs/gpx-mountain-mode.md §5.1).
class ElevationSegments {
  const ElevationSegments({required this.ascentM, required this.descentM});

  /// По одному значению на сегмент: индекс `i` — сегмент `i−1 → i`.
  /// Индекс 0 (старт) не используется и равен 0.
  final List<double> ascentM;
  final List<double> descentM;

  double get totalAscentM => ascentM.fold(0, (a, b) => a + b);
  double get totalDescentM => descentM.fold(0, (a, b) => a + b);
}

/// Считает D+/D− по сегментам между колонками ПП.
///
/// [columnDistancesKm] — накопленные километры колонок от старта (индекс 0 —
/// старт). Точки трека берутся от точки `Start` через сдвиг подводки
/// [ParsedTrack.startOffsetM].
ElevationSegments elevationForColumns({
  required ParsedTrack parsed,
  required List<double> columnDistancesKm,
}) {
  final count = columnDistancesKm.length;
  final ascent = List<double>.filled(count, 0);
  final descent = List<double>.filled(count, 0);
  if (count < 2 || !parsed.track.hasElevation) {
    return ElevationSegments(ascentM: ascent, descentM: descent);
  }

  // Границы в метрах по 2D-пути трека. Подводка сдвигает километры таблицы,
  // поэтому из них вычитаем сдвиг, чтобы попасть в индексы трека.
  final boundaries = [
    for (final km in columnDistancesKm)
      (km * 1000 - parsed.startOffsetM).clamp(0, double.infinity).toDouble(),
  ];
  final segments = computeSegments(parsed.metrics, boundaries);
  for (var s = 0; s < segments.length; s++) {
    ascent[s + 1] = segments[s].ascentM;
    descent[s + 1] = segments[s].descentM;
  }
  return ElevationSegments(ascentM: ascent, descentM: descent);
}

/// Сегменты для плана: длина и GAP-фактор по колонкам (индекс `i` — сегмент
/// `i−1 → i`, индекс 0 не используется).
///
/// Колонки с пустой или нулевой длиной дают сегмент с фактором 1 и нулевой
/// длиной; такие сегменты план пропускает.
List<PlanSegment> planSegmentsForColumns({
  required ParsedTrack? parsed,
  required List<double> columnDistancesKm,
}) {
  final count = columnDistancesKm.length;
  if (count < 2) return const [];
  final boundaries = [
    for (final km in columnDistancesKm)
      parsed == null
          ? km * 1000
          : (km * 1000 - parsed.startOffsetM)
                .clamp(0, double.infinity)
                .toDouble(),
  ];
  final result = <PlanSegment>[];
  if (parsed == null || !parsed.track.hasElevation) {
    for (var s = 0; s + 1 < count; s++) {
      final length = math.max(0.0, boundaries[s + 1] - boundaries[s]) / 1000;
      result.add(PlanSegment(distanceKm: length, gapFactor: 1));
    }
    return result;
  }
  final stats = computeSegments(parsed.metrics, boundaries);
  for (final s in stats) {
    result.add(
      PlanSegment(distanceKm: s.lengthM / 1000, gapFactor: s.gapFactor),
    );
  }
  return result;
}
