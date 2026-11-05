/// Арифметика плана в горном режиме (docs/gpx-mountain-mode.md §7).
///
/// Работает в секундах. Строки `ччмм` и UI сюда не попадают.
library;

/// Сегмент плана между двумя колонками ПП.
class PlanSegment {
  const PlanSegment({required this.distanceKm, required this.gapFactor});

  final double distanceKm;

  /// Из `SegmentStats.gapFactor`. `1`, если высот нет.
  final double gapFactor;
}

/// Итог расчёта: ходовые времена сегментов, прибытия и итоги.
class PlanResult {
  const PlanResult({
    required this.movingSec,
    required this.arrivalSec,
    required this.totalSec,
    required this.movingTotalSec,
  });

  /// Ходовое время каждого сегмента, сек. Индекс `i` — сегмент `i−1 → i`;
  /// для колонки 0 значение 0.
  final List<double> movingSec;

  /// Прибытие на колонку `i` от старта, сек (включая стоянки до `i`).
  final List<double> arrivalSec;

  /// Итог: ходовое время плюс все стоянки.
  final double totalSec;
  final double movingTotalSec;
}

/// Ходовое время сегментов от плоского темпа `flatPaceSecPerKm` и GAP.
List<double> movingFromFlatPace(
  List<PlanSegment> segments,
  double flatPaceSecPerKm,
) {
  return [
    for (final s in segments) s.distanceKm * flatPaceSecPerKm * s.gapFactor,
  ];
}

/// Масштабирует ходовые времена так, чтобы их сумма стала `targetMovingSec`.
/// Пропорционально сохраняет относительный вклад сегментов по GAP.
List<double> normalizeMoving(List<double> moving, double targetMovingSec) {
  final sum = moving.fold<double>(0, (a, b) => a + b);
  if (sum <= 0) return List<double>.of(moving);
  final lambda = targetMovingSec / sum;
  return [for (final m in moving) m * lambda];
}

/// Сумма стоянок на промежуточных колонках `1..count-2`. Старт и финиш
/// стоянок не имеют.
double sumIntermediateStops(List<double> stopsSec, int count) {
  var sum = 0.0;
  for (var i = 1; i < count - 1; i++) {
    sum += _stopAt(stopsSec, i);
  }
  return sum;
}

/// Суммарная длина сегментов, км.
double totalDistanceKm(List<PlanSegment> segments) =>
    segments.fold<double>(0, (a, s) => a + s.distanceKm);

/// Ходовое время от опоры «плоский темп» (§7.2 `flat(p0)`).
///
/// Возвращает `null`, если плоского темпа нет или он не положительный.
List<double>? movingForFlatPace(
  List<PlanSegment> segments,
  double? flatPaceSecPerKm,
) {
  if (flatPaceSecPerKm == null || flatPaceSecPerKm <= 0) return null;
  return movingFromFlatPace(segments, flatPaceSecPerKm);
}

/// Ходовое время от опоры «итоговое время» (§7.2 `targetTime(T)`).
///
/// `T` включает стоянки: ходовое время нормируется на `T − Σ стоянок`.
/// Возвращает `null`, если стоянки не оставляют времени на ход или
/// сегменты пустые.
List<double>? movingForTargetTime({
  required List<PlanSegment> segments,
  required List<double> stopsSec,
  required double totalSec,
}) {
  final count = segments.length + 1;
  final targetMoving = totalSec - sumIntermediateStops(stopsSec, count);
  if (targetMoving <= 0) return null;
  final raw = movingFromFlatPace(segments, 1);
  if (raw.fold<double>(0, (a, b) => a + b) <= 0) return null;
  return normalizeMoving(raw, targetMoving);
}

/// Ходовое время от опоры «ходовой темп» (§7.2 `targetPace(p)`).
///
/// Нормируется так, чтобы `movingTotal / D = p`. Стоянки не участвуют.
List<double>? movingForTargetPace({
  required List<PlanSegment> segments,
  required double movingPaceSecPerKm,
}) {
  if (movingPaceSecPerKm <= 0) return null;
  final distance = totalDistanceKm(segments);
  if (distance <= 0) return null;
  final raw = movingFromFlatPace(segments, 1);
  if (raw.fold<double>(0, (a, b) => a + b) <= 0) return null;
  return normalizeMoving(raw, movingPaceSecPerKm * distance);
}

