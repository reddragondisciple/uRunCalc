/// Чистые расчёты множителей окружения (docs/environment-conditions.md §5–8).
///
/// Здесь нет сети и Flutter: на вход приходят уже собранные погодные сэмплы и
/// участки покрытия. Благодаря этому формулы покрываются unit-тестами, а
/// провайдеры можно менять, не трогая расчёт.
library;

import 'dart:math' as math;

import 'environment_data.dart';
import 'factor_profile.dart';

double clampDouble(double value, double min, double max) {
  if (value.isNaN) return min;
  return value.clamp(min, max).toDouble();
}

/// Эффективная влажность почвы, §5.4.
///
/// [rain12] и [et012] — суммы за 12 ч до старта, [net72] — баланс
/// `rain − 0.6 × ET0` за 72 ч, [meltwater72] — талая вода за 72 ч.
double soilMoistureEffective({
  required double smTop,
  required double smDeep,
  required double rain12,
  required double et012,
  required double net72,
  required double meltwater72,
  required FactorProfile profile,
}) {
  final base = profile.weightTop * smTop + profile.weightDeep * smDeep;
  final rainCorr =
      profile.rain12Coeff * clampDouble((rain12 - 0.6 * et012) / 5, -1, 1);
  final trendCorr = profile.trend72Coeff * clampDouble(net72 / 20, -1, 1);
  final meltTerm = profile.meltCoeff * clampDouble(meltwater72 / 10, 0, 1);
  return clampDouble(base + rainCorr + trendCorr + meltTerm, 0, 0.55);
}

/// Состояние мокрости по `smEff`, §5.4.
Wetness wetnessFromSoil(double smEff, FactorProfile profile) {
  if (smEff < profile.dryBelow) return Wetness.dry;
  if (smEff < profile.dampBelow) return Wetness.damp;
  if (smEff < profile.wetBelow) return Wetness.wet;
  return Wetness.saturated;
}

/// Неизвестное покрытие считаем грунтом (§6.1).
SurfaceType effectiveSurfaceType(SurfaceType type) =>
    type == SurfaceType.unknown ? SurfaceType.dirt : type;

/// Мокрость с учётом правила «насыщенный грунт → грязь» (§6.4).
///
/// Зимой при отрицательной температуре правило не применяется: грунт мёрзлый,
/// работают снеговые правила.
Wetness effectiveWetness({
  required Wetness wetness,
  required SurfaceType surface,
  required double tempC,
}) {
  if (tempC < 0) return wetness;
  if (wetness != Wetness.saturated) return wetness;
  return switch (effectiveSurfaceType(surface)) {
    SurfaceType.dirt ||
    SurfaceType.ground ||
    SurfaceType.grass ||
    SurfaceType.compacted => Wetness.saturated,
    _ => wetness,
  };
}

/// Тип покрытия после правила грязи: насыщенный грунт становится `mud`.
SurfaceType surfaceAfterMud({
  required SurfaceType surface,
  required Wetness wetness,
  required double tempC,
}) {
  final type = effectiveSurfaceType(surface);
  if (tempC < 0 || wetness != Wetness.saturated) return type;
  return switch (type) {
    SurfaceType.dirt ||
    SurfaceType.ground ||
    SurfaceType.grass ||
    SurfaceType.compacted => SurfaceType.mud,
    _ => type,
  };
}

/// Множитель покрытия с мокростью, §8.1.
///
/// Для болота мокрость заменяется на [bogFactor], иначе `wetness[bog]` и
/// `bogFactor` удвоили бы эффект.
double surfaceFactor({
  required SurfaceType surface,
  required Wetness wetness,
  required FactorProfile profile,
  bool isBog = false,
  double bogFactor = 1.0,
}) {
  final type = effectiveSurfaceType(surface);
  final typePart = profile.surface[type] ?? profile.surface[SurfaceType.dirt]!;
  final wetPart = isBog ? bogFactor : (profile.wetness[wetness] ?? 1.0);
  return clampDouble(typePart * wetPart, profile.clampMin, profile.clampMax);
}

/// Строка матрицы кроссовок для участка (§7).
ShoeSurfaceClass shoeSurfaceClass({
  required SurfaceType surface,
  required Wetness wetness,
  bool isFord = false,
}) {
  if (isFord) return ShoeSurfaceClass.ford;
  final type = effectiveSurfaceType(surface);
  if (type == SurfaceType.mud) return ShoeSurfaceClass.saturated;
  switch (type) {
    case SurfaceType.asphalt:
    case SurfaceType.concrete:
    case SurfaceType.pavingStones:
      return wetness == Wetness.dry || wetness == Wetness.damp
          ? ShoeSurfaceClass.dryAsphalt
          : ShoeSurfaceClass.wetAsphalt;
    case SurfaceType.grass:
      return ShoeSurfaceClass.grass;
    case SurfaceType.sand:
      return ShoeSurfaceClass.sand;
    case SurfaceType.snowPacked:
      return ShoeSurfaceClass.snowPacked;
    case SurfaceType.snowDeep:
      return ShoeSurfaceClass.snowDeep;
    case SurfaceType.dirt:
    case SurfaceType.ground:
    case SurfaceType.compacted:
    case SurfaceType.unknown:
      return switch (wetness) {
        Wetness.dry || Wetness.damp => ShoeSurfaceClass.dryDirt,
        Wetness.wet => ShoeSurfaceClass.wetDirt,
        Wetness.saturated || Wetness.bog => ShoeSurfaceClass.saturated,
      };
    case SurfaceType.mud:
      return ShoeSurfaceClass.saturated;
  }
}

