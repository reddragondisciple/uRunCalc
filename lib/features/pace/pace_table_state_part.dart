part of 'pace_view.dart';

extension _PaceTableStatePart on _PaceViewState {
  PaceTableData _snapshotTable() {
    return PaceTableData(
      columns: _columns,
      fitTable: _fitTable,
      times: List<String>.of(_tableTimes),
      distances: List<String>.of(_tableDistances),
      planTimes: List<String>.of(_planTimes),
      planPaces: List<String>.of(_planPaces),
      notes: List<String>.of(_notes),
      water: List<String>.of(_water),
      food: List<String>.of(_food),
      locked: _locked,
      lockedLimits: _lockedLimits,
      plannedPaceOverride: _plannedPaceOverride,
      plannedTimeOverride: _plannedTimeOverride,
      plannedSummarySource: _plannedSummarySource,
      seeded: _seeded,
      boldColumns: List<int>.of(_boldColumns),
      mountain: _currentTableMountain(),
    );
  }

  /// Горные данные текущей таблицы. Треки и ручные высоты пока не редактируются
  /// экраном, поэтому переносим сохранённые, чтобы правка таблицы их не стирала.
  MountainData _currentTableMountain() {
    final saved = _controller.currentTable?.mountain ?? MountainData.empty;
    return MountainData(
      enabled: _mountainEnabled,
      stopsSec: _stopsSec,
      anchor: _planAnchor,
      tracks: _tracks,
      manualAscent: saved.manualAscent,
      manualDescent: saved.manualDescent,
      showStopsInPace: _showStopsInPace,
    );
  }

  void _saveCurrentTable() => _controller.saveCurrent(_snapshotTable());

  void _loadCurrentTable() {
    _boldColumns.clear();
    _loadedTrack = null;
    _loadedTrackKey = null;
    _clearDerivedTrackCache();
    _elevationRowOpen = false;
    final data = _controller.currentTable;
    if (data == null) {
      final distance = _controller.currentDistance;
      _resetTable(
        distance == null
            ? _PaceViewState._baseColumns
            : distance.checkpoints + 2,
        distance,
      );
      _saveCurrentTable();
      return;
    }

    _applyTableData(data);
    unawaited(_ensureTrackLoaded());
  }

  /// Раскладывает снимок таблицы по полям ввода.
  void _applyTableData(PaceTableData data) {
    _mountainEnabled = data.mountain.enabled;
    _showStopsInPace = data.mountain.showStopsInPace;
    _tracks = data.mountain.tracks;
    _planAnchor = data.mountain.anchor;
    _stopsSec = data.mountain.stopsSec;
    _columns = data.columns.clamp(3, _PaceViewState._maxColumns);
    _boldColumns.addAll(
      data.boldColumns.where((index) => index >= 0 && index < _columns),
    );
    _fitTable = data.fitTable;
    _tableTimes = _resizeList(data.times, _columns);
    _tableDistances = _resizeList(data.distances, _columns);
    _planTimes = _resizeList(data.planTimes, _columns);
    _planPaces = _resizeList(data.planPaces, _columns);
    _notes = _resizeList(data.notes, _columns);
    _water = _resizeList(data.water, _columns);
    _food = _resizeList(data.food, _columns);
    _tableDistances[0] = '0.00';
    _locked = data.locked;
    _lockedLimits = data.lockedLimits;
    _keyboardVisible = false;
    _replacePlanInput = false;
    _planTimesBeforeEdit = null;
    _planEditColumn = null;
    _plannedPaceOverride = data.plannedPaceOverride;
    _plannedTimeOverride = data.plannedTimeOverride;
    _plannedSummarySource = data.plannedSummarySource;
    _seeded = data.seeded;
    _limitDays = _computeDays(_tableTimes);
    _planDays = _computeDays(_planTimes);

    if (!data.seeded) {
      // Старая таблица без флага: заполняем стартовыми данными только если
      // пользователь ещё ничего не ввёл, и больше не трогаем её при загрузке.
      _seeded = true;
      if (data.isEmpty) {
        final distance = _controller.currentDistance;
        if (distance != null) _applyDistanceDefaults(distance);
      }
      _saveCurrentTable();
    }
  }

  void _resetTable(int columns, [PaceDistance? distance]) {
    _elevationRowOpen = false;
    _clearDerivedTrackCache();
    _mountainEnabled = false;
    _showStopsInPace = false;
    _tracks = TrackSlots.empty;
    _planAnchor = null;
    _stopsSec = const <int>[];
    final clamped = columns.clamp(3, _PaceViewState._maxColumns).toInt();
    _columns = clamped;
    _fitTable = true;
    _tableTimes = List.filled(clamped, '');
    _tableDistances = List.filled(clamped, '');
    _planTimes = List.filled(clamped, '');
    _planPaces = List.filled(clamped, '');
    _notes = List.filled(clamped, '');
    _water = List.filled(clamped, '');
    _food = List.filled(clamped, '');
    _tableDistances[0] = '0.00';
    _seeded = true;

    if (distance != null) _applyDistanceDefaults(distance);

    _locked = false;
    _lockedLimits = false;
    _keyboardVisible = false;
    _boldColumns.clear();
    _plannedPaceOverride = '';
    _plannedTimeOverride = '';
    _plannedSummarySource = PacePlannedSummarySource.none;
    _replacePlanInput = false;
    _planTimesBeforeEdit = null;
    _planEditColumn = null;
    _limitDays = _computeDays(_tableTimes);
    _planDays = _computeDays(_planTimes);
  }

  void _applyDistanceDefaults(PaceDistance distance) {
    for (var index = 0; index < _columns; index++) {
      if (index < distance.defaultTimes.length) {
        _tableTimes[index] = distance.defaultTimes[index];
      }
      if (index > 0 && index < distance.defaultDistances.length) {
        _tableDistances[index] = distance.defaultDistances[index];
      }
    }
    _limitDays = _computeDays(_tableTimes);
    _planDays = _computeDays(_planTimes);
  }

  void _resizeTable(int columns) {
    final clamped = columns.clamp(3, _PaceViewState._maxColumns).toInt();
    if (clamped == _columns) return;

    _update(() {
      _columns = clamped;
      if (clamped <= _PaceViewState._baseColumns) _fitTable = true;
      _tableTimes = _resizeList(_tableTimes, clamped);
      _tableDistances = _resizeList(_tableDistances, clamped);
      _planTimes = _resizeList(_planTimes, clamped);
      _planPaces = _resizeList(_planPaces, clamped);
      _notes = _resizeList(_notes, clamped);
      _water = _resizeList(_water, clamped);
      _food = _resizeList(_food, clamped);
      _tableDistances[0] = '0.00';
      _boldColumns.removeWhere((index) => index >= clamped);
      _limitDays = _computeDays(_tableTimes);
      _planDays = _computeDays(_planTimes);

      if (_focus.tableColumn >= clamped) {
        _focus = const _PaceFocus.top(_PaceTopField.distance);
      }
    });
  }

  List<String> _resizeList(List<String> source, int length) {
    return List.generate(
      length,
      (index) => index < source.length ? source[index] : '',
    );
  }
}
