/// Единый профиль коэффициентов окружения (docs/environment-conditions.md §8.3).
///
/// Профиль один на приложение, версионируется и хранится в
/// `SharedPreferences`. Его же будет использовать калибровка: поэтому все
/// коэффициенты собраны здесь, а не размазаны по расчётному коду.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'environment_data.dart';

/// Строка матрицы кроссовок: сочетание покрытия и мокрости.
enum ShoeSurfaceClass {
  dryAsphalt,
  wetAsphalt,
  dryDirt,
  wetDirt,
  saturated,
  grass,
  sand,
  snowPacked,
  snowDeep,
  ford,
}

/// Кусочно-линейная функция по точкам `(x, y)`.
class ProfileCurve {
  const ProfileCurve(this.points);

  final List<({double x, double y})> points;

  /// Значение в [x]; за пределами диапазона — крайние значения.
  double at(double x) {
    if (points.isEmpty) return 1;
    if (x <= points.first.x) return points.first.y;
    if (x >= points.last.x) return points.last.y;
    for (var i = 1; i < points.length; i++) {
      final right = points[i];
      if (x <= right.x) {
        final left = points[i - 1];
        final span = right.x - left.x;
        if (span <= 0) return right.y;
        final t = (x - left.x) / span;
        return left.y + (right.y - left.y) * t;
      }
    }
    return points.last.y;
  }

  List<List<double>> toJson() => [
    for (final point in points) [point.x, point.y],
  ];

  static ProfileCurve? tryFromJson(dynamic raw) {
    if (raw is! List) return null;
    final points = <({double x, double y})>[];
    for (final item in raw) {
      if (item is! List || item.length < 2) continue;
      final x = FactorProfile._double(item[0]);
      final y = FactorProfile._double(item[1]);
      if (x == null || y == null) continue;
      points.add((x: x, y: y));
    }
    if (points.length < 2) return null;
    points.sort((a, b) => a.x.compareTo(b.x));
    return ProfileCurve(points);
  }
}

/// Снеговые коэффициенты.
class SnowProfile {
  const SnowProfile({
    required this.thresholdM,
    required this.depthCoeff,
    required this.maxDepthM,
    required this.deepCap,
    required this.tempCoeff,
    required this.freshAddPerCm,
    required this.freshAddMax,
    required this.slushAdd,
    required this.dirtBelowM,
    required this.slushAboveM,
    required this.dirtFactorMin,
    required this.dirtFactorMax,
    required this.mudFactorMin,
    required this.mudFactorMax,
    required this.slushFactorMin,
    required this.slushFactorMax,
  });

  final double thresholdM;
  final double depthCoeff;
  final double maxDepthM;
  final double deepCap;
  final ProfileCurve tempCoeff;
  final double freshAddPerCm;
  final double freshAddMax;
  final double slushAdd;

  /// При плюсовой температуре: до этой глубины — обычная грунтовка.
  final double dirtBelowM;
  final double slushAboveM;
  final double dirtFactorMin;
  final double dirtFactorMax;
  final double mudFactorMin;
  final double mudFactorMax;
  final double slushFactorMin;
  final double slushFactorMax;
}

/// Расчистка снега в населённых пунктах.
class SettlementProfile {
  const SettlementProfile({required this.urbanity, required this.minClearance});

  final Map<SettlementContext, double> urbanity;
  final double minClearance;
}

/// Состояния снега.
class SnowStateProfile {
  const SnowStateProfile({
    required this.asphaltBelowM,
    required this.packedBelowM,
    required this.packedFactorMin,
    required this.packedFactorMax,
    required this.iceFactorMin,
    required this.iceFactorMax,
    required this.slushFactorMin,
    required this.slushFactorMax,
  });

  final double asphaltBelowM;
  final double packedBelowM;
  final double packedFactorMin;
  final double packedFactorMax;
  final double iceFactorMin;
  final double iceFactorMax;
  final double slushFactorMin;
  final double slushFactorMax;
}

