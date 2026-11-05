import '../../core/time_math.dart';

/// Какая из клеток темпа самая быстрая.
enum PaceHighlight { none, fastest, secondFastest }

/// Насколько план отклонился от лимита на конкретной колонке.
enum PlanTimeStatus { normal, behindLimit, closeToLimit }

/// Чистые расчёты таблицы Pace/Ultra: разбор времени и темпа, дни,
/// накопленное время, плановые показатели и подсветка.
class PaceTableCalculator {
  PaceTableCalculator._();

  static const int minutesPerDay = 24 * 60;

  /// План раньше лимита менее чем на столько минут подсвечивается жёлтым.
  static const int yellowWarningMinutes = 20;

  /// Превращает введённые цифры `ччмм` в минуты от полуночи.
  static int? parseTime(String buffer) {
    if (buffer.isEmpty) return null;
    final digits = buffer.padRight(4, '0');
    final hours = int.tryParse(digits.substring(0, 2));
    final minutes = int.tryParse(digits.substring(2, 4));
    if (hours == null || minutes == null || minutes > 59) return null;
    return hours * 60 + minutes;
  }

  /// Показывает буфер как `чч:мм`.
  static String timeText(String buffer) {
    if (buffer.isEmpty) return '00:00';
    final digits = buffer.padRight(4, '0');
    return '${digits.substring(0, 2)}:${digits.substring(2, 4)}';
  }

  /// Показывает буфер темпа как `м:сс`.
  static String paceText(String buffer) {
    if (buffer.isEmpty) return '0:00';
    final digits = buffer.length < 4 ? buffer.padRight(4, '0') : buffer;
    final minutes = int.tryParse(digits.substring(0, digits.length - 2)) ?? 0;
    final seconds = int.tryParse(digits.substring(digits.length - 2)) ?? 0;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Разбирает темп `ммсс` в секунды.
  static int? parsePace(String buffer) {
    if (buffer.isEmpty) return null;
    final digits = buffer.length < 4 ? buffer.padRight(4, '0') : buffer;
    final minutes = int.tryParse(digits.substring(0, digits.length - 2));
    final seconds = int.tryParse(digits.substring(digits.length - 2));
    if (minutes == null || seconds == null || seconds > 59) return null;
    return minutes * 60 + seconds;
  }

  /// Готовит буфер темпа из секунд: `1030`.
  static String paceBufferFromSeconds(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}'
        '${seconds.toString().padLeft(2, '0')}';
  }

  /// Готовит буфер времени из минут. Время суток циклично: план может
  /// пересекать несколько суток, поэтому результат всегда в 00:00–23:59.
  static String timeBufferFromMinutes(int totalMinutes) {
    final minutesInDay =
        ((totalMinutes % minutesPerDay) + minutesPerDay) % minutesPerDay;
    final hours = minutesInDay ~/ 60;
    final minutes = minutesInDay % 60;
    return '${hours.toString().padLeft(2, '0')}'
        '${minutes.toString().padLeft(2, '0')}';
  }

  /// Форматирует длительность как `чч:мм`.
  static String formatElapsedMinutes(int? minutes) {
    if (minutes == null) return '—';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${rest.toString().padLeft(2, '0')}';
  }

  /// Показывает столько знаков после запятой, сколько ввёл пользователь:
  /// целые значения остаются целыми, `20.3` — с одной десятой.
  static String formatDistance(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final normalized = trimmed.replaceAll(',', '.');
    final dot = normalized.indexOf('.');
    final decimals = dot < 0 ? 0 : normalized.length - dot - 1;
    final value = parseDecimal(trimmed);
    if (value == null) return '';
    if (decimals <= 0) return value.toStringAsFixed(0);
    if (decimals == 1) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }

  /// Номер дня для каждой колонки. Скачок времени назад означает новый день.
  static List<int> computeDays(List<String> times, {int? columns}) {
    final count = columns ?? times.length;
    final days = List<int>.filled(count, 0);
    var day = 0;
    int? previous;
    for (var index = 0; index < count; index++) {
      final time = index < times.length ? parseTime(times[index]) : null;
      if (time != null) {
        if (previous != null && time < previous) day++;
        previous = time;
      }
      days[index] = day;
    }
    return days;
  }

  /// Суммарное время от старта до каждой колонки. Скачок назад означает
  /// переход через полночь.
  static List<int?> elapsedByColumn(List<String> times, {int? columns}) {
    final count = columns ?? times.length;
    final elapsed = List<int?>.filled(count, null);
    if (times.isEmpty) return elapsed;
    final start = parseTime(times[0]);
    if (start == null) return elapsed;

    elapsed[0] = 0;
    var total = 0;
    var previous = start;
    for (var index = 1; index < count; index++) {
      final time = index < times.length ? parseTime(times[index]) : null;
      if (time == null) continue;
      var delta = time - previous;
      if (delta < 0) delta += minutesPerDay;
      total += delta;
      previous = time;
      elapsed[index] = total;
    }
    return elapsed;
  }