/// Плоский темп, который получается из введённого итогового времени
/// «плоские данные» (§7.3): `p0 = (T − Σ стоянок) / D`.
///
/// Возвращает `null`, если времени не хватает на ход или `D = 0`.
double? flatPaceForTotalTime({
  required List<PlanSegment> segments,
  required List<double> stopsSec,
  required double totalSec,
}) {
  final count = segments.length + 1;
  final distance = totalDistanceKm(segments);
  final moving = totalSec - sumIntermediateStops(stopsSec, count);
  if (distance <= 0 || moving <= 0) return null;
  return moving / distance;
}

/// Фактический темп сегмента `i−1 → i`, сек/км.
///
/// [withStops] = false — чистый ходовой темп (`moving_i / length_i`).
/// [withStops] = true — с учётом стоянки на `i−1`: разность прибытий.
/// Возвращает `null` для колонки 0 и нулевой длины.
double? segmentPaceSecPerKm({
  required PlanResult plan,
  required List<PlanSegment> segments,
  required int column,
  bool withStops = false,
}) {
  if (column <= 0 || column - 1 >= segments.length) return null;
  final distance = segments[column - 1].distanceKm;
  if (distance <= 0) return null;
  final seconds = withStops
      ? plan.arrivalSec[column] - plan.arrivalSec[column - 1]
      : plan.movingSec[column];
  return seconds / distance;
}

/// Собирает план по опоре: ходовое время сегментов → прибытия и итоги.
///
/// Возвращает `null`, если опора не применима (см. `movingFor…`).
PlanResult? planForMoving({
  required List<double>? moving,
  required List<double> stopsSec,
}) {
  if (moving == null) return null;
  // Индекс 0 — старт, у него нет сегмента. Добавляем его в начало.
  final padded = [0.0, ...moving];
  return assemblePlan(movingSec: padded, stopsSec: stopsSec);
}

/// Собирает прибытия и итоги.
///
/// `movingSec[i]` — ходовое время сегмента `i−1 → i` (индекс 0 не используется).
/// `stopsSec[i]` — стоянка на колонке `i`. Стоянки учитываются только на
/// промежуточных ПП: старт и финиш без стоянок.
/// Прибытие на `i` = старт + ходовое до `i` + стоянки на `1..i−1`.
PlanResult assemblePlan({
  required List<double> movingSec,
  required List<double> stopsSec,
}) {
  final count = movingSec.length;
  final arrival = List<double>.filled(count, 0);
  var elapsed = 0.0;
  var movingTotal = 0.0;
  var stopsTotal = 0.0;
  for (var i = 1; i < count; i++) {
    elapsed += movingSec[i];
    movingTotal += movingSec[i];
    arrival[i] = elapsed;
    if (i < count - 1) {
      final stop = _stopAt(stopsSec, i);
      elapsed += stop;
      stopsTotal += stop;
    }
  }
  return PlanResult(
    movingSec: List<double>.of(movingSec),
    arrivalSec: arrival,
    totalSec: movingTotal + stopsTotal,
    movingTotalSec: movingTotal,
  );
}

double _stopAt(List<double> stops, int index) {
  if (index < 0 || index >= stops.length) return 0;
  return stops[index];
}

/// Распределяет суммарные стоянки по промежуточным ПП.
///
/// Пустой ряд (все нули): сумма делится поровну между промежуточными ПП,
/// остаток уходит на последний. Заполненный ряд: значения масштабируются
/// пропорционально к новой сумме.
List<double> distributeStops({
  required int columns,
  required double totalSec,
  required List<double> current,
}) {
  final result = List<double>.filled(columns, 0);
  // Промежуточные ПП: колонки 1..columns-2 (старт и финиш не считаем).
  final intermediate = columns - 2;
  if (intermediate <= 0 || totalSec <= 0) return result;

  final currentSum = [
    for (var i = 1; i < columns - 1; i++) _stopAt(current, i),
  ].fold<double>(0, (a, b) => a + b);

  if (currentSum <= 0) {
    final share = (totalSec / intermediate).floorToDouble();
    for (var i = 1; i < columns - 1; i++) {
      result[i] = share;
    }
    result[columns - 2] += totalSec - share * intermediate;
    return result;
  }

  final factor = totalSec / currentSum;
  for (var i = 1; i < columns - 1; i++) {
    result[i] = (_stopAt(current, i) * factor).roundToDouble();
  }
  return result;
}