/// Укатанный снег.
class GroomedProfile {
  const GroomedProfile({
    required this.depthScale,
    required this.maxDepthScale,
    required this.packedShift,
    required this.factorCap,
  });

  final double depthScale;
  final double maxDepthScale;
  final double packedShift;
  final double factorCap;
}

/// Все коэффициенты окружения.
class FactorProfile {
  const FactorProfile({
    required this.version,
    required this.surface,
    required this.wetness,
    required this.weightTop,
    required this.weightDeep,
    required this.rain12Coeff,
    required this.trend72Coeff,
    required this.meltCoeff,
    required this.dryBelow,
    required this.dampBelow,
    required this.wetBelow,
    required this.bog,
    required this.shoes,
    required this.heat,
    required this.snow,
    required this.settlement,
    required this.roadClearance,
    required this.snowState,
    required this.groomed,
    required this.clampMin,
    required this.clampMax,
  });

  static const int currentVersion = 1;

  final int version;
  final Map<SurfaceType, double> surface;
  final Map<Wetness, double> wetness;
  final double weightTop;
  final double weightDeep;
  final double rain12Coeff;
  final double trend72Coeff;
  final double meltCoeff;
  final double dryBelow;
  final double dampBelow;
  final double wetBelow;
  final Map<String, double> bog;
  final Map<ShoeKind, Map<ShoeSurfaceClass, double>> shoes;
  final ProfileCurve heat;
  final SnowProfile snow;
  final SettlementProfile settlement;
  final Map<RoadClass, double> roadClearance;
  final SnowStateProfile snowState;
  final GroomedProfile groomed;
  final double clampMin;
  final double clampMax;

