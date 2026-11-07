part of 'pace_view.dart';

extension _PacePlanPart on _PaceViewState {
  String _formatElapsedMinutes(int? minutes) =>
      PaceTableCalculator.formatElapsedMinutes(minutes);

  void _resetPlannedSummary() {
    _plannedPaceOverride = '';
    _plannedTimeOverride = '';
    _plannedSummarySource = PacePlannedSummarySource.none;
  }

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

  /// Сдвигает плановые времена после отредактированной колонки на ту же
  /// разницу, чтобы сохранить темпы всех последующих сегментов. Обновляет
  /// до последнего сегмента, у которого задан плановый темп.
  /// Возвращает true, если таблица изменилась.
  bool _finalizePlanEdit() {
    final before = _planTimesBeforeEdit;
    final column = _planEditColumn;
    _planTimesBeforeEdit = null;
    _planEditColumn = null;
    if (before == null || column == null) return false;
    if (column <= 0 || column >= _planTimes.length) return false;

    final oldMinutes = _parseTimeBuffer(before[column]);
    final newMinutes = _parseTimeBuffer(_planTimes[column]);
    if (oldMinutes == null || newMinutes == null) return false;

    var delta = newMinutes - oldMinutes;
    if (delta > 12 * 60) delta -= 24 * 60;
    if (delta < -12 * 60) delta += 24 * 60;
    if (delta == 0) return false;

    var lastPaced = -1;
    for (var index = column + 1; index < _columns; index++) {
      final hasPace =
          _planPaces[index].isNotEmpty || _plannedPace(index) != null;
      if (hasPace) lastPaced = index;
    }
    if (lastPaced < 0) return false;

    for (var index = column + 1; index <= lastPaced; index++) {
      final time = _parseTimeBuffer(_planTimes[index]);
      if (time == null) continue;
      _planTimes[index] = _timeBufferFromMinutes(time + delta);
    }
    _planDays = _computeDays(_planTimes);
    return true;
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

  /// Диалог «плоские / с поправкой» (§7.3). Нужен только при горном режиме
  /// и загруженном треке с высотами; иначе возвращает `null` — ввод идёт
  /// по-старому.
  Future<PlanInputChoice?> _askPlanInputMode({
    required bool byTime,
    required double value,
  }) async {
    if (!_mountainEnabled) return null;
    final parsed = _loadedTrack;
    if (parsed == null || !parsed.track.hasElevation) return null;
    final segments = _planSegments();
    if (segments.isEmpty) return null;
    return showPlanInputDialog(
      context,
      previewFor: (mode, stopsMin) {
        final preview = _previewPlanInput(
          mode: mode,
          byTime: byTime,
          value: value,
          stopsMin: stopsMin,
        );
        return preview ?? AppStrings.paceInputPreviewUnavailable;
      },
    );
  }

  List<PlanSegment> _planSegments() => planSegmentsForColumns(
    parsed: _loadedTrack,
    columnDistancesKm: [
      for (final value in _tableDistances) parseDecimal(value) ?? 0,
    ],
  );

  /// Текст предпросмотра «Плоский 6:00 → расчётный 6:38, итог 12:34 (со
  /// стоянками 45 мин)». Стоянки — суммарные минуты, распределяются по ПП.
  String? _previewPlanInput({
    required PlanInputMode mode,
    required bool byTime,
    required double value,
    required int stopsMin,
  }) {
    final segments = _planSegments();
    final totalStopsSec = stopsMin * 60.0;
    final stops = distributeStops(
      columns: _columns,
      totalSec: totalStopsSec,
      current: _stopsSecList(),
    );
    final r = planFromInput(
      mode: mode,
      byTime: byTime,
      value: value,
      segments: segments,
      stopsSec: stops,
      totalStopsSec: totalStopsSec,
    );
    if (r == null) return null;
    final p = r.preview;
    final total = p.totalSec == null ? '' : _hmText(p.totalSec!.round());
    final moving = p.movingPaceSec == null
        ? ''
        : formatPaceSeconds(p.movingPaceSec!.round());
    if (mode == PlanInputMode.flatData && p.flatPaceSec != null) {
      return '${AppStrings.paceInputPreviewFlat} '
          '${formatPaceSeconds(p.flatPaceSec!.round())} → '
          '${AppStrings.paceInputPreviewCalc} $moving, '
          '${AppStrings.paceInputPreviewTotal} $total '
          '(${AppStrings.paceInputPreviewStops} $stopsMin ${AppStrings.paceInputMinutesShort})';
    }
    return '${AppStrings.paceInputPreviewCalc} $moving, '
        '${AppStrings.paceInputPreviewTotal} $total '
        '(${AppStrings.paceInputPreviewStops} $stopsMin ${AppStrings.paceInputMinutesShort})';
  }

  String _hmText(int seconds) {
    final parts = splitSeconds(seconds);
    final h = parts.days * 24 + parts.hours;
    return '$h:${parts.minutes.toString().padLeft(2, '0')}';
  }

  Future<bool> _confirmAndApplyPlannedTime() async {
    final duration = _parseTimeBuffer(_plannedTimeOverride);
    final distance = _totalTableDistance;
    final start = _planStartMinutes;
    if (duration == null || duration <= 0) {
      _showMessage(AppStrings.paceEnterPlannedTime);
      return false;
    }
    if (distance == null || distance <= 0) {
      _showMessage(AppStrings.paceFillDistance);
      return false;
    }
    if (start == null) {
      _showMessage(AppStrings.paceFillStartTime);
      return false;
    }

    final planStartFilled = _parseTimeBuffer(_planTimes[0]) != null;
    final confirmed = await _confirmPlanRecalculation(
      planStartFilled
          ? AppStrings.pacePlanRewriteKeepStart
          : AppStrings.pacePlanRewriteUseLimit,
    );
    if (!confirmed) return false;

    final choice = await _askPlanInputMode(
      byTime: true,
      value: duration * 60.0,
    );
    if (!mounted) return false;

    _update(() {
      if (!planStartFilled) _planTimes[0] = _tableTimes[0];
      final paceSeconds = (duration * 60 / distance).round();
      _applyPlanSchedule(paceSeconds, totalMinutes: duration);
      _setFlatAnchorFromTime(duration * 60.0);
      _resetPlannedSummary();
    });
    _applyPlanChoice(choice, byTime: true, value: duration * 60.0);
    return true;
  }

  Future<bool> _confirmAndApplyPlannedPace() async {
    final pace = _parsePaceBuffer(_plannedPaceOverride);
    final distance = _totalTableDistance;
    final start = _planStartMinutes;
    if (pace == null || pace <= 0) {
      _showMessage(AppStrings.paceEnterPlannedPace);
      return false;
    }
    if (distance == null || distance <= 0) {
      _showMessage(AppStrings.paceFillDistance);
      return false;
    }
    if (start == null) {
      _showMessage(AppStrings.paceFillStartTime);
      return false;
    }

    final planStartFilled = _parseTimeBuffer(_planTimes[0]) != null;
    final confirmed = await _confirmPlanRecalculation(
      planStartFilled
          ? AppStrings.pacePlanRewriteKeepStartPace
          : AppStrings.pacePlanRewriteUseLimitPace,
    );
    if (!confirmed) return false;

    final choice = await _askPlanInputMode(
      byTime: false,
      value: pace.toDouble(),
    );
    if (!mounted) return false;

    _update(() {
      if (!planStartFilled) _planTimes[0] = _tableTimes[0];
      _applyPlanSchedule(pace);
      _setFlatAnchor(pace.toDouble());
      _resetPlannedSummary();
    });
    _applyPlanChoice(choice, byTime: false, value: pace.toDouble());
    return true;
  }

  Future<bool> _confirmPlanRecalculation(String message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(AppStrings.paceRecalcTitle),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(AppStrings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(AppStrings.paceRecalcAction),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  void _applyPlanSchedule(int paceSeconds, {int? totalMinutes}) {
    final start =
        _parseTimeBuffer(_planTimes[0]) ?? _parseTimeBuffer(_tableTimes[0]);
    if (start == null) return;

    final startDistance = parseDecimal(_tableDistances[0]) ?? 0;
    final paceBuffer = _paceBufferFromSeconds(paceSeconds);
    var lastIndex = 0;

    for (var index = 1; index < _columns; index++) {
      _planPaces[index] = paceBuffer;
      final distance = parseDecimal(_tableDistances[index]);
      if (distance == null) {
        _planTimes[index] = '';
        continue;
      }
      final delta = distance - startDistance;
      final minutes = (delta * paceSeconds / 60).round();
      _planTimes[index] = _timeBufferFromMinutes(start + minutes);
      lastIndex = index;
    }

    if (totalMinutes != null && lastIndex > 0) {
      _planTimes[lastIndex] = _timeBufferFromMinutes(start + totalMinutes);
    }
    _planPaces[0] = '';
    _planDays = _computeDays(_planTimes);

    // Recalculate subsequent checkpoint times based on their individual paces
    // if those paces have been manually entered
    for (var index = 1; index < _columns; index++) {
      final paced = _parsePaceBuffer(_planPaces[index]);
      if (paced == null || paced == 0) continue;

      final distance = parseDecimal(_tableDistances[index]);
      final prevDistance = parseDecimal(_tableDistances[index - 1]);
      if (distance == null || prevDistance == null) continue;

      final distanceDelta = distance - prevDistance;
      if (distanceDelta <= 0) continue;

      // Get the previous plan time
      final prevPlanTime = _parseTimeBuffer(_planTimes[index - 1]);
      if (prevPlanTime == null) continue;

      // Calculate time for this segment based on its pace
      final segmentMinutes = (paced * distanceDelta / 60).round();
      _planTimes[index] = _timeBufferFromMinutes(prevPlanTime + segmentMinutes);
    }
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

  /// Применяет выбор диалога: опора по режиму, стоянки — суммарные минуты,
  /// распределённые по ПП. Без выбора (`null`) ничего не меняет.
  void _applyPlanChoice(
    PlanInputChoice? choice, {
    required bool byTime,
    required double value,
  }) {
    if (choice == null) return;
    final totalStopsSec = choice.stopsMin * 60.0;
    final stops = distributeStops(
      columns: _columns,
      totalSec: totalStopsSec,
      current: _stopsSecList(),
    );
    final r = planFromInput(
      mode: choice.mode,
      byTime: byTime,
      value: value,
      segments: _planSegments(),
      stopsSec: stops,
      totalStopsSec: totalStopsSec,
    );
    if (r == null) return;
    _update(() {
      _planAnchor = _toPlanAnchor(r.anchor);
      _setStopsSecList(stops);
      _recomputeMountainPlan();
    });
  }

  PlanAnchor _toPlanAnchor(PlanInputAnchor a) => switch (a.mode) {
    PlanAnchorMode.flat => PlanAnchor.flat(a.value),
    PlanAnchorMode.targetTime => PlanAnchor.targetTime(a.value.round()),
    PlanAnchorMode.targetPace => PlanAnchor.targetPace(a.value),
    PlanAnchorMode.manual => const PlanAnchor.manual(),
  };

  /// Опора «плоский темп» — только при включённом горном режиме: без него
  /// план считается как раньше и опора не нужна.
  void _setFlatAnchor(double paceSec) {
    if (!_mountainEnabled || paceSec <= 0) return;
    _planAnchor = PlanAnchor.flat(paceSec);
  }

  /// Итог по времени «плоские данные»: `p0 = (T − стоянки) / D` (§7.3).
  /// Стоянок в UI пока нет, поэтому учитываем сохранённые.
  void _setFlatAnchorFromTime(double totalSec) {
    if (!_mountainEnabled) return;
    final distance = _totalTableDistance;
    if (distance == null || distance <= 0) return;
    final stops = _stopsSecList();
    final moving = totalSec - sumIntermediateStops(stops, _columns);
    if (moving <= 0) return;
    _setFlatAnchor(moving / distance);
  }

  /// Пересчёт плана по опоре при изменении дистанций (§7.5). Работает только
  /// в горном режиме и при заданной опоре; иначе план не трогаем.
  /// Возвращает true, если план изменился.
  bool _recomputeMountainPlan() {
    final anchor = _planAnchor;
    if (!_mountainEnabled || anchor == null) return false;
    // Ручная правка времени или темпа: значения пользователя не пересчитываем.
    if (anchor.kind == PlanAnchorKind.manual) return false;
    final segments = planSegmentsForColumns(
      parsed: _loadedTrack,
      columnDistancesKm: [
        for (final value in _tableDistances) parseDecimal(value) ?? 0,
      ],
    );
    if (segments.isEmpty) return false;
    final start =
        _parseTimeBuffer(_planTimes[0]) ?? _parseTimeBuffer(_tableTimes[0]);
    if (start == null) return false;

    final plan = recomputePlan(
      anchor: switch (anchor.kind) {
        PlanAnchorKind.flat => PlanAnchorMode.flat,
        PlanAnchorKind.targetTime => PlanAnchorMode.targetTime,
        PlanAnchorKind.targetPace => PlanAnchorMode.targetPace,
        PlanAnchorKind.manual => PlanAnchorMode.manual,
      },
      segments: segments,
      stopsSec: _stopsSecList(),
      flatPaceSec: anchor.flatPaceSec,
      targetTotalSec: anchor.targetTotalSec?.toDouble(),
      targetPaceSec: anchor.targetPaceSec,
    );
    if (plan == null) return false;

    for (var index = 1; index < _columns; index++) {
      final pace = plan.paceSec[index];
      _planPaces[index] = pace > 0 ? _paceBufferFromSeconds(pace.round()) : '';
      _planTimes[index] = _timeBufferFromMinutes(
        start + (plan.arrivalSec[index] / 60).round(),
      );
    }
    _planDays = _computeDays(_planTimes);
    return true;
  }

  /// Ручная правка сегмента переводит опору в `manual` (§7.2).
  void _markManualAnchor() {
    if (!_mountainEnabled) return;
    _planAnchor = const PlanAnchor.manual();
  }

  List<double> _stopsSecList() {
    return [
      for (var i = 0; i < _columns; i++)
        i < _stopsSec.length ? _stopsSec[i].toDouble() : 0,
    ];
  }

  void _setStopsSecList(List<double> stops) {
    _stopsSec = [for (final value in stops) value.round()];
  }

  /// Минуты стоянки на колонке (целые, внутренне — секунды). Пусто = 0.
  int _stopMinutes(int column) {
    if (column <= 0 || column >= _stopsSec.length) return 0;
    return _stopsSec[column] ~/ 60;
  }

  String _stopBufferText(int column) {
    final minutes = _stopMinutes(column);
    return minutes == 0 ? '' : minutes.toString();
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

  /// Записывает стоянку колонки и сдвигает прибытия последующих колонок
  /// (дельта, §7.4). Темпы сегментов не меняются.
  void _setStopMinutes(int column, int minutes) {
    if (column <= 0 || column >= _columns - 1) return;
    final before = _stopsSec.length > column ? _stopsSec[column] : 0;
    final stops = _stopsSecList();
    stops[column] = minutes * 60.0;
    _setStopsSecList(stops);
    final deltaMin = (stops[column] - before) ~/ 60;
    if (deltaMin == 0) return;
    for (var index = column + 1; index < _columns; index++) {
      final time = _parseTimeBuffer(_planTimes[index]);
      if (time == null) continue;
      _planTimes[index] = _timeBufferFromMinutes(time + deltaMin);
    }
    _planDays = _computeDays(_planTimes);
  }

  void _applyPlanPace(int column) {
    if (column <= 0) return;

    final pace = _parsePaceBuffer(_planPaces[column]);
    if (pace == null) return;

    final previousTime = _parseTimeBuffer(_planTimes[column - 1]) ?? 0;
    final previousDistance = parseDecimal(_tableDistances[column - 1]);
    final distance = parseDecimal(_tableDistances[column]);
    if (previousDistance == null || distance == null) return;

    final distanceDelta = distance - previousDistance;
    if (distanceDelta <= 0) return;

    final minutes = (pace * distanceDelta / 60).round();
    _planTimes[column] = _timeBufferFromMinutes(previousTime + minutes);
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
          _distance = _appendDecimal(_distance, char);
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
      }
    });
  }

  String _appendInteger(String current, String char, int maxLength) {
    if (!_isDigitChar(char) || current.length >= maxLength) return current;
    return '$current$char';
  }

  String _appendDecimal(String current, String char) {
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

    if (current.length - dot - 1 >= 2) return current;
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

  String _removeLast(String value) {
    if (value.isEmpty) return value;
    return value.substring(0, value.length - 1);
  }

  bool _isDigitChar(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }
}
