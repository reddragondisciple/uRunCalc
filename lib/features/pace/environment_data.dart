/// Погода, покрытие, кроссовки и снег для таблицы Pace/Ultra.
///
/// Настройки хранятся вместе с таблицей; вычисленные данные (погодные
/// сэмплы, участки покрытия) живут в памяти и не сериализуются. Старые
/// таблицы без блока `environment` читаются как «всё выключено».
library;

/// Откуда взята погода.
enum WeatherMode { forecast, normals, historical }

/// Тип покрытия. `unknown` при расчёте заменяется на `dirt`.
enum SurfaceType {
  asphalt,
  concrete,
  pavingStones,
  compacted,
  dirt,
  ground,
  grass,
  sand,
  mud,
  snowPacked,
  snowDeep,
  unknown,
}

/// Состояние мокрости участка.
enum Wetness { dry, damp, wet, saturated, bog }

/// Тип обуви. `null` в настройках означает «не выбрано».
enum ShoeKind { road, trail, minimal }

/// Контекст населённого пункта для расчистки снега.
enum SettlementContext { urban, town, village, rural }

/// Класс дороги для расчистки снега.
enum RoadClass { pavedMajor, pavedLocal, footway, unpaved }

/// Состояние снега на участке.
enum SnowState { none, asphalt, packed, ice, loose, slush }

/// Настройки окружения одной таблицы.
class EnvironmentSettings {
  const EnvironmentSettings({
    this.surfaceEnabled = false,
    this.weatherEnabled = false,
    this.shoesEnabled = false,
    this.groomedSnow = false,
    this.startUtc,
    this.shoe,
  });

  static const EnvironmentSettings empty = EnvironmentSettings();

  final bool surfaceEnabled;
  final bool weatherEnabled;
  final bool shoesEnabled;

  /// Укатанный/натоптанный снег. По умолчанию выключено.
  final bool groomedSnow;

  /// Время старта в UTC. Нужно для прогноза/архива.
  final DateTime? startUtc;

  /// Выбранная обувь. `null` — множитель обуви 1.00.
  final ShoeKind? shoe;

  bool get anyEnabled => surfaceEnabled || weatherEnabled || shoesEnabled;

  EnvironmentSettings copyWith({
    bool? surfaceEnabled,
    bool? weatherEnabled,
    bool? shoesEnabled,
    bool? groomedSnow,
    DateTime? startUtc,
    ShoeKind? shoe,
    bool clearStart = false,
    bool clearShoe = false,
  }) {
    return EnvironmentSettings(
      surfaceEnabled: surfaceEnabled ?? this.surfaceEnabled,
      weatherEnabled: weatherEnabled ?? this.weatherEnabled,
      shoesEnabled: shoesEnabled ?? this.shoesEnabled,
      groomedSnow: groomedSnow ?? this.groomedSnow,
      startUtc: clearStart ? null : (startUtc ?? this.startUtc),
      shoe: clearShoe ? null : (shoe ?? this.shoe),
    );
  }

  Map<String, dynamic> toJson() => {
    'surfaceEnabled': surfaceEnabled,
    'weatherEnabled': weatherEnabled,
    'shoesEnabled': shoesEnabled,
    'groomedSnow': groomedSnow,
    if (startUtc != null) 'startUtcMs': startUtc!.millisecondsSinceEpoch,
    if (shoe != null) 'shoe': shoe!.name,
  };

  static EnvironmentSettings tryFromJson(dynamic raw) {
    if (raw is! Map) return empty;
    return EnvironmentSettings(
      surfaceEnabled: raw['surfaceEnabled'] is bool
          ? raw['surfaceEnabled'] as bool
          : false,
      weatherEnabled: raw['weatherEnabled'] is bool
          ? raw['weatherEnabled'] as bool
          : false,
      shoesEnabled: raw['shoesEnabled'] is bool
          ? raw['shoesEnabled'] as bool
          : false,
      groomedSnow: raw['groomedSnow'] is bool
          ? raw['groomedSnow'] as bool
          : false,
      startUtc: _readDateTime(raw['startUtcMs']),
      shoe: _readShoe(raw['shoe']),
    );
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value is! num || !value.isFinite) return null;
    return DateTime.fromMillisecondsSinceEpoch(value.round(), isUtc: true);
  }

  static ShoeKind? _readShoe(dynamic value) {
    if (value is! String) return null;
    for (final shoe in ShoeKind.values) {
      if (shoe.name == value) return shoe;
    }
    return null;
  }
}

/// Погодный сэмпл, привязанный к точке трека.
class WeatherSample {
  const WeatherSample({
    required this.distanceM,
    required this.timeUtc,
    required this.lat,
    required this.lon,
    required this.elevationM,
    required this.tempC,
    required this.apparentC,
    required this.humidityPct,
    required this.precipMm,
    required this.rainMm,
    required this.et0Mm,
    required this.windKmh,
    required this.snowfallCm,
    required this.snowDepthM,
    required this.soilMoistureTop,
    required this.soilMoistureDeep,
    required this.soilMoistureEff,
    required this.freezingLevelM,
    required this.mode,
    this.avgTemp5C = 0,
    this.frozenDays = 0,
  });

