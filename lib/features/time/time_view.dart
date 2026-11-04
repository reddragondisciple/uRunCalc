part of '../../main.dart';

enum _TimeTab { difference, addSubtract, converter }

enum _TimeField { date, days, hours, minutes, seconds }

class _TimeFocus {
  const _TimeFocus(this.group, this.field);

  final int group;
  final _TimeField field;
}

class _TimeView extends StatefulWidget {
  const _TimeView();

  @override
  State<_TimeView> createState() => _TimeViewState();
}

class _TimeViewState extends State<_TimeView> {
  _TimeTab _tab = _TimeTab.difference;
  bool _subtract = false;
  _TimeFocus _focus = const _TimeFocus(0, _TimeField.date);

  final List<Map<_TimeField, String>> _values = List.generate(
    3,
    (_) => {for (final field in _TimeField.values) field: ''},
  );

  String _raw(int group, _TimeField field) => _values[group][field] ?? '';

  String _dateText(String buffer) => TimeCalculator.dateInputText(buffer);

  String _formatDate(DateTime date) => TimeCalculator.formatDate(date);

  DateTime? _dateTimeFor(int group) {
    return TimeCalculator.dateTime(
      date: _raw(group, _TimeField.date),
      hours: _raw(group, _TimeField.hours),
      minutes: _raw(group, _TimeField.minutes),
    );
  }

  int? _durationSeconds(int group) {
    return TimeCalculator.durationSeconds(
      days: _raw(group, _TimeField.days),
      hours: _raw(group, _TimeField.hours),
      minutes: _raw(group, _TimeField.minutes),
      seconds: _raw(group, _TimeField.seconds),
    );
  }

  int? get _differenceSeconds {
    if (_tab != _TimeTab.difference) return null;

    final start = _dateTimeFor(0);
    final end = _dateTimeFor(1);
    if (start == null || end == null) return null;
    return end.difference(start).inSeconds;
  }

  DateTime? get _resultDateTime {
    if (_tab != _TimeTab.addSubtract) return null;

    final base = _dateTimeFor(0);
    final duration = _durationSeconds(1);
    if (base == null || duration == null) return null;

    return TimeCalculator.shifted(
      base: base,
      seconds: duration,
      subtract: _subtract,
    );
  }

  int? get _converterSeconds => _durationSeconds(0);

  bool get _resultNegative =>
      _tab == _TimeTab.difference && (_differenceSeconds ?? 0) < 0;

  bool _isFieldEditable(int group, _TimeField field) {
    return switch (_tab) {
      _TimeTab.difference =>
        (group == 0 || group == 1) &&
            (field == _TimeField.date ||
                field == _TimeField.hours ||
                field == _TimeField.minutes),
      _TimeTab.addSubtract =>
        group == 0
            ? (field == _TimeField.date ||
                  field == _TimeField.hours ||
                  field == _TimeField.minutes)
            : group == 1 &&
                  (field == _TimeField.days ||
                      field == _TimeField.hours ||
                      field == _TimeField.minutes ||
                      field == _TimeField.seconds),
      _TimeTab.converter =>
        group == 0 &&
            (field == _TimeField.days ||
                field == _TimeField.hours ||
                field == _TimeField.minutes ||
                field == _TimeField.seconds),
    };
  }

  bool _isFocused(int group, _TimeField field) {
    return _focus.group == group && _focus.field == field;
  }

  void _focusField(int group, _TimeField field) {
    if (!_isFieldEditable(group, field)) return;
    setState(() {
      _focus = _TimeFocus(group, field);
    });
  }

  void _selectTab(_TimeTab tab) {
    setState(() {
      _tab = tab;
      _focus = switch (tab) {
        _TimeTab.difference => const _TimeFocus(0, _TimeField.date),
        _TimeTab.addSubtract => const _TimeFocus(0, _TimeField.date),
        _TimeTab.converter => const _TimeFocus(0, _TimeField.days),
      };
    });
  }

