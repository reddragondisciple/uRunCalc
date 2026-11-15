import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_strings.dart';
import 'pace_gels.dart';

/// Результат диалога опций Pace: раскладка, время старта и настройки гелей.
class PaceOptionsResult {
  const PaceOptionsResult({
    required this.splitDistance,
    required this.startHours,
    required this.startMinutes,
    required this.settings,
  });

  final String splitDistance;
  final String startHours;
  final String startMinutes;
  final GelSettings settings;
}

/// Опции Pace: раскладка на, время старта и настройки гелей.
class PaceOptionsDialog extends StatefulWidget {
  const PaceOptionsDialog({
    super.key,
    required this.splitDistance,
    required this.startHours,
    required this.startMinutes,
    required this.settings,
  });

  final String splitDistance;
  final String startHours;
  final String startMinutes;
  final GelSettings settings;

  @override
  State<PaceOptionsDialog> createState() => _PaceOptionsDialogState();
}

class _PaceOptionsDialogState extends State<PaceOptionsDialog> {
  late final TextEditingController _split;
  late final TextEditingController _hours;
  late final TextEditingController _minutes;
  late GelSettings _settings;
  String? _error;

  @override
  void initState() {
    super.initState();
    _split = TextEditingController(text: widget.splitDistance);
    _hours = TextEditingController(text: widget.startHours);
    _minutes = TextEditingController(text: widget.startMinutes);
    _settings = widget.settings;
  }

  @override
  void dispose() {
    _split.dispose();
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _openGelSettings() async {
    final updated = await showDialog<GelSettings>(
      context: context,
      builder: (dialogContext) => GelSettingsDialog(settings: _settings),
    );
    if (!mounted || updated == null) return;
    setState(() => _settings = updated);
  }

  Future<void> _openCustomGels() async {
    final updated = await showDialog<GelSettings>(
      context: context,
      builder: (dialogContext) =>
          GelSettingsDialog(settings: _settings, scrollToCustom: true),
    );
    if (!mounted || updated == null) return;
    setState(() => _settings = updated);
  }

  void _save() {
    final split = _split.text.trim().replaceAll(',', '.');
    if (split.isNotEmpty) {
      final value = double.tryParse(split);
      if (value == null || !value.isFinite || value <= 0) {
        setState(() => _error = AppStrings.paceOptionsInvalidSplit);
        return;
      }
    }

    final hoursText = _hours.text.trim();
    final minutesText = _minutes.text.trim();
    final hours = hoursText.isEmpty ? 0 : int.tryParse(hoursText);
    final minutes = minutesText.isEmpty ? 0 : int.tryParse(minutesText);
    if (hours == null || minutes == null || hours < 0 || minutes < 0) {
      setState(() => _error = AppStrings.paceOptionsInvalidStart);
      return;
    }
    if (minutes > 59) {
      setState(() => _error = AppStrings.paceOptionsInvalidStart);
      return;
    }

    Navigator.pop(
      context,
      PaceOptionsResult(
        splitDistance: split,
        startHours: hoursText,
        startMinutes: minutesText,
        settings: _settings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.paceOptionsTitle),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('pace-options-split'),
                controller: _split,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: AppStrings.paceCalcSplit,
                  suffixText: AppStrings.paceHintKm,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                AppStrings.paceCalcStartTime,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('pace-options-start-hours'),
                      controller: _hours,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: const InputDecoration(hintText: '00'),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(':', style: TextStyle(fontSize: 18)),
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('pace-options-start-minutes'),
                      controller: _minutes,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: const InputDecoration(hintText: '00'),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              OutlinedButton.icon(
                key: const ValueKey('pace-options-gels'),
                onPressed: _openGelSettings,
                icon: const Icon(Icons.local_drink_outlined, size: 18),
                label: const Text(AppStrings.paceOptionsGels),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                key: const ValueKey('pace-options-custom-gels'),
                onPressed: _openCustomGels,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text(AppStrings.paceGelCustom),
              ),
              const SizedBox(height: 6),
              Text(
                _settingsSummary(_settings),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(AppStrings.cancel),
        ),
        FilledButton(
          key: const ValueKey('pace-options-save'),
          onPressed: _save,
          child: const Text(AppStrings.save),
        ),
      ],
    );
  }

