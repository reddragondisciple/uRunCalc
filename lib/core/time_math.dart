/// Общие примитивы для экранов Pace/Ultra/Time.
///
/// Здесь нет зависимостей от Flutter, поэтому функции легко тестировать
/// обычными unit-тестами.
library;

/// Форматирует темп как `мм:сс`.
String formatPaceSeconds(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Раскладывает длительность в дни, часы, минуты и секунды.
({int days, int hours, int minutes, int seconds}) splitSeconds(
  int totalSeconds,
) {
  final days = totalSeconds ~/ 86400;
  final hours = (totalSeconds % 86400) ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  return (days: days, hours: hours, minutes: minutes, seconds: seconds);
}

/// Суммирует части длительности `[дни, часы, минуты, секунды]`.
/// Возвращает `null`, если все части пустые.
int? parseDurationParts(List<String> values) {
  if (values.every((value) => value.trim().isEmpty)) return null;

  int read(int index) {
    return int.tryParse(values[index].trim()) ?? 0;
  }

  return read(0) * 86400 + read(1) * 3600 + read(2) * 60 + read(3);
}

/// Разбирает десятичное число, принимая и точку, и запятую.
double? parseDecimal(String text) {
  final normalized = text.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;

  final value = double.tryParse(normalized);
  if (value == null || !value.isFinite) return null;
  return value;
}
