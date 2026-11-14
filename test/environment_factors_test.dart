import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/pace/environment_data.dart';
import 'package:ultra_run_calc/features/pace/environment_factors.dart';
import 'package:ultra_run_calc/features/pace/factor_profile.dart';

void main() {
  final profile = FactorProfile.defaults();

  group('soil moisture', () {
    test('26.07.2026 Suzdal case is saturated', () {
      final smEff = soilMoistureEffective(
        smTop: 0.430,
        smDeep: 0.384,
        rain12: 2.5,
        et012: 0.4,
        net72: 13,
        meltwater72: 0,
        profile: profile,
      );

      expect(smEff, closeTo(0.45, 0.02));
      expect(wetnessFromSoil(smEff, profile), Wetness.saturated);
    });

    test('24.07.2026 Suzdal case stays wet without mud', () {
      final smEff = soilMoistureEffective(
        smTop: 0.354,
        smDeep: 0.328,
        rain12: 2.2,
        et012: 0.1,
        net72: 10,
        meltwater72: 0,
        profile: profile,
      );

      expect(smEff, closeTo(0.37, 0.02));
      expect(wetnessFromSoil(smEff, profile), Wetness.wet);
    });

    test('thresholds map to dry, damp, wet, saturated', () {
      expect(wetnessFromSoil(0.10, profile), Wetness.dry);
      expect(wetnessFromSoil(0.28, profile), Wetness.damp);
      expect(wetnessFromSoil(0.35, profile), Wetness.wet);
      expect(wetnessFromSoil(0.45, profile), Wetness.saturated);
    });

    test('result is clamped to 0..0.55', () {
      expect(
        soilMoistureEffective(
          smTop: 0.9,
          smDeep: 0.9,
          rain12: 100,
          et012: 0,
          net72: 100,
          meltwater72: 100,
          profile: profile,
        ),
        0.55,
      );
    });
  });

  group('heat', () {
    test('below 10 °C is neutral', () {
      expect(heatFactor(5, profile), 1.00);
      expect(heatFactor(10, profile), 1.00);
    });

    test('interpolates between profile points', () {
      expect(heatFactor(20, profile), closeTo(1.02, 0.001));
      expect(heatFactor(28, profile), closeTo(1.08, 0.001));
      expect(heatFactor(35, profile), closeTo(1.20, 0.001));
      expect(heatFactor(45, profile), closeTo(1.35, 0.001));
      expect(heatFactor(60, profile), closeTo(1.35, 0.001));
    });
  });

  group('surface and shoes', () {
    test('unknown surface is dirt', () {
      expect(effectiveSurfaceType(SurfaceType.unknown), SurfaceType.dirt);
      expect(
        surfaceFactor(
          surface: SurfaceType.unknown,
          wetness: Wetness.dry,
          profile: profile,
        ),
        closeTo(1.10, 0.001),
      );
    });

    test('saturated dirt becomes mud', () {
      expect(
        surfaceAfterMud(
          surface: SurfaceType.dirt,
          wetness: Wetness.saturated,
          tempC: 15,
        ),
        SurfaceType.mud,
      );
      // Зимой правило грязи не применяется.
      expect(
        surfaceAfterMud(
          surface: SurfaceType.dirt,
          wetness: Wetness.saturated,
          tempC: -5,
        ),
        SurfaceType.dirt,
      );
    });

    test('road shoes on saturated ground are 1.35', () {
      expect(
        shoeFactor(
          shoe: ShoeKind.road,
          surface: SurfaceType.dirt,
          wetness: Wetness.saturated,
          profile: profile,
        ),
        closeTo(1.35, 0.001),
      );
      expect(
        shoeFactor(
          shoe: ShoeKind.trail,
          surface: SurfaceType.dirt,
          wetness: Wetness.dry,
          profile: profile,
        ),
        closeTo(1.00, 0.001),
      );
      expect(
        shoeFactor(
          shoe: null,
          surface: SurfaceType.dirt,
          wetness: Wetness.saturated,
          profile: profile,
        ),
        closeTo(1.10, 0.001),
      );
    });
  });

  group('snow', () {
    test('below 2 cm is neutral', () {
      expect(
        snowFactor(
          snowDepthM: 0.01,
          tempC: -10,
          freshSnowCm: 0,
          urbanity: 0,
          roadClass: RoadClass.unpaved,
          groomed: false,
          wetness: Wetness.dry,
          profile: profile,
        ),
        1.00,
      );
    });

    test('cold loose snow slows down and is capped', () {
      final factor = snowFactor(
        snowDepthM: 0.30,
        tempC: -10,
        freshSnowCm: 0,
        urbanity: 0,
        roadClass: RoadClass.unpaved,
        groomed: false,
        wetness: Wetness.dry,
        profile: profile,
      );
      // 1 + 0.21 × 0.30 × 2.20 ≈ 1.139
      expect(factor, closeTo(1.14, 0.02));
    });

    test('fresh snow adds up to 0.25', () {
      final withFresh = snowFactor(
        snowDepthM: 0.30,
        tempC: -10,
        freshSnowCm: 100,
        urbanity: 0,
        roadClass: RoadClass.unpaved,
        groomed: false,
        wetness: Wetness.dry,
        profile: profile,
      );
      expect(withFresh, closeTo(1.39, 0.03));
    });

    test('positive temperature turns shallow snow into wet dirt', () {
      final factor = snowFactor(
        snowDepthM: 0.05,
        tempC: 2,
        freshSnowCm: 0,
        urbanity: 0,
        roadClass: RoadClass.unpaved,
        groomed: false,
        wetness: Wetness.dry,
        profile: profile,
      );
      expect(factor, inInclusiveRange(1.10, 1.15));
    });

    test('groomed snow is capped at 1.25', () {
      final factor = snowFactor(
        snowDepthM: 1.00,
        tempC: -15,
        freshSnowCm: 10,
        urbanity: 0,
        roadClass: RoadClass.unpaved,
        groomed: true,
        wetness: Wetness.dry,
        profile: profile,
      );
      expect(factor, lessThanOrEqualTo(1.25));
    });

    test('city clearance reduces effective depth', () {
      final rural = snowFactor(
        snowDepthM: 0.20,
        tempC: -10,
        freshSnowCm: 0,
        urbanity: 0,
        roadClass: RoadClass.unpaved,
        groomed: false,
        wetness: Wetness.dry,
        profile: profile,
      );
      final urban = snowFactor(
        snowDepthM: 0.20,
        tempC: -10,
        freshSnowCm: 0,
        urbanity: 1,
        roadClass: RoadClass.pavedMajor,
        groomed: false,
        wetness: Wetness.dry,
        profile: profile,
      );
      expect(urban, lessThan(rural));
    });
  });

  group('bog', () {
    test('snow keeps the bog unfrozen', () {
      expect(
        bogFactor(
          kind: 'bog',
          snowDepthM: 0.10,
          avgTemp5C: -15,
          frozenDays: 30,
          profile: profile,
        ),
        closeTo(1.35, 0.001),
      );
    });

    test('no snow and a week at -10 °C freezes only the top', () {
      expect(
        bogFactor(
          kind: 'bog',
          snowDepthM: 0,
          avgTemp5C: -12,
          frozenDays: 8,
          profile: profile,
        ),
        closeTo(1.20, 0.001),
      );
      // Слабый мокрый луг не становится хуже от корки.
      expect(
        bogFactor(
          kind: 'wetMeadow',
          snowDepthM: 0,
          avgTemp5C: -12,
          frozenDays: 8,
          profile: profile,
        ),
        closeTo(1.15, 0.001),
      );
    });

    test('grooming does not reduce a bog under snow', () {
      expect(
        bogFactor(
          kind: 'bog',
          snowDepthM: 0.20,
          avgTemp5C: -15,
          frozenDays: 30,
          profile: profile,
          groomed: true,
        ),
        closeTo(1.35, 0.001),
      );
    });
  });

  group('FactorProfile', () {
    test('JSON round trip preserves coefficients', () {
      final restored = FactorProfile.tryFromJson(profile.toJson());

      expect(restored.version, profile.version);
      expect(restored.surface[SurfaceType.dirt], 1.10);
      expect(restored.surface[SurfaceType.pavingStones], 1.03);
      expect(restored.wetness[Wetness.saturated], 1.20);
      expect(restored.shoes[ShoeKind.road]![ShoeSurfaceClass.saturated], 1.35);
      expect(restored.heat.at(35), closeTo(1.20, 0.001));
      expect(restored.bog['frozenTop'], 1.20);
      expect(restored.snow.depthCoeff, 0.21);
    });

    test('broken JSON falls back to defaults', () {
      final restored = FactorProfile.tryFromJson('broken');

      expect(restored.surface[SurfaceType.asphalt], 1.00);
      expect(restored.wetBelow, 0.40);
    });

    test('missing fields keep defaults', () {
      final restored = FactorProfile.tryFromJson({'version': 2});

      expect(restored.version, 2);
      expect(restored.dryBelow, 0.25);
      expect(restored.snow.maxDepthM, 1.00);
    });

    test('reads the old minimal shoe key as spikes', () {
      final json = profile.toJson();
      final shoes = Map<String, dynamic>.from(json['shoes'] as Map);
      shoes['minimal'] = shoes.remove('spikes');
      json['shoes'] = shoes;

      final restored = FactorProfile.tryFromJson(json);

      expect(
        restored.shoes[ShoeKind.spikes]![ShoeSurfaceClass.saturated],
        1.20,
      );
    });
  });
}
