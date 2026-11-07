part of 'pace_view.dart';

extension _PaceTableCellsPart on _PaceViewState {
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
}
