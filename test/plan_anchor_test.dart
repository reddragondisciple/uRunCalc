import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/gpx/elevation_segments.dart';
import 'package:ultra_run_calc/features/gpx/gpx_parser.dart';
import 'package:ultra_run_calc/features/gpx/parsed_track.dart';
import 'package:ultra_run_calc/features/gpx/plan_math.dart';
import 'package:ultra_run_calc/features/gpx/track_metrics.dart';

double _sum(List<double> values) => values.fold<double>(0, (a, b) => a + b);

void main() {
  recomputeTests();
  segmentTests();
  inputDialogTests();
  // Три сегмента: 10 км с фактором 1.0, 10 км с 1.3, 10 км с 0.8.
  const segments = [
    PlanSegment(distanceKm: 10, gapFactor: 1.0),
    PlanSegment(distanceKm: 10, gapFactor: 1.3),
    PlanSegment(distanceKm: 10, gapFactor: 0.8),
  ];
  // Колонки: старт, ПП1, ПП2, финиш → 4 колонки, стоянки по индексу колонки.
  const noStops = [0.0, 0.0, 0.0, 0.0];

  group('movingForFlatPace (опора flat)', () {
    test('ходовое время = длина × p0 × GAP по каждому сегменту', () {
      final moving = movingForFlatPace(segments, 360);
      expect(moving, isNotNull);
      expect(moving![0], closeTo(3600, 1e-9));
      expect(moving[1], closeTo(4680, 1e-9));
      expect(moving[2], closeTo(2880, 1e-9));
    });

    test('без плоского темпа или с нулём — null', () {
      expect(movingForFlatPace(segments, null), isNull);
      expect(movingForFlatPace(segments, 0), isNull);
    });
  });

  group('movingForTargetTime (опора targetTime, T со стоянками)', () {
    test('сумма ходового времени равна T минус стоянки', () {
      final stops = [0.0, 600.0, 300.0, 0.0];
      final moving = movingForTargetTime(
        segments: segments,
        stopsSec: stops,
        totalSec: 12 * 3600,
      );
      expect(moving, isNotNull);
      expect(_sum(moving!), closeTo(12 * 3600 - 900, 1e-6));
    });

    test('без стоянок сумма равна T', () {
      final moving = movingForTargetTime(
        segments: segments,
        stopsSec: noStops,
        totalSec: 10000,
      );
      expect(_sum(moving!), closeTo(10000, 1e-6));
    });

    test('сохраняет относительный вклад GAP между сегментами', () {
      final moving = movingForTargetTime(
        segments: segments,
        stopsSec: noStops,
        totalSec: 10000,
      )!;
      // Исходные доли: 3600 : 4680 : 2880 — отношение 1.3 сохраняется.
      expect(moving[1] / moving[0], closeTo(1.3, 1e-9));
    });

    test('стоянки съели всё время — null', () {
      final moving = movingForTargetTime(
        segments: segments,
        stopsSec: [0, 5000, 5000, 0],
        totalSec: 9000,
      );
      expect(moving, isNull);
    });
  });

  group('movingForTargetPace (опора targetPace, ходовой темп)', () {
    test('movingTotal / D равно введённому темпу', () {
      final moving = movingForTargetPace(
        segments: segments,
        movingPaceSecPerKm: 400,
      )!;
      expect(_sum(moving) / 30, closeTo(400, 1e-9));
    });

    test('нулевой темп — null', () {
      expect(
        movingForTargetPace(segments: segments, movingPaceSecPerKm: 0),
        isNull,
      );
    });
  });

  group('flatPaceForTotalTime (плоские данные, введено время)', () {
    test('p0 = (T − стоянки) / D', () {
      final p0 = flatPaceForTotalTime(
        segments: segments,
        stopsSec: [0, 600, 0, 0],
        totalSec: 30 * 360 + 600,
      );
      expect(p0, closeTo(360, 1e-9));
    });

    test('время меньше стоянок — null', () {
      expect(
        flatPaceForTotalTime(
          segments: segments,
          stopsSec: [0, 5000, 0, 0],
          totalSec: 1000,
        ),
        isNull,
      );
    });
  });

  group('planForMoving + стоянки', () {
    test('стоянка сдвигает прибытия, но не ходовой темп сегмента', () {
      final moving = movingForFlatPace(segments, 360);
      final noStop = planForMoving(moving: moving, stopsSec: noStops)!;
      final withStop = planForMoving(moving: moving, stopsSec: [0, 600, 0, 0])!;

      // Прибытие на ПП2 и далее сдвигается на 600 с.
      expect(withStop.arrivalSec[1], closeTo(noStop.arrivalSec[1], 1e-9));
      expect(withStop.arrivalSec[2] - noStop.arrivalSec[2], closeTo(600, 1e-9));
      // Ходовой темп сегмента 1→2 не меняется.
      expect(
        segmentPaceSecPerKm(plan: withStop, segments: segments, column: 2),
        closeTo(
          segmentPaceSecPerKm(plan: noStop, segments: segments, column: 2)!,
          1e-9,
        ),
      );
      // Итог включает стоянку.
      expect(withStop.totalSec, closeTo(noStop.totalSec + 600, 1e-9));
    });

    test('сегмент с учётом стоянок включает стоянку на предыдущем ПП', () {
      final moving = movingForFlatPace(segments, 360);
      final plan = planForMoving(moving: moving, stopsSec: [0, 600, 0, 0])!;
      final clean = segmentPaceSecPerKm(
        plan: plan,
        segments: segments,
        column: 2,
      )!;
      final withStops = segmentPaceSecPerKm(
        plan: plan,
        segments: segments,
        column: 2,
        withStops: true,
      )!;
      expect(withStops - clean, closeTo(600 / 10, 1e-9));
    });

    test('итог = ходовое + стоянки; финишная стоянка не учитывается', () {
      final moving = movingForFlatPace(segments, 360);
      final plan = planForMoving(moving: moving, stopsSec: [0, 0, 0, 900])!;
      expect(plan.totalSec, closeTo(plan.movingTotalSec, 1e-9));
    });
  });

  group('sumIntermediateStops', () {
    test('старт и финиш исключаются', () {
      expect(sumIntermediateStops([100, 200, 300, 400], 4), 500);
    });
  });
}

