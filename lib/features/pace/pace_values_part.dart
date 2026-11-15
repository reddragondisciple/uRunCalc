part of 'pace_view.dart';

extension _PaceValuesPart on _PaceViewState {
  String get _eventLabel => _controller.eventLabel;

  double? get _distanceValue => parseDecimal(_distance);

  double? get _splitDistanceValue => parseDecimal(_splitDistance);

  /// Сплит в процентах. Пустое поле — 0%.
  double? get _splitPercentValue {
    final raw = _splitPercent.trim().replaceAll(',', '.');
    if (raw.isEmpty || raw == '-' || raw == '+') return 0;
    return double.tryParse(raw);
  }

  /// Поле всегда показывает знак и `%`: `+5%`, `-3%`, пустое — подсказку.
  String _splitPercentText() {
    if (_splitPercent.isEmpty) return '';
    final negative = _splitPercent.startsWith('-');
    final body = negative ? _splitPercent.substring(1) : _splitPercent;
    return '${negative ? '-' : '+'}$body%';
  }

  /// Время старта в минутах от полуночи. Пустые поля означают 00:00.
  int get _startTimeMinutes =>
      (int.tryParse(_startHours.trim()) ?? 0) * 60 +
      (int.tryParse(_startMinutes.trim()) ?? 0);

  int? get _paceValue {
    if (_paceMinutes.trim().isEmpty && _paceSeconds.trim().isEmpty) {
      return null;
    }
    final minutes = int.tryParse(_paceMinutes.trim()) ?? 0;
    final seconds = int.tryParse(_paceSeconds.trim()) ?? 0;
    return minutes * 60 + seconds;
  }

  int? get _timeValue {
    return parseDurationParts([_days, _hours, _minutes, _seconds]);
  }

  int? get _computedPace {
    final distance = _distanceValue;
    final time = _timeValue;
    if (distance == null || time == null || distance <= 0) return null;
    return (time / distance).round();
  }

  double? get _computedDistance {
    final time = _timeValue;
    final pace = _paceValue;
    if (time == null || pace == null || pace <= 0) return null;
    return time / pace;
  }

  int? get _computedTime {
    final distance = _distanceValue;
    final pace = _paceValue;
    if (distance == null || pace == null || distance <= 0) return null;
    return (distance * pace).round();
  }

  /// Действующее расстояние для раскладки: введённое или вычисленное.
  double? get _effectiveDistance => switch (_calc) {
    _PaceCalc.distance => _computedDistance,
    _PaceCalc.pace || _PaceCalc.time => _distanceValue,
  };

  /// Действующий темп для раскладки: введённый или вычисленный.
  int? get _effectivePace => switch (_calc) {
    _PaceCalc.pace => _computedPace,
    _PaceCalc.distance || _PaceCalc.time => _paceValue,
  };

  /// Действующее время для раскладки: введённое или вычисленное.
  int? get _effectiveTime => switch (_calc) {
    _PaceCalc.time => _computedTime,
    _PaceCalc.pace || _PaceCalc.distance => _timeValue,
  };

  bool _isPaceField(_PaceTopField field) {
    return field == _PaceTopField.paceMinutes ||
        field == _PaceTopField.paceSeconds;
  }

  bool _isTimeField(_PaceTopField field) {
    return field == _PaceTopField.days ||
        field == _PaceTopField.hours ||
        field == _PaceTopField.minutes ||
        field == _PaceTopField.seconds;
  }

  bool _isTopEditable(_PaceTopField field) {
    final isSplitField =
        field == _PaceTopField.splitDistance ||
        field == _PaceTopField.splitPercent ||
        field == _PaceTopField.startHours ||
        field == _PaceTopField.startMinutes ||
        field == _PaceTopField.gelMinutes ||
        field == _PaceTopField.gelKm;
    return switch (_calc) {
      _PaceCalc.pace =>
        field == _PaceTopField.distance || _isTimeField(field) || isSplitField,
      _PaceCalc.distance =>
        _isPaceField(field) || _isTimeField(field) || isSplitField,
      _PaceCalc.time =>
        field == _PaceTopField.distance || _isPaceField(field) || isSplitField,
    };
  }

  bool _isTopFocused(_PaceTopField field) {
    return _focus.kind == _PaceFocusKind.top && _focus.field == field;
  }

  void _selectCalc(_PaceCalc calc) {
    _update(() {
      _calc = calc;
      _focus = switch (calc) {
        _PaceCalc.pace => const _PaceFocus.top(_PaceTopField.distance),
        _PaceCalc.distance => const _PaceFocus.top(_PaceTopField.paceMinutes),
        _PaceCalc.time => const _PaceFocus.top(_PaceTopField.distance),
      };
    });
  }

  void _focusTop(_PaceTopField field) {
    if (!_isTopEditable(field)) return;
    _update(() {
      _focus = _PaceFocus.top(field);
      _keyboardVisible = true;
    });
    _ensureFocusVisible();
  }

