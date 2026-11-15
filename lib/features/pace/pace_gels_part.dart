part of 'pace_view.dart';

/// Подписи левого и правого полей одной строки раскладки.
class PaceGelRowTexts {
  const PaceGelRowTexts({required this.left, required this.right});

  final String left;
  final String right;
}

extension _PaceGelsPart on _PaceViewState {
  PaceGelState get _gelState => PaceGelState(
    everyMinutes: _gelEveryMinutes,
    everyKm: _gelEveryKm,
    settings: _gelSettings,
    rows: Map<int, PaceGelRow>.unmodifiable(_gelRows),
  );

  double? get _gelMinutesValue => parseGelNumber(_gelEveryMinutes);

  double? get _gelKmValue => parseGelNumber(_gelEveryKm);

  /// Одновременно заполнено только одно поле: минуты важнее километров.
  void _normalizeGelInterval() {
    if ((_gelMinutesValue ?? 0) > 0) {
      _gelEveryKm = '';
    } else if ((_gelKmValue ?? 0) > 0) {
      _gelEveryMinutes = '';
    }
  }

  Future<void> _showPaceOptions() async {
    final result = await showDialog<PaceOptionsResult>(
      context: context,
      builder: (dialogContext) => PaceOptionsDialog(
        splitDistance: _splitDistance,
        startHours: _startHours,
        startMinutes: _startMinutes,
        settings: _gelSettings,
      ),
    );
    if (!mounted || result == null) return;

    _update(() {
      _splitDistance = result.splitDistance;
      _startHours = result.startHours;
      _startMinutes = result.startMinutes;
      _gelSettings = result.settings;
      _pruneGelSelections();
    });
  }

  /// Убирает из ручных строк токены удалённых своих гелей.
  void _pruneGelSelections() {
    final available = <String>{
      PaceGelTokens.simple,
      PaceGelTokens.iso,
      PaceGelTokens.coffee,
      for (final gel in _gelSettings.customGels) gel.token,
    };
    final updated = <int, PaceGelRow>{};
    for (final entry in _gelRows.entries) {
      final row = entry.value;
      final right = row.right;
      if (right == null) {
        updated[entry.key] = row;
        continue;
      }
      final filtered = [
        for (final token in right)
          if (available.contains(token)) token,
      ];
      updated[entry.key] = filtered.length == right.length
          ? row
          : row.copyWith(right: filtered);
    }
    _gelRows
      ..clear()
      ..addAll(updated);
  }