  final double distanceM;
  final DateTime timeUtc;
  final double lat;
  final double lon;
  final double elevationM;
  final double tempC;
  final double apparentC;
  final double humidityPct;
  final double precipMm;
  final double rainMm;
  final double et0Mm;
  final double windKmh;
  final double snowfallCm;
  final double snowDepthM;
  final double soilMoistureTop;
  final double soilMoistureDeep;
  final double soilMoistureEff;
  final double? freezingLevelM;
  final WeatherMode mode;

  /// Средняя температура за 5 дней до сэмпла, °C (для зимней логики болот).
  final double avgTemp5C;

  /// Сколько из последних 7 дней имели среднюю температуру ≤ −10 °C.
  final int frozenDays;
}

/// Однородный участок покрытия.
class SurfaceRun {
  const SurfaceRun({
    required this.startM,
    required this.endM,
    required this.type,
    required this.wetness,
    required this.confidence,
    this.isBog = false,
    this.bogKind,
    this.bogFactor = 1.0,
    this.surfaceSource = 'default',
    this.urbanity = 0,
    this.roadClass = RoadClass.unpaved,
    this.isFord = false,
    this.factor = 1.0,
    this.heatFactor = 1.0,
    this.snowFactor = 1.0,
    this.shoeFactor = 1.0,
  });

  final double startM;
  final double endM;
  final SurfaceType type;
  final Wetness wetness;
  final double confidence;
  final bool isBog;
  final String? bogKind;
  final double bogFactor;
  final String surfaceSource;

  /// 0..1: степень урбанизации для расчистки снега.
  final double urbanity;
  final RoadClass roadClass;
  final bool isFord;

  /// Итоговый множитель участка с учётом включённых галочек.
  final double factor;
  final double heatFactor;
  final double snowFactor;
  final double shoeFactor;
}

/// Участок с известной степенью урбанизации.
class SettlementRun {
  const SettlementRun({
    required this.startM,
    required this.endM,
    required this.context,
    required this.urbanity,
    required this.confidence,
  });

  final double startM;
  final double endM;
  final SettlementContext context;

  /// 0..1: 0 — поле, 1 — плотная городская застройка.
  final double urbanity;
  final double confidence;
}

/// Оценка снега на участке.
class SnowEstimate {
  const SnowEstimate({
    required this.startM,
    required this.endM,
    required this.effectiveDepthM,
    required this.probabilities,
  });

  final double startM;
  final double endM;

  /// Глубина после расчистки и укатки.
  final double effectiveDepthM;

  /// Вероятности состояний, сумма = 1.
  final Map<SnowState, double> probabilities;
}

/// Брод.
class Ford {
  const Ford({required this.distanceM, required this.confirmed, this.widthM});

  final double distanceM;

  /// `true` — OSM `ford=yes`/`highway=ford`; `false` — возможный брод.
  final bool confirmed;
  final double? widthM;
}

/// Полный результат расчёта окружения. В таблицу сохраняются только
/// [settings], остальное пересчитывается при загрузке.
class EnvironmentData {
  const EnvironmentData({
    required this.settings,
    this.weather = const [],
    this.surface = const [],
    this.settlements = const [],
    this.snow = const [],
    this.fords = const [],
    this.surfaceCoverage = 0,
    this.hasForecast = false,
    this.warning,
  });

  final EnvironmentSettings settings;
  final List<WeatherSample> weather;
  final List<SurfaceRun> surface;
  final List<SettlementRun> settlements;
  final List<SnowEstimate> snow;
  final List<Ford> fords;
  final double surfaceCoverage;

  /// `false` — прогноза нет, погодную полосу не рисуем.
  final bool hasForecast;
  final String? warning;

  /// Участок покрытия, содержащий [distanceM], или ближайший.
  SurfaceRun? runAt(double distanceM) {
    if (surface.isEmpty) return null;
    for (final run in surface) {
      if (distanceM >= run.startM && distanceM <= run.endM) return run;
    }
    SurfaceRun? best;
    var bestDelta = double.infinity;
    for (final run in surface) {
      final delta = distanceM < run.startM
          ? run.startM - distanceM
          : distanceM - run.endM;
      if (delta < bestDelta) {
        best = run;
        bestDelta = delta;
      }
    }
    return best;
  }

  /// Итоговый множитель окружения на расстоянии [distanceM].
  ///
  /// За пределами покрытого трека возвращается 1.00: неполный (DNF) трек
  /// не экстраполируется на оставшуюся дистанцию.
  double factorAt(double distanceM) {
    if (surface.isEmpty) return 1.0;
    if (distanceM < surface.first.startM || distanceM > surface.last.endM) {
      return 1.0;
    }
    return runAt(distanceM)?.factor ?? 1.0;
  }

  /// Средний множитель на отрезке `[startM, endM]`, взвешенный по длине.
  /// Если отрезок не пересекается с покрытым треком — 1.00.
  double factorBetween(double startM, double endM) {
    if (surface.isEmpty || endM <= startM) return 1.0;
    var weighted = 0.0;
    var covered = 0.0;
    for (final run in surface) {
      final from = run.startM > startM ? run.startM : startM;
      final to = run.endM < endM ? run.endM : endM;
      if (to <= from) continue;
      weighted += run.factor * (to - from);
      covered += to - from;
    }
    if (covered <= 0) return 1.0;
    return weighted / covered;
  }
}
