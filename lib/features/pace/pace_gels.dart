import 'pace_calculations.dart';

/// Питательный параметр геля: вещество, подпись и единица измерения.
class GelNutrientSpec {
  const GelNutrientSpec(this.id, this.label, this.unit);

  final String id;
  final String label;
  final String unit;
}

/// Известные параметры, которые предлагаются в настройках гелей.
class GelNutrients {
  GelNutrients._();

  static const GelNutrientSpec carbs = GelNutrientSpec(
    'carbs',
    'Углеводы',
    'г',
  );
  static const GelNutrientSpec caffeine = GelNutrientSpec(
    'caffeine',
    'Кофеин',
    'мг',
  );
  static const GelNutrientSpec sodium = GelNutrientSpec(
    'sodium',
    'Натрий',
    'мг',
  );
  static const GelNutrientSpec potassium = GelNutrientSpec(
    'potassium',
    'Калий',
    'мг',
  );
  static const GelNutrientSpec magnesium = GelNutrientSpec(
    'magnesium',
    'Магний',
    'мг',
  );
  static const GelNutrientSpec calcium = GelNutrientSpec(
    'calcium',
    'Кальций',
    'мг',
  );

  static const List<GelNutrientSpec> known = [
    carbs,
    caffeine,
    sodium,
    potassium,
    magnesium,
    calcium,
  ];

  static GelNutrientSpec? byId(String id) {
    for (final nutrient in known) {
      if (nutrient.id == id) return nutrient;
    }
    return null;
  }
}

/// Значение одного параметра в геле.
class GelNutrientValue {
  const GelNutrientValue({
    required this.id,
    required this.label,
    required this.unit,
    required this.amount,
  });

  final String id;
  final String label;
  final String unit;
  final double amount;
}

/// Количество гелей одного вида в раскладке.
class GelCount {
  const GelCount({
    required this.token,
    required this.name,
    required this.count,
  });

  final String token;
  final String name;
  final int count;
}

/// Состав геля для отображения и подсчёта статистики.
class GelProfile {
  const GelProfile({
    required this.token,
    required this.name,
    required this.nutrients,
  });

  final String token;
  final String name;
  final List<GelNutrientValue> nutrients;
}

/// Пользовательский параметр в своём геле.
class CustomGelNutrient {
  const CustomGelNutrient({
    required this.id,
    required this.label,
    required this.unit,
    required this.amount,
  });

  final String id;
  final String label;
  final String unit;
  final String amount;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'unit': unit,
    'amount': amount,
  };

  static CustomGelNutrient? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final label = _readString(raw['label']).trim();
    final unit = _readString(raw['unit']).trim();
    if (label.isEmpty || unit.isEmpty) return null;
    final id = _readString(raw['id']).trim();
    return CustomGelNutrient(
      id: id.isEmpty ? _customId(label, unit) : id,
      label: label,
      unit: unit,
      amount: _readString(raw['amount']),
    );
  }
}

/// Гель, созданный пользователем.
class CustomGel {
  const CustomGel({required this.name, required this.nutrients});

  final String name;
  final List<CustomGelNutrient> nutrients;

  String get token => 'custom:$name';

  Map<String, dynamic> toJson() => {
    'name': name,
    'nutrients': [for (final nutrient in nutrients) nutrient.toJson()],
  };

  static CustomGel? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final name = _readString(raw['name']).trim();
    if (name.isEmpty) return null;
    final nutrients = <CustomGelNutrient>[];
    final rawNutrients = raw['nutrients'];
    if (rawNutrients is List) {
      for (final rawNutrient in rawNutrients) {
        final nutrient = CustomGelNutrient.tryFromJson(rawNutrient);
        if (nutrient != null) nutrients.add(nutrient);
      }
    }
    if (nutrients.isEmpty) return null;
    return CustomGel(name: name, nutrients: nutrients);
  }
}

/// Настройки простого, изо- и кофегеля, а также список своих гелей.
class GelSettings {
  const GelSettings({
    this.simpleCarbs = '25',
    this.isoCarbs = '',
    this.isoSodium = '',
    this.isoPotassium = '',
    this.isoMagnesium = '',
    this.isoCalcium = '',
    this.coffeeCarbs = '',
    this.coffeeCaffeine = '',
    this.coffeeSodium = '',
    this.coffeePotassium = '',
    this.coffeeMagnesium = '',
    this.coffeeCalcium = '',
    this.customGels = const [],
  });

