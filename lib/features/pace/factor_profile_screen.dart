import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../theme/app_colors.dart';
import 'elevation_chart_view.dart' show surfaceTypeLabel;
import 'environment_data.dart';
import 'factor_profile.dart';

/// Полноэкранный редактор коэффициентов окружения.
///
/// Экран редактирует JSON-представление профиля: так не нужно дублировать
/// десятки полей в отдельной модели. После «Сохранить» возвращается новый
/// [FactorProfile], собранный тем же `tryFromJson`, что и при чтении с диска.
class FactorProfileScreen extends StatefulWidget {
  const FactorProfileScreen({super.key, required this.profile});

  final FactorProfile profile;

  @override
  State<FactorProfileScreen> createState() => _FactorProfileScreenState();
}

class _FactorProfileScreenState extends State<FactorProfileScreen> {
  late Map<String, dynamic> _json;
  late List<_FactorEntry> _entries;
  final Map<String, TextEditingController> _controllers = {};
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _json = _deepCopy(widget.profile.toJson()) as Map<String, dynamic>;
    _entries = _buildEntries(widget.profile);
  }

  /// `toJson` возвращает const-коллекции профиля. Для правок нужна глубокая
  /// копия: иначе `_setAt` упадёт на неизменяемой карте.
  static Object? _deepCopy(Object? value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _deepCopy(entry.value),
      };
    }
    if (value is List) {
      return [for (final item in value) _deepCopy(item)];
    }
    return value;
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _pathKey(List<Object> path) => path.join('/');

  TextEditingController _controllerFor(_FactorEntry entry) {
    final key = _pathKey(entry.path);
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: _formatDouble(entry.value)),
    );
  }

  void _resetDefaults() {
    final defaults = FactorProfile.defaults();
    final entries = _buildEntries(defaults);
    setState(() {
      for (final entry in entries) {
        _controllerFor(entry).text = _formatDouble(entry.value);
      }
      _changed = true;
    });
  }

  void _save() {
    for (final entry in _entries) {
      final raw = _controllerFor(entry).text.trim().replaceAll(',', '.');
      final value = double.tryParse(raw);
      if (value == null || !value.isFinite) continue;
      _setAt(_json, entry.path, value);
    }
    Navigator.of(context).pop(FactorProfile.tryFromJson(_json));
  }

  @override
  Widget build(BuildContext context) {
    final sections = <String, List<_FactorEntry>>{};
    for (final entry in _entries) {
      sections.putIfAbsent(entry.section, () => []).add(entry);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.paceSettingsFactors),
        actions: [
          IconButton(
            key: const ValueKey('factors-reset'),
            tooltip: AppStrings.reset,
            icon: const Icon(Icons.restart_alt),
            onPressed: _resetDefaults,
          ),
          TextButton(
            key: const ValueKey('factors-save'),
            onPressed: _save,
            child: const Text(AppStrings.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Множитель 1.00 — без поправки. Значения больше 1 замедляют '
              'участок, меньше 1 — ускоряют.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          for (final entry in sections.entries)
            ExpansionTile(
              key: ValueKey('factors-section-${entry.key}'),
              initiallyExpanded: entry.key == 'Покрытие',
              title: Text(entry.key),
              children: [
                for (final field in entry.value)
                  _FactorFieldRow(
                    entry: field,
                    controller: _controllerFor(field),
                    onChanged: () => _changed = true,
                  ),
              ],
            ),
          if (_changed)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Изменения применятся после «Сохранить».',
                style: TextStyle(color: AppColors.accent, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  static String _formatDouble(double value) {
    if (!value.isFinite) return '0';
    var text = value.toStringAsFixed(4);
    while (text.contains('.') && text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    return text;
  }

  static void _setAt(Map<String, dynamic> root, List<Object> path, double v) {
    dynamic node = root;
    for (var i = 0; i < path.length - 1; i++) {
      final key = path[i];
      node = node is Map ? node[key] : (node is List ? node[key as int] : null);
      if (node == null) return;
    }
    final last = path.last;
    if (node is Map) {
      node[last] = v;
    } else if (node is List && last is int && last < node.length) {
      node[last] = v;
    }
  }
}

class _FactorFieldRow extends StatelessWidget {
  const _FactorFieldRow({
    required this.entry,
    required this.controller,
    required this.onChanged,
  });

  final _FactorEntry entry;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              entry.label,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ),
          SizedBox(
            width: 96,
            height: 40,
            child: TextField(
              key: ValueKey('factor-${entry.path.join('-')}'),
              controller: controller,
              onChanged: (_) => onChanged(),
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FactorEntry {
  const _FactorEntry({
    required this.section,
    required this.label,
    required this.path,
    required this.value,
  });

  final String section;
  final String label;
  final List<Object> path;
  final double value;
}

String _wetnessLabel(Wetness wetness) => switch (wetness) {
  Wetness.dry => 'Сухо',
  Wetness.damp => 'Влажно',
  Wetness.wet => 'Мокро',
  Wetness.saturated => 'Насыщено',
  Wetness.bog => 'Болото',
};

String _shoeLabel(ShoeKind kind) => switch (kind) {
  ShoeKind.road => 'Дорожные',
  ShoeKind.trail => 'Трейловые',
  ShoeKind.spikes => 'С шипами',
};

String _shoeClassLabel(ShoeSurfaceClass item) => switch (item) {
  ShoeSurfaceClass.dryAsphalt => 'Сухой асфальт',
  ShoeSurfaceClass.wetAsphalt => 'Мокрый асфальт',
  ShoeSurfaceClass.dryDirt => 'Сухой грунт',
  ShoeSurfaceClass.wetDirt => 'Мокрый грунт',
  ShoeSurfaceClass.saturated => 'Насыщенный грунт',
  ShoeSurfaceClass.grass => 'Трава',
  ShoeSurfaceClass.sand => 'Песок',
  ShoeSurfaceClass.snowPacked => 'Укатанный снег',
  ShoeSurfaceClass.snowDeep => 'Глубокий снег',
  ShoeSurfaceClass.ford => 'Брод',
};

String _contextLabel(SettlementContext context) => switch (context) {
  SettlementContext.urban => 'Город',
  SettlementContext.town => 'Посёлок',
  SettlementContext.village => 'Село',
  SettlementContext.rural => 'Сельская местность',
};

String _roadLabel(RoadClass road) => switch (road) {
  RoadClass.pavedMajor => 'Асфальт, магистраль',
  RoadClass.pavedLocal => 'Асфальт, местная',
  RoadClass.footway => 'Пешеходная дорожка',
  RoadClass.unpaved => 'Без покрытия',
};

String _bogLabel(String key) => switch (key) {
  'bog' => 'Болото',
  'fen' => 'Топь',
  'marsh' => 'Марш',
  'swamp' => 'Заболоченный лес',
  'reedbed' => 'Камыш',
  'wetMeadow' => 'Мокрый луг',
  'peat' => 'Торф',
  'peatExtraction' => 'Торфоразработка',
  'boardwalk' => 'Настил',
  'pathInWetland' => 'Тропа по болоту',
  'worldCoverWetland' => 'Водно-болотные угодья',
  'frozenTop' => 'Мёрзлая корка',
  'snowCoverM' => 'Снег, м',
  'frozenTopTempC' => 'Мороз, °C',
  'frozenTopMinDays' => 'Дней мороза',
  _ => key,
};

List<_FactorEntry> _buildEntries(FactorProfile p) {
  final entries = <_FactorEntry>[];
  void add(String section, String label, List<Object> path, double value) {
    entries.add(
      _FactorEntry(section: section, label: label, path: path, value: value),
    );
  }

  for (final type in SurfaceType.values) {
    add('Покрытие', surfaceTypeLabel(type), [
      'surface',
      FactorProfile.surfaceKey(type),
    ], p.surface[type] ?? 1);
  }
  for (final wetness in Wetness.values) {
    add('Влажность', _wetnessLabel(wetness), [
      'wetness',
      wetness.name,
    ], p.wetness[wetness] ?? 1);
  }
  for (final shoe in ShoeKind.values) {
    for (final item in ShoeSurfaceClass.values) {
      add('Кроссовки: ${_shoeLabel(shoe)}', _shoeClassLabel(item), [
        'shoes',
        shoe.name,
        item.name,
      ], p.shoes[shoe]?[item] ?? 1);
    }
  }
  for (var i = 0; i < p.heat.points.length; i++) {
    final point = p.heat.points[i];
    add('Погода: жара', '${point.x} °C', ['heat', i, 0], point.x);
    add('Погода: жара', 'Множитель', ['heat', i, 1], point.y);
  }
  add('Погода: снег', 'Порог, м', ['snow', 'thresholdM'], p.snow.thresholdM);
  add('Погода: снег', 'Коэффициент глубины', [
    'snow',
    'depthCoeff',
  ], p.snow.depthCoeff);
  add('Погода: снег', 'Максимальная глубина, м', [
    'snow',
    'maxDepthM',
  ], p.snow.maxDepthM);
  add('Погода: снег', 'Потолок множителя', ['snow', 'deepCap'], p.snow.deepCap);
  add('Погода: снег', 'Свежий снег за см', [
    'snow',
    'freshAddPerCm',
  ], p.snow.freshAddPerCm);
  add('Погода: снег', 'Свежий снег, максимум', [
    'snow',
    'freshAddMax',
  ], p.snow.freshAddMax);
  add('Погода: снег', 'Слякоть, добавка', [
    'snow',
    'slushAdd',
  ], p.snow.slushAdd);
  for (var i = 0; i < p.snow.tempCoeff.points.length; i++) {
    final point = p.snow.tempCoeff.points[i];
    add('Погода: снег', 'Температура ${point.x} °C', [
      'snow',
      'tempCoeff',
      i,
      0,
    ], point.x);
    add('Погода: снег', 'Множитель при ${point.x} °C', [
      'snow',
      'tempCoeff',
      i,
      1,
    ], point.y);
  }
  add('Погода: снег (плюс)', 'Грунт до, м', [
    'snow',
    'positiveTemp',
    'dirtBelowM',
  ], p.snow.dirtBelowM);
  add('Погода: снег (плюс)', 'Слякоть выше, м', [
    'snow',
    'positiveTemp',
    'slushAboveM',
  ], p.snow.slushAboveM);
  add('Погода: снег (плюс)', 'Грунт от', [
    'snow',
    'positiveTemp',
    'dirtFactor',
    0,
  ], p.snow.dirtFactorMin);
  add('Погода: снег (плюс)', 'Грунт до', [
    'snow',
    'positiveTemp',
    'dirtFactor',
    1,
  ], p.snow.dirtFactorMax);
  add('Погода: снег (плюс)', 'Грязь от', [
    'snow',
    'positiveTemp',
    'mudFactor',
    0,
  ], p.snow.mudFactorMin);
  add('Погода: снег (плюс)', 'Грязь до', [
    'snow',
    'positiveTemp',
    'mudFactor',
    1,
  ], p.snow.mudFactorMax);
  add('Погода: снег (плюс)', 'Слякоть от', [
    'snow',
    'positiveTemp',
    'slushFactor',
    0,
  ], p.snow.slushFactorMin);
  add('Погода: снег (плюс)', 'Слякоть до', [
    'snow',
    'positiveTemp',
    'slushFactor',
    1,
  ], p.snow.slushFactorMax);

  add('Почва и мокрость', 'Верхний слой', ['soil', 'weightTop'], p.weightTop);
  add('Почва и мокрость', 'Глубокий слой', [
    'soil',
    'weightDeep',
  ], p.weightDeep);
  add('Почва и мокрость', 'Дождь за 12 ч', [
    'soil',
    'rain12Coeff',
  ], p.rain12Coeff);
  add('Почва и мокрость', 'Тренд за 72 ч', [
    'soil',
    'trend72Coeff',
  ], p.trend72Coeff);
  add('Почва и мокрость', 'Талая вода', ['soil', 'meltCoeff'], p.meltCoeff);
  add('Почва и мокрость', 'Сухо ниже', ['soil', 'dryBelow'], p.dryBelow);
  add('Почва и мокрость', 'Влажно ниже', ['soil', 'dampBelow'], p.dampBelow);
  add('Почва и мокрость', 'Мокро ниже', ['soil', 'wetBelow'], p.wetBelow);

  for (final entry in p.bog.entries) {
    add('Болота', _bogLabel(entry.key), ['bog', entry.key], entry.value);
  }
  for (final entry in p.settlement.urbanity.entries) {
    add('Расчистка снега', _contextLabel(entry.key), [
      'settlement',
      'urbanity',
      entry.key.name,
    ], entry.value);
  }
  add('Расчистка снега', 'Минимальная расчистка', [
    'settlement',
    'minClearance',
  ], p.settlement.minClearance);
  for (final entry in p.roadClearance.entries) {
    add('Расчистка снега', _roadLabel(entry.key), [
      'roadClearance',
      entry.key.name,
    ], entry.value);
  }

  add('Состояние снега', 'Асфальт ниже, м', [
    'snowState',
    'asphaltBelowM',
  ], p.snowState.asphaltBelowM);
  add('Состояние снега', 'Укатанный ниже, м', [
    'snowState',
    'packedBelowM',
  ], p.snowState.packedBelowM);
  add('Состояние снега', 'Укатанный от', [
    'snowState',
    'packedFactor',
    0,
  ], p.snowState.packedFactorMin);
  add('Состояние снега', 'Укатанный до', [
    'snowState',
    'packedFactor',
    1,
  ], p.snowState.packedFactorMax);
  add('Состояние снега', 'Лёд от', [
    'snowState',
    'iceFactor',
    0,
  ], p.snowState.iceFactorMin);
  add('Состояние снега', 'Лёд до', [
    'snowState',
    'iceFactor',
    1,
  ], p.snowState.iceFactorMax);
  add('Состояние снега', 'Слякоть от', [
    'snowState',
    'slushFactor',
    0,
  ], p.snowState.slushFactorMin);
  add('Состояние снега', 'Слякоть до', [
    'snowState',
    'slushFactor',
    1,
  ], p.snowState.slushFactorMax);
  add('Состояние снега', 'Укатка: глубина', [
    'groomed',
    'depthScale',
  ], p.groomed.depthScale);
  add('Состояние снега', 'Укатка: максимум глубины', [
    'groomed',
    'maxDepthScale',
  ], p.groomed.maxDepthScale);
  add('Состояние снега', 'Укатка: сдвиг', [
    'groomed',
    'packedShift',
  ], p.groomed.packedShift);
  add('Состояние снега', 'Укатка: потолок', [
    'groomed',
    'factorCap',
  ], p.groomed.factorCap);

  add('Ограничения', 'Минимальный множитель', ['clamp', 'min'], p.clampMin);
  add('Ограничения', 'Максимальный множитель', ['clamp', 'max'], p.clampMax);
  return entries;
}
