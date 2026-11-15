import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/pace/pace_calculations.dart';
import 'package:ultra_run_calc/features/pace/pace_gels.dart';

void main() {
  group('GelSettings', () {
    test('simple gel defaults to 25 g of carbs', () {
      const settings = GelSettings();
      final profile = settings.profileForToken(PaceGelTokens.simple);

      expect(profile, isNotNull);
      expect(profile!.nutrients.single.amount, 25);
      expect(profile.nutrients.single.unit, 'г');
    });

    test('totals only include positive nutrients', () {
      const settings = GelSettings(
        simpleCarbs: '25',
        isoCarbs: '30',
        isoSodium: '200',
        coffeeCarbs: '20',
        coffeeCaffeine: '80',
      );

      final totals = settings.totals([
        PaceGelTokens.simple,
        PaceGelTokens.iso,
        PaceGelTokens.coffee,
      ]);

      expect(totals.map((value) => value.id), ['carbs', 'caffeine', 'sodium']);
      expect(totals[0].amount, 75);
      expect(totals[1].amount, 80);
      expect(totals[2].amount, 200);
    });

    test('custom gel nutrients participate in totals', () {
      final settings = const GelSettings().withCustomGel(
        const CustomGel(
          name: 'Свой',
          nutrients: [
            CustomGelNutrient(
              id: 'carbs',
              label: 'Углеводы',
              unit: 'г',
              amount: '40',
            ),
            CustomGelNutrient(
              id: 'custom:соль|мг',
              label: 'Соль',
              unit: 'мг',
              amount: '150',
            ),
          ],
        ),
      );

      final totals = settings.totals(['${PaceGelTokens.customPrefix}Свой']);

      expect(totals.map((value) => value.label), ['Углеводы', 'Соль']);
      expect(totals[0].amount, 40);
      expect(totals[1].amount, 150);
    });

    test('survives a JSON round trip with custom gels', () {
      const settings = GelSettings(
        simpleCarbs: '30',
        isoCarbs: '20',
        isoSodium: '180',
        coffeeCarbs: '22',
        coffeeCaffeine: '90',
        customGels: [
          CustomGel(
            name: 'Мой',
            nutrients: [
              CustomGelNutrient(
                id: 'carbs',
                label: 'Углеводы',
                unit: 'г',
                amount: '35',
              ),
            ],
          ),
        ],
      );

      final restored = GelSettings.fromJson(settings.toJson());

      expect(restored.toJson(), settings.toJson());
    });
  });

  group('PaceGelPlanner', () {
    const points = [
      PaceSplitPoint(distanceKm: 1, seconds: 300),
      PaceSplitPoint(distanceKm: 2, seconds: 600),
      PaceSplitPoint(distanceKm: 3, seconds: 900),
      PaceSplitPoint(distanceKm: 4, seconds: 1200),
      PaceSplitPoint(distanceKm: 5, seconds: 1500),
      PaceSplitPoint(distanceKm: 6, seconds: 1800, isFinish: true),
    ];

    test('places gels every N kilometres on the nearest checkpoint', () {
      final rows = PaceGelPlanner.autoRows(
        points: points,
        everyMinutes: '',
        everyKm: '2',
        startSeconds: 0,
      );

      expect(rows, {1, 3});
    });

    test('places gels every N minutes on the nearest checkpoint', () {
      final rows = PaceGelPlanner.autoRows(
        points: points,
        everyMinutes: '10',
        everyKm: '',
        startSeconds: 0,
      );

      // 600 и 1200 секунд совпадают со второй и четвёртой точками.
      expect(rows, {1, 3});
    });

    test('does not put an automatic gel on the finish row', () {
      final rows = PaceGelPlanner.autoRows(
        points: points,
        everyMinutes: '',
        everyKm: '6',
        startSeconds: 0,
      );

      expect(rows, isEmpty);
    });
  });

  group('PaceGelState', () {
    test('survives a JSON round trip', () {
      const state = PaceGelState(
        everyMinutes: '30',
        everyKm: '',
        settings: GelSettings(simpleCarbs: '25'),
        rows: {
          1: PaceGelRow(
            left: ['pp', 'bio'],
            right: ['gel_iso', 'fruit'],
            leftOther: '',
            rightOther: 'свой текст',
          ),
        },
      );

      final restored = PaceGelState.fromJson(state.toJson());

      expect(restored.everyMinutes, '30');
      expect(restored.everyKm, '');
      expect(restored.settings.toJson(), state.settings.toJson());
      expect(restored.rows[1]!.left, ['pp', 'bio']);
      expect(restored.rows[1]!.right, ['gel_iso', 'fruit']);
      expect(restored.rows[1]!.rightOther, 'свой текст');
    });

    test('keeps the auto flag when the right field is absent', () {
      final state = PaceGelState.fromJson({
        'rows': [
          {
            'index': 2,
            'left': ['pp'],
            'leftOther': '',
          },
          {'index': 3, 'left': [], 'right': [], 'rightOther': ''},
        ],
      });

      expect(state.rows[2]!.right, isNull);
      expect(state.rows[3]!.right, isEmpty);
    });
  });
}
