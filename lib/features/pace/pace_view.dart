import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../../core/app_strings.dart';
import '../../core/key_labels.dart';
import '../../core/persisted_json_store.dart';
import '../../core/time_math.dart';
import '../../print_table.dart';
import '../../theme/app_colors.dart';
import '../../widgets/blinking_cursor.dart';
import '../gpx/checkpoint_matching.dart';
import '../gpx/elevation_format.dart';
import '../gpx/elevation_profile.dart';
import '../gpx/elevation_segments.dart';
import '../gpx/gpx_import.dart';
import '../gpx/parsed_track.dart';
import '../gpx/plan_math.dart';
import '../gpx/track_store.dart';
import 'elevation_cell_text.dart';
import 'elevation_chart_view.dart';
import 'mountain_data.dart';
import 'pace_calculations.dart';
import 'pace_catalog.dart';
import 'pace_gpx_import_ui.dart';
import 'pace_settings_menu.dart';
import 'pace_state_codec.dart';
import 'pace_state_controller.dart';
import 'pace_table_data.dart';

part 'pace_events_part.dart';
part 'pace_mountain_part.dart';
part 'pace_plan_part.dart';
part 'pace_table_part.dart';

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

enum PaceSurface { pace, ultra }

/// Тестовая подмена хранилища треков (in-memory). В продакшене не задаётся.
@visibleForTesting
TrackFileStore? debugTrackFileStoreOverride;

/// Тестовая подмена загрузчика состояния по ключу хранилища.
/// Позволяет проверить гонку «ввод пользователя до окончания загрузки».
@visibleForTesting
Future<Map<String, dynamic>?> Function(String storageKey)?
debugPaceStateLoaderOverride;

class PaceView extends StatefulWidget {
  const PaceView({super.key, required this.active, required this.surface});

  final bool active;
  final PaceSurface surface;

  @override
  State<PaceView> createState() => _PaceViewState();
}

class _PaceViewState extends State<PaceView> with WidgetsBindingObserver {
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

  /// Пользователь изменил состояние до окончания восстановления из хранилища.
  /// В этом случае поздний ответ загрузки не должен затирать ввод.
  bool _stateTouched = false;

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

  /// Файлы GPX-треков. Появляется после того, как `path_provider` вернёт
  /// каталог поддержки; до этого операции с треками недоступны.
  TrackFileStore? _trackFiles;

  /// Разобранный трек активного слота текущей дистанции. Читается с диска
  /// один раз и кэшируется; сбрасывается при смене дистанции или слота.
  ParsedTrack? _loadedTrack;
  String? _loadedTrackKey;
  bool _loadingTrack = false;

  /// Во время чтения поступил ещё один запрос: после завершения текущего
  /// нужно проверить актуальный ключ и при необходимости загрузить другой трек.
  bool _trackLoadQueued = false;

  /// Высота ряда подъём–спуск в портрете, пикселей.
  static const double _elevationRowHeight = 30;

  bool get _isUltra => widget.surface == PaceSurface.ultra;

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
    if (persist && !_controller.stateLoaded) _stateTouched = true;
    super.setState(fn);
    if (persist) _persist();
  }

  @override
  void didUpdateWidget(covariant PaceView oldWidget) {
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
    final loader = debugPaceStateLoaderOverride;
    final data = await (loader?.call(_storageKey) ?? _store.load());

    if (!mounted) return;
    if (_stateTouched) {
      // Пользователь уже начал вводить данные. Применение сохранённого
      // состояния затерло бы их, поэтому только разрешаем сохранение.
      _update(() => _controller.stateLoaded = true);
      return;
    }
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
}
