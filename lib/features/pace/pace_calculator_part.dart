part of 'pace_view.dart';

extension _PaceCalculatorPart on _PaceViewState {
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
        const SizedBox(height: 4),
        _buildGelEveryRow(),
        _buildGelStats(),
        const SizedBox(height: 8),
        _buildSplitSection(),
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
    required VoidCallback? onTap,
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
    final text = _topDistance();
    final named =
        text == AppStrings.paceMarathon || text == AppStrings.paceHalfMarathon;

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
            text: text,
            editable: !result,
            focused: _isTopFocused(_PaceTopField.distance),
            onTap: () => _focusTop(_PaceTopField.distance),
            hint: AppStrings.paceHintKm,
          ),
        ),
        if (_calc != _PaceCalc.distance) ...[
          const SizedBox(width: 4),
          _distancePresetButton(),
        ],
        SizedBox(
          width: 44,
          child: named
              ? null
              : const Padding(
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

  /// Компактная кнопка с готовыми дистанциями: 42.195, 21.097, 10 и 5 км.
  Widget _distancePresetButton() {
    return PopupMenuButton<String>(
      key: const ValueKey('pace-distance-presets'),
      tooltip: AppStrings.paceDistancePresets,
      padding: EdgeInsets.zero,
      onSelected: (value) {
        _update(() {
          _distance = value;
          _focus = const _PaceFocus.none();
          _keyboardVisible = false;
        });
      },
      itemBuilder: (context) => [
        for (final value in const ['42.195', '21.097', '10', '5'])
          PopupMenuItem<String>(
            key: ValueKey('pace-distance-preset-$value'),
            value: value,
            child: Text(switch (value) {
              '42.195' => '$value — ${AppStrings.paceMarathon}',
              '21.097' => '$value — ${AppStrings.paceHalfMarathon}',
              _ => value,
            }),
          ),
      ],
      child: Container(
        width: 30,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: Colors.grey.shade700),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(
          Icons.arrow_drop_down,
          size: 20,
          color: Colors.white70,
        ),
      ),
    );
  }

  Widget _buildSplitSection() {
    final data = _splitTableData();
    if (data == null) return const SizedBox.shrink();

    final norm = PaceNormatives.lookup(
      distanceKm: data.distance,
      timeSeconds: data.time,
    );
    final male = norm?.male;
    final female = norm?.female;
    final normative = <Widget>[
      if (male != null) _normativeLabel(AppStrings.paceNormativeMale, male),
      if (female != null) ...[
        if (male != null) const SizedBox(width: 10),
        _normativeLabel(AppStrings.paceNormativeFemale, female),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Сплит: положительный — быстрый старт, отрицательный — финиш.
            Expanded(
              child: Row(
                children: [
                  const Text(
                    AppStrings.paceSplitPercentPrint,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _field(
                      key: 'pace-split-percent',
                      text: _splitPercentText(),
                      editable: true,
                      focused: _isTopFocused(_PaceTopField.splitPercent),
                      onTap: () => _focusTop(_PaceTopField.splitPercent),
                      hint: AppStrings.paceSplitPercentHint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Разряды делят ряд со сплитом поровну.
            Expanded(
              child: normative.isEmpty
                  ? const SizedBox.shrink()
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(children: normative),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _buildSplitTable(data),
      ],
    );
  }

  Widget _normativeLabel(String gender, String category) {
    return Text(
      '$gender — $category',
      style: const TextStyle(
        color: AppColors.result,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  _SplitTableData? _splitTableData() {
    final distance = _effectiveDistance;
    final pace = _effectivePace;
    final time = _effectiveTime;
    final split = _splitDistanceValue;
    if (distance == null ||
        pace == null ||
        time == null ||
        split == null ||
        distance <= 0 ||
        pace <= 0 ||
        time <= 0 ||
        split <= 0) {
      return null;
    }

    final points = PaceTableCalculator.splitPoints(
      distanceKm: distance,
      splitKm: split,
      paceSeconds: pace,
      startSeconds: _startTimeMinutes * 60,
      splitPercent: _splitPercentValue ?? 0,
    );
    if (points.isEmpty) return null;

    return _SplitTableData(
      distance: distance,
      pace: pace,
      time: time,
      split: split,
      splitPercent: _splitPercentValue ?? 0,
      points: points,
    );
  }

  Widget _buildSplitTable(_SplitTableData data) {
    final truncated =
        data.distance / data.split > PaceTableCalculator.maxSplitRows + 1e-9;
    final gelTexts = _gelRowTexts(data);

    return Container(
      key: const ValueKey('pace-split-table'),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade700),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: AppColors.surfaceRaised,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                const SizedBox(
                  width: 58,
                  child: Text(
                    AppStrings.paceSplitTableDistance,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: Text(
                    AppStrings.paceGelLeftHeader,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 4,
                  child: Text(
                    AppStrings.paceGelRightHeader,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 6),
                const SizedBox(
                  width: 58,
                  child: Text(
                    AppStrings.paceSplitTableTime,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < data.points.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 58,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        data.labelAt(index),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 3,
                    child: _gelCell(
                      key: 'pace-split-left-$index',
                      text: gelTexts[index].left,
                      onTap: () => _editGelLeft(index),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 4,
                    child: _gelCell(
                      key: 'pace-split-right-$index',
                      text: gelTexts[index].right,
                      onTap: () => _editGelRight(index, data),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 58,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        PaceTableCalculator.formatClockTime(
                          data.points[index].seconds,
                        ),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: AppColors.result,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (truncated)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 7),
              child: Text(
                AppStrings.paceSplitTruncated(PaceTableCalculator.maxSplitRows),
                style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showSplitPrintDialog() async {
    final data = _splitTableData();
    if (data == null) return;

    final choice = await showDialog<_SplitPrintChoice>(
      context: context,
      builder: (dialogContext) {
        var layout = PaceSplitPrintLayout.twoColumns;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(AppStrings.paceSplitPrintTitle),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      AppStrings.paceSplitPrintDescription,
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      AppStrings.paceSplitPrintLayout,
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<PaceSplitPrintLayout>(
                      key: const ValueKey('pace-print-layout'),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: PaceSplitPrintLayout.twoColumns,
                          label: Text(AppStrings.paceSplitPrintTwoColumns),
                        ),
                        ButtonSegment(
                          value: PaceSplitPrintLayout.threeColumns,
                          label: Text(AppStrings.paceSplitPrintThreeColumns),
                        ),
                      ],
                      selected: {layout},
                      onSelectionChanged: (values) {
                        setDialogState(() => layout = values.first);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(AppStrings.cancel),
                ),
                OutlinedButton(
                  key: const ValueKey('pace-print-pdf'),
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    _SplitPrintChoice(share: true, layout: layout),
                  ),
                  child: const Text('PDF'),
                ),
                FilledButton(
                  key: const ValueKey('pace-print-now'),
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    _SplitPrintChoice(share: false, layout: layout),
                  ),
                  child: const Text(AppStrings.pacePrintAction),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted || choice == null) return;

    try {
      final bytes = await buildPaceSplitPdf(
        _buildSplitPrintData(data),
        layout: choice.layout,
      );
      if (!mounted) return;
      final fileName = _splitPrintFileName();
      if (choice.share) {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      } else {
        await Printing.layoutPdf(name: fileName, onLayout: (_) async => bytes);
      }
    } catch (error) {
      if (mounted) _showMessage(AppStrings.pacePrintFailed(error));
    }
  }

  PaceSplitPrintData _buildSplitPrintData(_SplitTableData data) {
    final breakdown = PaceTableCalculator.splitBreakdown(
      points: data.points,
      distanceKm: data.distance,
      splitKm: data.split,
      paceSeconds: data.pace,
      startSeconds: _startTimeMinutes * 60,
    );
    final percent = AppStrings.formatSplitPercent(
      data.splitPercent.clamp(
        -PaceTableCalculator.maxSplitPercent,
        PaceTableCalculator.maxSplitPercent,
      ),
    );
    final splitLine = '${AppStrings.paceSplitPercentPrint} $percent';
    final paceLine = breakdown == null
        ? null
        : '(${PaceTableCalculator.formatPaceDelta(breakdown.startPace - data.pace)} '
              '${formatPaceSeconds(breakdown.middlePace)} '
              '${PaceTableCalculator.formatPaceDelta(breakdown.finishPace - data.pace)})';
    final gelTexts = _gelRowTexts(data);

    return PaceSplitPrintData(
      title: AppStrings.paceSplitPrintDocumentTitle,
      summary: [
        '${AppStrings.paceCalcDistance}: '
            '${PaceTableCalculator.formatDistanceValue(data.distance)} '
            '${AppStrings.paceHintKm}',
        '${AppStrings.paceCalcPace}: ${formatPaceSeconds(data.pace)} '
            '${AppStrings.paceHintPace}',
        '${AppStrings.paceCalcTime}: '
            '${PaceTableCalculator.formatDurationSeconds(data.time)}',
        '${AppStrings.paceSplitPrintStart}: ${_startTimePrintText()}',
        '${AppStrings.paceCalcSplit}: '
            '${PaceTableCalculator.formatDistanceValue(data.split)} '
            '${AppStrings.paceHintKm}',
        splitLine,
        ?paceLine,
        ?_gelEveryPrintLine(),
        ?_gelCountsPrintLine(data),
        ?_gelStatsPrintLine(data),
      ],
      points: [
        for (var index = 0; index < data.points.length; index++)
          PaceSplitPrintPoint(
            distance: data.labelAt(index),
            time: PaceTableCalculator.formatClockTime(
              data.points[index].seconds,
            ),
            left: gelTexts[index].left,
            right: gelTexts[index].right,
          ),
      ],
    );
  }

  String _startTimePrintText() {
    final hours = _startHours.isEmpty ? '00' : _startHours.padLeft(2, '0');
    final minutes = _startMinutes.isEmpty
        ? '00'
        : _startMinutes.padLeft(2, '0');
    return '$hours:$minutes';
  }

  String _splitPrintFileName() {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    return 'uRunCalc_split_$stamp.pdf';
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
}

/// Выбранный макет и способ вывода печатной раскладки.
class _SplitPrintChoice {
  const _SplitPrintChoice({required this.share, required this.layout});

  final bool share;
  final PaceSplitPrintLayout layout;
}

/// Данные раскладки, общие для экранной таблицы и печати.
class _SplitTableData {
  const _SplitTableData({
    required this.distance,
    required this.pace,
    required this.time,
    required this.split,
    required this.splitPercent,
    required this.points,
  });

  final double distance;
  final int pace;
  final int time;
  final double split;
  final double splitPercent;
  final List<PaceSplitPoint> points;

  String labelAt(int index) {
    final point = points[index];
    if (point.isFinish) return AppStrings.paceSplitFinish;
    return PaceTableCalculator.splitDistanceLabel(split, index + 1);
  }
}
