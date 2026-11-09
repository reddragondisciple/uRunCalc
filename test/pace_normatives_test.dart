import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/pace/pace_normatives.dart';

void main() {
  test('returns the highest category for a marathon time', () {
    final result = PaceNormatives.lookup(
      distanceKm: 42.195,
      timeSeconds: 2 * 3600 + 35 * 60,
    );

    expect(result, isNotNull);
    expect(result!.male, 'I');
    expect(result.female, 'МС');
  });

  test('matches the half marathon preset and rounds the distance', () {
    final result = PaceNormatives.lookup(
      distanceKm: 21.097,
      timeSeconds: 3600 + 20 * 60,
    );

    expect(result, isNotNull);
    expect(result!.male, 'II');
    expect(result.female, 'КМС');
  });

  test('returns only the category that was actually met', () {
    final result = PaceNormatives.lookup(distanceKm: 10, timeSeconds: 40 * 60);

    expect(result, isNotNull);
    expect(result!.male, isNull);
    expect(result.female, 'I');
  });

  test('uses stadium standards for 5 km', () {
    final result = PaceNormatives.lookup(distanceKm: 5, timeSeconds: 17 * 60);

    expect(result, isNotNull);
    expect(result!.male, 'II');
    expect(result.female, 'КМС');
  });

  test('returns null when the time is slower than the third category', () {
    expect(
      PaceNormatives.lookup(
        distanceKm: 42.195,
        timeSeconds: 4 * 3600 + 20 * 60,
      ),
      isNull,
    );
    expect(PaceNormatives.lookup(distanceKm: 5, timeSeconds: 25 * 60), isNull);
  });

  test('returns null for a non-standard distance', () {
    expect(PaceNormatives.lookup(distanceKm: 7, timeSeconds: 30 * 60), isNull);
  });
}
