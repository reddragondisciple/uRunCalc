part of 'pace_view.dart';

extension _PacePlanPart on _PaceViewState {
  String _formatElapsedMinutes(int? minutes) =>
      PaceTableCalculator.formatElapsedMinutes(minutes);

  void _resetPlannedSummary() {
    _plannedPaceOverride = '';
    _plannedTimeOverride = '';
    _plannedSummarySource = PacePlannedSummarySource.none;
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

  /// Сегменты для плана. Кэш тот же, что и у D+/D−: один проход по треку на
  /// изменение дистанций, а не на каждую клетку и не на каждый предпросмотр.
  List<PlanSegment> _planSegments() {
    final parsed = _loadedTrack;
    if (identical(parsed, _cachedPlanTrack) &&
        _cachedPlanColumns == _columns &&
        listEquals(_cachedPlanDistances, _tableDistances) &&
        _cachedPlanSegments != null) {
      return _cachedPlanSegments!;
    }
    final segments = planSegmentsForColumns(
      parsed: parsed,
      columnDistancesKm: [
        for (final value in _tableDistances) parseDecimal(value) ?? 0,
      ],
    );
    _cachedPlanTrack = parsed;
    _cachedPlanColumns = _columns;
    _cachedPlanDistances = List<String>.of(_tableDistances);
    _cachedPlanSegments = segments;
    return segments;
  }

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
    final segments = _planSegments();
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
}
