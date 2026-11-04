/// Источник, из которого посчитаны итоговые плановые показатели.
enum PacePlannedSummarySource { none, pace, time }

/// Снимок таблицы Ultra/Pace, пригодный для хранения и передачи между
/// экранами.
///
/// Объект неизменяемый: списки копируются в конструкторе, поэтому после
/// создания данные нельзя случайно изменить из UI. Все «правки» выполняются
/// через создание нового снимка.
class PaceTableData {
  PaceTableData({
    required this.columns,
    required this.fitTable,
    required List<String> times,
    required List<String> distances,
    required List<String> planTimes,
    required List<String> planPaces,
    required List<String> notes,
    required List<String> water,
    required List<String> food,
    this.locked = false,
    this.lockedLimits = false,
    this.plannedPaceOverride = '',
    this.plannedTimeOverride = '',
    this.plannedSummarySource = PacePlannedSummarySource.none,
    this.seeded = false,
    List<int> boldColumns = const <int>[],
  }) : times = List<String>.unmodifiable(times),
       distances = List<String>.unmodifiable(distances),
       planTimes = List<String>.unmodifiable(planTimes),
       planPaces = List<String>.unmodifiable(planPaces),
       notes = List<String>.unmodifiable(notes),
       water = List<String>.unmodifiable(water),
       food = List<String>.unmodifiable(food),
       boldColumns = List<int>.unmodifiable(boldColumns);

  /// Восстанавливает таблицу из JSON. Возвращает `null`, если данные
  /// повреждены или относятся к неизвестному формату.
  static PaceTableData? tryFromJson(
    Map<dynamic, dynamic> data, {
    int minColumns = 3,
    int maxColumns = 20,
  }) {
    final rawColumns = data['columns'];
    if (rawColumns is! int) return null;
    final columns = rawColumns.clamp(minColumns, maxColumns).toInt();

    final boldColumns = <int>[];
    final rawBold = data['boldColumns'];
    if (rawBold is List) {
      for (final item in rawBold) {
        if (item is int) boldColumns.add(item);
      }
    }

    return PaceTableData(
      columns: columns,
      fitTable: data['fitTable'] is bool ? data['fitTable'] as bool : true,
      times: _readStringList(data['tableTimes'], columns),
      distances: _readStringList(data['tableDistances'], columns),
      planTimes: _readStringList(data['planTimes'], columns),
      planPaces: _readStringList(data['planPaces'], columns),
      notes: _readStringList(data['notes'], columns),
      water: _readStringList(data['water'], columns),
      food: _readStringList(data['food'], columns),
      locked: data['locked'] is bool ? data['locked'] as bool : false,
      lockedLimits: data['lockedLimits'] is bool
          ? data['lockedLimits'] as bool
          : false,
      plannedPaceOverride: _readString(data['plannedPaceOverride']),
      plannedTimeOverride: _readString(data['plannedTimeOverride']),
      plannedSummarySource: _plannedSourceFromName(
        data['plannedSummarySource'],
      ),
      seeded: data['seeded'] is bool ? data['seeded'] as bool : false,
      boldColumns: boldColumns,
    );
  }

  final int columns;
  final bool fitTable;
  final List<String> times;
  final List<String> distances;
  final List<String> planTimes;
  final List<String> planPaces;
  final List<String> notes;
  final List<String> water;
  final List<String> food;
  final bool locked;
  final bool lockedLimits;
  final String plannedPaceOverride;
  final String plannedTimeOverride;
  final PacePlannedSummarySource plannedSummarySource;

  /// Стартовые данные для этой таблицы уже применялись или проверялись.
  final bool seeded;
  final List<int> boldColumns;

  Map<String, dynamic> toJson() {
    return {
      'columns': columns,
      'fitTable': fitTable,
      'tableTimes': times,
      'tableDistances': distances,
      'planTimes': planTimes,
      'planPaces': planPaces,
      'notes': notes,
      'water': water,
      'food': food,
      'locked': locked,
      'lockedLimits': lockedLimits,
      'plannedPaceOverride': plannedPaceOverride,
      'plannedTimeOverride': plannedTimeOverride,
      'plannedSummarySource': plannedSummarySource.name,
      'seeded': seeded,
      'boldColumns': boldColumns,
    };
  }

  /// Пустая таблица: заполнены только служебные значения.
  bool get isEmpty {
    bool hasValue(List<String> values, {int skip = 0}) {
      for (var index = skip; index < values.length; index++) {
        if (values[index].trim().isNotEmpty) return true;
      }
      return false;
    }

    return !hasValue(times) &&
        !hasValue(distances, skip: 1) &&
        !hasValue(planTimes) &&
        !hasValue(planPaces) &&
        !hasValue(notes) &&
        !hasValue(water) &&
        !hasValue(food);
  }

  static String _readString(dynamic value) => value is String ? value : '';

  static List<String> _readStringList(dynamic value, int length) {
    final result = List<String>.filled(length, '');
    if (value is List) {
      for (var index = 0; index < length && index < value.length; index++) {
        final item = value[index];
        if (item is String) result[index] = item;
      }
    }
    return result;
  }

  static PacePlannedSummarySource _plannedSourceFromName(dynamic value) {
    if (value is String) {
      for (final source in PacePlannedSummarySource.values) {
        if (source.name == value) return source;
      }
    }
    return PacePlannedSummarySource.none;
  }
}
