import 'package:flutter/painting.dart';

import '../gpx/elevation_format.dart';

/// Клетка ряда подъём–спуск: подъём и спуск разными цветами, дефис между ними.
///
/// Цвета передаёт вызывающий код (палитра приложения), чтобы функция не
/// зависела от темы. Текст совпадает с [formatElevationPair].
List<TextSpan> elevationPairSpans(
  double ascentM,
  double descentM, {
  required Color upColor,
  required Color downColor,
  required Color separatorColor,
}) {
  return [
    TextSpan(
      text: formatElevationValue(ascentM),
      style: TextStyle(color: upColor),
    ),
    TextSpan(
      text: '-',
      style: TextStyle(color: separatorColor),
    ),
    TextSpan(
      text: formatElevationValue(descentM),
      style: TextStyle(color: downColor),
    ),
  ];
}