  /// Стартовые коэффициенты из документа.
  static FactorProfile defaults() {
    return FactorProfile(
      version: currentVersion,
      surface: const {
        SurfaceType.asphalt: 1.00,
        SurfaceType.concrete: 1.01,
        SurfaceType.pavingStones: 1.03,
        SurfaceType.compacted: 1.05,
        SurfaceType.dirt: 1.10,
        SurfaceType.ground: 1.12,
        SurfaceType.grass: 1.15,
        SurfaceType.sand: 1.30,
        SurfaceType.mud: 1.45,
        SurfaceType.snowPacked: 1.35,
        SurfaceType.snowDeep: 1.90,
        SurfaceType.unknown: 1.10,
      },
      wetness: const {
        Wetness.dry: 1.00,
        Wetness.damp: 1.04,
        Wetness.wet: 1.10,
        Wetness.saturated: 1.20,
        Wetness.bog: 1.35,
      },
      weightTop: 0.65,
      weightDeep: 0.35,
      rain12Coeff: 0.04,
      trend72Coeff: 0.02,
      meltCoeff: 0.04,
      dryBelow: 0.25,
      dampBelow: 0.32,
      wetBelow: 0.40,
      bog: const {
        'bog': 1.35,
        'fen': 1.25,
        'marsh': 1.30,
        'swamp': 1.30,
        'reedbed': 1.20,
        'wetMeadow': 1.15,
        'peat': 1.30,
        'peatExtraction': 1.40,
        'boardwalk': 1.05,
        'pathInWetland': 1.25,
        'frozenTop': 1.20,
        'snowCoverM': 0.05,
        'frozenTopTempC': -10,
        'frozenTopMinDays': 7,
      },
      shoes: const {
        ShoeKind.road: {
          ShoeSurfaceClass.dryAsphalt: 1.00,
          ShoeSurfaceClass.wetAsphalt: 1.08,
          ShoeSurfaceClass.dryDirt: 1.06,
          ShoeSurfaceClass.wetDirt: 1.15,
          ShoeSurfaceClass.saturated: 1.35,
          ShoeSurfaceClass.grass: 1.05,
          ShoeSurfaceClass.sand: 1.15,
          ShoeSurfaceClass.snowPacked: 1.25,
          ShoeSurfaceClass.snowDeep: 1.60,
          ShoeSurfaceClass.ford: 1.10,
        },
        ShoeKind.trail: {
          ShoeSurfaceClass.dryAsphalt: 1.02,
          ShoeSurfaceClass.wetAsphalt: 1.03,
          ShoeSurfaceClass.dryDirt: 1.00,
          ShoeSurfaceClass.wetDirt: 1.04,
          ShoeSurfaceClass.saturated: 1.10,
          ShoeSurfaceClass.grass: 1.00,
          ShoeSurfaceClass.sand: 1.04,
          ShoeSurfaceClass.snowPacked: 1.05,
          ShoeSurfaceClass.snowDeep: 1.20,
          ShoeSurfaceClass.ford: 1.02,
        },
        ShoeKind.minimal: {
          ShoeSurfaceClass.dryAsphalt: 1.01,
          ShoeSurfaceClass.wetAsphalt: 1.05,
          ShoeSurfaceClass.dryDirt: 1.02,
          ShoeSurfaceClass.wetDirt: 1.08,
          ShoeSurfaceClass.saturated: 1.20,
          ShoeSurfaceClass.grass: 1.01,
          ShoeSurfaceClass.sand: 1.08,
          ShoeSurfaceClass.snowPacked: 1.15,
          ShoeSurfaceClass.snowDeep: 1.40,
          ShoeSurfaceClass.ford: 1.05,
        },
      },
      heat: const ProfileCurve([
        (x: 10, y: 1.00),
        (x: 20, y: 1.02),
        (x: 28, y: 1.08),
        (x: 35, y: 1.20),
        (x: 45, y: 1.35),
      ]),
      snow: const SnowProfile(
        thresholdM: 0.02,
        depthCoeff: 0.21,
        maxDepthM: 1.00,
        deepCap: 1.90,
        tempCoeff: ProfileCurve([
          (x: -15, y: 2.60),
          (x: -12, y: 2.40),
          (x: -8, y: 2.00),
          (x: -5, y: 1.73),
          (x: -2, y: 1.15),
          (x: 0, y: 0.50),
          (x: 2, y: 0.50),
        ]),
        freshAddPerCm: 0.025,
        freshAddMax: 0.25,
        slushAdd: 0.15,
        dirtBelowM: 0.10,
        slushAboveM: 0.10,
        dirtFactorMin: 1.10,
        dirtFactorMax: 1.15,
        mudFactorMin: 1.15,
        mudFactorMax: 1.20,
        slushFactorMin: 1.15,
        slushFactorMax: 1.25,
      ),
      settlement: const SettlementProfile(
        urbanity: {
          SettlementContext.urban: 1.00,
          SettlementContext.town: 0.73,
          SettlementContext.village: 0.40,
          SettlementContext.rural: 0.00,
        },
        minClearance: 0.25,
      ),
      roadClearance: const {
        RoadClass.pavedMajor: 0.45,
        RoadClass.pavedLocal: 0.65,
        RoadClass.footway: 0.80,
        RoadClass.unpaved: 1.00,
      },
      snowState: const SnowStateProfile(
        asphaltBelowM: 0.02,
        packedBelowM: 0.10,
        packedFactorMin: 1.05,
        packedFactorMax: 1.15,
        iceFactorMin: 1.15,
        iceFactorMax: 1.30,
        slushFactorMin: 1.15,
        slushFactorMax: 1.30,
      ),
      groomed: const GroomedProfile(
        depthScale: 0.65,
        maxDepthScale: 0.70,
        packedShift: 0.30,
        factorCap: 1.25,
      ),
      clampMin: 0.70,
      clampMax: 2.00,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'surface': {
        for (final entry in surface.entries)
          _surfaceKey(entry.key): entry.value,
      },
      'wetness': {
        for (final entry in wetness.entries) entry.key.name: entry.value,
      },
      'soil': {
        'weightTop': weightTop,
        'weightDeep': weightDeep,
        'rain12Coeff': rain12Coeff,
        'trend72Coeff': trend72Coeff,
        'meltCoeff': meltCoeff,
        'dryBelow': dryBelow,
        'dampBelow': dampBelow,
        'wetBelow': wetBelow,
      },
      'bog': bog,
      'shoes': {
        for (final entry in shoes.entries)
          entry.key.name: {
            for (final item in entry.value.entries) item.key.name: item.value,
          },
      },
      'heat': heat.toJson(),
      'snow': {
        'thresholdM': snow.thresholdM,
        'depthCoeff': snow.depthCoeff,
        'maxDepthM': snow.maxDepthM,
        'deepCap': snow.deepCap,
        'tempCoeff': snow.tempCoeff.toJson(),
        'freshAddPerCm': snow.freshAddPerCm,
        'freshAddMax': snow.freshAddMax,
        'slushAdd': snow.slushAdd,
        'positiveTemp': {
          'dirtBelowM': snow.dirtBelowM,
          'slushAboveM': snow.slushAboveM,
          'dirtFactor': [snow.dirtFactorMin, snow.dirtFactorMax],
          'mudFactor': [snow.mudFactorMin, snow.mudFactorMax],
          'slushFactor': [snow.slushFactorMin, snow.slushFactorMax],
        },
      },
      'settlement': {
        'urbanity': {
          for (final entry in settlement.urbanity.entries)
            entry.key.name: entry.value,
        },
        'minClearance': settlement.minClearance,
      },
      'roadClearance': {
        for (final entry in roadClearance.entries) entry.key.name: entry.value,
      },
      'snowState': {
        'asphaltBelowM': snowState.asphaltBelowM,
        'packedBelowM': snowState.packedBelowM,
        'packedFactor': [snowState.packedFactorMin, snowState.packedFactorMax],
        'iceFactor': [snowState.iceFactorMin, snowState.iceFactorMax],
        'slushFactor': [snowState.slushFactorMin, snowState.slushFactorMax],
      },
      'groomed': {
        'depthScale': groomed.depthScale,
        'maxDepthScale': groomed.maxDepthScale,
        'packedShift': groomed.packedShift,
        'factorCap': groomed.factorCap,
      },
      'clamp': {'min': clampMin, 'max': clampMax},
    };
  }