  final String simpleCarbs;

  final String isoCarbs;
  final String isoSodium;
  final String isoPotassium;
  final String isoMagnesium;
  final String isoCalcium;

  final String coffeeCarbs;
  final String coffeeCaffeine;
  final String coffeeSodium;
  final String coffeePotassium;
  final String coffeeMagnesium;
  final String coffeeCalcium;

  final List<CustomGel> customGels;

  GelSettings copyWith({
    String? simpleCarbs,
    String? isoCarbs,
    String? isoSodium,
    String? isoPotassium,
    String? isoMagnesium,
    String? isoCalcium,
    String? coffeeCarbs,
    String? coffeeCaffeine,
    String? coffeeSodium,
    String? coffeePotassium,
    String? coffeeMagnesium,
    String? coffeeCalcium,
    List<CustomGel>? customGels,
  }) {
    return GelSettings(
      simpleCarbs: simpleCarbs ?? this.simpleCarbs,
      isoCarbs: isoCarbs ?? this.isoCarbs,
      isoSodium: isoSodium ?? this.isoSodium,
      isoPotassium: isoPotassium ?? this.isoPotassium,
      isoMagnesium: isoMagnesium ?? this.isoMagnesium,
      isoCalcium: isoCalcium ?? this.isoCalcium,
      coffeeCarbs: coffeeCarbs ?? this.coffeeCarbs,
      coffeeCaffeine: coffeeCaffeine ?? this.coffeeCaffeine,
      coffeeSodium: coffeeSodium ?? this.coffeeSodium,
      coffeePotassium: coffeePotassium ?? this.coffeePotassium,
      coffeeMagnesium: coffeeMagnesium ?? this.coffeeMagnesium,
      coffeeCalcium: coffeeCalcium ?? this.coffeeCalcium,
      customGels: customGels ?? this.customGels,
    );
  }

  GelSettings withCustomGel(CustomGel gel) {
    return copyWith(customGels: [...customGels, gel]);
  }

  GelSettings withoutCustomGel(String name) {
    return copyWith(
      customGels: [
        for (final gel in customGels)
          if (gel.name != name) gel,
      ],
    );
  }

  /// Гель по токену правого поля. `null` — токен не является гелем.
  GelProfile? profileForToken(String token) {
    final values = switch (token) {
      PaceGelTokens.simple => <GelNutrientValue>[
        _value(GelNutrients.carbs, simpleCarbs),
      ],
      PaceGelTokens.iso => <GelNutrientValue>[
        _value(GelNutrients.carbs, isoCarbs),
        _value(GelNutrients.sodium, isoSodium),
        _value(GelNutrients.potassium, isoPotassium),
        _value(GelNutrients.magnesium, isoMagnesium),
        _value(GelNutrients.calcium, isoCalcium),
      ],
      PaceGelTokens.coffee => <GelNutrientValue>[
        _value(GelNutrients.carbs, coffeeCarbs),
        _value(GelNutrients.caffeine, coffeeCaffeine),
        _value(GelNutrients.sodium, coffeeSodium),
        _value(GelNutrients.potassium, coffeePotassium),
        _value(GelNutrients.magnesium, coffeeMagnesium),
        _value(GelNutrients.calcium, coffeeCalcium),
      ],
      _ => null,
    };
    if (values != null) {
      return GelProfile(
        token: token,
        name: PaceGelCatalog.gelName(token),
        nutrients: [
          for (final value in values)
            if (value.amount > 0) value,
        ],
      );
    }

    if (!token.startsWith(PaceGelTokens.customPrefix)) return null;
    final name = token.substring(PaceGelTokens.customPrefix.length);
    final gel = customGels.where((gel) => gel.name == name).firstOrNull;
    if (gel == null) return null;

    final nutrients = <GelNutrientValue>[];
    for (final nutrient in gel.nutrients) {
      final amount = parseGelNumber(nutrient.amount);
      if (amount == null || amount <= 0) continue;
      final known = GelNutrients.byId(nutrient.id);
      nutrients.add(
        GelNutrientValue(
          id: known?.id ?? _customId(nutrient.label, nutrient.unit),
          label: known?.label ?? nutrient.label,
          unit: known?.unit ?? nutrient.unit,
          amount: amount,
        ),
      );
    }
    return GelProfile(token: token, name: gel.name, nutrients: nutrients);
  }

