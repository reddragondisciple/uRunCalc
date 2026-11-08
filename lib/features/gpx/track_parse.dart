/// Разбор GPX для импорта и загрузки таблицы.
///
/// Чистая логика без Flutter: файл можно разбирать в фоновом изоляте.
library;

import '../../core/app_strings.dart';
import 'checkpoint_matching.dart';
import 'gpx_parser.dart';
import 'gpx_track.dart';
import 'parsed_track.dart';
import 'track_metrics.dart';

/// Выбранный файл трека: имя и содержимое.
class PickedTrackFile {
  const PickedTrackFile({required this.name, required this.content});

  final String name;
  final String content;
}

/// Результат разбора: готовый трек или текст ошибки для пользователя.
class TrackParseResult {
  const TrackParseResult({this.parsed, this.error});

  final ParsedTrack? parsed;
  final String? error;
}

/// Разбирает содержимое GPX и считает метрики.
///
/// [withCandidates] отключают поиск кандидатов ПП: при обычной загрузке
/// таблицы они не нужны и только удлиняют разбор.
TrackParseResult parseTrackContent({
  required String content,
  bool withCandidates = true,
}) {
  try {
    final track = parseGpx(content);
    final metrics = computeTrackMetrics(track);
    final candidates = withCandidates
        ? buildCandidates(track, metrics)
        : const <CheckpointCandidate>[];
    final whole = computeSegments(metrics, [0, metrics.totalDistance2d]).single;
    return TrackParseResult(
      parsed: ParsedTrack(
        track: track,
        metrics: metrics,
        candidates: candidates,
        totalAscentM: whole.ascentM,
        totalDescentM: whole.descentM,
      ),
    );
  } on GpxFormatException catch (error) {
    return TrackParseResult(error: error.message);
  } catch (_) {
    return const TrackParseResult(error: AppStrings.paceTrackReadError);
  }
}

/// Разбирает выбранный файл. Оставлено для читаемости вызовов.
TrackParseResult parseTrackFile(
  PickedTrackFile file, {
  bool withCandidates = true,
}) {
  return parseTrackContent(
    content: file.content,
    withCandidates: withCandidates,
  );
}