  String _settingsSummary(GelSettings settings) {
    final parts = <String>[];
    final simple = parseGelNumber(settings.simpleCarbs);
    if (simple != null && simple > 0) {
      parts.add('${AppStrings.paceGelSimple}: ${formatGelAmount(simple)} г');
    }
    if (settings.customGels.isNotEmpty) {
      parts.add('${AppStrings.paceGelCustom}: ${settings.customGels.length}');
    }
    return parts.isEmpty ? AppStrings.paceGelNotConfigured : parts.join(' · ');
  }
}

/// Настройки простого, изо- и кофегеля и список своих гелей.
class GelSettingsDialog extends StatefulWidget {
  const GelSettingsDialog({
    super.key,
    required this.settings,
    this.scrollToCustom = false,
  });

  final GelSettings settings;
  final bool scrollToCustom;

  @override
  State<GelSettingsDialog> createState() => _GelSettingsDialogState();
}

class _GelSettingsDialogState extends State<GelSettingsDialog> {
  final ScrollController _scroll = ScrollController();
  late final TextEditingController _simpleCarbs;
  late final TextEditingController _isoCarbs;
  late final TextEditingController _isoSodium;
  late final TextEditingController _isoPotassium;
  late final TextEditingController _isoMagnesium;
  late final TextEditingController _isoCalcium;
  late final TextEditingController _coffeeCarbs;
  late final TextEditingController _coffeeCaffeine;
  late final TextEditingController _coffeeSodium;
  late final TextEditingController _coffeePotassium;
  late final TextEditingController _coffeeMagnesium;
  late final TextEditingController _coffeeCalcium;
  late List<CustomGel> _customGels;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = widget.settings;
    _simpleCarbs = TextEditingController(text: settings.simpleCarbs);
    _isoCarbs = TextEditingController(text: settings.isoCarbs);
    _isoSodium = TextEditingController(text: settings.isoSodium);
    _isoPotassium = TextEditingController(text: settings.isoPotassium);
    _isoMagnesium = TextEditingController(text: settings.isoMagnesium);
    _isoCalcium = TextEditingController(text: settings.isoCalcium);
    _coffeeCarbs = TextEditingController(text: settings.coffeeCarbs);
    _coffeeCaffeine = TextEditingController(text: settings.coffeeCaffeine);
    _coffeeSodium = TextEditingController(text: settings.coffeeSodium);
    _coffeePotassium = TextEditingController(text: settings.coffeePotassium);
    _coffeeMagnesium = TextEditingController(text: settings.coffeeMagnesium);
    _coffeeCalcium = TextEditingController(text: settings.coffeeCalcium);
    _customGels = List<CustomGel>.of(settings.customGels);
    if (widget.scrollToCustom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final controller in [
      _simpleCarbs,
      _isoCarbs,
      _isoSodium,
      _isoPotassium,
      _isoMagnesium,
      _isoCalcium,
      _coffeeCarbs,
      _coffeeCaffeine,
      _coffeeSodium,
      _coffeePotassium,
      _coffeeMagnesium,
      _coffeeCalcium,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _addCustomGel() async {
    final gel = await showDialog<CustomGel>(
      context: context,
      builder: (dialogContext) => CustomGelEditorDialog(
        existingNames: [
          ...PaceGelCatalog.rightBaseOptions
              .where((option) => PaceGelTokens.isGel(option.key))
              .map((option) => option.label),
          for (final gel in _customGels) gel.name,
        ],
      ),
    );
    if (!mounted || gel == null) return;
    setState(() {
      _customGels = [..._customGels, gel];
      _error = null;
    });
  }

  Future<void> _deleteCustomGel(CustomGel gel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.paceGelDeleteTitle),
        content: Text(AppStrings.paceGelDeleteQuestion(gel.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            key: const ValueKey('pace-gel-delete-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(AppStrings.paceGelClear),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _customGels = [
        for (final item in _customGels)
          if (item.name != gel.name) item,
      ];
    });
  }

  void _save() {
    final values = {
      _simpleCarbs: _simpleCarbs.text.trim(),
      _isoCarbs: _isoCarbs.text.trim(),
      _isoSodium: _isoSodium.text.trim(),
      _isoPotassium: _isoPotassium.text.trim(),
      _isoMagnesium: _isoMagnesium.text.trim(),
      _isoCalcium: _isoCalcium.text.trim(),
      _coffeeCarbs: _coffeeCarbs.text.trim(),
      _coffeeCaffeine: _coffeeCaffeine.text.trim(),
      _coffeeSodium: _coffeeSodium.text.trim(),
      _coffeePotassium: _coffeePotassium.text.trim(),
      _coffeeMagnesium: _coffeeMagnesium.text.trim(),
      _coffeeCalcium: _coffeeCalcium.text.trim(),
    };
    for (final value in values.values) {
      if (value.isEmpty) continue;
      final parsed = parseGelNumber(value);
      if (parsed == null) {
        setState(() => _error = AppStrings.paceGelInvalidNumber);
        return;
      }
    }

    Navigator.pop(
      context,
      GelSettings(
        simpleCarbs: _simpleCarbs.text.trim(),
        isoCarbs: _isoCarbs.text.trim(),
        isoSodium: _isoSodium.text.trim(),
        isoPotassium: _isoPotassium.text.trim(),
        isoMagnesium: _isoMagnesium.text.trim(),
        isoCalcium: _isoCalcium.text.trim(),
        coffeeCarbs: _coffeeCarbs.text.trim(),
        coffeeCaffeine: _coffeeCaffeine.text.trim(),
        coffeeSodium: _coffeeSodium.text.trim(),
        coffeePotassium: _coffeePotassium.text.trim(),
        coffeeMagnesium: _coffeeMagnesium.text.trim(),
        coffeeCalcium: _coffeeCalcium.text.trim(),
        customGels: _customGels,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.paceGelsTitle),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          controller: _scroll,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(AppStrings.paceGelSimple),
              _nutrientField(
                key: 'pace-gel-simple-carbs',
                controller: _simpleCarbs,
                label: GelNutrients.carbs,
              ),
              const SizedBox(height: 12),
              _sectionTitle(AppStrings.paceGelIso),
              _nutrientField(
                key: 'pace-gel-iso-carbs',
                controller: _isoCarbs,
                label: GelNutrients.carbs,
              ),
              _nutrientField(
                key: 'pace-gel-iso-sodium',
                controller: _isoSodium,
                label: GelNutrients.sodium,
              ),
              _nutrientField(
                key: 'pace-gel-iso-potassium',
                controller: _isoPotassium,
                label: GelNutrients.potassium,
              ),
              _nutrientField(
                key: 'pace-gel-iso-magnesium',
                controller: _isoMagnesium,
                label: GelNutrients.magnesium,
              ),
              _nutrientField(
                key: 'pace-gel-iso-calcium',
                controller: _isoCalcium,
                label: GelNutrients.calcium,
              ),
              const SizedBox(height: 12),
              _sectionTitle(AppStrings.paceGelCoffee),
              _nutrientField(
                key: 'pace-gel-coffee-carbs',
                controller: _coffeeCarbs,
                label: GelNutrients.carbs,
              ),
              _nutrientField(
                key: 'pace-gel-coffee-caffeine',
                controller: _coffeeCaffeine,
                label: GelNutrients.caffeine,
              ),
              _nutrientField(
                key: 'pace-gel-coffee-sodium',
                controller: _coffeeSodium,
                label: GelNutrients.sodium,
              ),
              _nutrientField(
                key: 'pace-gel-coffee-potassium',
                controller: _coffeePotassium,
                label: GelNutrients.potassium,
              ),
              _nutrientField(
                key: 'pace-gel-coffee-magnesium',
                controller: _coffeeMagnesium,
                label: GelNutrients.magnesium,
              ),
              _nutrientField(
                key: 'pace-gel-coffee-calcium',
                controller: _coffeeCalcium,
                label: GelNutrients.calcium,
              ),
              const Divider(height: 28),
              _sectionTitle(AppStrings.paceGelCustom),
              for (final gel in _customGels)
                ListTile(
                  key: ValueKey('pace-gel-custom-${gel.name}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(gel.name),
                  subtitle: Text(
                    _customGelSummary(gel),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: TextButton(
                    key: ValueKey('pace-gel-clear-${gel.name}'),
                    onPressed: () => _deleteCustomGel(gel),
                    child: const Text(AppStrings.paceGelClear),
                  ),
                ),
              OutlinedButton.icon(
                key: const ValueKey('pace-gel-add-custom'),
                onPressed: _addCustomGel,
                icon: const Icon(Icons.add, size: 18),
                label: const Text(AppStrings.paceGelAddCustom),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(AppStrings.cancel),
        ),
        FilledButton(
          key: const ValueKey('pace-gel-settings-save'),
          onPressed: _save,
          child: const Text(AppStrings.save),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }

  Widget _nutrientField({
    required String key,
    required TextEditingController controller,
    required GelNutrientSpec label,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TextField(
        key: ValueKey(key),
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        decoration: InputDecoration(
          labelText: '${label.label}, ${label.unit}',
          isDense: true,
        ),
      ),
    );
  }

  String _customGelSummary(CustomGel gel) {
    final parts = <String>[];
    for (final nutrient in gel.nutrients) {
      final amount = parseGelNumber(nutrient.amount);
      if (amount == null || amount <= 0) continue;
      parts.add(
        '${nutrient.label} ${formatGelAmount(amount)} ${nutrient.unit}',
      );
    }
    return parts.join(' · ');
  }
}

/// Редактор своего геля: название, известные вещества и собственные поля.
class CustomGelEditorDialog extends StatefulWidget {
  const CustomGelEditorDialog({super.key, required this.existingNames});

  final List<String> existingNames;

  @override
  State<CustomGelEditorDialog> createState() => _CustomGelEditorDialogState();
}

class _CustomGelEditorDialogState extends State<CustomGelEditorDialog> {
  late final TextEditingController _name;
  late final Map<String, bool> _checked;
  late final Map<String, TextEditingController> _amounts;
  final List<_CustomNutrientInput> _custom = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _checked = {for (final nutrient in GelNutrients.known) nutrient.id: false};
    _amounts = {
      for (final nutrient in GelNutrients.known)
        nutrient.id: TextEditingController(),
    };
  }

  @override
  void dispose() {
    _name.dispose();
    for (final controller in _amounts.values) {
      controller.dispose();
    }
    for (final input in _custom) {
      input.dispose();
    }
    super.dispose();
  }

  void _addCustomNutrient() {
    setState(() {
      _custom.add(_CustomNutrientInput());
      _error = null;
    });
  }

  void _removeCustomNutrient(int index) {
    setState(() {
      _custom.removeAt(index).dispose();
    });
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = AppStrings.paceGelNameRequired);
      return;
    }
    if (widget.existingNames.any(
      (existing) => existing.toLowerCase() == name.toLowerCase(),
    )) {
      setState(() => _error = AppStrings.paceGelNameExists);
      return;
    }

    final nutrients = <CustomGelNutrient>[];
    for (final nutrient in GelNutrients.known) {
      if (_checked[nutrient.id] != true) continue;
      final amount = _amounts[nutrient.id]!.text.trim();
      final parsed = parseGelNumber(amount);
      if (parsed == null || parsed <= 0) continue;
      nutrients.add(
        CustomGelNutrient(
          id: nutrient.id,
          label: nutrient.label,
          unit: nutrient.unit,
          amount: amount,
        ),
      );
    }

    for (final input in _custom) {
      final label = input.label.text.trim();
      final unit = input.unit.text.trim();
      final amount = input.amount.text.trim();
      final parsed = parseGelNumber(amount);
      if (label.isEmpty || unit.isEmpty || parsed == null || parsed <= 0) {
        continue;
      }
      nutrients.add(
        CustomGelNutrient(
          id: 'custom:${label.toLowerCase()}|${unit.toLowerCase()}',
          label: label,
          unit: unit,
          amount: amount,
        ),
      );
    }

    if (nutrients.isEmpty) {
      setState(() => _error = AppStrings.paceGelParameterRequired);
      return;
    }

    Navigator.pop(context, CustomGel(name: name, nutrients: nutrients));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.paceGelNewTitle),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('pace-gel-name'),
                controller: _name,
                decoration: const InputDecoration(
                  labelText: AppStrings.paceGelName,
                ),
              ),
              const SizedBox(height: 10),
              for (final nutrient in GelNutrients.known)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Checkbox(
                        key: ValueKey('pace-gel-check-${nutrient.id}'),
                        value: _checked[nutrient.id] ?? false,
                        onChanged: (value) {
                          setState(() {
                            _checked[nutrient.id] = value ?? false;
                            _error = null;
                          });
                        },
                      ),
                      Expanded(
                        child: Text(
                          '${nutrient.label}, ${nutrient.unit}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          key: ValueKey('pace-gel-amount-${nutrient.id}'),
                          controller: _amounts[nutrient.id],
                          enabled: _checked[nutrient.id] == true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                          decoration: const InputDecoration(isDense: true),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 20),
              Text(
                AppStrings.paceGelOwnNutrient,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              for (var index = 0; index < _custom.length; index++)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          key: ValueKey('pace-gel-custom-name-$index'),
                          controller: _custom[index].label,
                          decoration: const InputDecoration(
                            labelText: AppStrings.paceGelName,
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          key: ValueKey('pace-gel-custom-unit-$index'),
                          controller: _custom[index].unit,
                          decoration: const InputDecoration(
                            labelText: AppStrings.paceGelUnit,
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          key: ValueKey('pace-gel-custom-amount-$index'),
                          controller: _custom[index].amount,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: AppStrings.paceGelAmount,
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        key: ValueKey('pace-gel-custom-remove-$index'),
                        tooltip: AppStrings.paceGelRemoveNutrient,
                        onPressed: () => _removeCustomNutrient(index),
                        icon: const Icon(Icons.delete_outline, size: 18),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('pace-gel-add-nutrient'),
                  onPressed: _addCustomNutrient,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(AppStrings.paceGelAddNutrient),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(AppStrings.cancel),
        ),
        FilledButton(
          key: const ValueKey('pace-gel-custom-save'),
          onPressed: _save,
          child: const Text(AppStrings.add),
        ),
      ],
    );
  }
}

class _CustomNutrientInput {
  final TextEditingController label = TextEditingController();
  final TextEditingController unit = TextEditingController();
  final TextEditingController amount = TextEditingController();