  /// Суммарные параметры по выбранным в таблице гелям. Нулевые и пустые
  /// значения не попадают в результат.
  List<GelNutrientValue> totals(Iterable<String> tokens) {
    final totals = <String, GelNutrientValue>{};
    for (final token in tokens) {
      final profile = profileForToken(token);
      if (profile == null) continue;
      for (final nutrient in profile.nutrients) {
        final current = totals[nutrient.id];
        if (current == null) {
          totals[nutrient.id] = nutrient;
        } else {
          totals[nutrient.id] = GelNutrientValue(
            id: nutrient.id,
            label: current.label,
            unit: current.unit,
            amount: current.amount + nutrient.amount,
          );
        }
      }
    }
    if (totals.isEmpty) return const [];

    final result = <GelNutrientValue>[];
    for (final known in GelNutrients.known) {
      final value = totals.remove(known.id);
      if (value != null && value.amount > 0) result.add(value);
    }
    for (final value in totals.values) {
      if (value.amount > 0) result.add(value);
    }
    return result;
  }

  /// Количество гелей каждого вида: автоматических и выбранных вручную.
  /// Порядок совпадает со списком питания, свои гели идут после кофегеля.
  List<GelCount> countGels(Iterable<String> tokens) {
    final counts = <String, int>{};
    for (final token in tokens) {
      if (profileForToken(token) == null) continue;
      counts[token] = (counts[token] ?? 0) + 1;
    }
    if (counts.isEmpty) return const [];

    final result = <GelCount>[];
    for (final option in PaceGelCatalog.rightOptions(this)) {
      if (!PaceGelTokens.isGel(option.key)) continue;
      final count = counts.remove(option.key);
      if (count == null || count <= 0) continue;
      result.add(GelCount(token: option.key, name: option.label, count: count));
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
    'simpleCarbs': simpleCarbs,
    'isoCarbs': isoCarbs,
    'isoSodium': isoSodium,
    'isoPotassium': isoPotassium,
    'isoMagnesium': isoMagnesium,
    'isoCalcium': isoCalcium,
    'coffeeCarbs': coffeeCarbs,
    'coffeeCaffeine': coffeeCaffeine,
    'coffeeSodium': coffeeSodium,
    'coffeePotassium': coffeePotassium,
    'coffeeMagnesium': coffeeMagnesium,
    'coffeeCalcium': coffeeCalcium,
    'customGels': [for (final gel in customGels) gel.toJson()],
  };

  static GelSettings fromJson(dynamic raw) {
    if (raw is! Map) return const GelSettings();
    final customGels = <CustomGel>[];
    final rawCustom = raw['customGels'];
    if (rawCustom is List) {
      for (final rawGel in rawCustom) {
        final gel = CustomGel.tryFromJson(rawGel);
        if (gel != null &&
            !customGels.any((existing) => existing.name == gel.name)) {
          customGels.add(gel);
        }
      }
    }
    return GelSettings(
      simpleCarbs: _readOr(raw['simpleCarbs'], '25'),
      isoCarbs: _readString(raw['isoCarbs']),
      isoSodium: _readString(raw['isoSodium']),
      isoPotassium: _readString(raw['isoPotassium']),
      isoMagnesium: _readString(raw['isoMagnesium']),
      isoCalcium: _readString(raw['isoCalcium']),
      coffeeCarbs: _readString(raw['coffeeCarbs']),
      coffeeCaffeine: _readString(raw['coffeeCaffeine']),
      coffeeSodium: _readString(raw['coffeeSodium']),
      coffeePotassium: _readString(raw['coffeePotassium']),
      coffeeMagnesium: _readString(raw['coffeeMagnesium']),
      coffeeCalcium: _readString(raw['coffeeCalcium']),
      customGels: customGels,
    );
  }
}

/// Состояние строки таблицы раскладки в части меток и питания.
class PaceGelRow {
  const PaceGelRow({
    this.left = const [],
    this.right,
    this.leftOther = '',
    this.rightOther = '',
  });

  final List<String> left;

  /// `null` — правое поле не менялось вручную, гель раскладывается
  /// автоматически. Пустой список — пользователь снял все галочки.
  final List<String>? right;

  final String leftOther;
  final String rightOther;

