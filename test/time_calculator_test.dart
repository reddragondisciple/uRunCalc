import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/core/app_strings.dart';
import 'package:ultra_run_calc/features/time/time_calculator.dart';

void main() {
  group('date parsing', () {
    test('formats typed digits as a date', () {
      expect(TimeCalculator.dateInputText('01022026'), '01.02.2026');
      expect(TimeCalculator.dateInputText(''), AppStrings.timeDatePattern);
    });

    test('parses a valid date', () {
      final date = TimeCalculator.parseDate('01022026');

      expect(date, DateTime.utc(2026, 2, 1));
      expect(TimeCalculator.formatDate(date!), '01.02.2026');
    });

    test('rejects incomplete and impossible dates', () {
      expect(TimeCalculator.parseDate('0102202'), isNull);
      expect(TimeCalculator.parseDate('31022026'), isNull);
      expect(TimeCalculator.parseDate('01132026'), isNull);
    });
  });

  group('clock and duration', () {
    test('accepts hours beyond 24', () {
      expect(TimeCalculator.clockSeconds('500', '0'), 500 * 3600);
      expect(TimeCalculator.clockSeconds('', ''), 0);
      expect(TimeCalculator.clockSeconds('', '30'), 1800);
    });

    test('builds a date time from separate fields', () {
      final value = TimeCalculator.dateTime(
        date: '01022026',
        hours: '23',
        minutes: '30',
      );

      expect(value, DateTime.utc(2026, 2, 1, 23, 30));
    });

    test('duration requires at least one part', () {
      expect(
        TimeCalculator.durationSeconds(
          days: '',
          hours: '',
          minutes: '',
          seconds: '',
        ),
        isNull,
      );
      expect(
        TimeCalculator.durationSeconds(
          days: '1',
          hours: '2',
          minutes: '3',
          seconds: '4',
        ),
        93784,
      );
    });

    test('shifts a date time forward and backward', () {
      final base = DateTime.utc(2026, 2, 1, 23, 30);

      expect(
        TimeCalculator.shifted(base: base, seconds: 3600, subtract: false),
        DateTime.utc(2026, 2, 2, 0, 30),
      );
      expect(
        TimeCalculator.shifted(base: base, seconds: 3600, subtract: true),
        DateTime.utc(2026, 2, 1, 22, 30),
      );
    });
  });
}