/// Сдвигает плановые времена колонок после `column` на `deltaSec`
/// (правка времени или стоянки). Обновляет до `lastPacedColumn` включительно.
/// Возвращает новые прибытия; вход не мутирует.
List<double> shiftFollowing({
  required List<double> arrivalSec,
  required int column,
  required double deltaSec,
  required int lastPacedColumn,
}) {
  final result = List<double>.of(arrivalSec);
  for (var i = column + 1; i <= lastPacedColumn && i < result.length; i++) {
    result[i] += deltaSec;
  }
  return result;
}

/// Красное правило: прибытие + стоянка на ПП больше лимита.
bool isOverLimit({
  required double arrivalSec,
  required double stopSec,
  required double limitSec,
}) {
  return arrivalSec + stopSec > limitSec;
}

/// Красная подсветка «План» на колонке (§7.4, решение пользователя):
/// красим, если прибытие уже позже лимита (как раньше) либо если стоянка
/// на ПП выводит за лимит (`прибытие + стоянка > лимит`).
bool isPlanRed({
  required double arrivalSec,
  required double stopSec,
  required double limitSec,
}) {
  return arrivalSec > limitSec ||
      isOverLimit(arrivalSec: arrivalSec, stopSec: stopSec, limitSec: limitSec);
}

/// Вид опоры для чистого расчёта (зеркало `PlanAnchorKind` без зависимости
/// от слоя `features/pace`).
enum PlanAnchorMode { flat, targetTime, targetPace, manual }

/// Результат пересчёта плана по опоре: времена колонок от старта, сек.
/// `null` — опора не применима (нет данных для расчёта).
class RecomputedPlan {
  const RecomputedPlan({required this.arrivalSec, required this.paceSec});

  /// Прибытие на колонку `i`, сек от старта (включая стоянки до `i`).
  final List<double> arrivalSec;

  /// Ходовой темп каждого сегмента `i−1 → i`, сек/км (индекс 0 — 0).
  final List<double> paceSec;
}

/// Полный пересчёт плана (docs/gpx-mountain-mode.md §7.5, «если сомневаемся»).
///
/// Берёт опору, сегменты с GAP и стоянки и собирает прибытия и темпы.
/// Для `manual` опора не нормируется: используется [manualMovingSec] —
/// текущие ходовые времена сегментов (индекс 0 не используется).
RecomputedPlan? recomputePlan({
  required PlanAnchorMode anchor,
  required List<PlanSegment> segments,
  required List<double> stopsSec,
  double? flatPaceSec,
  double? targetTotalSec,
  double? targetPaceSec,
  List<double>? manualMovingSec,
}) {
  final count = segments.length + 1;
  List<double>? moving;
  switch (anchor) {
    case PlanAnchorMode.flat:
      moving = movingForFlatPace(segments, flatPaceSec ?? 0);
    case PlanAnchorMode.targetTime:
      moving = targetTotalSec == null
          ? null
          : movingForTargetTime(
              segments: segments,
              stopsSec: stopsSec,
              totalSec: targetTotalSec,
            );
    case PlanAnchorMode.targetPace:
      moving = targetPaceSec == null
          ? null
          : movingForTargetPace(
              segments: segments,
              movingPaceSecPerKm: targetPaceSec,
            );
    case PlanAnchorMode.manual:
      moving = manualMovingSec == null || manualMovingSec.length != count
          ? null
          : List<double>.of(manualMovingSec.skip(1));
  }
  final plan = planForMoving(moving: moving, stopsSec: stopsSec);
  if (plan == null) return null;
  final pace = List<double>.filled(count, 0);
  for (var i = 1; i < count; i++) {
    pace[i] =
        segmentPaceSecPerKm(plan: plan, segments: segments, column: i) ?? 0;
  }
  return RecomputedPlan(arrivalSec: plan.arrivalSec, paceSec: pace);
}

/// Режим ввода итога в диалоге «плоские / с поправкой» (§7.3).
enum PlanInputMode { flatData, withAdjustment }

