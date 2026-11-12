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
    Float64List? timesSec,
  }) : timesSec = timesSec ?? _nanTimes(lats.length),
       assert(lats.length == lons.length && lats.length == eles.length),
       assert(lats.length == (timesSec?.length ?? lats.length));

  final Float64List lats;
  final Float64List lons;
  final Float64List eles;

  /// Время точки, epoch seconds UTC. `NaN`, если `time` нет или он битый.
  /// Длина всегда совпадает с [lats].
  final Float64List timesSec;

  /// Индексы первой точки каждого `trkseg` (первый всегда 0).
  final List<int> segmentStarts;
  final List<GpxWaypoint> waypoints;

  /// Сколько точек отброшено как дубликаты (шаг меньше порога).
  final int droppedPoints;

  int get length => lats.length;

  /// Высоты есть, только если `ele` задан у каждой точки.
  bool get hasElevation => length > 0 && eles.every((e) => !e.isNaN);

  /// Время есть, только если `time` задан у каждой точки.
  bool get hasTime => length > 0 && timesSec.every((t) => !t.isNaN);
}

Float64List _nanTimes(int length) {
  final times = Float64List(length);
  if (length > 0) times.fillRange(0, length, double.nan);
  return times;
}

/// Ошибка разбора GPX: файл не похож на трек или превышены лимиты.
class GpxFormatException implements Exception {
  const GpxFormatException(this.message);

  final String message;

  @override
  String toString() => 'GpxFormatException: $message';
}