  PaceGelRow copyWith({
    List<String>? left,
    List<String>? right,
    bool clearRight = false,
    String? leftOther,
    String? rightOther,
  }) {
    return PaceGelRow(
      left: left ?? this.left,
      right: clearRight ? null : (right ?? this.right),
      leftOther: leftOther ?? this.leftOther,
      rightOther: rightOther ?? this.rightOther,
    );
  }

  Map<String, dynamic> toJson(int index) => {
    'index': index,
    'left': left,
    'right': right,
    'leftOther': leftOther,
    'rightOther': rightOther,
  };

  static PaceGelRow? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final index = raw['index'];
    if (index is! int || index < 0) return null;
    List<String> readList(dynamic value) {
      if (value is! List) return const [];
      return [
        for (final item in value)
          if (item is String) item,
      ];
    }

    final rawRight = raw['right'];
    return PaceGelRow(
      left: readList(raw['left']),
      right: rawRight is List ? readList(rawRight) : null,
      leftOther: _readString(raw['leftOther']),
      rightOther: _readString(raw['rightOther']),
    );
  }
}

/// Полное состояние гелей Pace, которое сохраняется вместе с калькулятором.
class PaceGelState {
  const PaceGelState({
    this.everyMinutes = '',
    this.everyKm = '',
    this.settings = const GelSettings(),
    this.rows = const {},
  });

  final String everyMinutes;
  final String everyKm;
  final GelSettings settings;

  /// Ручные изменения строк, ключ — индекс контрольной точки.
  final Map<int, PaceGelRow> rows;

  PaceGelState copyWith({
    String? everyMinutes,
    String? everyKm,
    GelSettings? settings,
    Map<int, PaceGelRow>? rows,
  }) {
    return PaceGelState(
      everyMinutes: everyMinutes ?? this.everyMinutes,
      everyKm: everyKm ?? this.everyKm,
      settings: settings ?? this.settings,
      rows: rows ?? this.rows,
    );
  }

  Map<String, dynamic> toJson() => {
    'everyMinutes': everyMinutes,
    'everyKm': everyKm,
    'settings': settings.toJson(),
    'rows': [for (final entry in rows.entries) entry.value.toJson(entry.key)],
  };

  static PaceGelState fromJson(dynamic raw) {
    if (raw is! Map) return const PaceGelState();
    final rows = <int, PaceGelRow>{};
    final rawRows = raw['rows'];
    if (rawRows is List) {
      for (final rawRow in rawRows) {
        final index = rawRow is Map ? rawRow['index'] : null;
        final row = PaceGelRow.tryFromJson(rawRow);
        if (index is int && index >= 0 && row != null) {
          rows[index] = row;
        }
      }
    }
    return PaceGelState(
      everyMinutes: _readString(raw['everyMinutes']),
      everyKm: _readString(raw['everyKm']),
      settings: GelSettings.fromJson(raw['settings']),
      rows: rows,
    );
  }
}

/// Токены и подписи пунктов таблицы.
class PaceGelTokens {
  PaceGelTokens._();

  static const String simple = 'gel_simple';
  static const String iso = 'gel_iso';
  static const String coffee = 'gel_coffee';
  static const String customPrefix = 'custom:';

  static const String water = 'water';
  static const String cola = 'cola';
  static const String isotonic = 'isotonic';
  static const String fruit = 'fruit';
  static const String other = 'other';

  static const String pp = 'pp';
  static const String bio = 'bio';
  static const String climb = 'climb';
  static const String descent = 'descent';

  static bool isGel(String token) =>
      token == simple ||
      token == iso ||
      token == coffee ||
      token.startsWith(customPrefix);
}

class GelOption {
  const GelOption(this.key, this.label);

  final String key;
  final String label;
}

/// Списки пунктов для левого и правого поля строки.
class PaceGelCatalog {
  PaceGelCatalog._();

  static const List<GelOption> leftOptions = [
    GelOption(PaceGelTokens.pp, 'ПП'),
    GelOption(PaceGelTokens.bio, 'био'),
    GelOption(PaceGelTokens.climb, 'подъём'),
    GelOption(PaceGelTokens.descent, 'спуск'),
    GelOption(PaceGelTokens.other, '+иное'),
  ];

  static const List<GelOption> rightBaseOptions = [
    GelOption(PaceGelTokens.simple, 'гель'),
    GelOption(PaceGelTokens.iso, 'изогель'),
    GelOption(PaceGelTokens.coffee, 'кофегель'),
    GelOption(PaceGelTokens.water, 'вода'),
    GelOption(PaceGelTokens.cola, 'кола'),
    GelOption(PaceGelTokens.isotonic, 'изотоник'),
    GelOption(PaceGelTokens.fruit, 'фрукты'),
    GelOption(PaceGelTokens.other, '+иное'),
  ];

