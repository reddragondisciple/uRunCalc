part of 'pace_view.dart';

extension _PaceTablePart on _PaceViewState {
  Widget _buildCalculator() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _calcButton(
              AppStrings.paceCalcPace,
              _PaceCalc.pace,
              'pace-calc-pace',
            ),
            const SizedBox(width: 4),
            _calcButton(
              AppStrings.paceCalcDistance,
              _PaceCalc.distance,
              'pace-calc-distance',
            ),
            const SizedBox(width: 4),
            _calcButton(
              AppStrings.paceCalcTime,
              _PaceCalc.time,
              'pace-calc-time',
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildPaceRow(),
        const SizedBox(height: 4),
        _buildDistanceRow(),
        const SizedBox(height: 4),
        _buildTimeRow(),
      ],
    );
  }

  Widget _calcButton(String label, _PaceCalc value, String key) {
    final selected = _calc == value;

    return Expanded(
      child: InkWell(
        key: ValueKey(key),
        onTap: () => _selectCalc(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
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
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cursor() => BlinkingCursor(active: widget.active);

  Widget _field({
    required String key,
    required String text,
    required bool editable,
    required bool focused,
    required VoidCallback onTap,
    String hint = '',
  }) {
    final borderColor = focused
        ? AppColors.focus
        : editable
        ? Colors.grey.shade700
        : const Color(0x66FF9800);

    return InkWell(
      key: ValueKey(key),
      onTap: editable ? onTap : null,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: editable ? AppColors.background : AppColors.surfaceRaised,
          border: Border.all(color: borderColor, width: focused ? 1.5 : 1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text.isEmpty ? hint : text,
                maxLines: 1,
                style: TextStyle(
                  color: editable
                      ? (text.isEmpty ? Colors.grey : Colors.white)
                      : AppColors.result,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (focused) _cursor(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaceRow() {
    final result = _calc == _PaceCalc.pace;

    return Row(
      children: [
        const SizedBox(
          width: 94,
          child: Text(
            AppStrings.paceCalcPace,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        Expanded(
          child: _field(
            key: 'pace-pace-min',
            text: _topPaceMinutes(),
            editable: !result,
            focused: _isTopFocused(_PaceTopField.paceMinutes),
            onTap: () => _focusTop(_PaceTopField.paceMinutes),
            hint: AppStrings.paceHintMinutes,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(':', style: TextStyle(color: Colors.grey, fontSize: 18)),
        ),
        Expanded(
          child: _field(
            key: 'pace-pace-sec',
            text: _topPaceSeconds(),
            editable: !result,
            focused: _isTopFocused(_PaceTopField.paceSeconds),
            onTap: () => _focusTop(_PaceTopField.paceSeconds),
            hint: AppStrings.paceHintSeconds,
          ),
        ),
        const SizedBox(
          width: 44,
          child: Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              AppStrings.paceHintPace,
              style: TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDistanceRow() {
    final result = _calc == _PaceCalc.distance;

    return Row(
      children: [
        const SizedBox(
          width: 94,
          child: Text(
            AppStrings.paceCalcDistance,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        Expanded(
          child: _field(
            key: 'pace-distance',
            text: _topDistance(),
            editable: !result,
            focused: _isTopFocused(_PaceTopField.distance),
            onTap: () => _focusTop(_PaceTopField.distance),
            hint: AppStrings.paceHintKm,
          ),
        ),
        const SizedBox(
          width: 44,
          child: Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              AppStrings.paceHintKm,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeRow() {
    const fields = [
      _PaceTopField.days,
      _PaceTopField.hours,
      _PaceTopField.minutes,
      _PaceTopField.seconds,
    ];
    const labels = [
      AppStrings.timeDays,
      AppStrings.timeHours,
      AppStrings.timeMinutes,
      AppStrings.timeSeconds,
    ];
    final result = _calc == _PaceCalc.time;

    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 94),
            for (final label in labels)
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            const SizedBox(
              width: 94,
              child: Text(
                AppStrings.paceCalcTime,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            for (final field in fields)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: _field(
                    key: 'pace-time-${field.name}',
                    text: _topTimePart(field),
                    editable: !result,
                    focused: _isTopFocused(field),
                    onTap: () => _focusTop(field),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  static const double _totalColumnWidth = 62;

  static const String _totalTimeDescription =
      AppStrings.paceTotalTimeDescription;
  static const String _limitPaceDescription =
      AppStrings.paceLimitPaceDescription;
  static const String _plannedPaceDescription =
      AppStrings.pacePlannedPaceDescription;
  static const String _plannedTimeDescription =
      AppStrings.pacePlannedTimeDescription;

  void _showTotalDescription(String title, String description) {
    _hideKeyboard();
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(description),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(AppStrings.close),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTable({required bool compact}) {
    _planStatuses = PaceTableCalculator.planStatuses(
      planTimes: _planTimes,
      limitTimes: _tableTimes,
      columns: _columns,
      stopsMin: [for (var i = 0; i < _columns; i++) _stopMinutes(i)],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = compact ? 2.0 : 5.0;

        // Ряд высот (горный режим) вставляется после «Расстояния» в обоих
        // режимах, поэтому подписи и высоты строятся от одного списка рядов.
        final elevationOn = _mountainEnabled;
        // Ряд стоянок раскрывается строкой под «Плановым темпом» (§7.4).
        final stopsOn = _stopsRowOpen ? 1 : 0;
        final compactLabels = <String>[
          '',
          AppStrings.paceRowLimit,
          AppStrings.paceRowDistance,
          if (elevationOn) AppStrings.paceRowElevation,
          AppStrings.paceRowSegmentPace,
          AppStrings.paceRowPlan,
          AppStrings.paceRowPlanPace,
          if (stopsOn == 1) AppStrings.paceRowStops,
          AppStrings.paceRowWater,
          AppStrings.paceRowFood,
        ];
        // Подписи портрета по рядам. Ряд высот — отдельная подпись только
        // в горном режиме; «План» стоит на своём ряду в любом режиме.
        // Порядок рядов портрета: заголовок, время, расстояние, [подъём и его
        // итог], сегментный темп, лимит, план (время), плановый темп, итоги
        // плана, вода, еда.
        final portraitLabels = <String>[
          '',
          '',
          '',
          '',
          if (elevationOn) ...['', ''],
          '',
          AppStrings.paceRowPlan,
          '',
          '',
          '',
          '',
          '',
        ];
        final labels = compact ? compactLabels : portraitLabels;

        late List<double> heights;
        if (compact) {
          // Горный режим: ряд высот вставлен после «Расстояния», а «Вода» и
          // «Еда» уступают ему место поровну.
          final weights = <double>[
            1.3,
            1.3,
            1.3,
            if (elevationOn) 1.3,
            1.3,
            1.3,
            1.3,
            if (stopsOn == 1) 1.3,
            elevationOn ? 1.6 : 2.1,
            elevationOn ? 1.6 : 2.1,
          ];
          final totalWeight = weights.fold<double>(0, (sum, w) => sum + w);
          final available = constraints.maxHeight.isFinite
              ? math.max(
                  0.0,
                  constraints.maxHeight - gap * (weights.length - 1),
                )
              : 30.0 * weights.length;
          final unit = available / totalWeight;
          heights = weights.map((w) => math.max(12.0, unit * w)).toList();
        } else {
          // Ряд заметок в два раза выше остальных, чтобы в нём помещался
          // крупный номер ПП и текст заметки. Вода и еда — максимально высокие.
          // Горный режим добавляет ряд подъёма и ряд его итога (2 ряда).
          heights = <double>[
            60, // заголовок
            30, // время
            30, // расстояние
            30, // сегментный темп
            if (elevationOn) ...[30, 30],
            30, // лимит: общее время / темп
            30, // план: время
            30, // план: темп
            if (stopsOn == 1) 30, // стоянки
            30, // итоги плана: темп | время
            110, // вода
            110, // еда
          ];
        }

        final rows = <Widget>[];
        if (compact) {
          rows.add(
            _tableRow(
              cells: _headerCells(true),
              height: heights[0],
              expanded: _fitTable,
              total: _totalHeaderCell(),
            ),
          );
          rows.add(
            _tableRow(
              cells: _timeCells(),
              height: heights[1],
              expanded: _fitTable,
              total: _totalValueCell(
                key: 'pace-total-time',
                text: _formatElapsedMinutes(_totalLimitMinutes),
                onTap: () => _showTotalDescription(
                  AppStrings.paceTotalTime,
                  _totalTimeDescription,
                ),
              ),
            ),
          );
          rows.add(
            _tableRow(
              cells: _distanceCells(),
              height: heights[2],
              expanded: _fitTable,
              total: _totalBlankCell(),
            ),
          );
          var next = 3;
          if (elevationOn) {
            rows.add(
              _tableRow(
                cells: _elevationCells(),
                height: heights[next],
                expanded: _fitTable,
                total: _elevationTotalCell(),
              ),
            );
            next++;
          }
          rows.add(
            _tableRow(
              cells: _segmentPaceCells(),
              height: heights[next],
              expanded: _fitTable,
              total: _totalValueCell(
                key: 'pace-total-pace',
                text: _overallPaceSeconds == null
                    ? '—'
                    : formatPaceSeconds(_overallPaceSeconds!),
                onTap: () => _showTotalDescription(
                  AppStrings.paceLimitPace,
                  _limitPaceDescription,
                ),
              ),
            ),
          );
          rows.add(
            _tableRow(
              cells: _planTimeCells(),
              height: heights[next + 1],
              expanded: _fitTable,
              total: _totalValueCell(
                key: 'pace-total-plan-time',
                text: _focus.kind == _PaceFocusKind.summaryPlannedTime
                    ? _timeBufferText(_plannedTimeOverride)
                    : _formatElapsedMinutes(_overallPlannedFinishMinutes),
                focused: _focus.kind == _PaceFocusKind.summaryPlannedTime,
                editable: !_locked,
                cursorFirst: true,
                color: Colors.white,
                onTap: _locked ? null : _focusSummaryPlannedTime,
                onLongPress: () => _showTotalDescription(
                  AppStrings.pacePlannedTime,
                  _plannedTimeDescription,
                ),
              ),
            ),
          );
          rows.add(
            _tableRow(
              cells: _planPaceCells(),
              height: heights[next + 2],
              expanded: _fitTable,
              total: _totalValueCell(
                key: 'pace-total-plan-pace',
                text: _focus.kind == _PaceFocusKind.summaryPlannedPace
                    ? _paceBufferText(_plannedPaceOverride)
                    : _overallPlannedPaceSeconds == null
                    ? '—'
                    : formatPaceSeconds(_overallPlannedPaceSeconds!),
                focused: _focus.kind == _PaceFocusKind.summaryPlannedPace,
                editable: !_locked,
                cursorFirst: true,
                color: Colors.white,
                onTap: _locked ? null : _focusSummaryPlannedPace,
                onLongPress: () => _showTotalDescription(
                  AppStrings.pacePlannedPace,
                  _plannedPaceDescription,
                ),
              ),
            ),
          );
          if (_stopsRowOpen) {
            rows.add(
              _tableRow(
                cells: _stopsCells(compact: true),
                height: heights[next + 3],
                expanded: _fitTable,
                total: _totalValueCell(
                  key: 'pace-total-stops',
                  text: _formatStopsTotal(),
                  color: Colors.white,
                ),
              ),
            );
          }
          rows.add(
            _wrappedTextRow(
              values: _water,
              keyPrefix: 'pace-water',
              title: AppStrings.paceRowWater,
              height: heights[next + 3 + stopsOn],
              expanded: _fitTable,
              showFirstPlaceholder: false,
              total: _totalBlankCell(),
            ),
          );
          rows.add(
            _wrappedTextRow(
              values: _food,
              keyPrefix: 'pace-food',
              title: AppStrings.paceRowFood,
              height: heights[next + 4 + stopsOn],
              expanded: _fitTable,
              showFirstPlaceholder: false,
              total: _totalBlankCell(),
            ),
          );
        } else {
          // Смещение рядов портрета: горный режим добавляет ряд высот и его итог.
          final pe = elevationOn ? 2 : 0;
          rows.add(
            _tableRow(
              cells: _headerCells(false),
              height: heights[0],
              expanded: _fitTable,
            ),
          );
          rows.add(
            _tableRow(
              cells: _timeCells(),
              height: heights[1],
              expanded: _fitTable,
            ),
          );
          rows.add(
            _tableRow(
              cells: _distanceCells(),
              height: heights[2],
              expanded: _fitTable,
            ),
          );
          rows.add(
            _tableRow(
              cells: _segmentPaceCells(),
              height: heights[3],
              expanded: _fitTable,
            ),
          );
          if (_mountainEnabled) {
            rows.add(
              _tableRow(
                cells: _elevationCells(),
                height: _PaceViewState._elevationRowHeight,
                expanded: _fitTable,
              ),
            );
            rows.add(
              _elevationTotalRow(
                height: _PaceViewState._elevationRowHeight,
                expanded: _fitTable,
                meters: true,
              ),
            );
          }
          rows.add(
            _limitSummarySplitRow(height: heights[4 + pe], expanded: _fitTable),
          );
          rows.add(
            _tableRow(
              cells: _planTimeCells(),
              height: heights[5 + pe],
              expanded: _fitTable,
            ),
          );
          rows.add(
            _tableRow(
              cells: _planPaceCells(),
              height: heights[6 + pe],
              expanded: _fitTable,
            ),
          );
          if (_stopsRowOpen) {
            rows.add(
              _tableRow(
                cells: _stopsCells(),
                height: heights[7 + pe],
                expanded: _fitTable,
              ),
            );
          }
          rows.add(
            _plannedSummaryPairRow(
              height: heights[7 + pe + stopsOn],
              expanded: _fitTable,
            ),
          );
          rows.add(
            _wrappedTextRow(
              values: _water,
              keyPrefix: 'pace-water',
              title: AppStrings.paceRowWater,
              height: heights[8 + pe + stopsOn],
              expanded: _fitTable,
              showFirstPlaceholder: true,
              fontSize: 10.5,
            ),
          );
          rows.add(
            _wrappedTextRow(
              values: _food,
              keyPrefix: 'pace-food',
              title: AppStrings.paceRowFood,
              height: heights[9 + pe + stopsOn],
              expanded: _fitTable,
              showFirstPlaceholder: true,
              fontSize: 10.5,
            ),
          );
        }

        if (compact) {
          const labelWidth = 58.0;
          final availableWidth = math.max(
            1.0,
            constraints.maxWidth - labelWidth,
          );
          final tableWidth = _fitTable
              ? availableWidth
              : _columns * _PaceViewState._fixedCellWidth + _totalColumnWidth;

          final table = SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                for (var index = 0; index < rows.length; index++) ...[
                  if (index > 0) SizedBox(height: gap),
                  rows[index],
                ],
              ],
            ),
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: labelWidth,
                child: Column(
                  children: [
                    for (var index = 0; index < labels.length; index++) ...[
                      if (index > 0) SizedBox(height: gap),
                      SizedBox(
                        height: heights[index],
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            labels[index],
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: _fitTable
                    ? table
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: table,
                      ),
              ),
            ],
          );
        }

        final tableWidth = _fitTable
            ? constraints.maxWidth
            : _columns * _PaceViewState._fixedCellWidth;
        final table = SizedBox(
          width: tableWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < rows.length; index++) ...[
                if (index > 0) SizedBox(height: gap),
                if (index < labels.length && labels[index].isNotEmpty) ...[
                  Text(
                    labels[index],
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                  const SizedBox(height: 2),
                ],
                rows[index],
              ],
            ],
          ),
        );

        return _fitTable
            ? table
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: table,
              );
      },
    );
  }

  Widget _tableRow({
    required List<Widget> cells,
    required double height,
    required bool expanded,
    Widget? total,
  }) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (final cell in cells)
            expanded
                ? Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0.5),
                      child: SizedBox(height: height, child: cell),
                    ),
                  )
                : SizedBox(
                    width: _PaceViewState._fixedCellWidth,
                    height: height,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0.5),
                      child: cell,
                    ),
                  ),
          if (total != null)
            SizedBox(
              width: _totalColumnWidth,
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0.5),
                child: total,
              ),
            ),
        ],
      ),
    );
  }

  Widget _totalHeaderCell() {
    return _interactiveCell(
      key: 'pace-total-header',
      text: 'Total',
      result: true,
      bold: true,
      fontSize: 30,
    );
  }

  Widget _totalBlankCell() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: Colors.grey.shade900),
      ),
    );
  }

  Widget _totalValueCell({
    required String key,
    required String text,
    bool focused = false,
    bool editable = false,
    bool cursorFirst = false,
    Color? color,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return _interactiveCell(
      key: key,
      text: text,
      focused: focused,
      editable: editable,
      cursorFirst: cursorFirst,
      result: true,
      bold: true,
      fontSize: 30,
      color: color,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  Widget _limitSummarySplitRow({
    required double height,
    required bool expanded,
  }) {
    final pace = _overallPaceSeconds;
    final row = SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: _interactiveCell(
                key: 'pace-overall-time',
                text: AppStrings.paceTotalTimeLine(
                  _formatElapsedMinutes(_totalLimitMinutes),
                ),
                result: true,
                fontSize: 14,
                onTap: _hideKeyboard,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: _interactiveCell(
                key: 'pace-overall',
                text: AppStrings.paceLimitPaceLine(
                  pace == null ? '—' : formatPaceSeconds(pace),
                ),
                result: true,
                fontSize: 14,
                onTap: _hideKeyboard,
              ),
            ),
          ),
        ],
      ),
    );

    return expanded
        ? row
        : SizedBox(
            width: _columns * _PaceViewState._fixedCellWidth,
            child: row,
          );
  }

  /// Ячейка итогового планового темпа (без строки, для общего ряда портрета).
  Widget _plannedPaceSummaryCell() {
    final focused = _focus.kind == _PaceFocusKind.summaryPlannedPace;
    final seconds = _overallPlannedPaceSeconds;
    final cell = _interactiveCell(
      key: 'pace-overall-plan',
      text: focused
          ? AppStrings.pacePlannedPaceLine(
              _paceBufferText(_plannedPaceOverride),
            )
          : AppStrings.pacePlannedPaceLine(
              seconds == null ? '—' : formatPaceSeconds(seconds),
            ),
      focused: focused,
      editable: !_locked,
      cursorFirst: true,
      result: true,
      fontSize: 14,
      color: Colors.white,
      onTap: _locked ? null : () => _focusSummaryPlannedPace(),
    );
    return cell;
  }

  /// Ячейка итогового планового времени (для общего ряда портрета).
  Widget _plannedTimeSummaryCell() {
    final focused = _focus.kind == _PaceFocusKind.summaryPlannedTime;
    final cell = _interactiveCell(
      key: 'pace-overall-plan-time',
      text: focused
          ? AppStrings.pacePlannedTimeLine(
              _timeBufferText(_plannedTimeOverride),
            )
          : AppStrings.pacePlannedTimeLine(
              _formatElapsedMinutes(_overallPlannedFinishMinutes),
            ),
      focused: focused,
      editable: !_locked,
      cursorFirst: true,
      result: true,
      fontSize: 14,
      color: Colors.white,
      onTap: _locked ? null : () => _focusSummaryPlannedTime(),
    );
    return cell;
  }

  /// Итоги плана одной строкой в портрете: темп и время делят ширину пополам.
  Widget _plannedSummaryPairRow({
    required double height,
    required bool expanded,
  }) {
    final row = SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(child: _plannedTimeSummaryCell()),
          Expanded(child: _plannedPaceSummaryCell()),
        ],
      ),
    );
    return expanded
        ? row
        : SizedBox(
            width: _columns * _PaceViewState._fixedCellWidth,
            child: row,
          );
  }

  List<Widget> _headerCells(bool compact) {
    return List.generate(
      _columns,
      (index) => _noteCell(index, compact: compact),
    );
  }

  /// Цвет текста в ряду ПП (заголовки колонок и заметки). Такой же, как у
  /// итоговых подписей «Общее время» / «Темп в лимит».
  Color? _textColorForRow() {
    return AppColors.result;
  }

  Widget _noteCell(int index, {required bool compact}) {
    final label = _columnLabel(index);
    final note = _notes[index];
    final dayBorder = _dayBorderColor(index, _limitDays);
    final bold = _boldColumns.contains(index);
    final textColor = _textColorForRow();

    if (compact) {
      final editable = !_locked;
      final numericLabel = int.tryParse(label) != null;
      final borderColor = bold
          ? Colors.grey.shade500
          : dayBorder ??
                (editable ? Colors.grey.shade700 : Colors.grey.shade900);

      return _noteSemantics(
        index,
        label: label,
        note: note,
        enabled: editable,
        child: InkWell(
          key: ValueKey('pace-note-$index'),
          onTap: editable ? () => _editNote(index) : null,
          onLongPress: () => _toggleBoldColumn(index),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border.all(color: borderColor, width: bold ? 3 : 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: textColor ?? Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                if (note.isNotEmpty) ...[
                  SizedBox(width: 2),
                  Expanded(
                    // Номер ПП занимает меньше места, чтобы заметке осталось
                    // больше ширины и её шрифт не мельчал.
                    flex: numericLabel ? 5 : 3,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        note,
                        maxLines: 1,
                        style: TextStyle(
                          color: textColor ?? Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final editable = !_locked;
    final borderColor = bold
        ? Colors.grey.shade500
        : dayBorder ?? (editable ? Colors.grey.shade700 : Colors.grey.shade900);
    return _noteSemantics(
      index,
      label: label,
      note: note,
      enabled: editable,
      child: InkWell(
        key: ValueKey('pace-note-$index'),
        onTap: editable ? () => _editNote(index) : null,
        onLongPress: () => _toggleBoldColumn(index),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border.all(color: borderColor, width: bold ? 3 : 1),
          ),
          child: Column(
            children: [
              Expanded(
                flex: note.isEmpty ? 1 : 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: textColor ?? Colors.white,
                      fontSize: 30,
                      height: 1,
                    ),
                  ),
                ),
              ),
              if (note.isNotEmpty)
                Expanded(
                  flex: 3,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Reduce note font size by one step and decrease text color brightness using .withValues() instead of deprecated .withOpacity()
                      final fontSize =
                          (_noteFontSize(note, constraints.maxWidth) - 1.0)
                              .clamp(8.0, 19.0);
                      final adjustedTextColor =
                          textColor?.withValues(
                            red: 255,
                            green: 229,
                            blue: 214,
                          ) ??
                          Colors.white;
                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          child: Text(
                            note,
                            maxLines: 3,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: adjustedTextColor,
                              fontSize: fontSize,
                              height: 1.05,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Заголовок колонки с заметкой читается целиком, а подсказка объясняет
  /// долгое нажатие, которое выделяет колонку.
  Widget _noteSemantics(
    int index, {
    required String label,
    required String note,
    required bool enabled,
    required Widget child,
  }) {
    return Semantics(
      label: note.isEmpty ? label : '$label, $note',
      hint: AppStrings.paceLongPressColumn,
      button: true,
      excludeSemantics: true,
      onTap: enabled ? () => _editNote(index) : null,
      onLongPress: () => _toggleBoldColumn(index),
      child: child,
    );
  }

  /// Подбирает размер заметки так, чтобы самое длинное слово помещалось в
  /// клетку целиком. Короткие заметки остаются крупными, длинные — мельче.
  double _noteFontSize(String note, double width) {
    var longest = 1;
    for (final word in note.split(RegExp(r'\s+'))) {
      if (word.length > longest) longest = word.length;
    }
    final byWidth = width / (longest * 0.58);
    return byWidth.clamp(9.0, 20.0);
  }

  void _toggleBoldColumn(int index) {
    _update(() {
      if (!_boldColumns.add(index)) _boldColumns.remove(index);
    });
  }

  List<Widget> _timeCells() {
    return List.generate(_columns, (index) {
      final focused =
          _focus.kind == _PaceFocusKind.tableTime &&
          _focus.tableColumn == index;
      // Красным подсвечиваются обе клетки, если план позже лимита.
      final highlight = _limitTimeHighlight(index);
      // Row 1 (index 0 in times row) has default tan color
      final textColor = _cellTextColor(1);
      final editable = !_locked && !_lockedLimits;

      return _interactiveCell(
        key: 'pace-table-time-$index',
        text: _tableTimeText(index),
        placeholder: _tableTimes[index].isEmpty,
        focused: focused,
        editable: editable,
        dayBorder: _dayBorderColor(index, _limitDays),
        boldBorder: _boldColumns.contains(index),
        color: highlight ?? textColor,
        semanticLabel: AppStrings.paceLimitSemantic(_tableTimeText(index)),
        semanticHint: _statusFor(index) == PlanTimeStatus.behindLimit
            ? AppStrings.pacePlanBehind
            : null,
        onTap: editable ? () => _focusTableTime(index) : null,
      );
    });
  }

  List<Widget> _distanceCells() {
    return List.generate(_columns, (index) {
      final focused =
          _focus.kind == _PaceFocusKind.tableDistance &&
          _focus.tableColumn == index;
      // Row 2 (index 1 in distances row) has default tan color
      final textColor = _cellTextColor(2);
      final editable = !_locked && !_lockedLimits;

      return _interactiveCell(
        key: 'pace-table-distance-$index',
        text: _tableDistanceText(index),
        placeholder: _tableDistances[index].isEmpty,
        focused: focused,
        editable: editable,
        dayBorder: _dayBorderColor(index, _limitDays),
        boldBorder: _boldColumns.contains(index),
        color: textColor,
        onTap: editable ? () => _focusTableDistance(index) : null,
      );
    });
  }

  /// Темп сегмента для ряда: чистый (по лимиту) или «с учётом стоянок»
  /// по прибытиям плана, если включён переключатель в меню (§5).
  int? _segmentPaceFor(int index) {
    if (!_showStopsInPace || !_mountainEnabled) return _segmentPace(index);
    final arrivals = PaceTableCalculator.elapsedByColumn(
      _planTimes,
      columns: _columns,
    );
    final pace = stopsAwareSegmentPace(
      arrivalSec: [
        for (final minutes in arrivals) minutes == null ? null : minutes * 60.0,
      ],
      // Длина сегмента `i−1 → i` = разность накопленных дистанций.
      distancesKm: [
        for (var i = 1; i < _columns; i++)
          (parseDecimal(_tableDistances[i]) ?? 0) -
              (parseDecimal(_tableDistances[i - 1]) ?? 0),
      ],
      column: index,
    );
    return pace?.round();
  }

  List<Widget> _segmentPaceCells() {
    final paces = List<int?>.generate(_columns, _segmentPaceFor);
    return List.generate(_columns, (index) {
      final pace = paces[index];
      const baseColor = AppColors.focus;
      // Самая быстрая дистанция — красным, вторая — жёлтым, остальные зелёные.
      final color = _paceHighlight(index, paces) ?? baseColor;

      return _interactiveCell(
        key: 'pace-table-pace-$index',
        text: index == 0
            ? 'PACE'
            : pace == null
            ? '—'
            : formatPaceSeconds(pace),
        result: true,
        color: color,
        dayBorder: _dayBorderColor(index, _limitDays),
        boldBorder: _boldColumns.contains(index),
        onTap: _hideKeyboard,
      );
    });
  }

  List<Widget> _planTimeCells() {
    return List.generate(_columns, (index) {
      final focused =
          _focus.kind == _PaceFocusKind.tablePlanTime &&
          _focus.tableColumn == index;
      // Row 6 has white color for plan time
      final textColor = _cellTextColor(6, isPlanRow: true);
      // Красным — план позже лимита, жёлтым — план лучше лимита менее чем
      // на 20 минут.
      final highlight = _planTimeHighlight(index);
      final statusHint = switch (_statusFor(index)) {
        PlanTimeStatus.behindLimit => AppStrings.paceBehindLimit,
        PlanTimeStatus.closeToLimit => AppStrings.paceCloseToLimit,
        PlanTimeStatus.normal => null,
      };
      final editable = !_locked;

      return _interactiveCell(
        key: 'pace-plan-time-$index',
        text: _planTimeText(index),
        placeholder: _planTimes[index].isEmpty,
        focused: focused,
        editable: editable,
        cursorFirst: focused,
        dayBorder: _dayBorderColor(index, _planDays),
        boldBorder: _boldColumns.contains(index),
        color: highlight ?? textColor,
        semanticLabel: AppStrings.pacePlanSemantic(_planTimeText(index)),
        semanticHint: statusHint,
        onTap: editable ? () => _focusPlanTime(index) : null,
      );
    });
  }

  List<Widget> _planPaceCells() {
    final paces = List<int?>.generate(_columns, _plannedPace);
    return List.generate(_columns, (index) {
      if (index == 0) {
        return _interactiveCell(
          key: 'pace-plan-pace-0',
          text: '↓\npace',
          maxLines: 2,
          fontSize: 14,
          result: true,
          color: Colors.white,
          dayBorder: _dayBorderColor(index, _planDays),
          boldBorder: _boldColumns.contains(index),
          onTap: _hideKeyboard,
          onLongPress: _toggleStopsRow,
        );
      }

      final focused =
          _focus.kind == _PaceFocusKind.tablePlanPace &&
          _focus.tableColumn == index;
      // Row 7 has white color for plan pace
      final textColor = _cellTextColor(7, isPlanRow: true);
      final planned = paces[index];
      final editable = !_locked;

      return _interactiveCell(
        key: 'pace-plan-pace-$index',
        text: _planPaceText(index),
        placeholder: !focused && planned == null,
        focused: focused,
        editable: editable,
        cursorFirst: focused,
        color: textColor,
        dayBorder: _dayBorderColor(index, _planDays),
        boldBorder: _boldColumns.contains(index),
        onTap: editable ? () => _focusPlanPace(index) : null,
      );
    });
  }

  /// Ряд стоянок (§7.4): целые минуты, пусто = 0. Колонки 0 и финиш — без
  /// стоянок. Красный — «План» выходит за лимит (`isPlanRed`), см. ряд
  /// плана-времени.
  List<Widget> _stopsCells({bool compact = false}) {
    return List.generate(_columns, (index) {
      if (index == 0 || index == _columns - 1) {
        return _interactiveCell(
          key: 'pace-stop-$index',
          text: index == 0 && !compact ? AppStrings.paceRowStops : '',
          result: true,
          color: Colors.grey,
          fontSize: 14,
          dayBorder: _dayBorderColor(index, _planDays),
          boldBorder: _boldColumns.contains(index),
          onTap: _hideKeyboard,
          onLongPress: _toggleStopsRow,
        );
      }
      final focused =
          _focus.kind == _PaceFocusKind.tableStop &&
          _focus.tableColumn == index;
      final minutes = _stopMinutes(index);
      return _interactiveCell(
        key: 'pace-stop-$index',
        text: focused
            ? _stopBufferText(index)
            : (minutes == 0 ? '0' : '$minutes'),
        placeholder: !focused && minutes == 0,
        focused: focused,
        editable: !_locked,
        cursorFirst: focused,
        color: Colors.white,
        dayBorder: _dayBorderColor(index, _planDays),
        boldBorder: _boldColumns.contains(index),
        semanticLabel: AppStrings.paceStopsHint,
        onTap: _locked ? null : () => _focusStop(index),
        onLongPress: _toggleStopsRow,
      );
    });
  }

  /// Итог стоянок для колонки Total (ландшафт): сумма по ПП, сек → ч:мм.
  String _formatStopsTotal() {
    final total = sumIntermediateStops(_stopsSecList(), _columns);
    if (total <= 0) return '0';
    return _formatElapsedMinutes((total / 60).round());
  }

  void _focusStop(int column) {
    if (_locked) return;
    _beginTableFocus(_PaceFocus.tableStop(column));
  }

  void _toggleStopsRow() {
    _hideKeyboard();
    _update(() => _stopsRowOpen = !_stopsRowOpen, persist: false);
  }

  Widget _wrappedTextRow({
    required List<String> values,
    required String keyPrefix,
    required String title,
    required double height,
    required bool expanded,
    required bool showFirstPlaceholder,
    Widget? total,
    double fontSize = 11.5,
  }) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final width = expanded
            ? constraints.maxWidth
            : _columns * _PaceViewState._fixedCellWidth;
        final cellWidth = width / _columns;
        final covered = List<bool>.filled(_columns, false);
        for (var index = 0; index < _columns; index++) {
          if (values[index].isEmpty) continue;
          for (
            var next = index + 1;
            next < _columns && values[next].isEmpty;
            next++
          ) {
            covered[next] = true;
          }
        }

        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              for (var index = 0; index < _columns; index++)
                Positioned(
                  left: index * cellWidth + 0.5,
                  top: 0,
                  width: cellWidth - 1,
                  height: height,
                  child: _wrappedTextCellBackground(
                    values: values,
                    keyPrefix: keyPrefix,
                    title: title,
                    index: index,
                    showPlaceholder:
                        showFirstPlaceholder &&
                        index == 0 &&
                        values[index].isEmpty,
                    showDash:
                        index != 0 && values[index].isEmpty && !covered[index],
                  ),
                ),
              for (var index = 0; index < _columns; index++)
                if (values[index].isNotEmpty)
                  Positioned(
                    left: index * cellWidth + 0.5,
                    top: 0,
                    width: cellWidth * _overflowSpan(values, index) - 1,
                    height: height,
                    child: IgnorePointer(
                      child: _wrappedTextContent(
                        value: values[index],
                        keyPrefix: keyPrefix,
                        keySuffix: '$keyPrefix-text-$index',
                        height: height,
                        fontSize: fontSize,
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );

    return SizedBox(
      height: height,
      child: Row(
        children: [
          if (expanded)
            Expanded(child: content)
          else
            SizedBox(
              width: _columns * _PaceViewState._fixedCellWidth,
              child: content,
            ),
          if (total != null)
            SizedBox(
              width: _totalColumnWidth,
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0.5),
                child: total,
              ),
            ),
        ],
      ),
    );
  }

  int _overflowSpan(List<String> values, int index) {
    var span = 1;
    for (
      var next = index + 1;
      next < values.length && values[next].isEmpty;
      next++
    ) {
      span++;
    }
    return span;
  }

  Widget _wrappedTextCellBackground({
    required List<String> values,
    required String keyPrefix,
    required String title,
    required int index,
    required bool showPlaceholder,
    required bool showDash,
  }) {
    final editable = !_locked;
    final bold = _boldColumns.contains(index);
    final borderColor = bold
        ? Colors.grey.shade500
        : _dayBorderColor(index, _limitDays) ??
              (editable ? Colors.grey.shade700 : Colors.grey.shade900);

    return InkWell(
      key: ValueKey('$keyPrefix-$index'),
      onTap: editable
          ? () => _editListCell(
              title: '$title ${_columnLabel(index)}',
              values: values,
              index: index,
            )
          : null,
      child: Container(
        alignment: Alignment.topLeft,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: borderColor, width: bold ? 3 : 1),
        ),
        child: showPlaceholder
            ? Center(
                child: Text(
                  title,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
              )
            : showDash
            ? Center(
                child: Text(
                  '—',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _wrappedTextContent({
    required String value,
    required String keyPrefix,
    required String keySuffix,
    required double height,
    double fontSize = 11.5,
  }) {
    return PaceWrappedTextContent(
      value: value,
      cellKeySuffix: keySuffix,
      height: height,
      fontSize: fontSize,
      water: keyPrefix == 'pace-water',
    );
  }

  Widget _interactiveCell({
    required String key,
    required String text,
    bool focused = false,
    bool editable = false,
    bool placeholder = false,
    bool result = false,
    bool bold = false,
    bool cursorFirst = false,
    int maxLines = 1,
    double fontSize = 30,
    Color? color,
    Color? dayBorder,
    bool boldBorder = false,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    String? semanticLabel,
    String? semanticHint,
    List<TextSpan>? spans,
  }) {
    return PaceInteractiveCell(
      cellKey: key,
      text: text,
      focusAnchorKey: _focusAnchorKey,
      focused: focused,
      editable: editable,
      placeholder: placeholder,
      result: result,
      bold: bold,
      cursorFirst: cursorFirst,
      cursorActive: widget.active,
      maxLines: maxLines,
      fontSize: fontSize,
      color: color,
      dayBorder: dayBorder,
      boldBorder: boldBorder,
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: semanticLabel,
      semanticHint: semanticHint,
      spans: spans,
    );
  }

  void _onPadKey(String key) {
    if (key == AppStrings.ok) {
      unawaited(_commitInput());
      return;
    }
    if (key == '⌫') {
      _backspaceActive();
      return;
    }
    if (key == AppStrings.reset) {
      _clearActive();
      return;
    }

    for (final char in key.split('')) {
      _appendActive(char);
    }
  }
}
