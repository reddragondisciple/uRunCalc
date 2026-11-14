part of 'pace_view.dart';

extension _PaceInputPart on _PaceViewState {
  void _beginTableFocus(_PaceFocus focus) {
    if (_locked) return;
    _finalizePlanEdit();
    _commitDays();
    _update(() {
      _trackPlanEdit(focus);
      _focus = focus;
      _keyboardVisible = true;
    });
    _ensureFocusVisible();
  }

  void _trackPlanEdit(_PaceFocus focus) {
    final isPlanEdit =
        focus.kind == _PaceFocusKind.tablePlanTime ||
        focus.kind == _PaceFocusKind.tablePlanPace;
    _replacePlanInput =
        isPlanEdit ||
        focus.kind == _PaceFocusKind.summaryPlannedPace ||
        focus.kind == _PaceFocusKind.summaryPlannedTime;
    if (!isPlanEdit) {
      _planTimesBeforeEdit = null;
      _planEditColumn = null;
      return;
    }
    _planEditColumn = focus.tableColumn;
    _planTimesBeforeEdit = List<String>.of(_planTimes);
  }

  void _focusTableTime(int column) {
    if (_locked || _lockedLimits) return;
    _beginTableFocus(_PaceFocus.tableTime(column));
  }

  void _focusTableDistance(int column) {
    if (column == 0 || _locked || _lockedLimits) return;
    _beginTableFocus(_PaceFocus.tableDistance(column));
  }

  void _focusPlanTime(int column) {
    if (_locked) return;
    _beginTableFocus(_PaceFocus.tablePlanTime(column));
  }

  void _focusPlanPace(int column) {
    if (column == 0 || _locked) return;
    _beginTableFocus(_PaceFocus.tablePlanPace(column));
  }

  void _focusSummaryPlannedPace() {
    if (_locked) return;
    _beginTableFocus(const _PaceFocus.summaryPlannedPace());
  }

  void _focusSummaryPlannedTime() {
    if (_locked) return;
    _beginTableFocus(const _PaceFocus.summaryPlannedTime());
  }

  Future<void> _commitInput() async {
    final focus = _focus;
    if (focus.kind == _PaceFocusKind.summaryPlannedPace &&
        _plannedSummarySource == PacePlannedSummarySource.none &&
        _plannedPaceOverride.isEmpty) {
      _finishInput();
      return;
    }
    if (focus.kind == _PaceFocusKind.summaryPlannedTime &&
        _plannedSummarySource == PacePlannedSummarySource.none &&
        _plannedTimeOverride.isEmpty) {
      _finishInput();
      return;
    }
    var apply = true;
    switch (focus.kind) {
      case _PaceFocusKind.summaryPlannedTime:
        apply = await _confirmAndApplyPlannedTime();
      case _PaceFocusKind.summaryPlannedPace:
        apply = await _confirmAndApplyPlannedPace();
      default:
        break;
    }
    if (!mounted || !apply) return;
    _finishInput();
  }

  /// Завершает ввод: пересчитывает дни и убирает клавиатуру.
  void _finishInput() {
    _replacePlanInput = false;
    final planChanged = _finalizePlanEdit();
    final distancesChanged = _recomputeMountainPlan();
    _commitDays();
    if (!planChanged &&
        !distancesChanged &&
        !_keyboardVisible &&
        _focus.kind == _PaceFocusKind.none) {
      return;
    }
    _update(() {
      _keyboardVisible = false;
      _focus = const _PaceFocus.none();
    });
  }

  void _hideKeyboard() {
    if (!_isUltra) return;
    _finishInput();
  }

