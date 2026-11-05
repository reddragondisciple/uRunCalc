part of '../../main.dart';

enum _PaceCalc { pace, distance, time }

enum _PaceTopField {
  distance,
  paceMinutes,
  paceSeconds,
  days,
  hours,
  minutes,
  seconds,
}

class _PrintRequest {
  const _PrintRequest({required this.landscape, required this.share});

  final bool landscape;
  final bool share;
}

enum _PaceFocusKind {
  none,
  top,
  tableTime,
  tableDistance,
  tablePlanTime,
  tablePlanPace,
  tableStop,
  summaryPlannedPace,
  summaryPlannedTime,
}

class _PaceFocus {
  const _PaceFocus.none()
    : kind = _PaceFocusKind.none,
      field = null,
      tableColumn = -1;

  const _PaceFocus.top(this.field)
    : kind = _PaceFocusKind.top,
      tableColumn = -1;

  const _PaceFocus.tableTime(this.tableColumn)
    : kind = _PaceFocusKind.tableTime,
      field = null;

  const _PaceFocus.tableDistance(this.tableColumn)
    : kind = _PaceFocusKind.tableDistance,
      field = null;

  const _PaceFocus.tablePlanTime(this.tableColumn)
    : kind = _PaceFocusKind.tablePlanTime,
      field = null;

  const _PaceFocus.tablePlanPace(this.tableColumn)
    : kind = _PaceFocusKind.tablePlanPace,
      field = null;

  const _PaceFocus.tableStop(this.tableColumn)
    : kind = _PaceFocusKind.tableStop,
      field = null;

  const _PaceFocus.summaryPlannedPace()
    : kind = _PaceFocusKind.summaryPlannedPace,
      field = null,
      tableColumn = -1;

  const _PaceFocus.summaryPlannedTime()
    : kind = _PaceFocusKind.summaryPlannedTime,
      field = null,
      tableColumn = -1;

  final _PaceFocusKind kind;
  final _PaceTopField? field;
  final int tableColumn;
}

enum _PaceSurface { pace, ultra }

/// Тестовая подмена хранилища треков (in-memory). В продакшене не задаётся.
@visibleForTesting
TrackFileStore? debugTrackFileStoreOverride;

class _PaceView extends StatefulWidget {
  const _PaceView({required this.active, required this.surface});

  final bool active;
  final _PaceSurface surface;

  @override
  State<_PaceView> createState() => _PaceViewState();
}

class _PaceViewState extends State<_PaceView> with WidgetsBindingObserver {
  static const int _maxColumns = PaceStateCodec.maxColumns;
  static const int _baseColumns = 8;
  static const double _fixedCellWidth = 52;

  static const List<Color> _dayColors = [
    Color(0xFF1B5E20),
    Colors.blue,
    AppColors.warning,
    AppColors.danger,
    Colors.cyan,
    Colors.orange,
    Colors.white,
  ];

  _PaceCalc _calc = _PaceCalc.pace;
  _PaceFocus _focus = const _PaceFocus.top(_PaceTopField.distance);

  /// Мероприятия, выбранная таблица и снимки всех таблиц.
  late final PaceStateController _controller = PaceStateController.defaults();

  String _distance = '';
  String _paceMinutes = '';
  String _paceSeconds = '';
  String _days = '';
  String _hours = '';
  String _minutes = '';
  String _seconds = '';

  int _columns = _baseColumns;
  bool _fitTable = true;

  late List<String> _tableTimes;
  late List<String> _tableDistances;
  late List<String> _planTimes;
  late List<String> _planPaces;
  late List<String> _notes;
  late List<String> _water;
  late List<String> _food;

  late List<int> _limitDays;
  late List<int> _planDays;

  bool _locked = false;
  bool _lockedLimits = false;
  bool _keyboardVisible = false;

  String _plannedPaceOverride = '';
  String _plannedTimeOverride = '';
  PacePlannedSummarySource _plannedSummarySource =
      PacePlannedSummarySource.none;

  /// Стартовые данные этой таблицы уже применены или проверены.
  bool _seeded = false;

  /// Колонки, у которых долгим нажатием включены жирные границы.
  final Set<int> _boldColumns = {};

  /// Снимок плановых времён до начала редактирования ряда «План» или
  /// «Плановый темп». Нужен, чтобы после завершения ввода сдвинуть все
  /// последующие плановые времена на ту же разницу.
  List<String>? _planTimesBeforeEdit;
  int? _planEditColumn;

  /// Первый введённый символ заменяет старое значение поля. Так пользователь
  /// может нажать на ячейку и сразу набрать, например, 0855.
  bool _replacePlanInput = false;

  final GlobalKey _focusAnchorKey = GlobalKey();

  late final PersistedJsonStore _store = PersistedJsonStore(
    storageKey: _storageKey,
    legacyStorageKey: _isUltra ? null : PaceStateCodec.legacyStorageKey,
    schemaVersion: 3,
  );

  /// Горный режим текущей таблицы. Хранится в [MountainData] снимка таблицы.
  bool _mountainEnabled = false;

  /// Глобальный переключатель: показывать темп сегмента с учётом стоянок.
  bool _showStopsInPace = false;

  /// Треки текущей таблицы. Загружаются вместе с таблицей и сохраняются
  /// через снимок, поэтому при переключении дистанции не смешиваются.
  TrackSlots _tracks = TrackSlots.empty;

  /// Опора плана (docs/gpx-mountain-mode.md §7.2). `null` — ещё не задана.
  PlanAnchor? _planAnchor;

  /// Стоянки по колонкам, сек. Сохраняются в снимок таблицы.
  List<int> _stopsSec = const <int>[];

  /// Раскрыт ли ряд стоянок (долгое нажатие на PACE). Не сохраняется.
  bool _stopsRowOpen = false;

  /// Активный слот трека: `primary` или `backup`. Хранится в [TrackSlots].
  String get _activeTrackSlot => _tracks.active;