void segmentTests() {
  group('planSegmentsForColumns', () {
    test('без трека: все факторы 1, длины из колонок', () {
      final segs = planSegmentsForColumns(
        parsed: null,
        columnDistancesKm: const [0, 10, 25],
      );
      expect(segs.map((s) => s.distanceKm), [10, 15]);
      expect(segs.every((s) => s.gapFactor == 1), isTrue);
    });

    test('реальный hill.gpx: подъём даёт фактор больше 1', () {
      final track = parseGpx(File('test/fixtures/hill.gpx').readAsStringSync());
      final metrics = computeTrackMetrics(track);
      final parsed = ParsedTrack(
        track: track,
        metrics: metrics,
        candidates: const [],
        totalAscentM: 0,
        totalDescentM: 0,
      );
      final total = parsed.metrics.totalDistance2d / 1000;
      final segs = planSegmentsForColumns(
        parsed: parsed,
        columnDistancesKm: [0, total / 2, total],
      );
      expect(segs, hasLength(2));
      expect(
        segs.first.distanceKm + segs.last.distanceKm,
        closeTo(total, 1e-6),
      );
      expect(segs.any((s) => s.gapFactor > 1), isTrue);
    });
  });
}

void recomputeTests() {
  group('recomputePlan (полный пересчёт, §7.5)', () {
    const segs = [
      PlanSegment(distanceKm: 10, gapFactor: 1.0),
      PlanSegment(distanceKm: 10, gapFactor: 1.3),
      PlanSegment(distanceKm: 10, gapFactor: 0.8),
    ];
    const stops = [0.0, 600.0, 0.0, 0.0];

    test('flat: прибытие на финиш = ходовое + стоянки', () {
      final plan = recomputePlan(
        anchor: PlanAnchorMode.flat,
        segments: segs,
        stopsSec: stops,
        flatPaceSec: 360,
      )!;
      // ходовое 3600 + 4680 + 2880 = 11160, плюс стоянка 600 на ПП1.
      expect(plan.arrivalSec.last, closeTo(11160 + 600, 1e-6));
      expect(plan.paceSec[2], closeTo(468, 1e-9));
    });

    test('targetTime: финиш равен T (со стоянками)', () {
      final plan = recomputePlan(
        anchor: PlanAnchorMode.targetTime,
        segments: segs,
        stopsSec: stops,
        targetTotalSec: 12000,
      )!;
      expect(plan.arrivalSec.last, closeTo(12000, 1e-6));
    });

    test('targetPace: ходовой средний темп равен p', () {
      final plan = recomputePlan(
        anchor: PlanAnchorMode.targetPace,
        segments: segs,
        stopsSec: stops,
        targetPaceSec: 400,
      )!;
      // Ходовое время = темп сегмента × длина; сумма = 400 × 30 км.
      var moving = 0.0;
      for (var i = 1; i < plan.paceSec.length; i++) {
        moving += plan.paceSec[i] * segs[i - 1].distanceKm;
      }
      expect(moving, closeTo(12000, 1e-6));
    });

    test('manual: опора не нормируется, берём текущие ходовые времена', () {
      final plan = recomputePlan(
        anchor: PlanAnchorMode.manual,
        segments: segs,
        stopsSec: const [0, 0, 0, 0],
        manualMovingSec: const [0, 3000, 3000, 3000],
      )!;
      expect(plan.arrivalSec.last, closeTo(9000, 1e-9));
    });

    test('manual без корректной длины — null', () {
      expect(
        recomputePlan(
          anchor: PlanAnchorMode.manual,
          segments: segs,
          stopsSec: stops,
          manualMovingSec: const [0, 1],
        ),
        isNull,
      );
    });

    test(
      'сдвиг границы: p_flat сохраняется, сегмент пересчитывается по новому GAP',
      () {
        // Сегмент 1 стал длиннее при том же плоском темпе p_flat.
        const before = PlanSegment(distanceKm: 10, gapFactor: 1.3);
        const after = PlanSegment(distanceKm: 12, gapFactor: 1.3);
        final pFlat = 360.0;
        final p1 = recomputePlan(
          anchor: PlanAnchorMode.flat,
          segments: const [before],
          stopsSec: const [0, 0],
          flatPaceSec: pFlat,
        )!;
        final p2 = recomputePlan(
          anchor: PlanAnchorMode.flat,
          segments: const [after],
          stopsSec: const [0, 0],
          flatPaceSec: pFlat,
        )!;
        expect(p1.paceSec[1], closeTo(p2.paceSec[1], 1e-9));
        expect(p2.arrivalSec.last, closeTo(p1.arrivalSec.last * 1.2, 1e-6));
      },
    );
  });
}