  /// Читает профиль. Недостающие или битые поля заменяются значениями по
  /// умолчанию: старый профиль не должен ломать расчёт.
  static FactorProfile tryFromJson(dynamic raw) {
    final fallback = defaults();
    if (raw is! Map) return fallback;

    final soil = _map(raw['soil']);
    final snowRaw = _map(raw['snow']);
    final positive = _map(snowRaw['positiveTemp']);
    final settlementRaw = _map(raw['settlement']);
    final snowStateRaw = _map(raw['snowState']);
    final groomedRaw = _map(raw['groomed']);
    final clampRaw = _map(raw['clamp']);

    return FactorProfile(
      version: _double(raw['version'])?.round() ?? fallback.version,
      surface: _surfaceMap(raw['surface'], fallback.surface),
      wetness: _wetnessMap(raw['wetness'], fallback.wetness),
      weightTop: _double(soil['weightTop']) ?? fallback.weightTop,
      weightDeep: _double(soil['weightDeep']) ?? fallback.weightDeep,
      rain12Coeff: _double(soil['rain12Coeff']) ?? fallback.rain12Coeff,
      trend72Coeff: _double(soil['trend72Coeff']) ?? fallback.trend72Coeff,
      meltCoeff: _double(soil['meltCoeff']) ?? fallback.meltCoeff,
      dryBelow: _double(soil['dryBelow']) ?? fallback.dryBelow,
      dampBelow: _double(soil['dampBelow']) ?? fallback.dampBelow,
      wetBelow: _double(soil['wetBelow']) ?? fallback.wetBelow,
      bog: _stringDoubleMap(raw['bog'], fallback.bog),
      shoes: _shoeMap(raw['shoes'], fallback.shoes),
      heat: ProfileCurve.tryFromJson(raw['heat']) ?? fallback.heat,
      snow: SnowProfile(
        thresholdM: _double(snowRaw['thresholdM']) ?? fallback.snow.thresholdM,
        depthCoeff: _double(snowRaw['depthCoeff']) ?? fallback.snow.depthCoeff,
        maxDepthM: _double(snowRaw['maxDepthM']) ?? fallback.snow.maxDepthM,
        deepCap: _double(snowRaw['deepCap']) ?? fallback.snow.deepCap,
        tempCoeff:
            ProfileCurve.tryFromJson(snowRaw['tempCoeff']) ??
            fallback.snow.tempCoeff,
        freshAddPerCm:
            _double(snowRaw['freshAddPerCm']) ?? fallback.snow.freshAddPerCm,
        freshAddMax:
            _double(snowRaw['freshAddMax']) ?? fallback.snow.freshAddMax,
        slushAdd: _double(snowRaw['slushAdd']) ?? fallback.snow.slushAdd,
        dirtBelowM: _double(positive['dirtBelowM']) ?? fallback.snow.dirtBelowM,
        slushAboveM:
            _double(positive['slushAboveM']) ?? fallback.snow.slushAboveM,
        dirtFactorMin:
            _pair(positive['dirtFactor'], 0) ?? fallback.snow.dirtFactorMin,
        dirtFactorMax:
            _pair(positive['dirtFactor'], 1) ?? fallback.snow.dirtFactorMax,
        mudFactorMin:
            _pair(positive['mudFactor'], 0) ?? fallback.snow.mudFactorMin,
        mudFactorMax:
            _pair(positive['mudFactor'], 1) ?? fallback.snow.mudFactorMax,
        slushFactorMin:
            _pair(positive['slushFactor'], 0) ?? fallback.snow.slushFactorMin,
        slushFactorMax:
            _pair(positive['slushFactor'], 1) ?? fallback.snow.slushFactorMax,
      ),
      settlement: SettlementProfile(
        urbanity: _contextMap(
          settlementRaw['urbanity'],
          fallback.settlement.urbanity,
        ),
        minClearance:
            _double(settlementRaw['minClearance']) ??
            fallback.settlement.minClearance,
      ),
      roadClearance: _roadMap(raw['roadClearance'], fallback.roadClearance),
      snowState: SnowStateProfile(
        asphaltBelowM:
            _double(snowStateRaw['asphaltBelowM']) ??
            fallback.snowState.asphaltBelowM,
        packedBelowM:
            _double(snowStateRaw['packedBelowM']) ??
            fallback.snowState.packedBelowM,
        packedFactorMin:
            _pair(snowStateRaw['packedFactor'], 0) ??
            fallback.snowState.packedFactorMin,
        packedFactorMax:
            _pair(snowStateRaw['packedFactor'], 1) ??
            fallback.snowState.packedFactorMax,
        iceFactorMin:
            _pair(snowStateRaw['iceFactor'], 0) ??
            fallback.snowState.iceFactorMin,
        iceFactorMax:
            _pair(snowStateRaw['iceFactor'], 1) ??
            fallback.snowState.iceFactorMax,
        slushFactorMin:
            _pair(snowStateRaw['slushFactor'], 0) ??
            fallback.snowState.slushFactorMin,
        slushFactorMax:
            _pair(snowStateRaw['slushFactor'], 1) ??
            fallback.snowState.slushFactorMax,
      ),
      groomed: GroomedProfile(
        depthScale:
            _double(groomedRaw['depthScale']) ?? fallback.groomed.depthScale,
        maxDepthScale:
            _double(groomedRaw['maxDepthScale']) ??
            fallback.groomed.maxDepthScale,
        packedShift:
            _double(groomedRaw['packedShift']) ?? fallback.groomed.packedShift,
        factorCap:
            _double(groomedRaw['factorCap']) ?? fallback.groomed.factorCap,
      ),
      clampMin: _double(clampRaw['min']) ?? fallback.clampMin,
      clampMax: _double(clampRaw['max']) ?? fallback.clampMax,
    );
  }

