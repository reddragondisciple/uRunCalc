import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/plan_math.dart';

void main() {
  group('movingFromFlatPace', () {
    test('плоский сегмент: длина × темп', () {
      final moving = movingFromFlatPace([
        const PlanSegment(distanceKm: 10, gapFactor: 1),
      ], 360);
      expect(moving.single, closeTo(3600, 1e-9));
    });

    test('подъём увеличивает ходовое время', () {
      final moving = movingFromFlatPace([
        const PlanSegment(distanceKm: 10, gapFactor: 1.3),
      ], 360);
      expect(moving.single, closeTo(4680, 1e-9));
    });
  });

  group('normalizeMoving (targetTime / targetPace)', () {
    test('сумма после λ равна цели', () {
      final moving = [1000.0, 2000.0, 3000.0];
      final scaled = normalizeMoving(moving, 5000);
      expect(scaled.fold<double>(0, (a, b) => a + b), closeTo(5000, 1e-9));
    });

    test('относительные доли сегментов сохраняются', () {
      final scaled = normalizeMoving([1000, 3000], 8000);
      expect(scaled[1] / scaled[0], closeTo(3, 1e-9));
    });
  });

  group('assemblePlan', () {
    test('стоянка сдвигает прибытия, но не ходовой темп', () {
      final plan = assemblePlan(
        movingSec: [0, 600, 600, 600],
        stopsSec: [0, 300, 0, 0],
      );
      expect(plan.movingSec, [0, 600, 600, 600]);
      expect(plan.arrivalSec, [0, 600, 1500, 2100]);
      expect(plan.totalSec, 2100);
    });

    test('стоянка на финише не учитывается', () {
      final plan = assemblePlan(
        movingSec: [0, 600, 600],
        stopsSec: [0, 0, 900],
      );
      expect(plan.totalSec, 1200);
    });
  });

  group('distributeStops', () {
    test('пустой ряд: сумма делится поровну, остаток на последний ПП', () {
      // 5 колонок → промежуточные 1..3, сумма 10 мин = 600 с.
      final stops = distributeStops(
        columns: 5,
        totalSec: 600,
        current: const [0, 0, 0, 0, 0],
      );
      expect(stops, [0, 200, 200, 200, 0]);
    });

    test('остаток от деления уходит на последний промежуточный ПП', () {
      final stops = distributeStops(
        columns: 4,
        totalSec: 100,
        current: const [0, 0, 0, 0],
      );
      // Промежуточные: 1, 2. 100/2 = 50 каждой.
      expect(stops.sublist(1, 3), [50, 50]);
    });

    test('заполненный ряд масштабируется пропорционально', () {
      final stops = distributeStops(
        columns: 4,
        totalSec: 600,
        current: const [0, 100, 300, 0],
      );
      expect(stops[1], 150);
      expect(stops[2], 450);
    });
  });

  group('shiftFollowing (дельта к последующим прибытиям)', () {
    test('правка колонки сдвигает только следующие до lastPaced', () {
      final shifted = shiftFollowing(
        arrivalSec: [0, 600, 1200, 1800, 2400],
        column: 1,
        deltaSec: 120,
        lastPacedColumn: 3,
      );
      expect(shifted, [0, 600, 1320, 1920, 2400]);
    });
  });

  group('isOverLimit', () {
    test('красный, если прибытие + стоянка больше лимита', () {
      expect(
        isOverLimit(arrivalSec: 3000, stopSec: 600, limitSec: 3500),
        isTrue,
      );
      expect(
        isOverLimit(arrivalSec: 3000, stopSec: 400, limitSec: 3500),
        isFalse,
      );
    });
  });

  group('isPlanRed', () {
    test('красный, если прибытие уже позже лимита', () {
      expect(
        isPlanRed(arrivalSec: 3600, stopSec: 0, limitSec: 3500),
        isTrue,
      );
    });

    test('красный, если стоянка выводит за лимит', () {
      expect(
        isPlanRed(arrivalSec: 3000, stopSec: 600, limitSec: 3500),
        isTrue,
      );
    });

    test('не красный, если прибытие + стоянка укладываются в лимит', () {
      expect(
        isPlanRed(arrivalSec: 3000, stopSec: 400, limitSec: 3500),
        isFalse,
      );
    });
  });

  group('stopsAwareSegmentPace', () {
    test('считает разность прибытий на длину сегмента', () {
      // 10 км за 3000 с ходом + 600 с стоянки → 3600 с на 10 км = 360 с/км.
      final pace = stopsAwareSegmentPace(
        arrivalSec: [0, 3600],
        distancesKm: [10],
        column: 1,
      );
      expect(pace, closeTo(360, 1e-9));
    });

    test('null без данных прибытия или нулевой длины', () {
      expect(
        stopsAwareSegmentPace(arrivalSec: [0, null], distancesKm: [10], column: 1),
        isNull,
      );
      expect(
        stopsAwareSegmentPace(arrivalSec: [0, 100], distancesKm: [0], column: 1),
        isNull,
      );
      expect(
        stopsAwareSegmentPace(arrivalSec: [0, 100], distancesKm: [10], column: 0),
        isNull,
      );
    });
  });
}