/// Итог для диалога и предпросмотра (в таблицу не попадает).
class PlanPreview {
  const PlanPreview({
    required this.flatPaceSec,
    required this.movingPaceSec,
    required this.totalSec,
    required this.stopsSec,
  });

  /// Введённый плоский темп (для «плоских» — `p0`; для «с поправкой» —
  /// `null`, если введено время и плоский эквивалент не нужен для показа).
  final double? flatPaceSec;

  /// Средний ходовой темп по дистанции, сек/км (`movingTotal / D`).
  final double? movingPaceSec;

  /// Итог с учётом стоянок, сек.
  final double? totalSec;

  /// Суммарные стоянки, сек.
  final double stopsSec;
}

/// Опора для ввода итога: вид и значение (без зависимости от `pace/`).
class PlanInputAnchor {
  const PlanInputAnchor(this.mode, this.value);

  /// `flat` — значение плоский темп (сек/км); `targetTime` — итог (сек);
  /// `targetPace` — ходовой темп (сек/км).
  final PlanAnchorMode mode;
  final double value;
}

/// Строит опору и предпросмотр по введённому итогу.
///
/// [byTime] — ввод времени (`value` = сек итога), иначе ввод темпа
/// (`value` = сек/км). [stopsSec] — стоянки по колонкам (сек), уже
/// распределённые по ПП; [totalStopsSec] — их сумма.
/// Возвращает null, если данных недостаточно.
({PlanInputAnchor anchor, PlanPreview preview})? planFromInput({
  required PlanInputMode mode,
  required bool byTime,
  required double value,
  required List<PlanSegment> segments,
  required List<double> stopsSec,
  required double totalStopsSec,
}) {
  final distance = totalDistanceKm(segments);
  if (distance <= 0 || value <= 0) return null;

  if (mode == PlanInputMode.flatData) {
    final p0 = byTime
        ? flatPaceForTotalTime(
            segments: segments,
            stopsSec: stopsSec,
            totalSec: value,
          )
        : value;
    if (p0 == null || p0 <= 0) return null;
    final movingTotal = movingFromFlatPace(
      segments,
      p0,
    ).fold<double>(0, (a, b) => a + b);
    return (
      anchor: PlanInputAnchor(PlanAnchorMode.flat, p0),
      preview: PlanPreview(
        flatPaceSec: p0,
        movingPaceSec: movingTotal / distance,
        totalSec: movingTotal + totalStopsSec,
        stopsSec: totalStopsSec,
      ),
    );
  }

  if (byTime) {
    final moving = movingForTargetTime(
      segments: segments,
      stopsSec: stopsSec,
      totalSec: value,
    );
    if (moving == null) return null;
    return (
      anchor: PlanInputAnchor(PlanAnchorMode.targetTime, value),
      preview: PlanPreview(
        flatPaceSec: null,
        movingPaceSec: moving.fold<double>(0, (a, b) => a + b) / distance,
        totalSec: value,
        stopsSec: totalStopsSec,
      ),
    );
  }

  final moving = movingForTargetPace(
    segments: segments,
    movingPaceSecPerKm: value,
  );
  if (moving == null) return null;
  return (
    anchor: PlanInputAnchor(PlanAnchorMode.targetPace, value),
    preview: PlanPreview(
      flatPaceSec: null,
      movingPaceSec: value,
      totalSec: moving.fold<double>(0, (a, b) => a + b) + totalStopsSec,
      stopsSec: totalStopsSec,
    ),
  );
}

/// Темп сегмента `i−1 → i`, сек/км, «с учётом стоянок» (§5/§7):
/// `(прибытие_i − прибытие_{i−1}) / расстояние_i`.
///
/// [arrivalSec] — прибытия по колонкам плана (сек от старта). Возвращает
/// `null`, если данных недостаточно или расстояние нулевое.
double? stopsAwareSegmentPace({
  required List<double?> arrivalSec,
  required List<double> distancesKm,
  required int column,
}) {
  if (column <= 0 || column >= arrivalSec.length) return null;
  if (column - 1 >= distancesKm.length) return null;
  final distance = distancesKm[column - 1];
  if (distance <= 0) return null;
  final now = arrivalSec[column];
  final before = arrivalSec[column - 1];
  if (now == null || before == null) return null;
  return (now - before) / distance;
}