/// Множитель обуви. Если обувь не выбрана — 1.00.
double shoeFactor({
  required ShoeKind? shoe,
  required SurfaceType surface,
  required Wetness wetness,
  required FactorProfile profile,
  bool isFord = false,
}) {
  if (shoe == null) return 1.0;
  final surfaceClass = shoeSurfaceClass(
    surface: surface,
    wetness: wetness,
    isFord: isFord,
  );
  return profile.shoes[shoe]?[surfaceClass] ?? 1.0;
}

/// Множитель жары по `apparent_temperature`, §5.2.
double heatFactor(double apparentC, FactorProfile profile) {
  return clampDouble(
    profile.heat.at(apparentC),
    profile.clampMin,
    profile.clampMax,
  );
}

/// Оценка высоты нуля изотермы, если провайдер её не вернул (§5.5).
double estimateFreezingLevelM({
  required double elevationM,
  required double tempC,
}) {
  return elevationM + math.max(0, tempC) / 0.0065;
}

/// Множитель снега, §5.5 и §8.3.
///
/// [urbanity] — 0..1, [roadClass] — класс дороги, [groomed] — укатанность.
/// [snowDepthM] — сырая глубина из прогноза/архива.
double snowFactor({
  required double snowDepthM,
  required double tempC,
  required double freshSnowCm,
  required double urbanity,
  required RoadClass roadClass,
  required bool groomed,
  required Wetness wetness,
  required FactorProfile profile,
}) {
  if (snowDepthM <= 0 || !snowDepthM.isFinite) return 1.0;

  final clearance = clampDouble(
    1 - urbanity * 0.75,
    profile.settlement.minClearance,
    1.0,
  );
  final road = profile.roadClearance[roadClass] ?? 1.0;
  var effective = snowDepthM * clearance * road;
  if (groomed) {
    effective = math.min(
      effective * profile.groomed.depthScale,
      profile.groomed.maxDepthScale * snowDepthM,
    );
  }

  final snow = profile.snow;
  if (effective < snow.thresholdM) return 1.0;

  // Плюсовая температура: снег тает и превращается в мокрую грунтовку или
  // слякоть. Формула холодного снега здесь даёт неверный знак.
  if (tempC > 0) {
    if (effective < snow.dirtBelowM) {
      final t = clampDouble(
        (effective - snow.thresholdM) /
            math.max(0.0001, snow.dirtBelowM - snow.thresholdM),
        0,
        1,
      );
      final isMud = wetness == Wetness.saturated;
      final min = isMud ? snow.mudFactorMin : snow.dirtFactorMin;
      final max = isMud ? snow.mudFactorMax : snow.dirtFactorMax;
      return clampDouble(min + (max - min) * t, 1.0, profile.clampMax);
    }
    final t = clampDouble((effective - snow.slushAboveM) / 0.30, 0, 1);
    return clampDouble(
      snow.slushFactorMin + (snow.slushFactorMax - snow.slushFactorMin) * t,
      1.0,
      profile.clampMax,
    );
  }

  final tempCoeff = snow.tempCoeff.at(tempC);
  final depthPart =
      snow.depthCoeff * math.min(effective, snow.maxDepthM) * tempCoeff;
  final freshPart = math.min(
    snow.freshAddMax,
    freshSnowCm * snow.freshAddPerCm,
  );
  var factor = 1 + depthPart + freshPart;
  factor = math.min(factor, snow.deepCap);
  if (groomed) factor = math.min(factor, profile.groomed.factorCap);
  return clampDouble(factor, 1.0, profile.clampMax);
}

/// Множитель болота с зимней логикой, §6.5.
///
/// Под снегом ≥ [snowCoverM] болото не мёрзнет: фактор не снижается. Без снега
/// и после недели ≤ −10 °C замерзает только верхняя корка, и фактор всё равно
/// не ниже [frozenTop].
double bogFactor({
  required String kind,
  required double snowDepthM,
  required double avgTemp5C,
  required int frozenDays,
  required FactorProfile profile,
  bool groomed = false,
}) {
  final base = profile.bog[kind] ?? 1.0;
  if (base <= 1.0) return 1.0;

  final snowCover = profile.bog['snowCoverM'] ?? 0.05;
  if (snowDepthM >= snowCover) {
    // Укатка снега не укатывает болото под ним.
    return base;
  }

  final frozenTemp = profile.bog['frozenTopTempC'] ?? -10;
  final minDays = (profile.bog['frozenTopMinDays'] ?? 7).round();
  if (avgTemp5C <= frozenTemp && frozenDays >= minDays) {
    final frozenTop = profile.bog['frozenTop'] ?? 1.20;
    return math.min(base, frozenTop);
  }
  return base;
}

/// Итоговый множитель участка: покрытие × обувь × погода.
double segmentFactor({
  required SurfaceType surface,
  required Wetness wetness,
  required bool isBog,
  required double bogFactorValue,
  required ShoeKind? shoe,
  required bool isFord,
  required double heatFactorValue,
  required double snowFactorValue,
  required FactorProfile profile,
}) {
  final surfacePart = surfaceFactor(
    surface: surface,
    wetness: wetness,
    profile: profile,
    isBog: isBog,
    bogFactor: bogFactorValue,
  );
  final shoePart = shoeFactor(
    shoe: shoe,
    surface: surface,
    wetness: wetness,
    profile: profile,
    isFord: isFord,
  );
  return clampDouble(
    surfacePart * shoePart * heatFactorValue * snowFactorValue,
    profile.clampMin,
    profile.clampMax,
  );
}
