import 'dart:typed_data';

/// Путевая точка GPX (`wpt`). Имя и координаты — без интерпретации.
class GpxWaypoint {
  const GpxWaypoint({required this.name, required this.lat, required this.lon});

  final String name;
  final double lat;
  final double lon;
}

/// Разобранный трек: точки в порядке файла, склеенные `trkseg`.
///
/// Высоты храним как `NaN`, если в точке нет `ele`.
class GpxTrack {
  GpxTrack({
    required this.lats,
    required this.lons,
    required this.eles,
    required this.segmentStarts,
    required this.waypoints,
    required this.droppedPoints,
  }) : assert(lats.length == lons.length && lats.length == eles.length);

  final Float64List lats;
  final Float64List lons;
  final Float64List eles;

  /// Индексы первой точки каждого `trkseg` (первый всегда 0).
  final List<int> segmentStarts;
  final List<GpxWaypoint> waypoints;

  /// Сколько точек отброшено как дубликаты (шаг меньше порога).
  final int droppedPoints;

  int get length => lats.length;

  /// Высоты есть, только если `ele` задан у каждой точки.
  bool get hasElevation => length > 0 && eles.every((e) => !e.isNaN);
}

/// Ошибка разбора GPX: файл не похож на трек или превышены лимиты.
class GpxFormatException implements Exception {
  const GpxFormatException(this.message);

  final String message;

  @override
  String toString() => 'GpxFormatException: $message';
}
