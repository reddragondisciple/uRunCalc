/// Сопоставление путевых точек GPX с колонками ПП (docs/gpx-mountain-mode.md §4.3–4.5).
///
/// Чистая логика без Flutter. Имена не угадываются произвольно: кандидат
/// предлагается только если его имя или расстояние однозначно указывают на
/// колонку, остальное пользователь выбирает вручную.
library;

/// Результат нормализации имени путевой точки.
class CheckpointName {
  const CheckpointName({
    required this.labels,
    required this.suffixNote,
    required this.kind,
  });

  /// Метки ПП, которые имя может задавать: `CP2`, `CP5` для `CP2/5`,
  /// либо `START`, `FINISH`. Пусто, если имя не ПП (`MP1`, `Брод`).
  final List<String> labels;

  /// Отрезанный суффикс (`-Вода`, `(Заброска)`). Пустая строка, если нечего.
  /// Пишется в заметку колонки, а не выбрасывается.
  final String suffixNote;

  final CheckpointKind kind;
}

enum CheckpointKind {
  /// Колонка `n` (1-based, без старта и финиша).
  numbered,
  start,
  finish,

  /// Точка на трассе, которая не является ПП (`MP`, `Брод`, `ToD`).
  other,
}

final RegExp _suffixPattern = RegExp(r'\s*(\([^)]*\)|-\s*[^-/]+$)');

/// Нормализует имя `wpt` по правилам §4.4.
CheckpointName normalizeCheckpointName(String raw) {
  var text = raw.trim();
  final suffixes = <String>[];

  // Отрезаем суффиксы `(…)` и `-Вода`, сохраняя их текст.
  while (true) {
    final match = _suffixPattern.firstMatch(text);
    if (match == null || match.start == 0) break;
    suffixes.insert(
      0,
      match.group(0)!.trim().replaceFirst(RegExp(r'^-\s*'), ''),
    );
    text = text.substring(0, match.start).trim();
  }
  // Хвостовое «Вода» / «Water» без дефиса.
  final tail = RegExp(r'\s+(вода|water)$', caseSensitive: false);
  final tailMatch = tail.firstMatch(text);
  if (tailMatch != null) {
    suffixes.insert(0, tailMatch.group(1)!);
    text = text.substring(0, tailMatch.start).trim();
  }

  final upper = text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

  // Кириллица → латиница: СР → CP, КП → CP.
  final latin = upper.replaceAll('СР', 'CP').replaceAll('КП', 'CP');

  // `Start/Finish` разбираем как два ярлыка, `CC start` — тоже старт.
  final parts = latin.split('/').map((p) => p.trim()).toList();
  if (parts.length == 2 && parts.every(_isStartOrFinish)) {
    return _named(
      labels: [
        if (parts.any(_isStart)) 'START',
        if (parts.any(_isFinish)) 'FINISH',
      ],
      kind: CheckpointKind.start,
      suffixes: suffixes,
    );
  }
  if (_isStart(latin)) {
    return _named(
      labels: const ['START'],
      kind: CheckpointKind.start,
      suffixes: suffixes,
    );
  }
  if (_isFinish(latin)) {
    return _named(
      labels: const ['FINISH'],
      kind: CheckpointKind.finish,
      suffixes: suffixes,
    );
  }

  final cp = RegExp(r'^CP\s*(\d+(?:\s*/\s*\d+)*)$').firstMatch(latin);
  if (cp != null) {
    final numbers = cp
        .group(1)!
        .split('/')
        .map((n) => int.parse(n.trim()))
        .toList();
    return _named(
      labels: [for (final n in numbers) 'CP$n'],
      kind: CheckpointKind.numbered,
      suffixes: suffixes,
    );
  }

  // Не ПП (MP, Брод, ToD, название трассы): суффиксы не пишем в заметку,
  // чтобы не записывать туда имя трассы.
  return const CheckpointName(
    labels: [],
    suffixNote: '',
    kind: CheckpointKind.other,
  );
}

CheckpointName _named({
  required List<String> labels,
  required CheckpointKind kind,
  required List<String> suffixes,
}) {
  return CheckpointName(
    labels: labels,
    suffixNote: suffixes.where((s) => s.isNotEmpty).join(' '),
    kind: kind,
  );
}

bool _isStart(String text) =>
    text == 'START' || text == 'СТАРТ' || text == 'CC START';

bool _isFinish(String text) => text == 'FINISH' || text == 'ФИНИШ';

bool _isStartOrFinish(String part) => _isStart(part) || _isFinish(part);

/// Добавляет суффикс в заметку колонки по правилам §4.4:
/// пустая → суффикс; непустая → `старая · суффикс`; дубликат не пишем.
String mergeNote(String existing, String suffix) {
  final note = existing.trim();
  final add = suffix.trim();
  if (add.isEmpty) return note;
  if (note.isEmpty) return add;
  if (note.split(' · ').contains(add)) return note;
  return '$note · $add';
}