  static String gelName(String token) => switch (token) {
    PaceGelTokens.simple => 'гель',
    PaceGelTokens.iso => 'изогель',
    PaceGelTokens.coffee => 'кофегель',
    _ =>
      token.startsWith(PaceGelTokens.customPrefix)
          ? token.substring(PaceGelTokens.customPrefix.length)
          : token,
  };

  static List<GelOption> rightOptions(GelSettings settings) {
    return [
      ...rightBaseOptions.take(3),
      for (final gel in settings.customGels) GelOption(gel.token, gel.name),
      ...rightBaseOptions.skip(3),
    ];
  }

  /// Подписи выбранных пунктов в порядке списка, через запятую.
  static String labelsFor({
    required Iterable<String> selected,
    required List<GelOption> options,
    required String otherText,
  }) {
    final keys = selected.toSet();
    final labels = <String>[];
    for (final option in options) {
      if (!keys.contains(option.key)) continue;
      if (option.key == PaceGelTokens.other) {
        final text = otherText.trim();
        labels.add(text.isEmpty ? 'иное' : text);
      } else {
        labels.add(option.label);
      }
    }
    return labels.join(', ');
  }
}

/// Автоматическая раскладка обычных гелей по контрольным точкам.
class PaceGelPlanner {
  PaceGelPlanner._();

  static const int maxAutoGels = 500;

  static Set<int> autoRows({
    required List<PaceSplitPoint> points,
    required String everyMinutes,
    required String everyKm,
    required int startSeconds,
  }) {
    if (points.isEmpty) return const {};
    final minutes = parseGelNumber(everyMinutes);
    final kilometers = parseGelNumber(everyKm);
    final result = <int>{};

    int? nearestBySeconds(int target) {
      int? best;
      var bestDelta = double.infinity;
      for (var index = 0; index < points.length; index++) {
        final point = points[index];
        if (point.isFinish) continue;
        final delta = (point.seconds - target).abs().toDouble();
        if (delta < bestDelta) {
          bestDelta = delta;
          best = index;
        }
      }
      return best;
    }

    int? nearestByDistance(double target) {
      int? best;
      var bestDelta = double.infinity;
      for (var index = 0; index < points.length; index++) {
        final point = points[index];
        if (point.isFinish) continue;
        final delta = (point.distanceKm - target).abs();
        if (delta < bestDelta) {
          bestDelta = delta;
          best = index;
        }
      }
      return best;
    }

    if (minutes != null && minutes > 0) {
      final lastSeconds = points.last.seconds;
      for (var step = 1; step <= maxAutoGels; step++) {
        final target = startSeconds + (minutes * 60 * step).round();
        if (target >= lastSeconds) break;
        final index = nearestBySeconds(target);
        if (index != null) result.add(index);
      }
      return result;
    }

    if (kilometers != null && kilometers > 0) {
      final lastDistance = points.last.distanceKm;
      for (var step = 1; step <= maxAutoGels; step++) {
        final target = kilometers * step;
        if (target >= lastDistance - 1e-9) break;
        final index = nearestByDistance(target);
        if (index != null) result.add(index);
      }
      return result;
    }

    return result;
  }
}

/// Разбирает число из поля геля. Запятая и точка равнозначны.
double? parseGelNumber(String raw) {
  final normalized = raw.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  final value = double.tryParse(normalized);
  if (value == null || !value.isFinite || value < 0) return null;
  return value;
}

/// Форматирует количество без лишних нулей: `25`, `12.5`, `0.25`.
String formatGelAmount(double value) {
  if (!value.isFinite) return '';
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  var text = value.toStringAsFixed(2);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

GelNutrientValue _value(GelNutrientSpec spec, String raw) {
  return GelNutrientValue(
    id: spec.id,
    label: spec.label,
    unit: spec.unit,
    amount: parseGelNumber(raw) ?? 0,
  );
}

String _customId(String label, String unit) =>
    'custom:${label.trim().toLowerCase()}|${unit.trim().toLowerCase()}';

String _readString(dynamic value) => value is String ? value : '';

String _readOr(dynamic value, String fallback) {
  if (value is! String) return fallback;
  return value;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
