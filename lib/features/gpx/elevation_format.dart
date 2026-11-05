/// Формат ряда подъём–спуск в клетке таблицы (docs/gpx-mountain-mode.md §5.3).
///
/// Числа меньше 1000 м показываем целыми метрами (`143-109`), от 1000 м —
/// десятыми километра (`1.2-0.3`). Футы — только для будущего имперского режима.
library;

/// Порог перехода с метров на километры.
const double elevationKmThresholdM = 1000;

/// Одно число для клетки: метры или км с одним знаком.
String formatElevationValue(double meters) {
  final value = meters < 0 ? 0.0 : meters;
  final metersRounded = value.round();
  // Округление до 1000 м уже километры: 999.6 м → `1.0`, а не `1000`.
  if (metersRounded < elevationKmThresholdM) {
    return metersRounded.toString();
  }
  final km = (value / 1000 * 10).round() / 10;
  return km.toStringAsFixed(1);
}

/// Пара подъём–спуск: `90-11`, `1.2-0.3`. Без стрелок — стрелки добавляет
/// вызывающий код, если клетка достаточно широкая.
String formatElevationPair(double ascentM, double descentM) {
  return '${formatElevationValue(ascentM)}-${formatElevationValue(descentM)}';
}

/// Футы для имперского режима: только целые футы, без километров.
String formatElevationPairFeet(double ascentM, double descentM) {
  final up = (ascentM * 3.28084).round();
  final down = (descentM * 3.28084).round();
  return '$up-$down';
}

/// Всегда целые метры, без перехода к километрам (портретный итог подъёма).
String formatElevationMeters(double meters) {
  final value = meters < 0 ? 0.0 : meters;
  return value.round().toString();
}