  String _topTimeValue(_PaceTopField field) {
    return switch (field) {
      _PaceTopField.days => _days,
      _PaceTopField.hours => _hours,
      _PaceTopField.minutes => _minutes,
      _PaceTopField.seconds => _seconds,
      _ => '',
    };
  }

  void _setTopTimeValue(_PaceTopField field, String value) {
    switch (field) {
      case _PaceTopField.days:
        _days = value;
      case _PaceTopField.hours:
        _hours = value;
      case _PaceTopField.minutes:
        _minutes = value;
      case _PaceTopField.seconds:
        _seconds = value;
      default:
        break;
    }
  }

  String _topPaceMinutes() {
    if (_calc == _PaceCalc.pace) {
      final pace = _computedPace;
      return pace == null ? '—' : '${pace ~/ 60}';
    }
    return _paceMinutes;
  }

  String _topPaceSeconds() {
    if (_calc == _PaceCalc.pace) {
      final pace = _computedPace;
      return pace == null ? '' : '${pace % 60}'.padLeft(2, '0');
    }
    return _paceSeconds;
  }

  String _topDistance() {
    if (_calc == _PaceCalc.distance) {
      final distance = _computedDistance;
      return distance == null ? '—' : distance.toStringAsFixed(2);
    }
    return _distance;
  }

  String _topTimePart(_PaceTopField field) {
    if (_calc != _PaceCalc.time) return _topTimeValue(field);

    final time = _computedTime;
    if (time == null) return field == _PaceTopField.days ? '—' : '';

    final parts = splitSeconds(time);
    return switch (field) {
      _PaceTopField.days => '${parts.days}',
      _PaceTopField.hours => '${parts.hours}'.padLeft(2, '0'),
      _PaceTopField.minutes => '${parts.minutes}'.padLeft(2, '0'),
      _PaceTopField.seconds => '${parts.seconds}'.padLeft(2, '0'),
      _ => '',
    };
  }

  String _timeBufferText(String buffer) => PaceTableCalculator.timeText(buffer);

  int? _parseTimeBuffer(String buffer) => PaceTableCalculator.parseTime(buffer);

  String _paceBufferText(String buffer) => PaceTableCalculator.paceText(buffer);

  int? _parsePaceBuffer(String buffer) => PaceTableCalculator.parsePace(buffer);

  String _paceBufferFromSeconds(int totalSeconds) =>
      PaceTableCalculator.paceBufferFromSeconds(totalSeconds);

  String _timeBufferFromMinutes(int totalMinutes) =>
      PaceTableCalculator.timeBufferFromMinutes(totalMinutes);

  String _columnLabel(int index) {
    if (index == 0) return 'Start';
    if (index == _columns - 1) return 'Finish';
    return '$index';
  }

  String _tableTimeText(int column) {
    return _timeBufferText(_tableTimes[column]);
  }

  String _tableDistanceText(int column) {
    if (column == 0) return 'KM';
    final focused =
        _focus.kind == _PaceFocusKind.tableDistance &&
        _focus.tableColumn == column;
    if (focused) return _tableDistances[column];
    return _formatDistanceInput(_tableDistances[column]);
  }

  /// Показывает столько знаков после запятой, сколько ввёл пользователь:
  /// целые значения остаются целыми, `20.3` — с одной десятой, `20.35` — с
  /// двумя.
  String _formatDistanceInput(String raw) =>
      PaceTableCalculator.formatDistance(raw);

  String _planTimeText(int column) {
    return _timeBufferText(_planTimes[column]);
  }

  String _planPaceText(int column) {
    if (column == 0) return 'PACE';
    final focused =
        _focus.kind == _PaceFocusKind.tablePlanPace &&
        _focus.tableColumn == column;
    if (focused) return _paceBufferText(_planPaces[column]);
    if (_planPaces[column].isNotEmpty) {
      return _paceBufferText(_planPaces[column]);
    }

    final pace = _plannedPace(column);
    return pace == null ? '0:00' : formatPaceSeconds(pace);
  }

  /// Определяет цвет текста для ячейки таблицы Ultra.
  /// Ряды ПП, Лимит и Расстояние (индексы 0-2) используют тот же цвет, что и
  /// итоговые подписи «Общее время» / «Темп в лимит».
  /// План и ниже (индексы 6-9): белый.
  Color? _cellTextColor(int rowIndex, {bool isPlanRow = false}) {
    if (rowIndex <= 2) {
      return AppColors.result;
    }
    if (isPlanRow || rowIndex >= 6) {
      return Colors.white;
    }
    return null;
  }

  int? _segmentPace(int index) => PaceTableCalculator.segmentPace(
    times: _tableTimes,
    distances: _tableDistances,
    index: index,
  );

