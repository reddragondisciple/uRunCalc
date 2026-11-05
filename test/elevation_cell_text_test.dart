import 'dart:ui' show Color;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/elevation_format.dart';
import 'package:ultra_run_calc/features/pace/elevation_cell_text.dart';

const _red = Color(0xFFFF0000);
const _green = Color(0xFF00FF00);
const _amber = Color(0xFFFFB74D);

void main() {
  test('подъём красным, спуск зелёным, дефис нейтральным', () {
    final spans = elevationPairSpans(
      143,
      109,
      upColor: _red,
      downColor: _green,
      separatorColor: _amber,
    );
    expect(spans.map((s) => s.text).join(), '143-109');
    expect(spans[0].style?.color, _red);
    expect(spans[1].style?.color, _amber);
    expect(spans[2].style?.color, _green);
  });

  test('текст совпадает с formatElevationPair, в т.ч. километры', () {
    for (final pair in [(0.0, 0.0), (90.0, 11.0), (1200.0, 300.0)]) {
      final spans = elevationPairSpans(
        pair.$1,
        pair.$2,
        upColor: _red,
        downColor: _green,
        separatorColor: _amber,
      );
      expect(
        spans.map((s) => s.text).join(),
        formatElevationPair(pair.$1, pair.$2),
      );
    }
  });
}
