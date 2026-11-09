part of 'pace_view.dart';

extension _PaceTablePart on _PaceViewState {
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
        const compactLabelWidth = 58.0;
        final compactAvailableWidth = math.max(
          1.0,
          constraints.maxWidth - compactLabelWidth,
        );
        final compactTableWidth = _fitTable
            ? compactAvailableWidth
            : _columns * _PaceViewState._fixedCellWidth + _totalColumnWidth;
        // В ландшафте полоса профиля заканчивается на «Финише» и не заезжает
        // на служебную колонку Total.
        final compactDataWidth = math.max(
          0.0,
          compactTableWidth - _totalColumnWidth,
        );

        // Ряд высот (горный режим) вставляется после «Темпа сегмента» в обоих
        // режимах, поэтому подписи и высоты строятся от одного списка рядов.
        final elevationOn = _mountainEnabled;
        // Полоса профиля раскрывается под блоком высот, как ряд стоянок.
        // Без трека с высотами не раскрываем: показывать нечего.
        final stripOn = elevationOn && _elevationRowOpen && _hasElevationData;
        // Ряд стоянок раскрывается строкой под «Плановым темпом» (§7.4).
        final stopsOn = _stopsRowOpen ? 1 : 0;
        final compactLabels = <String>[
          '',
          AppStrings.paceRowLimit,
          AppStrings.paceRowDistance,
          AppStrings.paceRowSegmentPace,
          if (elevationOn) AppStrings.paceRowElevation,
          if (stripOn) '',
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
          if (stripOn) '',
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
          // Горный режим: ряд высот вставлен после «Темпа сегмента», а
          // «Вода» и «Еда» уступают ему место поровну.
          final weights = <double>[
            1.3,
            1.3,
            1.3,
            1.3,
            if (elevationOn) 1.3,
            if (stripOn) 2.4,
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
          // Темп сегмента идёт сразу под расстоянием, как в портрете.
          rows.add(
            _tableRow(
              cells: _segmentPaceCells(),
              height: heights[next++],
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
          if (elevationOn) {
            rows.add(
              _tableRow(
                cells: _elevationCells(),
                height: heights[next++],
                expanded: _fitTable,
                total: _elevationTotalCell(),
              ),
            );
          }
          if (stripOn) {
            rows.add(
              _elevationStripRow(
                height: heights[next++],
                width: compactDataWidth,
              ),
            );
          }
          rows.add(
            _tableRow(
              cells: _planTimeCells(),
              height: heights[next++],
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
              height: heights[next++],
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
                height: heights[next++],
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
              height: heights[next++],
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
              height: heights[next++],
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
            if (stripOn) {
              rows.add(
                _elevationStripRow(
                  height: _PaceViewState._elevationStripHeight,
                ),
              );
            }
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
          final table = SizedBox(
            width: compactTableWidth,
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
                width: compactLabelWidth,
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
                child: KeyedSubtree(
                  key: _tableViewportKey,
                  child: _fitTable
                      ? table
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: table,
                        ),
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

        return KeyedSubtree(
          key: _tableViewportKey,
          child: _fitTable
              ? table
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: table,
                ),
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