  int? _plannedPace(int column) => PaceTableCalculator.plannedPace(
    planTimes: _planTimes,
    distances: _tableDistances,
    column: column,
  );

  int? get _overallPaceSeconds => _overallPaceFor(_tableTimes);

  int? _overallPaceFor(List<String> times) => PaceTableCalculator.overallPace(
    times: times,
    distances: _tableDistances,
    columns: _columns,
  );

  Color? _paceHighlight(int column, List<int?> paces) {
    return switch (PaceTableCalculator.paceHighlight(
      column: column,
      paces: paces,
    )) {
      PaceHighlight.fastest => AppColors.danger,
      PaceHighlight.secondFastest => AppColors.secondary,
      PaceHighlight.none => null,
    };
  }

  List<int> _computeDays(List<String> times) =>
      PaceTableCalculator.computeDays(times, columns: _columns);

  Color? _limitTimeHighlight(int column) {
    return _statusFor(column) == PlanTimeStatus.behindLimit
        ? AppColors.danger
        : null;
  }

  Color? _planTimeHighlight(int column) {
    return switch (_statusFor(column)) {
      PlanTimeStatus.behindLimit => AppColors.danger,
      PlanTimeStatus.closeToLimit => AppColors.warning,
      PlanTimeStatus.normal => null,
    };
  }

  PlanTimeStatus _statusFor(int column) {
    if (column < 0 || column >= _planStatuses.length) {
      return PlanTimeStatus.normal;
    }
    return _planStatuses[column];
  }

  /// Пересчитывает дни только по завершении ввода: при смене поля,
  /// нажатии «ОК», закрытии клавиатуры или тапе вне полей ввода.
  void _commitDays() {
    if (!_isUltra) return;
    final limitDays = _computeDays(_tableTimes);
    final planDays = _computeDays(_planTimes);
    if (listEquals(limitDays, _limitDays) && listEquals(planDays, _planDays)) {
      return;
    }
    _update(() {
      _limitDays = limitDays;
      _planDays = planDays;
    });
  }

  Color? _dayBorderColor(int column, List<int> days) {
    if (column < 0 || column >= days.length) return null;
    final day = days[column];
    if (day <= 0) return null;
    return _PaceViewState._dayColors[(day - 1) %
        _PaceViewState._dayColors.length];
  }

  int? get _totalLimitMinutes =>
      PaceTableCalculator.elapsedMinutes(_tableTimes, columns: _columns);

  double? get _totalTableDistance {
    if (_tableDistances.isEmpty) return null;
    final start = parseDecimal(_tableDistances[0]);
    double? end;
    for (var index = 1; index < _columns; index++) {
      final distance = parseDecimal(_tableDistances[index]);
      if (distance != null) end = distance;
    }
    if (start == null || end == null) return null;
    final delta = end - start;
    return delta > 0 ? delta : null;
  }

  int? get _planStartMinutes {
    final plan = _parseTimeBuffer(_planTimes[0]);
    if (plan != null) return plan;
    return _parseTimeBuffer(_tableTimes[0]);
  }

  int? get _overallPlannedPaceSeconds {
    switch (_plannedSummarySource) {
      case PacePlannedSummarySource.pace:
        return _parsePaceBuffer(_plannedPaceOverride) ??
            _overallPaceFor(_planTimes);
      case PacePlannedSummarySource.time:
        final duration = _parseTimeBuffer(_plannedTimeOverride);
        final distance = _totalTableDistance;
        if (duration == null || distance == null || distance <= 0) {
          return _overallPaceFor(_planTimes);
        }
        return (duration * 60 / distance).round();
      case PacePlannedSummarySource.none:
        return _overallPaceFor(_planTimes);
    }
  }

  /// Итоговое плановое время — это длительность от планового старта до
  /// планового финиша, а не время суток финиша.
  int? get _overallPlannedFinishMinutes {
    switch (_plannedSummarySource) {
      case PacePlannedSummarySource.pace:
        final pace = _parsePaceBuffer(_plannedPaceOverride);
        final distance = _totalTableDistance;
        if (pace == null || distance == null || distance <= 0) {
          return _plannedDurationFromPlan;
        }
        return (pace * distance / 60).round();
      case PacePlannedSummarySource.time:
        return _parseTimeBuffer(_plannedTimeOverride) ??
            _plannedDurationFromPlan;
      case PacePlannedSummarySource.none:
        return _plannedDurationFromPlan;
    }
  }

  int? get _plannedDurationFromPlan {
    final start = _parseTimeBuffer(_planTimes[0]);
    if (start == null) return null;

    var total = 0;
    var previous = start;
    var found = false;
    for (var index = 1; index < _columns; index++) {
      final time = _parseTimeBuffer(_planTimes[index]);
      if (time == null) continue;

      var delta = time - previous;
      if (delta < 0) delta += 24 * 60;
      total += delta;
      previous = time;
      found = true;
    }
    return found ? total : null;
  }
}