  static String _surfaceKey(SurfaceType type) => switch (type) {
    SurfaceType.pavingStones => 'paving_stones',
    SurfaceType.snowPacked => 'snow_packed',
    SurfaceType.snowDeep => 'snow_deep',
    _ => type.name,
  };

  static SurfaceType? _surfaceFromKey(String key) {
    for (final type in SurfaceType.values) {
      if (_surfaceKey(type) == key || type.name == key) return type;
    }
    return null;
  }

  static Map<SurfaceType, double> _surfaceMap(
    dynamic raw,
    Map<SurfaceType, double> fallback,
  ) {
    final map = Map<SurfaceType, double>.of(fallback);
    if (raw is! Map) return map;
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = _double(entry.value);
      if (key is! String || value == null) continue;
      final type = _surfaceFromKey(key);
      if (type != null) map[type] = value;
    }
    return map;
  }

  static Map<Wetness, double> _wetnessMap(
    dynamic raw,
    Map<Wetness, double> fallback,
  ) {
    final map = Map<Wetness, double>.of(fallback);
    if (raw is! Map) return map;
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = _double(entry.value);
      if (key is! String || value == null) continue;
      for (final wetness in Wetness.values) {
        if (wetness.name == key) map[wetness] = value;
      }
    }
    return map;
  }

  static Map<String, double> _stringDoubleMap(
    dynamic raw,
    Map<String, double> fallback,
  ) {
    final map = Map<String, double>.of(fallback);
    if (raw is! Map) return map;
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = _double(entry.value);
      if (key is String && value != null) map[key] = value;
    }
    return map;
  }

  static Map<ShoeKind, Map<ShoeSurfaceClass, double>> _shoeMap(
    dynamic raw,
    Map<ShoeKind, Map<ShoeSurfaceClass, double>> fallback,
  ) {
    final result = {
      for (final entry in fallback.entries)
        entry.key: Map<ShoeSurfaceClass, double>.of(entry.value),
    };
    if (raw is! Map) return result;
    for (final shoe in ShoeKind.values) {
      final section = raw[shoe.name];
      if (section is! Map) continue;
      final target = result.putIfAbsent(
        shoe,
        () => <ShoeSurfaceClass, double>{},
      );
      for (final entry in section.entries) {
        final key = entry.key;
        final value = _double(entry.value);
        if (key is! String || value == null) continue;
        for (final surfaceClass in ShoeSurfaceClass.values) {
          if (surfaceClass.name == key) target[surfaceClass] = value;
        }
      }
    }
    return result;
  }

  static Map<SettlementContext, double> _contextMap(
    dynamic raw,
    Map<SettlementContext, double> fallback,
  ) {
    final map = Map<SettlementContext, double>.of(fallback);
    if (raw is! Map) return map;
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = _double(entry.value);
      if (key is! String || value == null) continue;
      for (final context in SettlementContext.values) {
        if (context.name == key) map[context] = value;
      }
    }
    return map;
  }

  static Map<RoadClass, double> _roadMap(
    dynamic raw,
    Map<RoadClass, double> fallback,
  ) {
    final map = Map<RoadClass, double>.of(fallback);
    if (raw is! Map) return map;
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = _double(entry.value);
      if (key is! String || value == null) continue;
      for (final road in RoadClass.values) {
        if (road.name == key) map[road] = value;
      }
    }
    return map;
  }

  static Map<dynamic, dynamic> _map(dynamic raw) =>
      raw is Map ? raw : const <dynamic, dynamic>{};

  static double? _double(dynamic value) {
    if (value is num && value.isFinite) return value.toDouble();
    return null;
  }

  static double? _pair(dynamic raw, int index) {
    if (raw is! List || raw.length <= index) return null;
    return _double(raw[index]);
  }
}

/// Хранит единственный профиль в `SharedPreferences`.
class FactorProfileStore {
  static const String storageKey = 'environment_profile_v1';

  Future<FactorProfile> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return FactorProfile.defaults();
      return FactorProfile.tryFromJson(jsonDecode(raw));
    } catch (_) {
      return FactorProfile.defaults();
    }
  }

  Future<void> save(FactorProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(profile.toJson()));
  }
}
