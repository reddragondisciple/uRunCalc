import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../../core/app_strings.dart';
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
import '../gpx/track_parse.dart';
import '../gpx/track_parse_async.dart';
import '../gpx/track_store.dart';
import 'elevation_cell_text.dart';
import 'elevation_chart_view.dart';
import 'mountain_data.dart';
import 'pace_calculations.dart';
import 'pace_cells.dart';
import 'pace_keyboard.dart';
import 'pace_catalog.dart';
import 'pace_gpx_import_ui.dart';
import 'pace_settings_menu.dart';
import 'pace_state_codec.dart';
import 'pace_state_controller.dart';
import 'pace_table_data.dart';

part 'pace_calculator_part.dart';
part 'pace_events_part.dart';
part 'pace_input_part.dart';
part 'pace_mountain_part.dart';
part 'pace_plan_part.dart';
part 'pace_table_state_part.dart';
part 'pace_table_cells_part.dart';
part 'pace_table_part.dart';
part 'pace_values_part.dart';

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

  /// Разобранные треки для быстрого возврата на дистанцию/слот. Ключ —
  /// [TrackMeta] вместе с дистанцией и слотом. Храним несколько последних:
  /// переключение между двумя дистанциями не должно перечитывать файл.
  final Map<String, ParsedTrack> _parsedTrackCache = {};
  static const int _parsedTrackCacheLimit = 3;

  /// Кэш производных от трека. Пересчитывается только при смене трека,
  /// дистанций или числа колонок — иначе один и тот же проход по точкам
  /// выполнялся бы несколько раз за кадр.
  ElevationSegments? _cachedElevation;
  ParsedTrack? _cachedElevationTrack;
  List<String> _cachedElevationDistances = const [];
  int _cachedElevationColumns = -1;

  List<PlanSegment>? _cachedPlanSegments;
  ParsedTrack? _cachedPlanTrack;
  List<String> _cachedPlanDistances = const [];
  int _cachedPlanColumns = -1;

  List<ProfilePoint>? _cachedProfile;
  ParsedTrack? _cachedProfileTrack;

  /// Раскрыта ли встроенная полоса профиля высот. Не сохраняется.
  bool _elevationRowOpen = false;

  /// Видимая область таблицы: нужна, чтобы делить ряд высот на левую и
  /// правую половину при горизонтальной прокрутке.
  final GlobalKey _tableViewportKey = GlobalKey();

  /// Высота ряда подъём–спуск в портрете, пикселей.
  static const double _elevationRowHeight = 30;

  /// Высота встроенной полосы профиля в портрете, пикселей.
  static const double _elevationStripHeight = 96;

  /// Служебная клетка раскрытия в итоговом ряду высот, пикселей.
  static const double _elevationToggleWidth = 30;

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

  /// Статусы плана относительно лимита. Пересчитываются один раз в
  /// `_buildTable`, чтобы не разбирать время для каждой клетки отдельно.
  List<PlanTimeStatus> _planStatuses = const <PlanTimeStatus>[];

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
            SizedBox(
              width: 190,
              child: PaceKeyboard(
                compact: true,
                tableLayout: false,
                isUltra: _isUltra,
                onKey: _onPadKey,
                onClear: _clearActive,
              ),
            ),
          ],
        );
      }

      return Column(
        children: [
          Expanded(child: calculator),
          PaceKeyboard(
            compact: false,
            tableLayout: false,
            isUltra: _isUltra,
            onKey: _onPadKey,
            onClear: _clearActive,
          ),
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
                        child: PaceKeyboard(
                          compact: true,
                          tableLayout: true,
                          isUltra: _isUltra,
                          onKey: _onPadKey,
                          onClear: _clearActive,
                        ),
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
              ? PaceKeyboard(
                  compact: false,
                  tableLayout: false,
                  isUltra: _isUltra,
                  onKey: _onPadKey,
                  onClear: _clearActive,
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}