  void _ensureFocusVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureFocusVisibleNow();
    });
  }

  void _ensureFocusVisibleNow() {
    if (!mounted) return;
    final target = _focusAnchorKey.currentContext;
    if (target == null || !target.mounted) return;
    final targetBox = target.findRenderObject();
    if (targetBox is! RenderBox || !targetBox.hasSize) return;

    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final axis = landscape ? Axis.horizontal : Axis.vertical;

    ScrollableState? scrollable;
    target.visitAncestorElements((element) {
      final state = element is StatefulElement ? element.state : null;
      if (state is ScrollableState && state.position.axis == axis) {
        scrollable = state;
        return false;
      }
      return true;
    });
    final state = scrollable;
    if (state == null) return;

    final viewportBox = state.context.findRenderObject();
    if (viewportBox is! RenderBox || !viewportBox.hasSize) return;

    final position = state.position;
    final targetTopLeft = targetBox.localToGlobal(Offset.zero);
    final viewportTopLeft = viewportBox.localToGlobal(Offset.zero);

    double delta;
    if (axis == Axis.vertical) {
      final targetStart = targetTopLeft.dy;
      final targetEnd = targetStart + targetBox.size.height;
      final viewportStart = viewportTopLeft.dy;
      final viewportEnd = viewportStart + viewportBox.size.height;
      if (targetEnd > viewportEnd) {
        delta = targetEnd - viewportEnd;
      } else if (targetStart < viewportStart) {
        delta = targetStart - viewportStart;
      } else {
        return;
      }
    } else {
      final targetStart = targetTopLeft.dx;
      final targetEnd = targetStart + targetBox.size.width;
      final viewportStart = viewportTopLeft.dx;
      final viewportEnd = viewportStart + viewportBox.size.width;
      if (targetEnd > viewportEnd) {
        delta = targetEnd - viewportEnd;
      } else if (targetStart < viewportStart) {
        delta = targetStart - viewportStart;
      } else {
        return;
      }
    }

    position.animateTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  String _appendTimeBuffer(String current, String char) {
    if (char == ':') return current;

    if (!_isDigitChar(char) || current.length >= 4) return current;
    if (current.length == 2 && char.codeUnitAt(0) > 0x35) return current;
    return '$current$char';
  }

  String _appendPaceBuffer(String current, String char) {
    if (char == ':') return current;

    // Темп — это минуты и секунды; минуты могут быть больше 99
    // (например, 100:00), поэтому длина не ограничивается.
    if (!_isDigitChar(char)) return current;
    return '$current$char';
  }

  void _appendTableTime(int column, String char) {
    _update(() {
      _tableTimes[column] = _appendTimeBuffer(_tableTimes[column], char);
    });
  }

  void _appendPlanTime(int column, String char) {
    _update(() {
      if (_replacePlanInput) {
        _planTimes[column] = '';
        _planPaces[column] = '';
        _replacePlanInput = false;
      }
      _planTimes[column] = _appendTimeBuffer(_planTimes[column], char);
      _planPaces[column] = '';
      // Правка старта плана не фиксирует ручную опору: от неё план должен
      // пересчитаться. Ручными считаются только промежуточные прибытия.
      if (column > 0) _markManualAnchor();
      _resetPlannedSummary();
    });
  }

  /// Ввод стоянки: только цифры, до 3 знаков (минуты). Колонка 0 и финиш —
  /// без стоянок (см. `sumIntermediateStops`).
  void _appendStop(int column, String char) {
    if (column <= 0 || column >= _columns - 1) return;
    if (!_isDigitChar(char)) return;
    final current = _stopBufferText(column);
    if (current.length >= 3) return;
    final next = current == '0' ? char : '$current$char';
    _update(() => _setStopMinutes(column, int.parse(next)));
  }

  void _removeStopDigit(int column) {
    if (column <= 0 || column >= _columns - 1) return;
    final current = _stopBufferText(column);
    final rest = current.length <= 1
        ? ''
        : current.substring(0, current.length - 1);
    _update(() => _setStopMinutes(column, rest.isEmpty ? 0 : int.parse(rest)));
  }

  void _appendPlanPace(int column, String char) {
    if (column == 0) return;
    _update(() {
      if (_replacePlanInput) {
        _planPaces[column] = '';
        _replacePlanInput = false;
      }
      _planPaces[column] = _appendPaceBuffer(_planPaces[column], char);
      _applyPlanPace(column);
      _markManualAnchor();
      _resetPlannedSummary();
    });
  }

  void _appendTableDistance(int column, String char) {
    if (column == 0) return;
    _update(() {
      _tableDistances[column] = _appendDecimal(_tableDistances[column], char);
      _resetPlannedSummary();
    });
  }

  void _appendTopField(_PaceTopField field, String char) {
    if (!_isTopEditable(field)) return;

    _update(() {
      switch (field) {
        case _PaceTopField.distance:
          _distance = _appendDecimal(_distance, char, maxDecimals: 3);
        case _PaceTopField.paceMinutes:
          _paceMinutes = _appendInteger(_paceMinutes, char, 3);
        case _PaceTopField.paceSeconds:
          _paceSeconds = _appendInteger(_paceSeconds, char, 2);
        case _PaceTopField.days:
          _days = _appendInteger(_days, char, 3);
        case _PaceTopField.hours:
        case _PaceTopField.minutes:
        case _PaceTopField.seconds:
          _setTopTimeValue(
            field,
            _appendInteger(_topTimeValue(field), char, 2),
          );
        case _PaceTopField.splitDistance:
          _splitDistance = _appendDecimal(_splitDistance, char, maxDecimals: 3);
        case _PaceTopField.splitPercent:
          _splitPercent = _appendSplitPercent(_splitPercent, char);
        case _PaceTopField.startHours:
          _startHours = _appendInteger(_startHours, char, 2);
        case _PaceTopField.startMinutes:
          _startMinutes = _appendInteger(_startMinutes, char, 2);
      }
    });
  }

  String _appendInteger(String current, String char, int maxLength) {
    if (!_isDigitChar(char) || current.length >= maxLength) return current;
    return '$current$char';
  }

  /// Ввод процента сплита. Знак хранится отдельно и не мешает точке.
  String _appendSplitPercent(String current, String char) {
    final negative = current.startsWith('-');
    final body = _appendDecimal(
      negative ? current.substring(1) : current,
      char,
      maxDecimals: 1,
    );
    return negative ? '-$body' : body;
  }

  String _appendDecimal(String current, String char, {int maxDecimals = 2}) {
    if (char == '.') {
      if (current.contains('.')) return current;
      return current.isEmpty ? '0.' : '$current.';
    }

    if (!_isDigitChar(char)) return current;

    final dot = current.indexOf('.');
    if (dot == -1) {
      if (current.length >= 5) return current;
      return '$current$char';
    }

    if (current.length - dot - 1 >= maxDecimals) return current;
    return '$current$char';
  }

  void _appendActive(String char) {
    switch (_focus.kind) {
      case _PaceFocusKind.none:
        break;
      case _PaceFocusKind.top:
        _appendTopField(_focus.field!, char);
      case _PaceFocusKind.tableTime:
        _appendTableTime(_focus.tableColumn, char);
      case _PaceFocusKind.tableDistance:
        _appendTableDistance(_focus.tableColumn, char);
      case _PaceFocusKind.tablePlanTime:
        _appendPlanTime(_focus.tableColumn, char);
      case _PaceFocusKind.tablePlanPace:
        _appendPlanPace(_focus.tableColumn, char);
      case _PaceFocusKind.tableStop:
        _appendStop(_focus.tableColumn, char);
      case _PaceFocusKind.summaryPlannedPace:
        _update(() {
          if (_replacePlanInput) {
            _plannedPaceOverride = '';
            _replacePlanInput = false;
          }
          _plannedPaceOverride = _appendPaceBuffer(_plannedPaceOverride, char);
          _plannedSummarySource = PacePlannedSummarySource.pace;
        });
      case _PaceFocusKind.summaryPlannedTime:
        _update(() {
          if (_replacePlanInput) {
            _plannedTimeOverride = '';
            _replacePlanInput = false;
          }
          _plannedTimeOverride = _appendTimeBuffer(_plannedTimeOverride, char);
          _plannedSummarySource = PacePlannedSummarySource.time;
        });
    }
  }

  void _backspaceActive() {
    _replacePlanInput = false;
    _update(() {
      switch (_focus.kind) {
        case _PaceFocusKind.none:
          break;
        case _PaceFocusKind.top:
          final field = _focus.field!;
          switch (field) {
            case _PaceTopField.distance:
              _distance = _removeLast(_distance);
            case _PaceTopField.paceMinutes:
              _paceMinutes = _removeLast(_paceMinutes);
            case _PaceTopField.paceSeconds:
              _paceSeconds = _removeLast(_paceSeconds);
            case _PaceTopField.days:
            case _PaceTopField.hours:
            case _PaceTopField.minutes:
            case _PaceTopField.seconds:
              _setTopTimeValue(field, _removeLast(_topTimeValue(field)));
            case _PaceTopField.splitDistance:
              _splitDistance = _removeLast(_splitDistance);
            case _PaceTopField.splitPercent:
              _splitPercent = _removeLast(_splitPercent);
            case _PaceTopField.startHours:
              _startHours = _removeLast(_startHours);
            case _PaceTopField.startMinutes:
              _startMinutes = _removeLast(_startMinutes);
          }
        case _PaceFocusKind.tableTime:
          _tableTimes[_focus.tableColumn] = _removeLast(
            _tableTimes[_focus.tableColumn],
          );
        case _PaceFocusKind.tableDistance:
          if (_focus.tableColumn == 0) return;
          _tableDistances[_focus.tableColumn] = _removeLast(
            _tableDistances[_focus.tableColumn],
          );
          _resetPlannedSummary();
        case _PaceFocusKind.tablePlanTime:
          _planTimes[_focus.tableColumn] = _removeLast(
            _planTimes[_focus.tableColumn],
          );
          _planPaces[_focus.tableColumn] = '';
          if (_focus.tableColumn > 0) _markManualAnchor();
          _resetPlannedSummary();
        case _PaceFocusKind.tablePlanPace:
          final column = _focus.tableColumn;
          _planPaces[column] = _removeLast(_planPaces[column]);
          _applyPlanPace(column);
          _markManualAnchor();
          _resetPlannedSummary();
        case _PaceFocusKind.tableStop:
          _removeStopDigit(_focus.tableColumn);
        case _PaceFocusKind.summaryPlannedPace:
          _plannedPaceOverride = _removeLast(_plannedPaceOverride);
          _plannedSummarySource = PacePlannedSummarySource.pace;
        case _PaceFocusKind.summaryPlannedTime:
          _plannedTimeOverride = _removeLast(_plannedTimeOverride);
          _plannedSummarySource = PacePlannedSummarySource.time;
      }
    });
  }

  void _clearActive() {
    _replacePlanInput = false;
    _update(() {
      switch (_focus.kind) {
        case _PaceFocusKind.none:
          break;
        case _PaceFocusKind.top:
          final field = _focus.field!;
          switch (field) {
            case _PaceTopField.distance:
              _distance = '';
            case _PaceTopField.paceMinutes:
              _paceMinutes = '';
            case _PaceTopField.paceSeconds:
              _paceSeconds = '';
            case _PaceTopField.days:
            case _PaceTopField.hours:
            case _PaceTopField.minutes:
            case _PaceTopField.seconds:
              _setTopTimeValue(field, '');
            case _PaceTopField.splitDistance:
              _splitDistance = '';
            case _PaceTopField.splitPercent:
              _splitPercent = '';
            case _PaceTopField.startHours:
              _startHours = '';
            case _PaceTopField.startMinutes:
              _startMinutes = '';
          }
        case _PaceFocusKind.tableTime:
          _tableTimes[_focus.tableColumn] = '';
        case _PaceFocusKind.tableDistance:
          if (_focus.tableColumn == 0) return;
          _tableDistances[_focus.tableColumn] = '';
          _resetPlannedSummary();
        case _PaceFocusKind.tablePlanTime:
          _planTimes[_focus.tableColumn] = '';
          _planPaces[_focus.tableColumn] = '';
          _resetPlannedSummary();
        case _PaceFocusKind.tablePlanPace:
          final column = _focus.tableColumn;
          _planPaces[column] = '';
          if (column > 0) _planTimes[column] = '';
          _resetPlannedSummary();
        case _PaceFocusKind.tableStop:
          _setStopMinutes(_focus.tableColumn, 0);
        case _PaceFocusKind.summaryPlannedPace:
          _plannedPaceOverride = '';
          _plannedSummarySource = PacePlannedSummarySource.none;
        case _PaceFocusKind.summaryPlannedTime:
          _plannedTimeOverride = '';
          _plannedSummarySource = PacePlannedSummarySource.none;
      }
    });
  }

  /// `±` меняет полярность только в поле сплита. В остальных полях минус
  /// не поддерживается.
  void _toggleSplitSign() {
    if (_focus.kind != _PaceFocusKind.top ||
        _focus.field != _PaceTopField.splitPercent) {
      return;
    }
    _update(() {
      if (_splitPercent.startsWith('-')) {
        _splitPercent = _splitPercent.substring(1);
      } else {
        _splitPercent = '-$_splitPercent';
      }
    });
  }

  String _removeLast(String value) {
    if (value.isEmpty) return value;
    return value.substring(0, value.length - 1);
  }

  bool _isDigitChar(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }
}
