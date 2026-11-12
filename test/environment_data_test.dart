import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/pace/environment_data.dart';

void main() {
  group('EnvironmentSettings', () {
    test('defaults: everything off, no start, no shoes', () {
      const settings = EnvironmentSettings.empty;

      expect(settings.surfaceEnabled, isFalse);
      expect(settings.weatherEnabled, isFalse);
      expect(settings.shoesEnabled, isFalse);
      expect(settings.groomedSnow, isFalse);
      expect(settings.startUtc, isNull);
      expect(settings.shoe, isNull);
      expect(settings.anyEnabled, isFalse);
    });

    test('survives a JSON round trip', () {
      final settings = EnvironmentSettings(
        surfaceEnabled: true,
        weatherEnabled: true,
        shoesEnabled: true,
        groomedSnow: true,
        startUtc: DateTime.utc(2026, 7, 24, 19, 3, 33),
        shoe: ShoeKind.road,
      );

      final restored = EnvironmentSettings.tryFromJson(settings.toJson());

      expect(restored.surfaceEnabled, isTrue);
      expect(restored.weatherEnabled, isTrue);
      expect(restored.shoesEnabled, isTrue);
      expect(restored.groomedSnow, isTrue);
      expect(restored.startUtc, DateTime.utc(2026, 7, 24, 19, 3, 33));
      expect(restored.shoe, ShoeKind.road);
    });

    test('unknown or broken JSON reads as everything off', () {
      expect(EnvironmentSettings.tryFromJson(null).anyEnabled, isFalse);
      expect(EnvironmentSettings.tryFromJson('x').anyEnabled, isFalse);
      expect(
        EnvironmentSettings.tryFromJson({'surfaceEnabled': 'yes'}).anyEnabled,
        isFalse,
      );
      expect(EnvironmentSettings.tryFromJson({'shoe': 'unknown'}).shoe, isNull);
      expect(
        EnvironmentSettings.tryFromJson({'startUtcMs': 'now'}).startUtc,
        isNull,
      );
    });

    test('copyWith changes flags and can clear start and shoes', () {
      final settings = EnvironmentSettings(
        surfaceEnabled: true,
        startUtc: DateTime.utc(2026, 7, 24),
        shoe: ShoeKind.trail,
      );

      final changed = settings.copyWith(
        weatherEnabled: true,
        groomedSnow: true,
        shoe: ShoeKind.minimal,
      );
      expect(changed.surfaceEnabled, isTrue);
      expect(changed.weatherEnabled, isTrue);
      expect(changed.groomedSnow, isTrue);
      expect(changed.shoe, ShoeKind.minimal);
      expect(changed.startUtc, DateTime.utc(2026, 7, 24));

      final cleared = changed.copyWith(clearStart: true, clearShoe: true);
      expect(cleared.startUtc, isNull);
      expect(cleared.shoe, isNull);
      expect(cleared.weatherEnabled, isTrue);
    });
  });

  group('EnvironmentData DNF', () {
    EnvironmentData dataWithOneRun() => const EnvironmentData(
      settings: EnvironmentSettings(surfaceEnabled: true),
      surface: [
        SurfaceRun(
          startM: 0,
          endM: 1000,
          type: SurfaceType.dirt,
          wetness: Wetness.dry,
          confidence: 1,
          factor: 1.5,
        ),
      ],
    );

    test('inside the covered track returns the run factor', () {
      final data = dataWithOneRun();

      expect(data.factorAt(0), 1.5);
      expect(data.factorAt(500), 1.5);
      expect(data.factorAt(1000), 1.5);
    });

    test('beyond the covered track is 1.00, no extrapolation', () {
      final data = dataWithOneRun();

      expect(data.factorAt(1500), 1.0);
      expect(data.factorBetween(1000, 2000), 1.0);
      expect(data.factorBetween(0, 2000), 1.5);
    });
  });
}