  /// Итоговая длительность от первой до последней заполненной колонки.
  static int? elapsedMinutes(List<String> times, {int? columns}) {
    if (times.isEmpty) return null;
    final start = parseTime(times[0]);
    if (start == null) return null;

    final count = columns ?? times.length;
    var total = 0;
    var found = false;
    var previous = start;
    for (var index = 1; index < count; index++) {
      final time = index < times.length ? parseTime(times[index]) : null;
      if (time == null) continue;

      var delta = time - previous;
      if (delta < 0) delta += minutesPerDay;
      total += delta;
      previous = time;
      found = true;
    }
    return found ? total : null;
  }

  /// Статус плана для всех колонок. Считается один раз за построение таблицы,
  /// чтобы не разбирать время заново для каждой клетки.
  static List<PlanTimeStatus> planStatuses({
    required List<String> planTimes,
    required List<String> limitTimes,
    int? columns,
    List<int>? stopsMin,
  }) {
    final count =
        columns ??
        (planTimes.length > limitTimes.length
            ? planTimes.length
            : limitTimes.length);
    final plan = elapsedByColumn(planTimes, columns: count);
    final limit = elapsedByColumn(limitTimes, columns: count);
    // Красный по §7.4: стоянка на ПП выводит план за лимит.
    bool stopOverLimit(int column) {
      if (stopsMin == null || column >= stopsMin.length) return false;
      final stop = stopsMin[column];
      final limitValue = limit[column];
      final planValue = plan[column];
      if (stop <= 0 || limitValue == null || planValue == null) return false;
      return planValue + stop > limitValue;
    }

    return List<PlanTimeStatus>.generate(count, (column) {
      if (column <= 0) return PlanTimeStatus.normal;
      final planValue = plan[column];
      final limitValue = limit[column];
      if (planValue == null || limitValue == null) {
        return PlanTimeStatus.normal;
      }

      final delta = planValue - limitValue;
      if (delta > 0 || stopOverLimit(column)) {
        return PlanTimeStatus.behindLimit;
      }
      if (delta < 0 && -delta < yellowWarningMinutes) {
        return PlanTimeStatus.closeToLimit;
      }
      return PlanTimeStatus.normal;
    });
  }

  /// Темп сегмента между колонками `index - 1` и `index`.
  static int? segmentPace({
    required List<String> times,
    required List<String> distances,
    required int index,
  }) {
    if (index <= 0 || index >= times.length || index >= distances.length) {
      return null;
    }

    final previousTime = parseTime(times[index - 1]);
    final time = parseTime(times[index]);
    final previousDistance = parseDecimal(distances[index - 1]);
    final distance = parseDecimal(distances[index]);

    if (previousTime == null ||
        time == null ||
        previousDistance == null ||
        distance == null) {
      return null;
    }

    var timeDelta = time - previousTime;
    if (timeDelta < 0) timeDelta += minutesPerDay;

    final distanceDelta = distance - previousDistance;
    if (distanceDelta <= 0) return null;

    return (timeDelta * 60 / distanceDelta).round();
  }

  /// Плановый темп между колонками `column - 1` и `column`.
  static int? plannedPace({
    required List<String> planTimes,
    required List<String> distances,
    required int column,
  }) {
    if (column <= 0) return null;
    return segmentPace(times: planTimes, distances: distances, index: column);
  }

  /// Средний темп от старта до последней колонки, где есть и время, и
  /// расстояние.
  static int? overallPace({
    required List<String> times,
    required List<String> distances,
    int? columns,
  }) {
    if (times.isEmpty || distances.isEmpty) return null;

    final startTime = parseTime(times[0]);
    final startDistance = parseDecimal(distances[0]) ?? 0;
    if (startTime == null) return null;

    final count = columns ?? times.length;
    var lastIndex = -1;
    for (var index = 1; index < count; index++) {
      if (index < times.length &&
          index < distances.length &&
          parseTime(times[index]) != null &&
          parseDecimal(distances[index]) != null) {
        lastIndex = index;
      }
    }
    if (lastIndex < 1) return null;

    var elapsed = 0;
    var previousTime = startTime;
    for (var index = 1; index <= lastIndex; index++) {
      final currentTime = parseTime(times[index]);
      if (currentTime == null) continue;

      var delta = currentTime - previousTime;
      if (delta < 0) delta += minutesPerDay;
      elapsed += delta;
      previousTime = currentTime;
    }

    final endDistance = parseDecimal(distances[lastIndex]);
    if (endDistance == null) return null;

    final distanceDelta = endDistance - startDistance;
    if (distanceDelta <= 0) return null;

    return (elapsed * 60 / distanceDelta).round();
  }

  /// Какая клетка быстрее всех и какая вторая по скорости.
  static PaceHighlight paceHighlight({
    required int column,
    required List<int?> paces,
  }) {
    if (column < 0 || column >= paces.length) return PaceHighlight.none;

    final values = <int>[];
    for (final pace in paces) {
      if (pace != null) values.add(pace);
    }
    if (values.isEmpty) return PaceHighlight.none;

    values.sort();
    final minimum = values.first;
    int? second;
    for (final value in values) {
      if (value > minimum) {
        second = value;
        break;
      }
    }

    final pace = paces[column];
    if (pace == null) return PaceHighlight.none;
    if (pace == minimum) return PaceHighlight.fastest;
    if (second != null && pace == second) return PaceHighlight.secondFastest;
    return PaceHighlight.none;
  }
}