  void dispose() {
    label.dispose();
    unit.dispose();
    amount.dispose();
  }
}

/// Результат выбора пунктов для одной строки таблицы.
class GelSelectionResult {
  const GelSelectionResult({required this.selected, required this.other});

  final List<String> selected;
  final String other;
}

/// Диалог с чекбоксами для левого или правого поля строки.
Future<GelSelectionResult?> showGelSelectionDialog(
  BuildContext context, {
  required String title,
  required List<GelOption> options,
  required Iterable<String> selected,
  required String otherText,
}) {
  return showDialog<GelSelectionResult>(
    context: context,
    builder: (dialogContext) => _GelSelectionDialog(
      title: title,
      options: options,
      selected: selected.toSet(),
      otherText: otherText,
    ),
  );
}

class _GelSelectionDialog extends StatefulWidget {
  const _GelSelectionDialog({
    required this.title,
    required this.options,
    required this.selected,
    required this.otherText,
  });

  final String title;
  final List<GelOption> options;
  final Set<String> selected;
  final String otherText;

  @override
  State<_GelSelectionDialog> createState() => _GelSelectionDialogState();
}

class _GelSelectionDialogState extends State<_GelSelectionDialog> {
  late final Set<String> _selected;
  late final TextEditingController _other;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.of(widget.selected);
    _other = TextEditingController(text: widget.otherText);
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  void _save() {
    final selected = <String>[];
    for (final option in widget.options) {
      if (_selected.contains(option.key)) selected.add(option.key);
    }
    if (selected.any((key) => !widget.options.any((o) => o.key == key))) {
      setState(() => _error = AppStrings.paceGelUnknownOption);
      return;
    }
    Navigator.pop(
      context,
      GelSelectionResult(selected: selected, other: _other.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final option in widget.options) ...[
                CheckboxListTile(
                  key: ValueKey('gel-select-${option.key}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _selected.contains(option.key),
                  title: Text(option.label),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selected.add(option.key);
                      } else {
                        _selected.remove(option.key);
                      }
                      _error = null;
                    });
                  },
                ),
                if (option.key == PaceGelTokens.other &&
                    _selected.contains(PaceGelTokens.other))
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 6),
                    child: TextField(
                      key: const ValueKey('gel-select-other-text'),
                      controller: _other,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: AppStrings.paceGelNote,
                        isDense: true,
                      ),
                    ),
                  ),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('gel-select-clear'),
          onPressed: () => setState(() {
            _selected.clear();
            _other.clear();
          }),
          child: const Text(AppStrings.reset),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(AppStrings.cancel),
        ),
        FilledButton(
          key: const ValueKey('gel-select-save'),
          onPressed: _save,
          child: const Text(AppStrings.ok),
        ),
      ],
    );
  }
}
