/// Применение импорта GPX к таблице ПП (docs/gpx-mountain-mode.md §4.2, §4.4, §4.6).
///
/// Чистая логика: вход — текущие значения колонок и выбор пользователя,
/// выход — новые значения. Ничего не мутирует и не знает про UI.
library;

import 'checkpoint_matching.dart';
import 'checkpoint_names.dart';
import 'gpx_parser.dart';
import 'gpx_track.dart';

/// Старт трека дальше этого от точки `Start` — спрашиваем пользователя (м).
const double startOffsetPromptMeters = 200;

/// Режим импорта.
enum GpxImportMode {
  /// Только общая дистанция: меняется финиш, остальные колонки не трогаем.
  finishOnly,

  /// Финиш и отмеченные колонки по сравнительной таблице.
  checkpoints,
}

/// Причина отказа импорта.
enum GpxImportError {
  /// Финиш раньше последнего ПП — дистанция из трека не подходит к таблице.
  finishBeforeLastCheckpoint,

  /// После применения расстояния перестают возрастать.
  nonMonotonicDistances,
}

/// Итог применения: новые значения или ошибка.
class GpxImportResult {
  const GpxImportResult.ok({
    required this.distances,
    required this.notes,
    required this.changedColumns,
  }) : error = null;

  const GpxImportResult.failed(this.error)
    : distances = const [],
      notes = const [],
      changedColumns = const [];

  final List<String> distances;
  final List<String> notes;
  final List<int> changedColumns;
  final GpxImportError? error;

  bool get ok => error == null;
}

/// Выбор пользователя на одну колонку.
class ColumnChoice {
  const ColumnChoice({required this.column, required this.pass});

  final int column;

  /// Проходка, которую применяем; `null` — колонка не меняется.
  final ColumnSuggestion? pass;
}

/// Нужен ли вопрос о старте. Возвращает `true`, если старт трека дальше
/// [startOffsetPromptMeters] от точки `Start` (нужно спросить, что считать стартом).
bool startNeedsDecision(double startOffsetMeters) =>
    startOffsetMeters.abs() > startOffsetPromptMeters;

/// Км как строка для таблицы: до сотых, без хвостовых нулей (`40.2`, `109.31`).
String formatKm(double km) {
  final rounded = (km * 100).round() / 100;
  var text = rounded.toStringAsFixed(2);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}

/// Применяет импорт.
///
/// [distances] — текущие расстояния колонок, км (строки). [notes] — заметки.
/// [finishKm] — длина трека 2D, км. [choices] — отмеченные колонки; для
/// режима [GpxImportMode.finishOnly] игнорируются.
GpxImportResult applyGpxImport({
  required GpxImportMode mode,
  required List<String> distances,
  required List<String> notes,
  required double finishKm,
  List<ColumnChoice> choices = const [],
}) {
  final count = distances.length;
  final newDistances = List<String>.of(distances);
  final newNotes = List<String>.of(notes);
  final changed = <int>[];

  if (mode == GpxImportMode.finishOnly) {
    // Финиш не может быть раньше последнего промежуточного ПП.
    final lastIntermediate = count >= 3 ? _parseKm(distances[count - 2]) : null;
    if (lastIntermediate != null && finishKm <= lastIntermediate) {
      return const GpxImportResult.failed(
        GpxImportError.finishBeforeLastCheckpoint,
      );
    }
    newDistances[count - 1] = formatKm(finishKm);
    changed.add(count - 1);
    return _finish(newDistances, newNotes, changed, count);
  }

  for (final choice in choices) {
    final suggestion = choice.pass;
    if (suggestion == null || suggestion.pass == null) continue;
    if (choice.column < 0 || choice.column >= count) continue;

    newDistances[choice.column] = formatKm(suggestion.pass!.distanceM / 1000);
    changed.add(choice.column);

    final candidate = suggestion.candidate;
    if (candidate != null) {
      newNotes[choice.column] = mergeNote(
        newNotes[choice.column],
        candidate.name.suffixNote,
      );
    }
  }

  // Финиш всегда привязываем к концу трека, если он не выбран явно.
  if (!changed.contains(count - 1)) {
    newDistances[count - 1] = formatKm(finishKm);
    changed.add(count - 1);
  }

  return _finish(newDistances, newNotes, changed, count);
}

GpxImportResult _finish(
  List<String> distances,
  List<String> notes,
  List<int> changed,
  int count,
) {
  // Расстояния должны строго возрастать от старта к финишу, иначе план
  // не посчитается. Пустые значения пропускаем.
  double? previous;
  for (var i = 0; i < count; i++) {
    final value = _parseKm(distances[i]);
    if (value == null) continue;
    if (previous != null && value <= previous) {
      return const GpxImportResult.failed(GpxImportError.nonMonotonicDistances);
    }
    previous = value;
  }
  return GpxImportResult.ok(
    distances: distances,
    notes: notes,
    changedColumns: List<int>.unmodifiable(changed.toSet().toList()..sort()),
  );
}

double? _parseKm(String text) {
  final normalized = text.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}

/// Смещение начала трека от точки `Start`, м. Положительно — трек начинается
/// дальше от старта. `null`, если в файле нет точки `Start`.
///
/// `Start/Finish` — одна `wpt` с двумя ярлыками. Для старта берём ту из
/// точек с меткой START, что ближе к первой точке трека, а не к финишу.
double? trackStartOffsetMeters(GpxTrack track) {
  if (track.length == 0) return null;
  final firstLat = track.lats[0];
  final firstLon = track.lons[0];
  final lastLat = track.lats[track.length - 1];
  final lastLon = track.lons[track.length - 1];

  double? best;
  for (final wpt in track.waypoints) {
    if (!normalizeCheckpointName(wpt.name).labels.contains('START')) continue;
    final toStart = haversineMeters(wpt.lat, wpt.lon, firstLat, firstLon);
    final toFinish = haversineMeters(wpt.lat, wpt.lon, lastLat, lastLon);
    // Для петли старт и финиш совпадают: тогда точка считается стартом,
    // а финишную проходку (ближе к концу трека) пропускаем, только если
    // она явно ближе к финишу, чем к началу.
    final isFinishOnly = toFinish < toStart - 1;
    if (isFinishOnly) continue;
    if (best == null || toStart < best) best = toStart;
  }
  return best;
}
