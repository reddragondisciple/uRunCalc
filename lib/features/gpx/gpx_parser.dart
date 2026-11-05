import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'gpx_track.dart';

/// Лимиты из ТЗ: больше — отказ с сообщением.
const int gpxMaxPoints = 200000;
const int gpxMaxBytes = 50 * 1024 * 1024;

/// Точки ближе этого шага (2D, м) внутри сегмента считаются дубликатами.
const double gpxMinStepMeters = 0.5;

/// Разбирает GPX. Берёт первый `trk`, в котором есть точки.
///
/// Чистая функция: без Flutter и без файловой системы.
GpxTrack parseGpx(String source) {
  if (source.length > gpxMaxBytes) {
    throw const GpxFormatException('Файл больше 50 МБ');
  }

  final XmlDocument document;
  try {
    document = XmlDocument.parse(source);
  } on XmlException catch (error) {
    throw GpxFormatException('Не удалось разобрать XML: ${error.message}');
  }

  final root = document.rootElement;
  if (root.name.local != 'gpx') {
    throw const GpxFormatException('Это не GPX-файл');
  }

  final waypoints = <GpxWaypoint>[];
  for (final wpt in _children(root, 'wpt')) {
    final lat = _number(wpt, 'lat');
    final lon = _number(wpt, 'lon');
    if (lat == null || lon == null) continue;
    waypoints.add(
      GpxWaypoint(name: _childText(wpt, 'name') ?? '', lat: lat, lon: lon),
    );
  }

  List<XmlElement>? segments;
  for (final trk in _children(root, 'trk')) {
    final candidates = _children(trk, 'trkseg').toList();
    if (candidates.any((seg) => _children(seg, 'trkpt').isNotEmpty)) {
      segments = candidates;
      break;
    }
  }
  if (segments == null) {
    throw const GpxFormatException('В файле нет трека с точками');
  }

  final lats = <double>[];
  final lons = <double>[];
  final eles = <double>[];
  final segmentStarts = <int>[];
  var dropped = 0;

  for (final seg in segments) {
    final points = _children(seg, 'trkpt');
    if (points.isEmpty) continue;
    final segmentStart = lats.length;
    segmentStarts.add(segmentStart);

    for (final pt in points) {
      final lat = _number(pt, 'lat');
      final lon = _number(pt, 'lon');
      if (lat == null || lon == null) {
        dropped++;
        continue;
      }
      if (lats.length >= gpxMaxPoints) {
        throw const GpxFormatException('Больше 200 000 точек');
      }

      final inSegment = lats.length > segmentStart;
      if (inSegment &&
          haversineMeters(lats.last, lons.last, lat, lon) < gpxMinStepMeters) {
        dropped++;
        continue;
      }

      lats.add(lat);
      lons.add(lon);
      eles.add(_number(pt, 'ele') ?? double.nan);
    }
  }

  if (lats.length < 2) {
    throw const GpxFormatException('Слишком мало точек для трека');
  }

  return GpxTrack(
    lats: Float64List.fromList(lats),
    lons: Float64List.fromList(lons),
    eles: Float64List.fromList(eles),
    segmentStarts: segmentStarts,
    waypoints: waypoints,
    droppedPoints: dropped,
  );
}

/// Расстояние по большому кругу, метры.
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadius = 6371000.0;
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dPhi = (lat2 - lat1) * math.pi / 180;
  final dLambda = (lon2 - lon1) * math.pi / 180;
  final a =
      math.pow(math.sin(dPhi / 2), 2) +
      math.cos(phi1) * math.cos(phi2) * math.pow(math.sin(dLambda / 2), 2);
  return 2 * earthRadius * math.asin(math.min(1.0, math.sqrt(a.toDouble())));
}

Iterable<XmlElement> _children(XmlNode parent, String localName) {
  return parent.children.whereType<XmlElement>().where(
    (element) => element.name.local == localName,
  );
}

String? _childText(XmlElement parent, String localName) {
  for (final child in _children(parent, localName)) {
    return child.innerText.trim();
  }
  return null;
}

/// Число из атрибута (`lat`, `lon`) или дочернего элемента (`ele`).
double? _number(XmlElement element, String name) {
  final raw = element.getAttribute(name) ?? _childText(element, name);
  if (raw == null) return null;
  final value = double.tryParse(raw.trim());
  if (value == null || !value.isFinite) return null;
  return value;
}
