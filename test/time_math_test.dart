import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/core/time_math.dart';

void main() {
  test('formatPaceSeconds pads seconds', () {
    expect(formatPaceSeconds(600), '10:00');
    expect(formatPaceSeconds(65), '1:05');
    expect(formatPaceSeconds(0), '0:00');
  });

  test('splitSeconds splits days and time', () {
    final parts = splitSeconds(90061);

    expect(parts.days, 1);
    expect(parts.hours, 1);
    expect(parts.minutes, 1);
    expect(parts.seconds, 1);
  });

  test('parseDurationParts sums parts and ignores empty input', () {
    expect(parseDurationParts(['1', '2', '3', '4']), 93784);
    expect(parseDurationParts(['', '', '', '']), isNull);
    expect(parseDurationParts(['0', '0', '0', '30']), 30);
  });

  test('parseDecimal accepts dot and comma', () {
    expect(parseDecimal('20.3'), 20.3);
    expect(parseDecimal('20,3'), 20.3);
    expect(parseDecimal(' 42 '), 42);
  });

  test('parseDecimal rejects empty and invalid values', () {
    expect(parseDecimal(''), isNull);
    expect(parseDecimal('abc'), isNull);
    expect(parseDecimal('Infinity'), isNull);
  });
}