  String get _activeTrackSlotLabel => _activeTrackSlot == 'backup'
      ? AppStrings.paceTrackBackup
      : AppStrings.paceTrackPrimary;

  /// Переключает горный режим. Данные таблицы не теряются при выключении —
  /// только скрываются ряды.
  void _setMountainMode(bool enabled) {
    _update(() => _mountainEnabled = enabled);
  }

  void _setStopsInPace(bool enabled) {
    _update(() => _showStopsInPace = enabled);
  }

  /// Выбор основного/резервного слота. Сам трек пока не переключается:
  /// это сделает импорт (следующий шаг).
  Future<void> _chooseTrackSlot() async {
    final next = _activeTrackSlot == 'backup' ? 'primary' : 'backup';
    _update(() => _tracks = _withActive(_tracks, next));
    unawaited(_ensureTrackLoaded());
  }

  /// Загрузка GPX: слот → файл → разбор → старт → режим → применение.
  Future<void> _importGpxFlow() async {
    _hideKeyboard();
    if (_locked) {
      final unlock = await confirmUnlockForImport(context);
      if (!unlock || !mounted) return;
      _applyLocks(all: false);
    }

    final slot = await _pickTrackSlot();
    if (slot == null || !mounted) return;

    final existing = slot == 'backup' ? _tracks.backup : _tracks.primary;
    if (existing != null) {
      final replace = await confirmTrackOverwrite(context);
      if (!replace || !mounted) return;
    }

    final files = _trackFiles;
    if (files == null) {
      _showMessage(AppStrings.paceTrackReadError);
      return;
    }

    final picked = await TrackFilePicker.pick();
    if (picked == null || !mounted) return;

    final parsed = parseTrackFile(picked);
    if (parsed.parsed == null) {
      _showMessage('${AppStrings.paceTrackParseErrorPrefix}${parsed.error}');
      return;
    }
    var track = parsed.parsed!;

    // Трек начинается далеко от точки Start: спрашиваем, что считать стартом.
    final startOffset = trackStartOffsetMeters(track.track);
    if (startOffset != null && startNeedsDecision(startOffset)) {
      final choice = await askTrackStart(context);
      if (choice == null || !mounted) return;
      if (choice == TrackStartChoice.nearestPoint) {
        track = track.measuredFromStart();
      }
    }

    final mode = await showImportModeDialog(context);
    if (mode == null || !mounted) return;

    final columns = _tableDistances.length;
    final labels = _checkpointLabels(columns);
    final currentKm = [
      for (final value in _tableDistances) parseDecimal(value) ?? 0,
    ];

    var choices = <ColumnChoice>[];
    if (mode == GpxImportMode.checkpoints) {
      final suggestions = suggestColumns(
        columnLabels: labels,
        columnDistancesM: [for (final km in currentKm) km * 1000],
        candidates: candidatesFromStart(track),
        trackLengthM: track.lengthKm * 1000,
      );
      final picks = await showCheckpointCompareDialog(
        context,
        labels: [for (final l in labels) _labelText(l)],
        currentKm: currentKm,
        suggestions: suggestions,
      );
      if (picks == null || !mounted) return;
      choices = picks;
    }

    final result = applyGpxImport(
      mode: mode,
      distances: List<String>.of(_tableDistances),
      notes: List<String>.of(_notes),
      finishKm: track.lengthKm,
      choices: choices,
    );
    if (!result.ok) {
      _showMessage(importErrorText(result.error!));
      return;
    }

    // Сначала файл, потом метаданные: при сбое записи таблица не меняется.
    final fileName = slot == 'backup' ? 'backup.gpx' : 'primary.gpx';
    final key = trackDistanceKey(
      _controller.selectedEvent,
      _controller.selectedDistance,
    );
    try {
      await files.write(
        distanceKey: key,
        fileName: fileName,
        content: picked.content,
      );
    } catch (error) {
      debugPrint('uRunCalc: не удалось сохранить трек: $error');
      _showMessage(AppStrings.paceTrackReadError);
      return;
    }
    if (!mounted) return;

    final meta = TrackMeta(
      relativePath: fileName,
      originalName: picked.name,
      importedAtMs: DateTime.now().millisecondsSinceEpoch,
      points: track.track.length,
      lengthM: track.metrics.totalDistance2d,
      ascentM: track.totalAscentM,
      descentM: track.totalDescentM,
      hasElevation: track.track.hasElevation,
      offsetM: track.startOffsetM,
    );
    // Таблица и метаданные трека меняются одним шагом, чтобы сохранение
    // не зафиксировало половину изменений.
    _update(() {
      for (final index in result.changedColumns) {
        _tableDistances[index] = result.distances[index];
      }
      for (var i = 0; i < _notes.length && i < result.notes.length; i++) {
        _notes[i] = result.notes[i];
      }
      _mountainEnabled = true;
      _tracks = _withTrackMeta(_tracks, slot, meta);
    });
    _loadedTrack = null;
    _loadedTrackKey = null;
    unawaited(_ensureTrackLoaded());
    _showMessage(AppStrings.paceTrackImportApplied);
  }

  TrackSlots _withActive(TrackSlots current, String active) {
    return TrackSlots(
      active: active,
      primary: current.primary,
      backup: current.backup,
    );
  }

  TrackSlots _withTrackMeta(TrackSlots current, String slot, TrackMeta meta) {
    return TrackSlots(
      active: slot,
      primary: slot == 'primary' ? meta : current.primary,
      backup: slot == 'backup' ? meta : current.backup,
    );
  }

  /// Метки колонок для сопоставления: старт, промежуточные ПП, финиш.
  List<String> _checkpointLabels(int columns) {
    return [
      for (var i = 0; i < columns; i++)
        if (i == 0) 'START' else if (i == columns - 1) 'FINISH' else 'CP$i',
    ];
  }

