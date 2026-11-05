import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/elevation_format.dart';

void main() {
  test('меньше 1000 м — целые метры', () {
    expect(formatElevationPair(90, 11), '90-11');
    expect(formatElevationPair(143, 109), '143-109');
    expect(formatElevationValue(999.4), '999');
  });

  test('от 1000 м — десятые километра', () {
    expect(formatElevationPair(1200, 1300), '1.2-1.3');
    // Числа округляются отдельно: 300 м остаются метрами.
    expect(formatElevationPair(1200, 300), '1.2-300');
    expect(formatElevationValue(1000), '1.0');
  });

  test('граница округления: 999.6 м не превращается в «1000»', () {
    expect(formatElevationValue(999.6), '1.0');
  });

  test('ноль и отрицательные не портят формат', () {
    expect(formatElevationPair(0, 0), '0-0');
    expect(formatElevationPair(-5, 0), '0-0');
  });

  test('футы — целые, без километров', () {
    expect(formatElevationPairFeet(100, 50), '328-164');
    expect(formatElevationPairFeet(1000, 0), '3281-0');
  });

  test('formatElevationMeters всегда метры, даже от 1000 м', () {
    expect(formatElevationMeters(999.6), '1000');
    expect(formatElevationMeters(1200), '1200');
    expect(formatElevationMeters(-3), '0');
  });
}
