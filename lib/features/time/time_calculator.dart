import '../../core/app_strings.dart';
import '../../core/time_math.dart';

/// Чистые расчёты экрана Time: разбор дат и времени, разница, сдвиг и
/// длительности.
class TimeCalculator {
  TimeCalculator._();

  /// Показывает введённые цифры как `дд.мм.гггг`.
  static String dateInputText(String buffer) {
    if (buffer.isEmpty) return AppStrings.timeDatePattern;

    final text = StringBuffer();
    for (var index = 0; index < buffer.length; index++) {
      if (index == 2 || index == 4) text.write('.');
      text.write(buffer[index]);
    }
    return text.toString();
  }

  static String formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year.toString().padLeft(4, '0')}';
  }

  /// Разбирает `ддммгггг`. Возвращает `null` для несуществующих дат.
  static DateTime? parseDate(String buffer) {
    if (buffer.length != 8) return null;

    final day = int.tryParse(buffer.substring(0, 2));
    final month = int.tryParse(buffer.substring(2, 4));
    final year = int.tryParse(buffer.substring(4, 8));
    if (day == null || month == null || year == null) return null;
    if (day < 1 || day > 31 || month < 1 || month > 12) return null;

    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  /// Часы и минуты не ограничены: можно вводить 500 часов или 1000 минут.
  static int clockSeconds(String hoursText, String minutesText) {
    if (hoursText.isEmpty && minutesText.isEmpty) return 0;

    final hours = int.tryParse(hoursText) ?? 0;
    final minutes = int.tryParse(minutesText) ?? 0;
    return hours * 3600 + minutes * 60;
  }

  static DateTime? dateTime({
    required String date,
    required String hours,
    required String minutes,
  }) {
    final parsed = parseDate(date);
    if (parsed == null) return null;

    final clock = clockSeconds(hours, minutes);
    return parsed.add(Duration(seconds: clock));
  }

  /// Длительность из четырёх полей. `null`, если поля пусты.
  static int? durationSeconds({
    required String days,
    required String hours,
    required String minutes,
    required String seconds,
  }) {
    final parts = [days, hours, minutes, seconds];
    if (parts.every((value) => value.trim().isEmpty)) return null;
    return parseDurationParts(parts);
  }

  static DateTime? shifted({
    required DateTime base,
    required int seconds,
    required bool subtract,
  }) {
    final delta = Duration(seconds: seconds);
    return subtract ? base.subtract(delta) : base.add(delta);
  }
}