  String _valueFor(int group, _TimeField field) {
    if (group == 2) {
      if (_tab == _TimeTab.difference) {
        final seconds = _differenceSeconds?.abs();
        if (seconds == null) {
          return field == _TimeField.days ? '—' : '';
        }

        final split = splitSeconds(seconds);
        return switch (field) {
          _TimeField.days => '${split.days}',
          _TimeField.hours => '${split.hours}'.padLeft(2, '0'),
          _TimeField.minutes => '${split.minutes}'.padLeft(2, '0'),
          _TimeField.seconds => '${split.seconds}'.padLeft(2, '0'),
          _TimeField.date => '',
        };
      }

      if (_tab == _TimeTab.addSubtract) {
        final result = _resultDateTime;
        if (result == null) {
          return field == _TimeField.date ? '—' : '';
        }

        return switch (field) {
          _TimeField.date => _formatDate(result),
          _TimeField.hours => result.hour.toString().padLeft(2, '0'),
          _TimeField.minutes => result.minute.toString().padLeft(2, '0'),
          _TimeField.seconds => result.second.toString().padLeft(2, '0'),
          _TimeField.days => '',
        };
      }
    }

    final raw = _raw(group, field);
    if (field == _TimeField.date) return _dateText(raw);
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTabs(),
                const SizedBox(height: 10),
                ..._buildTabContent(),
              ],
            ),
          ),
        ),
        _buildKeyboard(),
      ],
    );
  }

  Widget _buildTabs() {
    return Row(
      children: [
        _tabButton(
          AppStrings.timeTabDifference,
          _TimeTab.difference,
          'time-tab-difference',
        ),
        const SizedBox(width: 4),
        _tabButton(
          AppStrings.timeTabAddSubtract,
          _TimeTab.addSubtract,
          'time-tab-add',
        ),
        const SizedBox(width: 4),
        _tabButton(
          AppStrings.timeTabConverter,
          _TimeTab.converter,
          'time-tab-converter',
        ),
      ],
    );
  }

  Widget _tabButton(String label, _TimeTab value, String key) {
    final selected = _tab == value;

    return Expanded(
      child: InkWell(
        key: ValueKey(key),
        onTap: () => _selectTab(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.background,
            border: Border.all(
              color: selected ? AppColors.accent : Colors.grey.shade700,
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.background : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTabContent() {
    return switch (_tab) {
      _TimeTab.difference => [
        _dateTimeGroup(0, AppStrings.timeStart),
        const SizedBox(height: 10),
        _dateTimeGroup(1, AppStrings.timeEnd),
        const SizedBox(height: 10),
        _resultDurationRow(AppStrings.timeTabDifference),
      ],
      _TimeTab.addSubtract => [
        _dateTimeGroup(0, AppStrings.timeDateTime),
        const SizedBox(height: 10),
        _buildOperationToggle(),
        const SizedBox(height: 10),
        _durationRow(1, AppStrings.timeDuration),
        const SizedBox(height: 10),
        _resultDateTimeRow(AppStrings.timeResult),
      ],
      _TimeTab.converter => [
        _durationRow(0, AppStrings.timeTime),
        const SizedBox(height: 12),
        _buildConverterOutput(),
      ],
    };
  }

  Widget _buildOperationToggle() {
    return Row(
      children: [
        _operationButton('+', false, 'time-op-add'),
        const SizedBox(width: 4),
        _operationButton('−', true, 'time-op-sub'),
      ],
    );
  }

  Widget _operationButton(String label, bool subtract, String key) {
    final selected = _subtract == subtract;

    return Expanded(
      child: InkWell(
        key: ValueKey(key),
        onTap: () {
          setState(() {
            _subtract = subtract;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.background,
            border: Border.all(
              color: selected ? AppColors.accent : Colors.grey.shade700,
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.background : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateTimeGroup(int group, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(
                label,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            Expanded(child: _timeField(group, _TimeField.date)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(
              width: 76,
              child: Text(
                AppStrings.timeTime,
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ),
            Expanded(child: _timeField(group, _TimeField.hours)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                ':',
                style: TextStyle(color: Colors.grey, fontSize: 18),
              ),
            ),
            Expanded(child: _timeField(group, _TimeField.minutes)),
          ],
        ),
      ],
    );
  }

  Widget _durationRow(int group, String label) {
    const parts = [
      _TimeField.days,
      _TimeField.hours,
      _TimeField.minutes,
      _TimeField.seconds,
    ];
    const partLabels = [
      AppStrings.timeDays,
      AppStrings.timeHours,
      AppStrings.timeMinutes,
      AppStrings.timeSeconds,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(width: 76),
            for (final partLabel in partLabels)
              Expanded(
                child: Text(
                  partLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(
                label,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            for (final part in parts)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: _timeField(group, part),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _resultDurationRow(String label) {
    const parts = [
      _TimeField.days,
      _TimeField.hours,
      _TimeField.minutes,
      _TimeField.seconds,
    ];
    const partLabels = [
      AppStrings.timeDays,
      AppStrings.timeHours,
      AppStrings.timeMinutes,
      AppStrings.timeSeconds,
    ];
    final negative = _resultNegative;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(width: 76),
            for (final partLabel in partLabels)
              Expanded(
                child: Text(
                  partLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(
                negative ? '− $label' : label,
                style: const TextStyle(color: AppColors.result, fontSize: 13),
              ),
            ),
            for (final part in parts)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: _timeField(2, part, result: true),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _resultDateTimeRow(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(
                label,
                style: const TextStyle(color: AppColors.result, fontSize: 13),
              ),
            ),
            Expanded(child: _timeField(2, _TimeField.date, result: true)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(
              width: 76,
              child: Text(
                AppStrings.timeTime,
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ),
            Expanded(child: _timeField(2, _TimeField.hours, result: true)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                ':',
                style: TextStyle(color: Colors.grey, fontSize: 18),
              ),
            ),
            Expanded(child: _timeField(2, _TimeField.minutes, result: true)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                ':',
                style: TextStyle(color: Colors.grey, fontSize: 18),
              ),
            ),
            Expanded(child: _timeField(2, _TimeField.seconds, result: true)),
          ],
        ),
      ],
    );
  }

  Widget _timeField(int group, _TimeField field, {bool result = false}) {
    final editable = !result && _isFieldEditable(group, field);
    final focused = _isFocused(group, field);
    final text = _valueFor(group, field);
    final placeholder =
        !result && _raw(group, field).isEmpty && field != _TimeField.date;

    return InkWell(
      key: ValueKey('time-$group-${field.name}'),
      onTap: editable ? () => _focusField(group, field) : null,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: editable ? AppColors.background : AppColors.surfaceRaised,
          border: Border.all(
            color: focused
                ? AppColors.focus
                : editable
                ? Colors.grey.shade700
                : const Color(0x66FF9800),
            width: focused ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            style: TextStyle(
              color: editable
                  ? (placeholder ? Colors.grey : Colors.white)
                  : AppColors.result,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConverterOutput() {
    final seconds = _converterSeconds;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade800),
        borderRadius: BorderRadius.circular(8),
      ),
      child: seconds == null
          ? const Text(
              AppStrings.timeEnterTime,
              style: TextStyle(color: Colors.grey, fontSize: 14),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _converterLine(AppStrings.timeTotalDays, seconds / 86400, ''),
                _converterLine(AppStrings.timeTotalHours, seconds / 3600, ''),
                _converterLine(AppStrings.timeTotalMinutes, seconds / 60, ''),
                _converterLine(
                  AppStrings.timeTotalSeconds,
                  seconds.toDouble(),
                  '',
                ),
              ],
            ),
    );
  }

  Widget _converterLine(String label, double value, String suffix) {
    final text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Text(
            '$text$suffix',
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyboard() {
    return Container(
      height: 184,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      color: AppColors.surface,
      child: Column(
        children: [
          _keyRow(['1', '2', '3']),
          _keyRow(['4', '5', '6']),
          _keyRow(['7', '8', '9']),
          _keyRow(['⌫', '0', '00']),
        ],
      ),
    );
  }

  Widget _keyRow(List<String> keys) {
    return Expanded(
      child: Row(
        children: [for (final key in keys) Expanded(child: _padKey(key))],
      ),
    );
  }

  Widget _padKey(String key) {
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: Semantics(
        button: true,
        label: semanticKeyLabel(key),
        hint: key == '⌫' ? AppStrings.longPressClear : null,
        onTap: () => _onPadKey(key),
        onLongPress: key == '⌫' ? _clearActive : null,
        excludeSemantics: true,
        child: Material(
          color: AppColors.background,
          child: InkWell(
            key: ValueKey('time-key-$key'),
            onTap: () => _onPadKey(key),
            onLongPress: key == '⌫' ? _clearActive : null,
            child: Center(
              child: Text(
                key,
                style: const TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onPadKey(String key) {
    if (key == '⌫') {
      _backspaceActive();
      return;
    }

    for (final char in key.split('')) {
      _appendActive(char);
    }
  }

  void _appendActive(String char) {
    if (!_isFieldEditable(_focus.group, _focus.field)) return;

    setState(() {
      final field = _focus.field;
      final group = _focus.group;
      final current = _raw(group, field);

      if (field == _TimeField.date) {
        if (!_isDigitChar(char) || current.length >= 8) return;
        _values[group][field] = '$current$char';
        return;
      }

      // Длина полей не ограничена: допускаются значения вроде 1000 минут
      // или 500 часов.
      if (!_isDigitChar(char)) return;

      _values[group][field] = '$current$char';
    });
  }

  void _backspaceActive() {
    if (!_isFieldEditable(_focus.group, _focus.field)) return;

    setState(() {
      final current = _raw(_focus.group, _focus.field);
      if (current.isEmpty) return;
      _values[_focus.group][_focus.field] = current.substring(
        0,
        current.length - 1,
      );
    });
  }

  void _clearActive() {
    if (!_isFieldEditable(_focus.group, _focus.field)) return;

    setState(() {
      _values[_focus.group][_focus.field] = '';
    });
  }

  bool _isDigitChar(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }
}

final RegExp _exactValuePattern = RegExp(r'@(-?\d+):(\d+);');
final RegExp _numberPattern = RegExp(r'\d+(?:\.\d*)?|\.\d+');
final RegExp _digitGroupPattern = RegExp(r'\B(?=(\d{3})+(?!\d))');

/// Текстовая версия выражения: дроби записываются как a/b, числа группируются.
String _displayText(String value) {
  var text = value.replaceAllMapped(_exactValuePattern, (match) {
    final numerator = BigInt.parse(match.group(1)!);
    final denominator = BigInt.parse(match.group(2)!);
    final rational = Rational(numerator, denominator);

    if (rational.isDisplayableFraction) {
      return rational.toFractionString();
    }

    return rational.toDisplayString();
  });

  text = text.replaceAll('sqrt(', '√(');
  text = text.replaceAll('inv(', '1/(');
  text = text.replaceAll('*', '×');
  text = text.replaceAll('-', '−');

  return _groupDigits(text);
}

String _groupDigits(String text) {
  return text.replaceAllMapped(_numberPattern, (match) {
    final number = match.group(0)!;
    final dotIndex = number.indexOf('.');
    final integerPart = dotIndex == -1 ? number : number.substring(0, dotIndex);
    final decimalPart = dotIndex == -1 ? '' : number.substring(dotIndex);

    final groupedInteger = integerPart.replaceAllMapped(
      _digitGroupPattern,
      (_) => '\u2009',
    );

    return '$groupedInteger$decimalPart';
  });
}

String _formatDecimal(String text) {
  final formatted = text.replaceAll('-', '−');
  if (formatted.contains('e')) return formatted;
  return _groupDigits(formatted);
}

String _decimalSymbol(Rational value, bool approximate) {
  if (!value.decimalDisplayIsExact) return '≈';
  if (approximate && !value.isInteger) return '≈';
  return '=';
}

String _historyText(String expression, Rational value, bool approximate) {
  final left = _displayText(expression);
  final decimal = _formatDecimal(value.toDisplayString());
  final symbol = _decimalSymbol(value, approximate);
  final showsFraction = !approximate && value.isDisplayableFraction;

  if (showsFraction) {
    final fraction = value.toFractionString();
    if (left == fraction) {
      return '$left $symbol $decimal';
    }
    if (left == decimal) {
      return '$left = $fraction';
    }
    return '$left = $fraction $symbol $decimal';
  }

  if (value.isInteger && symbol == '=') {
    return '$left = $decimal';
  }

  return '$left $symbol $decimal';
}

/// Экран с информацией о проекте и ссылкой на автора.
