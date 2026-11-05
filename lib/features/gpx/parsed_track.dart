/// Разобранный трек с метриками, кандидатами и сдвигом старта.
///
/// Чистая логика без Flutter: используется импортом и покрыта тестами.
library;

import 'checkpoint_matching.dart';
import 'gpx_import.dart';
import 'gpx_track.dart';
import 'track_metrics.dart';

/// Результат разбора: трек, метрики и кандидаты для сравнения.
class ParsedTrack {
  ParsedTrack({
    required this.track,
    required this.metrics,
    required this.candidates,
    required this.totalAscentM,
    required this.totalDescentM,
    this.startOffsetM = 0,
  });

  final GpxTrack track;
  final TrackMetrics metrics;
  final List<CheckpointCandidate> candidates;

  /// Суммарный набор и сброс по всему треку, м (по сырым высотам).
  final double totalAscentM;
  final double totalDescentM;

  /// Подводка: расстояние от точки `Start` до начала трека, м. Ноль — трек
  /// начинается со старта. Километры отсчитываются от `Start`, поэтому
  /// каждая отметка трека получает этот сдвиг.
  final double startOffsetM;

  /// Длина от точки `Start` до финиша, км.
  double get lengthKm => (metrics.totalDistance2d + startOffsetM) / 1000;

  /// Километраж точки трека от `Start`, м.
  double distanceFromStartM(double cumDistanceM) => cumDistanceM + startOffsetM;

  /// Копия с отсчётом от точки `Start`. Если точки `Start` нет или трек
  /// начинается с неё, возвращается без сдвига.
  ParsedTrack measuredFromStart() {
    final offset = trackStartOffsetMeters(track) ?? 0;
    return ParsedTrack(
      track: track,
      metrics: metrics,
      candidates: candidates,
      totalAscentM: totalAscentM,
      totalDescentM: totalDescentM,
      startOffsetM: offset,
    );
  }
}

/// Кандидаты с километражем от точки `Start`: сдвиг подводки применён к
/// каждой проходке. Исходные кандидаты не меняются.
List<CheckpointCandidate> candidatesFromStart(ParsedTrack parsed) {
  if (parsed.startOffsetM == 0) return parsed.candidates;
  return [
    for (final cand in parsed.candidates)
      CheckpointCandidate(
        rawName: cand.rawName,
        name: cand.name,
        onTrack: cand.onTrack,
        passes: [
          for (final pass in cand.passes)
            TrackPass(
              index: pass.index,
              distanceM: parsed.distanceFromStartM(pass.distanceM),
              offsetFromTrackM: pass.offsetFromTrackM,
            ),
        ],
      ),
  ];
}

extension ParsedTrackOffset on ParsedTrack {
  /// Копия с сохранённой подводкой (из `TrackMeta.offsetM`), без повторного
  /// поиска точки `Start`.
  ParsedTrack measuredFromStartIfOffset(double offsetM) {
    return ParsedTrack(
      track: track,
      metrics: metrics,
      candidates: candidates,
      totalAscentM: totalAscentM,
      totalDescentM: totalDescentM,
      startOffsetM: offsetM,
    );
  }
}