void inputDialogTests() {
  group('planFromInput (диалог «плоские / с поправкой», §7.3)', () {
    const segs = [
      PlanSegment(distanceKm: 10, gapFactor: 1.0),
      PlanSegment(distanceKm: 10, gapFactor: 1.3),
      PlanSegment(distanceKm: 10, gapFactor: 0.8),
    ];
    const stops = [0.0, 0.0, 0.0, 0.0];

    test('плоский темп: опора flat, ходовой темп = p0 × средний GAP', () {
      final r = planFromInput(
        mode: PlanInputMode.flatData,
        byTime: false,
        value: 360,
        segments: segs,
        stopsSec: stops,
        totalStopsSec: 0,
      )!;
      expect(r.anchor.mode, PlanAnchorMode.flat);
      expect(r.anchor.value, 360);
      // Средний GAP = (1.0 + 1.3 + 0.8) / 3 = 1.0333…
      expect(r.preview.movingPaceSec, closeTo(360 * 31 / 30, 1e-9));
      expect(r.preview.totalSec, closeTo(360 * 31, 1e-6));
    });

    test('плоское время: p0 = T / D, опора flat', () {
      final r = planFromInput(
        mode: PlanInputMode.flatData,
        byTime: true,
        value: 30 * 360,
        segments: segs,
        stopsSec: stops,
        totalStopsSec: 0,
      )!;
      expect(r.anchor.mode, PlanAnchorMode.flat);
      expect(r.anchor.value, closeTo(360, 1e-9));
    });

    test('плоское время со стоянками: стоянки вычитаются из T', () {
      final r = planFromInput(
        mode: PlanInputMode.flatData,
        byTime: true,
        value: 30 * 360 + 900,
        segments: segs,
        stopsSec: const [0, 900, 0, 0],
        totalStopsSec: 900,
      )!;
      // p0 = (T − стоянки) / D: введённое время — плоское. Итог с GAP и
      // стоянками больше T — это и есть поправка на высоты (§7.3).
      expect(r.anchor.value, closeTo(360, 1e-9));
      expect(r.preview.stopsSec, 900);
      expect(r.preview.totalSec, closeTo(360 * 31 + 900, 1e-6));
      expect(r.preview.totalSec!, greaterThan(30 * 360 + 900));
    });

    test('с поправкой по времени: опора targetTime, итог = T', () {
      final r = planFromInput(
        mode: PlanInputMode.withAdjustment,
        byTime: true,
        value: 12000,
        segments: segs,
        stopsSec: stops,
        totalStopsSec: 0,
      )!;
      expect(r.anchor.mode, PlanAnchorMode.targetTime);
      expect(r.anchor.value, 12000);
      expect(r.preview.totalSec, 12000);
      expect(r.preview.flatPaceSec, isNull);
    });

    test('с поправкой по темпу: опора targetPace, ходовой темп = p', () {
      final r = planFromInput(
        mode: PlanInputMode.withAdjustment,
        byTime: false,
        value: 400,
        segments: segs,
        stopsSec: stops,
        totalStopsSec: 0,
      )!;
      expect(r.anchor.mode, PlanAnchorMode.targetPace);
      expect(r.preview.movingPaceSec, 400);
      expect(r.preview.totalSec, closeTo(12000, 1e-6));
    });

    test('нулевой или пустой ввод — null', () {
      expect(
        planFromInput(
          mode: PlanInputMode.flatData,
          byTime: false,
          value: 0,
          segments: segs,
          stopsSec: stops,
          totalStopsSec: 0,
        ),
        isNull,
      );
      expect(
        planFromInput(
          mode: PlanInputMode.withAdjustment,
          byTime: true,
          value: 100,
          segments: const [],
          stopsSec: const [0],
          totalStopsSec: 0,
        ),
        isNull,
      );
    });
  });
}