  Widget _buildGelEveryRow() {
    final minutesLocked = (_gelKmValue ?? 0) > 0;
    final kmLocked = (_gelMinutesValue ?? 0) > 0;

    return Row(
      children: [
        const SizedBox(
          width: 94,
          child: Text(
            AppStrings.paceGelEvery,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        Expanded(
          child: _field(
            key: 'pace-gel-every-minutes',
            text: _gelEveryMinutes,
            editable: !minutesLocked,
            focused: _isTopFocused(_PaceTopField.gelMinutes),
            onTap: minutesLocked
                ? null
                : () => _focusTop(_PaceTopField.gelMinutes),
            hint: '0',
          ),
        ),
        const SizedBox(
          width: 38,
          child: Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              AppStrings.paceGelEveryMinutes,
              style: TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ),
        ),
        Expanded(
          child: _field(
            key: 'pace-gel-every-km',
            text: _gelEveryKm,
            editable: !kmLocked,
            focused: _isTopFocused(_PaceTopField.gelKm),
            onTap: kmLocked ? null : () => _focusTop(_PaceTopField.gelKm),
            hint: '0',
          ),
        ),
        const SizedBox(
          width: 58,
          child: Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              AppStrings.paceGelEveryKm,
              style: TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGelStats() {
    final data = _splitTableData();
    if (data == null) return const SizedBox.shrink();
    final totals = _gelTotals(data);
    if (totals.isEmpty) return const SizedBox.shrink();

    return Container(
      key: const ValueKey('pace-gel-stats'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: Colors.grey.shade800),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${AppStrings.paceGelStats}:',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          ),
          for (final total in totals)
            Text(
              '${total.label} ${formatGelAmount(total.amount)} ${total.unit}',
              style: const TextStyle(color: AppColors.result, fontSize: 12),
            ),
        ],
      ),
    );
  }

  List<GelNutrientValue> _gelTotals(_SplitTableData data) {
    final autoRows = _autoGelRowsFor(data);
    final tokens = <String>[];
    for (var index = 0; index < data.points.length; index++) {
      final row = _gelRows[index];
      final right = row?.right;
      if (right != null) {
        tokens.addAll(right);
      } else if (autoRows.contains(index)) {
        tokens.add(PaceGelTokens.simple);
      }
    }
    return _gelSettings.totals(tokens);
  }

  Set<int> _autoGelRowsFor(_SplitTableData data) {
    return PaceGelPlanner.autoRows(
      points: data.points,
      everyMinutes: _gelEveryMinutes,
      everyKm: _gelEveryKm,
      startSeconds: _startTimeMinutes * 60,
    );
  }

  List<PaceGelRowTexts> _gelRowTexts(_SplitTableData data) {
    final autoRows = _autoGelRowsFor(data);
    final rightOptions = PaceGelCatalog.rightOptions(_gelSettings);
    return [
      for (var index = 0; index < data.points.length; index++)
        _gelRowTextsAt(
          index: index,
          auto: autoRows.contains(index),
          rightOptions: rightOptions,
        ),
    ];
  }

  PaceGelRowTexts _gelRowTextsAt({
    required int index,
    required bool auto,
    required List<GelOption> rightOptions,
  }) {
    final row = _gelRows[index];
    final left = PaceGelCatalog.labelsFor(
      selected: row?.left ?? const <String>[],
      options: PaceGelCatalog.leftOptions,
      otherText: row?.leftOther ?? '',
    );
    final selectedRight =
        row?.right ??
        (auto ? const <String>[PaceGelTokens.simple] : const <String>[]);
    final right = PaceGelCatalog.labelsFor(
      selected: selectedRight,
      options: rightOptions,
      otherText: row?.rightOther ?? '',
    );
    return PaceGelRowTexts(left: left, right: right);
  }

  Future<void> _editGelLeft(int index) async {
    final current = _gelRows[index] ?? const PaceGelRow();
    final result = await showGelSelectionDialog(
      context,
      title: AppStrings.paceGelLeftTitle,
      options: PaceGelCatalog.leftOptions,
      selected: current.left,
      otherText: current.leftOther,
    );
    if (!mounted || result == null) return;
    _update(() {
      _gelRows[index] = current.copyWith(
        left: result.selected,
        leftOther: result.other,
      );
    });
  }

  Future<void> _editGelRight(int index, _SplitTableData data) async {
    final current = _gelRows[index] ?? const PaceGelRow();
    final selected =
        current.right ??
        (_autoGelRowsFor(data).contains(index)
            ? const <String>[PaceGelTokens.simple]
            : const <String>[]);
    final result = await showGelSelectionDialog(
      context,
      title: AppStrings.paceGelRightTitle,
      options: PaceGelCatalog.rightOptions(_gelSettings),
      selected: selected,
      otherText: current.rightOther,
    );
    if (!mounted || result == null) return;
    _update(() {
      _gelRows[index] = current.copyWith(
        right: result.selected,
        rightOther: result.other,
      );
    });
  }

  Widget _gelCell({
    required String key,
    required String text,
    required Future<void> Function() onTap,
  }) {
    return InkWell(
      key: ValueKey(key),
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        constraints: const BoxConstraints(minHeight: 26),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: Colors.grey.shade800),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text.isEmpty ? AppStrings.paceGelEmpty : text,
          style: TextStyle(
            color: text.isEmpty ? Colors.grey.shade600 : Colors.white,
            fontSize: 11,
            height: 1.2,
          ),
        ),
      ),
    );
  }

  /// «Гели каждые 30 минут» / «Гели каждые 5 километров» для печати.
  String? _gelEveryPrintLine() {
    final minutes = _gelMinutesValue;
    if (minutes != null && minutes > 0) {
      return '${AppStrings.paceGelEvery}: '
          '${formatGelAmount(minutes)} ${AppStrings.paceGelEveryMinutes}';
    }
    final km = _gelKmValue;
    if (km != null && km > 0) {
      return '${AppStrings.paceGelEvery}: '
          '${formatGelAmount(km)} ${AppStrings.paceGelEveryKm}';
    }
    return null;
  }

  /// Строка статистики для печати. `null` — гелей в таблице нет.
  String? _gelStatsPrintLine(_SplitTableData data) {
    final totals = _gelTotals(data);
    if (totals.isEmpty) return null;
    return '${AppStrings.paceGelStats}: ${[for (final total in totals) '${total.label} ${formatGelAmount(total.amount)} ${total.unit}'].join(' · ')}';
  }
}