  String _labelText(String label) {
    if (label == 'START') return AppStrings.paceTrackStartLabel;
    if (label == 'FINISH') return AppStrings.paceTrackFinishLabel;
    return label;
  }

  /// Выбор слота загрузки. Возвращает `primary`, `backup` или `null`.
  Future<String?> _pickTrackSlot() {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text(AppStrings.paceTrackImportTitle),
          children: [
            SimpleDialogOption(
              key: const ValueKey('gpx-slot-primary'),
              onPressed: () => Navigator.pop(dialogContext, 'primary'),
              child: const Text(AppStrings.paceTrackPrimary),
            ),
            SimpleDialogOption(
              key: const ValueKey('gpx-slot-backup'),
              onPressed: () => Navigator.pop(dialogContext, 'backup'),
              child: const Text(AppStrings.paceTrackBackup),
            ),
          ],
        );
      },
    );
  }

  Future<void> _manualElevationFlow() async {}

  /// Файлы GPX-треков. Появляется после того, как `path_provider` вернёт
  /// каталог поддержки; до этого операции с треками недоступны.
  TrackFileStore? _trackFiles;

  Future<void> _initTrackFiles() async {
    final override = debugTrackFileStoreOverride;
    if (override != null) {
      _trackFiles = override;
    } else {
      final support = await getApplicationSupportDirectory();
      if (!mounted) return;
      _trackFiles = DirectoryTrackFileStore(
        Directory('${support.path}${Platform.pathSeparator}tracks'),
      );
    }
    // Загрузка трека могла стартовать раньше, чем появилось хранилище.
    unawaited(_ensureTrackLoaded());
  }

  bool get _isUltra => widget.surface == _PaceSurface.ultra;

  String get _storageKey =>
      _isUltra ? PaceStateCodec.ultraStorageKey : PaceStateCodec.paceStorageKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetTable(_columns);
    _loadPaceState();
    unawaited(_initTrackFiles());
  }

  /// Единая точка изменения состояния: перерисовывает экран и планирует
  /// сохранение. Сохранение можно отключить для чисто визуальных изменений.
  void _update(VoidCallback fn, {bool persist = true}) {
    super.setState(fn);
    if (persist) _persist();
  }

  @override
  void didUpdateWidget(covariant _PaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && oldWidget.active) {
      if (_isUltra) {
        final planChanged = _finalizePlanEdit();
        _limitDays = _computeDays(_tableTimes);
        _planDays = _computeDays(_planTimes);
        _keyboardVisible = false;
        _focus = const _PaceFocus.none();
        if (planChanged) _persist();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_store.flush());
    }
  }

  Map<String, dynamic> _buildPersistedState() {
    if (!_isUltra) {
      return PaceStateCodec.encodeCalculator(
        PaceCalculatorState(
          calc: _calc.name,
          distance: _distance,
          paceMinutes: _paceMinutes,
          paceSeconds: _paceSeconds,
          days: _days,
          hours: _hours,
          minutes: _minutes,
          seconds: _seconds,
        ),
      );
    }

    // Текущая таблица может ещё не попасть в снимки, если пользователь не
    // переключал мероприятие. Снимок берём напрямую, не меняя состояние.
    return _controller.encode(
      snapshot: _controller.selectedDistance == PaceCatalog.noDistance
          ? null
          : _snapshotTable(),
    );
  }

  void _persist() {
    if (!_controller.stateLoaded) return;
    _store.schedule(_buildPersistedState);
  }

  Future<void> _loadPaceState() async {
    final data = await _store.load();

    if (!mounted) return;
    _update(() {
      if (data != null) {
        _applyState(data);
      } else if (_isUltra) {
        _loadCurrentTable();
      }
      _controller.stateLoaded = true;
    });
  }

  void _applyState(Map<String, dynamic> data) {
    if (_isUltra) {
      _applyUltraState(data);
    } else {
      _applyCalculatorState(data);
    }
    _focus = _isUltra
        ? const _PaceFocus.none()
        : const _PaceFocus.top(_PaceTopField.distance);
  }

  void _applyCalculatorState(Map<String, dynamic> data) {
    final state = PaceStateCodec.decodeCalculator(data);
    try {
      _calc = _PaceCalc.values.byName(state.calc);
    } catch (_) {
      // Неизвестный режим оставляем по умолчанию.
    }

    _distance = state.distance;
    _paceMinutes = state.paceMinutes;
    _paceSeconds = state.paceSeconds;
    _days = state.days;
    _hours = state.hours;
    _minutes = state.minutes;
    _seconds = state.seconds;
  }

  void _applyUltraState(Map<String, dynamic> data) {
    final state = PaceStateCodec.decodeUltra(
      data,
      fallbackEvents: _controller.events,
      fallbackEvent: _controller.selectedEvent,
    );

    _controller.apply(state);
    _controller.prepareDefaults();
    _loadCurrentTable();
  }

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
    final data = _controller.currentTable;
    if (data == null) {
      final distance = _controller.currentDistance;
      _resetTable(
        distance == null ? _baseColumns : distance.checkpoints + 2,
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
    _columns = data.columns.clamp(3, _maxColumns);
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
    _mountainEnabled = false;
    _showStopsInPace = false;
    _tracks = TrackSlots.empty;
    _planAnchor = null;
    _stopsSec = const <int>[];
    final clamped = columns.clamp(3, _maxColumns).toInt();
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
    final clamped = columns.clamp(3, _maxColumns).toInt();
    if (clamped == _columns) return;

    _update(() {
      _columns = clamped;
      if (clamped <= _baseColumns) _fitTable = true;
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

  String get _eventLabel => _controller.eventLabel;

  double? get _distanceValue => parseDecimal(_distance);

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
    return switch (_calc) {
      _PaceCalc.pace => field == _PaceTopField.distance || _isTimeField(field),
      _PaceCalc.distance => _isPaceField(field) || _isTimeField(field),
      _PaceCalc.time => field == _PaceTopField.distance || _isPaceField(field),
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
    });
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

  /// Статусы плана относительно лимита. Пересчитываются один раз в
  /// `_buildTable`, чтобы не разбирать время для каждой клетки отдельно.
  List<PlanTimeStatus> _planStatuses = const <PlanTimeStatus>[];

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
    return _dayColors[(day - 1) % _dayColors.length];
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
    final rest = current.length <= 1 ? '' : current.substring(0, current.length - 1);
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

  Future<void> _editTextCell({
    required String title,
    required String value,
    required ValueChanged<String> onSaved,
    bool multiline = false,
  }) async {
    _hideKeyboard();
    var text = value;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextFormField(
            initialValue: value,
            autofocus: true,
            keyboardType: multiline
                ? TextInputType.multiline
                : TextInputType.text,
            minLines: multiline ? 3 : 1,
            maxLines: multiline ? 6 : 1,
            textInputAction: multiline
                ? TextInputAction.newline
                : TextInputAction.done,
            onChanged: (value) => text = value,
            decoration: const InputDecoration(
              hintText: AppStrings.paceEnterText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(AppStrings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, text),
              child: const Text(AppStrings.save),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;
    _update(() {
      onSaved(result.trim());
    });
  }

  Future<void> _editNote(int index) async {
    await _editTextCell(
      title: AppStrings.paceNoteTitle(_columnLabel(index)),
      value: _notes[index],
      onSaved: (text) {
        if (index < _notes.length) _notes[index] = text;
      },
    );
  }

  Future<void> _editListCell({
    required String title,
    required List<String> values,
    required int index,
  }) async {
    await _editTextCell(
      title: title,
      value: values[index],
      multiline: true,
      onSaved: (text) {
        if (index < values.length) values[index] = text;
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showEventMenu() async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text(AppStrings.paceEventTitle),
          children: [
            for (final event in _controller.events)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.pop(dialogContext, 'event:${event.name}'),
                child: Row(
                  children: [
                    Expanded(child: Text(event.name)),
                    if (event.name == _controller.selectedEvent)
                      const Icon(
                        Icons.check,
                        color: AppColors.accent,
                        size: 20,
                      ),
                  ],
                ),
              ),
            const Divider(),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, 'add'),
              child: const Text(AppStrings.paceEventAdd),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, 'remove'),
              child: const Text(AppStrings.paceEventRemove),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;

    if (result == 'add') {
      await _addEvent();
    } else if (result == 'remove') {
      await _removeEvent();
    } else if (result.startsWith('event:')) {
      final name = result.substring('event:'.length);
      await _showDistanceMenu(_controller.eventNamed(name));
    }
  }

  Future<void> _showDistanceMenu(PaceEvent event) async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: Text(event.name),
          children: [
            if (event.distances.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(AppStrings.paceDistanceNone),
              ),
            for (final distance in event.distances)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.pop(dialogContext, 'distance:${distance.name}'),
                child: Row(
                  children: [
                    Expanded(child: Text(distance.name)),
                    Text(
                      AppStrings.paceCheckpoints(distance.checkpoints),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    if (event.name == _controller.selectedEvent &&
                        distance.name == _controller.selectedDistance)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.check,
                          color: AppColors.accent,
                          size: 20,
                        ),
                      ),
                  ],
                ),
              ),
            const Divider(),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, 'add'),
              child: const Text(AppStrings.paceDistanceAdd),
            ),
            if (event.distances.isNotEmpty)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, 'remove'),
                child: const Text(AppStrings.paceDistanceRemove),
              ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;

    if (result == 'add') {
      await _addDistance(event);
    } else if (result == 'remove') {
      await _removeDistance(event);
    } else if (result.startsWith('distance:')) {
      final name = result.substring('distance:'.length);
      final distance = event.distances.firstWhere(
        (distance) => distance.name == name,
        orElse: () => event.distances.first,
      );
      _selectDistance(event, distance);
    }
  }

  void _selectDistance(PaceEvent event, PaceDistance distance) {
    _commitDays();
    _update(() {
      _saveCurrentTable();
      _controller.select(event, distance);
      _focus = const _PaceFocus.none();
      _keyboardVisible = false;
      _loadCurrentTable();
    });
  }

  Future<void> _addEvent() async {
    var name = '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(AppStrings.paceEventNew),
          content: TextFormField(
            autofocus: true,
            onChanged: (value) => name = value,
            decoration: const InputDecoration(
              hintText: AppStrings.paceDistanceName,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(AppStrings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, name.trim()),
              child: const Text(AppStrings.add),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null || result.isEmpty) return;

    if (_controller.events.any((event) => event.name == result)) {
      _showMessage(AppStrings.paceEventExists);
      return;
    }

    _update(() {
      _controller.addEvent(result);
    });
  }

  Future<void> _removeEvent() async {
    if (_controller.events.length <= 1) {
      _showMessage(AppStrings.paceEventCannotRemoveLast);
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text(AppStrings.paceEventRemoveTitle),
          children: [
            for (final event in _controller.events)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, event.name),
                child: Text(event.name),
              ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;

    final wasSelected = _controller.selectedEvent == result;
    _update(() {
      _saveCurrentTable();
      _controller.removeEvent(result);
      if (wasSelected) _loadCurrentTable();
    });
  }

  Future<void> _addDistance(PaceEvent event) async {
    var name = '';
    var checkpoints = '4';

    final result = await showDialog<({String name, int checkpoints})>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(AppStrings.paceDistanceTitle(event.name)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                autofocus: true,
                onChanged: (value) => name = value,
                decoration: const InputDecoration(
                  labelText: AppStrings.paceDistanceName,
                  hintText: 'T100',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: checkpoints,
                keyboardType: TextInputType.number,
                onChanged: (value) => checkpoints = value,
                decoration: const InputDecoration(
                  labelText: AppStrings.paceDistanceCheckpoints,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(AppStrings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, (
                name: name.trim(),
                checkpoints: int.tryParse(checkpoints) ?? 0,
              )),
              child: const Text(AppStrings.add),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null || result.name.isEmpty) return;

    if (event.distances.any((distance) => distance.name == result.name)) {
      _showMessage(AppStrings.paceDistanceExists);
      return;
    }

    if (result.checkpoints < 1 || result.checkpoints > _maxColumns - 2) {
      _showMessage(AppStrings.paceCheckpointsRange(_maxColumns - 2));
      return;
    }

    _update(() {
      _controller.addDistance(event, result.name, result.checkpoints);
    });
  }

  Future<void> _removeDistance(PaceEvent event) async {
    if (event.distances.length <= 1) {
      _showMessage(AppStrings.paceDistanceCannotRemoveLast);
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: Text(AppStrings.paceDistanceRemoveTitle(event.name)),
          children: [
            for (final distance in event.distances)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, distance.name),
                child: Text(
                  AppStrings.paceDistanceOption(
                    distance.name,
                    distance.checkpoints,
                  ),
                ),
              ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;

    final wasSelected =
        event.name == _controller.selectedEvent &&
        _controller.selectedDistance == result;
    _update(() {
      _saveCurrentTable();
      _controller.removeDistance(event, result);
      if (wasSelected) _loadCurrentTable();
    });
    await _deleteRemovedTracks();
  }

  /// Удаляет каталоги треков удалённых дистанций. Ошибки файловой системы
  /// не блокируют интерфейс: трек просто останется до следующей очистки.
  Future<void> _deleteRemovedTracks() async {
    final files = _trackFiles;
    for (final (event, distance) in _controller.takeRemovedDistances()) {
      if (files == null) continue;
      try {
        await files.deleteDistance(trackDistanceKey(event, distance));
      } catch (error) {
        debugPrint(
          'uRunCalc: не удалось удалить трек $event/$distance: $error',
        );
      }
    }
  }

  /// Меню-шестерёнка: колонки, горный режим, треки, стоянки.
  Future<void> _showSettingsMenu() async {
    await PaceSettingsMenu.show(
      context,
      state: PaceSettingsState(
        mountainMode: _mountainEnabled,
        showStopsInPace: _showStopsInPace,
        activeSlotLabel: _activeTrackSlotLabel,
      ),
      actions: PaceSettingsActions(
        onColumns: _showColumnsDialog,
        onMountainChanged: _setMountainMode,
        onImportGpx: _importGpxFlow,
        onTrackSlot: _chooseTrackSlot,
        onManualElevation: _manualElevationFlow,
        onStopsModeChanged: _setStopsInPace,
      ),
    );
  }

  Future<void> _showColumnsDialog() async {
    var columns = _columns;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(AppStrings.paceColumnsTitle),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    key: const ValueKey('pace-columns-minus'),
                    onPressed: columns > 3
                        ? () => setDialogState(() => columns--)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '$columns',
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('pace-columns-plus'),
                    onPressed: columns < _maxColumns
                        ? () => setDialogState(() => columns++)
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(AppStrings.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _resizeTable(columns);
                  },
                  child: const Text(AppStrings.apply),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _toggleScale() {
    _hideKeyboard();
    _update(() {
      _fitTable = !_fitTable;
    });
  }

  Widget _buildTableToolbar() {
    return Row(
      children: [
        Expanded(
          flex: 6,
          child: _toolbarButton(
            key: 'pace-event-button',
            label: _eventLabel,
            semanticLabel: AppStrings.paceEventSemantic(_eventLabel),
            icon: Icons.flag_outlined,
            onTap: _locked
                ? null
                : () {
                    _hideKeyboard();
                    _showEventMenu();
                  },
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: 2,
          child: _toolbarButton(
            key: 'pace-settings-button',
            semanticLabel: AppStrings.paceSettingsSemantic,
            icon: Icons.settings_outlined,
            onTap: _locked
                ? null
                : () {
                    _hideKeyboard();
                    _showSettingsMenu();
                  },
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: 2,
          child: _toolbarButton(
            key: 'pace-lock-button',
            semanticLabel: _locked || _lockedLimits
                ? AppStrings.paceUnlockTable
                : AppStrings.paceLockTable,
            icon: _locked || _lockedLimits ? Icons.lock : Icons.lock_open,
            onTap: _showLockMenu,
            active: _locked || _lockedLimits,
          ),
        ),
        if (_columns > _baseColumns) ...[
          const SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: _toolbarButton(
              key: 'pace-scale-button',
              label: _fitTable
                  ? AppStrings.paceScaleFit
                  : AppStrings.paceScaleActual,
              icon: Icons.zoom_out_map,
              onTap: _toggleScale,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showLockMenu() async {
    _hideKeyboard();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text(AppStrings.paceLockTitle),
          children: [
            if (!_locked) ...[
              SimpleDialogOption(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _lockedLimits ? 'unlock_limits' : 'lock_limits',
                ),
                child: Text(
                  _lockedLimits
                      ? AppStrings.paceUnlockLimits
                      : AppStrings.paceLockLimits,
                ),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, 'lock_all'),
                child: const Text(AppStrings.paceLockAll),
              ),
            ] else
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, 'unlock_all'),
                child: const Text(AppStrings.paceUnlockAll),
              ),
            const Divider(),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, 'print'),
              child: const Text(AppStrings.paceLockPaper),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;

    switch (result) {
      case 'lock_limits':
        _applyLocks(limits: true);
      case 'unlock_limits':
        _applyLocks(limits: false);
      case 'lock_all':
        _applyLocks(all: true);
      case 'unlock_all':
        _applyLocks(all: false);
      case 'print':
        await _showPrintDialog();
    }
  }

  /// Применяет фиксацию без лишних подтверждений.
  ///
  /// [all] управляет полной фиксацией, [limits] — только рядами
  /// «Лимит» и «Расстояние». Полная фиксация всегда включает лимиты.
  void _applyLocks({bool? all, bool? limits}) {
    _update(() {
      if (all != null) {
        _locked = all;
        _lockedLimits = all;
      }
      if (limits != null) {
        if (!_locked) _lockedLimits = limits;
      }
      _keyboardVisible = false;
      _focus = const _PaceFocus.none();
    });
    _persist();
  }

  Future<void> _showPrintDialog() async {
    _hideKeyboard();
    var landscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    final request = await showDialog<_PrintRequest>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(AppStrings.pacePrintTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(AppStrings.pacePrintOrientation),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text(AppStrings.pacePrintPortrait),
                        selected: !landscape,
                        onSelected: (_) =>
                            setDialogState(() => landscape = false),
                      ),
                      ChoiceChip(
                        label: const Text(AppStrings.pacePrintLandscape),
                        selected: landscape,
                        onSelected: (_) =>
                            setDialogState(() => landscape = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    AppStrings.pacePrintDescription,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(AppStrings.cancel),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    _PrintRequest(landscape: landscape, share: true),
                  ),
                  child: const Text('PDF'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    _PrintRequest(landscape: landscape, share: false),
                  ),
                  child: const Text(AppStrings.pacePrintAction),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || request == null) return;

    try {
      final data = _buildPrintData();
      final bytes = await buildTablePdf(data, landscape: request.landscape);
      if (!mounted) return;
      final fileName = _printFileName(data.event);
      if (request.share) {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      } else {
        await Printing.layoutPdf(name: fileName, onLayout: (_) async => bytes);
      }
    } catch (error) {
      if (mounted) _showMessage(AppStrings.pacePrintFailed(error));
    }
  }

  PrintTableData _buildPrintData() {
    final segmentPaces = <String>[
      for (var index = 0; index < _columns; index++)
        index == 0
            ? 'PACE'
            : _segmentPace(index) == null
            ? '—'
            : formatPaceSeconds(_segmentPace(index)!),
    ];
    final planPaces = <String>[
      for (var index = 0; index < _columns; index++) _planPaceText(index),
    ];
    final columns = <String>[
      for (var index = 0; index < _columns; index++)
        _notes[index].trim().isEmpty
            ? _columnLabel(index)
            : '${_columnLabel(index)}\n${_notes[index].trim()}',
    ];
    final pace = _overallPaceSeconds;
    final plannedPace = _overallPlannedPaceSeconds;

    return PrintTableData(
      event: _eventLabel,
      columns: columns,
      times: [
        for (var index = 0; index < _columns; index++) _tableTimeText(index),
      ],
      distances: [
        for (var index = 0; index < _columns; index++)
          _tableDistanceText(index),
      ],
      segmentPaces: segmentPaces,
      planTimes: [
        for (var index = 0; index < _columns; index++) _planTimeText(index),
      ],
      planPaces: planPaces,
      water: List<String>.of(_water),
      food: List<String>.of(_food),
      limitTime: _formatElapsedMinutes(_totalLimitMinutes),
      limitPace: pace == null ? '—' : formatPaceSeconds(pace),
      plannedPace: plannedPace == null ? '—' : formatPaceSeconds(plannedPace),
      plannedTime: _formatElapsedMinutes(_overallPlannedFinishMinutes),
      boldColumns: _boldColumns.toList()..sort(),
      dayIndexes: List<int>.of(_limitDays),
    );
  }

  String _printFileName(String event) {
    final safe = event
        .replaceAll(RegExp(r'[^0-9A-Za-zА-Яа-яЁё_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    return 'uRunCalc_${safe.isEmpty ? 'table' : safe}_$stamp.pdf';
  }

  Widget _toolbarButton({
    required String key,
    String? label,
    String? semanticLabel,
    required IconData icon,
    VoidCallback? onTap,
    bool active = false,
  }) {
    final enabled = onTap != null;
    final accent = active ? AppColors.accent : Colors.grey;
    final iconOnly = label == null;
    final button = InkWell(
      key: ValueKey(key),
      onTap: onTap,
      child: Container(
        height: 34,
        padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 6),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: active ? accent : Colors.grey.shade700),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: iconOnly ? 20 : 15,
              color: enabled ? accent : Colors.grey.shade600,
            ),
            if (label != null) ...[
              const SizedBox(width: 4),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: enabled ? Colors.white : Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    // Кнопки без подписи (например, замок) не читаются скринридером, поэтому
    // задаём отдельную семантическую подпись и дублируем действие.
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      onTap: onTap,
      excludeSemantics: true,
      child: button,
    );
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    if (!_isUltra) {
      final calculator = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
        child: _buildCalculator(),
      );

      if (landscape) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: calculator),
            SizedBox(width: 190, child: _buildKeyboard(compact: true)),
          ],
        );
      }

      return Column(
        children: [
          Expanded(child: calculator),
          _buildKeyboard(compact: false),
        ],
      );
    }

    if (landscape) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final keyboardWidth = math.min(
            160.0,
            math.max(110.0, constraints.maxWidth * 0.2),
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _hideKeyboard,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                    child: _buildTable(compact: true),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.centerRight,
                onEnd: _ensureFocusVisibleNow,
                child: _keyboardVisible
                    ? SizedBox(
                        width: keyboardWidth,
                        child: _buildKeyboard(compact: true, tableLayout: true),
                      )
                    : const SizedBox(width: 0),
              ),
            ],
          );
        },
      );
    }

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _hideKeyboard,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTableToolbar(),
                  const SizedBox(height: 8),
                  _buildTable(compact: false),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          onEnd: _ensureFocusVisibleNow,
          child: _keyboardVisible
              ? _buildKeyboard(compact: false)
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }

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
                height: _elevationRowHeight,
                expanded: _fitTable,
              ),
            );
            rows.add(
              _elevationTotalRow(
                height: _elevationRowHeight,
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
              : _columns * _fixedCellWidth + _totalColumnWidth;

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
            : _columns * _fixedCellWidth;
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
                    width: _fixedCellWidth,
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
        : SizedBox(width: _columns * _fixedCellWidth, child: row);
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
  Widget _plannedSummaryPairRow({required double height, required bool expanded}) {
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
        : SizedBox(width: _columns * _fixedCellWidth, child: row);
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

  /// Разобранный трек активного слота текущей дистанции. Читается с диска
  /// один раз и кэшируется; сбрасывается при смене дистанции или слота.
  ParsedTrack? _loadedTrack;
  String? _loadedTrackKey;
  bool _loadingTrack = false;

  /// D+/D− по сегментам текущей таблицы. `null`, если трека нет или он не
  /// загружен; тогда ряд показывает прочерк.
  ElevationSegments? get _elevationSegments {
    final parsed = _loadedTrack;
    if (parsed == null) return null;
    return elevationForColumns(
      parsed: parsed,
      columnDistancesKm: [
        for (final value in _tableDistances) parseDecimal(value) ?? 0,
      ],
    );
  }

  /// Читает активный трек с диска. Ошибки не роняют экран: ряд просто пуст.
  Future<void> _ensureTrackLoaded() async {
    final files = _trackFiles;
    final meta = _tracks.activeTrack;
    final key =
        '${trackDistanceKey(_controller.selectedEvent, _controller.selectedDistance)}'
        '/${_tracks.active}';
    if (files == null || meta == null || !_mountainEnabled) return;
    if (_loadedTrackKey == key && _loadedTrack != null) return;
    if (_loadingTrack) return;

    _loadingTrack = true;
    try {
      final content = await files.read(
        distanceKey: trackDistanceKey(
          _controller.selectedEvent,
          _controller.selectedDistance,
        ),
        fileName: meta.relativePath,
      );
      if (!mounted || content == null) return;
      final parsed = parseTrackFile(
        PickedTrackFile(name: meta.originalName, content: content),
      );
      if (!mounted) return;
      _update(() {
        _loadedTrack = parsed.parsed?.measuredFromStartIfOffset(meta.offsetM);
        _loadedTrackKey = key;
      }, persist: false);
    } catch (error) {
      debugPrint('uRunCalc: не удалось прочитать трек: $error');
    } finally {
      _loadingTrack = false;
    }
  }

  /// Маркер ПП на карте. Пустое расстояние — маркера нет.
  ElevationMarker? _elevationMarker(int index, double? km) {
    if (km == null) return null;
    final note = index < _notes.length ? _notes[index].trim() : '';
    return ElevationMarker(
      km: km,
      label: index == 0
          ? AppStrings.paceTrackStartLabel
          : (note.isEmpty ? 'CP$index' : note),
    );
  }

  /// Долгое нажатие на ряд высот открывает карту по текущему треку.
  /// Без трека карта показывает «нет данных о высоте».
  void _openElevationChart() {
    final parsed = _loadedTrack;
    final elevation = _elevationSegments;
    final kms = <double?>[for (final v in _tableDistances) parseDecimal(v)];
    final data = ElevationChartData(
      profile: parsed == null
          ? const []
          : buildElevationProfile(parsed, maxPoints: 1000),
      markers: [
        for (var i = 0; i < kms.length; i++) ?_elevationMarker(i, kms[i]),
      ],
      totalAscentM: elevation?.totalAscentM ?? 0,
      totalDescentM: elevation?.totalDescentM ?? 0,
      boundariesKm: [for (final km in kms) ?km],
    );
    unawaited(showElevationChart(context, data));
  }

  /// Высота ряда подъём–спуск в портрете, пикселей.
  static const double _elevationRowHeight = 30;

  /// Клетки ряда подъём–спуск. Первая клетка служебная: `↑↓`.
  List<Widget> _elevationCells() {
    final elevation = _elevationSegments;
    return List.generate(_columns, (index) {
      if (index == 0) {
        return _interactiveCell(
          key: 'pace-elevation-label',
          text: '↑↓',
          result: true,
          color: Colors.grey,
          onLongPress: _openElevationChart,
        );
      }
      final text = elevation == null
          ? ''
          : formatElevationPair(
              elevation.ascentM[index],
              elevation.descentM[index],
            );
      return _interactiveCell(
        key: 'pace-elevation-$index',
        text: text,
        placeholder: elevation == null,
        spans: elevation == null
            ? null
            : elevationPairSpans(
                elevation.ascentM[index],
                elevation.descentM[index],
                upColor: AppColors.danger,
                downColor: AppColors.focus,
                separatorColor: AppColors.result,
              ),
        result: true,
        dayBorder: _dayBorderColor(index, _limitDays),
        boldBorder: _boldColumns.contains(index),
        onLongPress: _openElevationChart,
      );
    });
  }

  /// Итог набора и сброса в портрете: отдельный ряд под рядом высот, две
  /// половины — набор слева, сброс справа. Как ряд «Общее время / Темп в лимит».
  Widget _elevationTotalRow({
    required double height,
    required bool expanded,
    bool meters = false,
  }) {
    final elevation = _elevationSegments;
    String fmt(double value) =>
        meters ? formatElevationMeters(value) : formatElevationValue(value);
    final ascent = elevation == null ? '—' : fmt(elevation.totalAscentM);
    final descent = elevation == null ? '—' : fmt(elevation.totalDescentM);
    final row = SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: _interactiveCell(
                key: 'pace-elevation-total-up',
                text: AppStrings.paceTotalAscentLine(ascent),
                result: true,
                fontSize: 14,
                onLongPress: _openElevationChart,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: _interactiveCell(
                key: 'pace-elevation-total-down',
                text: AppStrings.paceTotalDescentLine(descent),
                result: true,
                fontSize: 14,
                onLongPress: _openElevationChart,
              ),
            ),
          ),
        ],
      ),
    );
    return expanded
        ? row
        : SizedBox(width: _columns * _fixedCellWidth, child: row);
  }

  /// Итог набора и сброса по всей дистанции (ландшафт, колонка Total).
  Widget _elevationTotalCell() {
    final elevation = _elevationSegments;
    return _interactiveCell(
      key: 'pace-elevation-total',
      text: elevation == null
          ? '—'
          : formatElevationPair(
              elevation.totalAscentM,
              elevation.totalDescentM,
            ),
      result: true,
      bold: true,
      onLongPress: _openElevationChart,
    );
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
        text: focused ? _stopBufferText(index) : (minutes == 0 ? '0' : '$minutes'),
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
            : _columns * _fixedCellWidth;
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
            SizedBox(width: _columns * _fixedCellWidth, child: content),
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
    final maxLines = math.max(1, (height / 13).floor());
    return Container(
      key: ValueKey(keySuffix),
      alignment: Alignment.topLeft,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Text.rich(
        TextSpan(
          children: keyPrefix == 'pace-water'
              ? _waterSpans(value)
              : [TextSpan(text: value)],
        ),
        maxLines: maxLines,
        overflow: TextOverflow.clip,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          height: 1.15,
        ),
      ),
    );
  }

  List<InlineSpan> _waterSpans(String value) {
    final spans = <InlineSpan>[];
    for (final match in RegExp(r'\S+|\s+').allMatches(value)) {
      final part = match.group(0)!;
      if (part.trim().isEmpty) {
        spans.add(TextSpan(text: part));
        continue;
      }

      final normalized = part.toLowerCase().replaceAll(
        RegExp(r'[^а-яёa-z0-9]'),
        '',
      );
      final color = switch (normalized) {
        'кола' => const Color(0xFFD2A679),
        'вода' => const Color(0xFF64B5F6),
        'пиво' => const Color(0xFFFFEB3B),
        'ягер' => const Color(0xFF81C784),
        _ => Colors.white,
      };
      spans.add(
        TextSpan(
          text: part,
          style: TextStyle(color: color),
        ),
      );
    }
    return spans;
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
    final defaultBorder = editable
        ? Colors.grey.shade700
        : Colors.grey.shade900;
    final borderColor = focused
        ? AppColors.focus
        : boldBorder
        ? Colors.grey.shade500
        : dayBorder ?? defaultBorder;
    final borderWidth = focused ? 1.5 : (boldBorder ? 3.0 : 1.0);

    final cell = InkWell(
      key: ValueKey(key),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: result ? AppColors.surfaceRaised : AppColors.background,
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (focused && cursorFirst) _cursor(),
              if (spans != null && !placeholder)
                Text.rich(
                  TextSpan(
                    children: spans,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: bold ? FontWeight.bold : null,
                    ),
                  ),
                  maxLines: maxLines,
                  textAlign: TextAlign.center,
                )
              else
                Text(
                  text,
                  maxLines: maxLines,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: placeholder
                        ? Colors.grey.shade600
                        : color ?? (result ? AppColors.result : Colors.white),
                    fontSize: fontSize,
                    fontWeight: bold ? FontWeight.bold : null,
                  ),
                ),
              if (focused && !cursorFirst) _cursor(),
            ],
          ),
        ),
      ),
    );

    final content = focused
        ? KeyedSubtree(key: _focusAnchorKey, child: cell)
        : cell;
    if (semanticLabel == null && semanticHint == null) return content;

    // Цвет клетки передаёт статус плана, но скринридер его не видит — поэтому
    // для таких клеток задаём текстовую подпись и подсказку.
    return Semantics(
      label: semanticLabel,
      hint: semanticHint,
      button: onTap != null,
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onLongPress,
      child: content,
    );
  }

  Widget _buildKeyboard({required bool compact, bool tableLayout = false}) {
    final extraKey = _isUltra ? AppStrings.ok : '00';
    if (tableLayout) {
      return Container(
        height: compact ? null : 180,
        padding: EdgeInsets.fromLTRB(4, 4, 4, compact ? 4 : 6),
        color: AppColors.surface,
        child: Column(
          children: [
            _keyRow(['.', AppStrings.reset, '⌫'], compact),
            _keyRow(['1', '2', '3'], compact),
            _keyRow(['4', '5', '6'], compact),
            _keyRow(['7', '8', '9'], compact),
            Expanded(
              child: Row(
                children: [
                  Expanded(flex: 2, child: _padKey('0', compact)),
                  Expanded(flex: 1, child: _padKey(extraKey, compact)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: compact ? null : 180,
      padding: EdgeInsets.fromLTRB(4, 4, 4, compact ? 4 : 6),
      color: AppColors.surface,
      child: Column(
        children: [
          _keyRow(['1', '2', '3', '⌫'], compact),
          _keyRow(['4', '5', '6', '.'], compact),
          _keyRow(['7', '8', '9', AppStrings.reset], compact),
          Expanded(
            child: Row(
              children: [
                Expanded(flex: 2, child: _padKey('0', compact)),
                Expanded(flex: 2, child: _padKey(extraKey, compact)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _keyRow(List<String> keys, bool compact) {
    return Expanded(
      child: Row(
        children: [
          for (final key in keys) Expanded(child: _padKey(key, compact)),
        ],
      ),
    );
  }

  Widget _padKey(String key, bool compact) {
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: Semantics(
        button: true,
        label: semanticKeyLabel(key),
        hint: key == '⌫' ? AppStrings.longPressClear : null,
        onTap: () => _onPadKey(key),
        onLongPress: key == '⌫' ? _clearActive : null,
        excludeSemantics: true,
        child: Material(
          color: AppColors.background,
          child: InkWell(
            key: ValueKey('pace-key-$key'),
            onTap: () => _onPadKey(key),
            onLongPress: key == '⌫' ? _clearActive : null,
            child: Center(
              child: Text(
                key,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 16 : 20,
                ),
              ),
            ),
          ),
        ),
      ),
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
