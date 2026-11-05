/// Сопоставление кандидатов из трека с колонками ПП (docs/gpx-mountain-mode.md §4.5).
///
/// Чистая логика: вход — накопленные расстояния колонок и точки трека,
/// выход — предложения. Ничего не применяется автоматически без решения
/// пользователя; здесь только подсказки и флажки по умолчанию.
library;

import 'dart:math' as math;

import 'checkpoint_names.dart';
import 'gpx_parser.dart';
import 'gpx_track.dart';
import 'track_metrics.dart';

/// Точка лежит на треке, если ближайшая точка трека в этом радиусе (м).
const double onTrackMaxMeters = 250;

/// Проходки одного имени, слипающиеся в пределах этого расстояния (м), —
/// одна проходка.
const double passMergeMeters = 500;

/// Автоподсказка: не дальше `min(0.5 км, 5% длины трека)`.
const double autoSuggestMaxMeters = 500;

/// Флажок по умолчанию — только если точка стоит на треке не дальше этого (м).
const double autoCheckOffTrackMeters = 100;
const double autoSuggestTrackShare = 0.05;

/// Одна проходка трека через точку ПП.
class TrackPass {
  const TrackPass({
    required this.index,
    required this.distanceM,
    required this.offsetFromTrackM,
  });

  /// Индекс точки трека, ближайшей к кандидату.
  final int index;

  /// Накопленное 2D-расстояние от старта трека, м.
  final double distanceM;

  /// Расстояние от точки ПП до трека, м (≤ [onTrackMaxMeters]).
  final double offsetFromTrackM;
}

/// Кандидат из `wpt` с именем и всеми его проходками по треку.
class CheckpointCandidate {
  const CheckpointCandidate({
    required this.rawName,
    required this.name,
    required this.passes,
    required this.onTrack,
  });

  final String rawName;
  final CheckpointName name;

  /// Все проходки; пусто, если точка вне трека (ToD end и т.п.).
  final List<TrackPass> passes;

  /// Есть ли хотя бы одна проходка в радиусе [onTrackMaxMeters].
  final bool onTrack;
}

/// Предложение для одной колонки.
class ColumnSuggestion {
  const ColumnSuggestion({
    required this.column,
    required this.candidate,
    required this.pass,
    required this.checked,
  });

  final int column;

  /// Кандидат, которого предлагаем; `null` — подходящего нет.
  final CheckpointCandidate? candidate;

  /// Проходка, которую предлагаем.
  final TrackPass? pass;

  /// Флажок «актуализировать из трека» по умолчанию.
  final bool checked;

  /// Сдвиг относительно текущего расстояния колонки, м.
  double? deltaM(double currentDistanceM) =>
      pass == null ? null : pass!.distanceM - currentDistanceM;
}

/// Строит кандидатов из `wpt` трека.
List<CheckpointCandidate> buildCandidates(
  GpxTrack track,
  TrackMetrics metrics,
) {
  final result = <CheckpointCandidate>[];
  for (final wpt in track.waypoints) {
    final name = normalizeCheckpointName(wpt.name);
    final passes = _findPasses(track, metrics, wpt.lat, wpt.lon);
    result.add(
      CheckpointCandidate(
        rawName: wpt.name,
        name: name,
        passes: passes,
        onTrack: passes.isNotEmpty,
      ),
    );
  }
  return result;
}

/// Локальные минимумы расстояния до трека внутри порога, слипшиеся в пределах
/// [passMergeMeters] — одна проходка.
List<TrackPass> _findPasses(
  GpxTrack track,
  TrackMetrics metrics,
  double lat,
  double lon,
) {
  final n = track.length;
  final dist = List<double>.filled(n, 0);
  var bestAny = double.infinity;
  for (var i = 0; i < n; i++) {
    dist[i] = haversineMeters(lat, lon, track.lats[i], track.lons[i]);
    if (dist[i] < bestAny) bestAny = dist[i];
  }
  if (bestAny > onTrackMaxMeters) return const [];

  // Локальные минимумы, которые лежат в пределах порога.
  final minima = <int>[];
  for (var i = 0; i < n; i++) {
    if (dist[i] > onTrackMaxMeters) continue;
    final prevOk = i == 0 || dist[i] <= dist[i - 1];
    final nextOk = i == n - 1 || dist[i] <= dist[i + 1];
    if (prevOk && nextOk) minima.add(i);
  }

  final passes = <TrackPass>[];
  for (final i in minima) {
    final cum = metrics.cumDist2d[i];
    if (passes.isNotEmpty &&
        (cum - passes.last.distanceM).abs() < passMergeMeters) {
      // Слипшаяся проходка: оставляем более близкую к точке.
      if (dist[i] < passes.last.offsetFromTrackM) {
        passes[passes.length - 1] = TrackPass(
          index: i,
          distanceM: cum,
          offsetFromTrackM: dist[i],
        );
      }
      continue;
    }
    passes.add(TrackPass(index: i, distanceM: cum, offsetFromTrackM: dist[i]));
  }
  return passes;
}

/// Подбирает проходки под колонки.
///
/// [columnLabels] — метки колонок: `START`, `CP1`… `FINISH` (или пусто,
/// если имя колонки неизвестно — тогда только по расстоянию не назначаем).
/// [columnDistancesM] — текущие расстояния колонок, м.
///
/// Правила:
/// - колонка получает проходку с совпавшим именем, либо ближайшую к текущему
///   расстоянию из того же имени;
/// - одна проходка не назначается двум колонкам;
/// - флажок по умолчанию — только если имя однозначно и расстояние в допуске.
List<ColumnSuggestion> suggestColumns({
  required List<String> columnLabels,
  required List<double> columnDistancesM,
  required List<CheckpointCandidate> candidates,
  required double trackLengthM,
}) {
  final count = columnLabels.length;
  final used = <TrackPass>{};
  final result = List<ColumnSuggestion>.generate(
    count,
    (column) => ColumnSuggestion(
      column: column,
      candidate: null,
      pass: null,
      checked: false,
    ),
  );
  final limit = math.min(
    autoSuggestMaxMeters,
    trackLengthM * autoSuggestTrackShare,
  );

  // Колонки с именем, у которых есть совпадения.
  for (var column = 0; column < count; column++) {
    final label = columnLabels[column];
    final current = columnDistancesM[column];

    final matches = <(CheckpointCandidate, TrackPass)>[];
    for (final cand in candidates) {
      if (!cand.name.labels.contains(label)) continue;
      for (final pass in cand.passes) {
        if (!used.contains(pass)) matches.add((cand, pass));
      }
    }
    if (matches.isEmpty) continue;

    matches.sort(
      (a, b) => (a.$2.distanceM - current).abs().compareTo(
        (b.$2.distanceM - current).abs(),
      ),
    );
    final best = matches.first;
    final near = (best.$2.distanceM - current).abs() <= limit;
    final onTrack = best.$2.offsetFromTrackM <= autoCheckOffTrackMeters;

    used.add(best.$2);
    result[column] = ColumnSuggestion(
      column: column,
      candidate: best.$1,
      pass: best.$2,
      checked: near && onTrack,
    );
  }
  return result;
}
