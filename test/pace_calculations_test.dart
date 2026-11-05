import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/pace/pace_calculations.dart';

void main() {
  group('time and pace buffers', () {
    test('parses hours and minutes', () {
      expect(PaceTableCalculator.parseTime('0500'), 300);
      expect(PaceTableCalculator.parseTime('0930'), 570);
      expect(PaceTableCalculator.parseTime(''), isNull);
      expect(PaceTableCalculator.parseTime('1260'), isNull);
    });

    test('formats time and pace', () {
      expect(PaceTableCalculator.timeText('0500'), '05:00');
      expect(PaceTableCalculator.timeText(''), '00:00');
      expect(PaceTableCalculator.paceText('1030'), '10:30');
      expect(PaceTableCalculator.paceText(''), '0:00');
    });

    test('parses pace and rejects invalid seconds', () {
      expect(PaceTableCalculator.parsePace('1030'), 630);
      expect(PaceTableCalculator.parsePace('1060'), isNull);
      expect(PaceTableCalculator.parsePace(''), isNull);
      expect(PaceTableCalculator.paceBufferFromSeconds(630), '1030');
    });

    test('wraps plan time around midnight', () {
      expect(PaceTableCalculator.timeBufferFromMinutes(1440), '0000');
      expect(PaceTableCalculator.timeBufferFromMinutes(1500), '0100');
      expect(PaceTableCalculator.timeBufferFromMinutes(-30), '2330');
    });

    test('formats elapsed minutes', () {
      expect(PaceTableCalculator.formatElapsedMinutes(90), '01:30');
      expect(PaceTableCalculator.formatElapsedMinutes(null), '—');
    });

    test('keeps the precision the user typed for distance', () {
      expect(PaceTableCalculator.formatDistance('20'), '20');
      expect(PaceTableCalculator.formatDistance('20.3'), '20.3');
      expect(PaceTableCalculator.formatDistance('20,35'), '20.35');
      expect(PaceTableCalculator.formatDistance('abc'), '');
    });
  });

  group('day boundaries', () {
    test('increments the day when time jumps backwards', () {
      expect(
        PaceTableCalculator.computeDays(['2300', '0100', '0200', '2300']),
        [0, 1, 1, 1],
      );
    });

    test('computes elapsed time across midnight', () {
      expect(PaceTableCalculator.elapsedByColumn(['2300', '0100', '0200']), [
        0,
        120,
        180,
      ]);
      expect(PaceTableCalculator.elapsedMinutes(['2300', '0100', '0200']), 180);
    });
  });

  group('plan status', () {
    const limit = ['0500', '0700', '0800'];

    test('marks a plan red when a stop pushes it over the limit', () {
      // Прибытие 0650 (в лимит), стоянка 20 мин → 0710 > 0700.
      final statuses = PaceTableCalculator.planStatuses(
        planTimes: ['0500', '0650', '0800'],
        limitTimes: limit,
        columns: 3,
        stopsMin: [0, 20, 0],
      );
      expect(statuses[1], PlanTimeStatus.behindLimit);
    });

    test('ignores stops when they fit inside the limit', () {
      final statuses = PaceTableCalculator.planStatuses(
        planTimes: ['0500', '0650', '0800'],
        limitTimes: limit,
        columns: 3,
        stopsMin: [0, 5, 0],
      );
      expect(statuses[1], PlanTimeStatus.closeToLimit);
    });

    test('marks a plan behind the limit', () {
      final statuses = PaceTableCalculator.planStatuses(
        planTimes: ['0500', '0730', '0800'],
        limitTimes: limit,
      );

      expect(statuses[0], PlanTimeStatus.normal);
      expect(statuses[1], PlanTimeStatus.behindLimit);
      expect(statuses[2], PlanTimeStatus.normal);
    });

    test('marks a plan close to the limit as a warning', () {
      final statuses = PaceTableCalculator.planStatuses(
        planTimes: ['0500', '0650'],
        limitTimes: limit,
      );

      expect(statuses[1], PlanTimeStatus.closeToLimit);
    });

    test('does not warn when the plan is 20 minutes or more ahead', () {
      final statuses = PaceTableCalculator.planStatuses(
        planTimes: ['0500', '0640'],
        limitTimes: limit,
      );

      expect(statuses[1], PlanTimeStatus.normal);
    });

    test('ignores columns with missing data', () {
      final statuses = PaceTableCalculator.planStatuses(
        planTimes: ['0500'],
        limitTimes: limit,
      );

      expect(statuses, everyElement(PlanTimeStatus.normal));
    });
  });

  group('paces', () {
    test('computes a segment pace', () {
      expect(
        PaceTableCalculator.segmentPace(
          times: ['0500', '0700'],
          distances: ['0', '10'],
          index: 1,
        ),
        720,
      );
    });

    test('returns null for a non-positive distance delta', () {
      expect(
        PaceTableCalculator.segmentPace(
          times: ['0500', '0700'],
          distances: ['10', '10'],
          index: 1,
        ),
        isNull,
      );
    });

    test('computes planned and overall pace', () {
      expect(
        PaceTableCalculator.plannedPace(
          planTimes: ['0500', '0530'],
          distances: ['0', '5'],
          column: 1,
        ),
        360,
      );
      expect(
        PaceTableCalculator.overallPace(
          times: ['0500', '0700'],
          distances: ['0', '10'],
        ),
        720,
      );
    });

    test('highlights the fastest and second fastest pace', () {
      const paces = <int?>[600, 700, 700, null];

      expect(
        PaceTableCalculator.paceHighlight(column: 0, paces: paces),
        PaceHighlight.fastest,
      );
      expect(
        PaceTableCalculator.paceHighlight(column: 1, paces: paces),
        PaceHighlight.secondFastest,
      );
      expect(
        PaceTableCalculator.paceHighlight(column: 3, paces: paces),
        PaceHighlight.none,
      );
    });
  });
}
