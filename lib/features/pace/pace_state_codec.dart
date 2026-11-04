import 'pace_catalog.dart';
import 'pace_table_data.dart';

/// Простое состояние калькулятора Pace в том виде, в каком оно хранится
/// на диске.
class PaceCalculatorState {
  const PaceCalculatorState({
    this.calc = '',
    this.distance = '',
    this.paceMinutes = '',
    this.paceSeconds = '',
    this.days = '',
    this.hours = '',
    this.minutes = '',
    this.seconds = '',
  });

  /// Восстанавливает поля из JSON, подставляя пустые строки вместо
  /// значений неизвестного типа. Имя режима не проверяется: это делает UI,
  /// чтобы оставить текущий режим при неизвестном значении.
  factory PaceCalculatorState.fromJson(Map<dynamic, dynamic> data) {
    return PaceCalculatorState(
      calc: _readString(data['calc']),
      distance: _readString(data['distance']),
      paceMinutes: _readString(data['paceMinutes']),
      paceSeconds: _readString(data['paceSeconds']),
      days: _readString(data['days']),
      hours: _readString(data['hours']),
      minutes: _readString(data['minutes']),
      seconds: _readString(data['seconds']),
    );
  }

  final String calc;
  final String distance;
  final String paceMinutes;
  final String paceSeconds;
  final String days;
  final String hours;
  final String minutes;
  final String seconds;

  Map<String, dynamic> toJson() {
    return {
      'calc': calc,
      'distance': distance,
      'paceMinutes': paceMinutes,
      'paceSeconds': paceSeconds,
      'days': days,
      'hours': hours,
      'minutes': minutes,
      'seconds': seconds,
    };
  }

  static String _readString(dynamic value) => value is String ? value : '';
}

/// Полное состояние Ultra, восстановленное из хранилища: мероприятия,
/// выбранная таблица и снимки всех таблиц по ключу
/// [PaceStateCodec.tableKey].
class PaceUltraState {
  PaceUltraState({
    required List<PaceEvent> events,
    required this.selectedEvent,
    required this.selectedDistance,
    required Map<String, PaceTableData> tables,
  }) : events = List<PaceEvent>.unmodifiable(events),
       tables = Map<String, PaceTableData>.unmodifiable(tables);

  final List<PaceEvent> events;
  final String selectedEvent;
  final String selectedDistance;
  final Map<String, PaceTableData> tables;
}

/// Кодек состояния Pace/Ultra: ключи хранилища, формат JSON и миграции.
///
/// Класс не зависит от Flutter и виджетов, поэтому его легко покрывать
/// unit-тестами. Виджет отвечает только за снимок текущей таблицы и за
/// применение восстановленного состояния к своим полям.
class PaceStateCodec {
  PaceStateCodec._();

  /// Максимальное число колонок таблицы и предел числа ПП.
  static const int maxColumns = 20;

  static const String legacyStorageKey = 'pace_state_v1';
  static const String paceStorageKey = 'pace_calc_state_v1';
  static const String ultraStorageKey = 'ultra_state_v1';

  /// Разделитель мероприятия и дистанции в ключах карты таблиц.
  static const String _keySeparator = '\u0001';

  static String tableKey(String event, String distance) =>
      '$event$_keySeparator$distance';

  static String tableKeyPrefix(String event) => '$event$_keySeparator';

  static Map<String, dynamic> encodeCalculator(PaceCalculatorState state) =>
      state.toJson();

  static PaceCalculatorState decodeCalculator(Map<String, dynamic> data) =>
      PaceCalculatorState.fromJson(data);

  /// Собирает JSON состояния Ultra. [currentTable] — снимок открытой таблицы;
  /// он всегда важнее одноимённой записи из [tables], потому что пользователь
  /// мог изменить её, не переключая мероприятие.
  static Map<String, dynamic> encodeUltra({
    required Iterable<PaceEvent> events,
    required String selectedEvent,
    required String selectedDistance,
    required Map<String, PaceTableData> tables,
    PaceTableData? currentTable,
  }) {
    final encodedTables = <String, dynamic>{};
    for (final entry in tables.entries) {
      final separator = entry.key.indexOf(_keySeparator);
      if (separator < 0) continue;
      final eventName = entry.key.substring(0, separator);
      final distanceName = entry.key.substring(separator + 1);
      final eventTables = encodedTables.putIfAbsent(
        eventName,
        () => <String, dynamic>{},
      );
      if (eventTables is Map<String, dynamic>) {
        eventTables[distanceName] = entry.value.toJson();
      }
    }

    if (currentTable != null && selectedDistance != PaceCatalog.noDistance) {
      final currentTables = encodedTables.putIfAbsent(
        selectedEvent,
        () => <String, dynamic>{},
      );
      if (currentTables is Map<String, dynamic>) {
        currentTables[selectedDistance] = currentTable.toJson();
      }
    }

    return {
      'events': [
        for (final event in events)
          {
            'name': event.name,
            'distances': [
              for (final distance in event.distances)
                {'name': distance.name, 'checkpoints': distance.checkpoints},
            ],
          },
      ],
      'selectedEvent': selectedEvent,
      'selectedDistance': selectedDistance,
      'tables': encodedTables,
    };
  }

  /// Восстанавливает состояние Ultra. [fallbackEvents] и [fallbackEvent]
  /// используются, если в данных нет корректного списка мероприятий или
  /// выбранное мероприятие не найдено.
  static PaceUltraState decodeUltra(
    Map<String, dynamic> data, {
    required Iterable<PaceEvent> fallbackEvents,
    required String fallbackEvent,
  }) {
    var events = _normalizeEvents(_decodeEvents(data['events']));
    if (events.isEmpty) {
      events = _normalizeEvents(fallbackEvents);
    }

    if (events.isEmpty) {
      return PaceUltraState(
        events: const [],
        selectedEvent: fallbackEvent,
        selectedDistance: PaceCatalog.noDistance,
        tables: const {},
      );
    }

    var selectedEvent = fallbackEvent;
    final storedEvent = data['selectedEvent'];
    if (storedEvent is String &&
        events.any((event) => event.name == storedEvent)) {
      selectedEvent = storedEvent;
    }
    final event = events.firstWhere(
      (event) => event.name == selectedEvent,
      orElse: () => events.first,
    );
    selectedEvent = event.name;

    final storedDistance = data['selectedDistance'];
    var requestedDistance = storedDistance is String ? storedDistance : '';
    if (event.name == PaceCatalog.madFoxEvent &&
        requestedDistance == PaceCatalog.legacyVrDistance) {
      requestedDistance = PaceCatalog.vrDistance;
    }
    final String selectedDistance;
    if (event.distances.any((distance) => distance.name == requestedDistance)) {
      selectedDistance = requestedDistance;
    } else if (event.distances.isNotEmpty) {
      selectedDistance = event.distances.first.name;
    } else {
      selectedDistance = PaceCatalog.noDistance;
    }

    final tables = <String, PaceTableData>{};
    final rawTables = data['tables'];
    if (rawTables is Map) {
      for (final eventEntry in rawTables.entries) {
        final eventName = eventEntry.key;
        final eventTables = eventEntry.value;
        if (eventName is! String || eventTables is! Map) continue;
        for (final distanceEntry in eventTables.entries) {
          var distanceName = distanceEntry.key;
          final rawTable = distanceEntry.value;
          if (distanceName is! String || rawTable is! Map) continue;
          if (eventName == PaceCatalog.madFoxEvent &&
              distanceName == PaceCatalog.legacyVrDistance) {
            distanceName = PaceCatalog.vrDistance;
          }
          final table = PaceTableData.tryFromJson(
            rawTable,
            maxColumns: maxColumns,
          );
          if (table != null) {
            tables.putIfAbsent(tableKey(eventName, distanceName), () => table);
          }
        }
      }
    }

    // Данные старой версии хранились одной таблицей без разбивки по
    // мероприятиям и дистанциям.
    final legacyTable = PaceTableData.tryFromJson(data, maxColumns: maxColumns);
    if (legacyTable != null) {
      tables.putIfAbsent(
        tableKey(selectedEvent, selectedDistance),
        () => legacyTable,
      );
    }

    return PaceUltraState(
      events: events,
      selectedEvent: selectedEvent,
      selectedDistance: selectedDistance,
      tables: tables,
    );
  }

  static List<PaceEvent> _decodeEvents(dynamic rawEvents) {
    if (rawEvents is! List) return const [];

    final events = <PaceEvent>[];
    for (final rawEvent in rawEvents) {
      if (rawEvent is! Map) continue;
      final name = rawEvent['name'];
      if (name is! String || name.isEmpty) continue;

      final distances = <PaceDistance>[];
      final rawDistances = rawEvent['distances'];
      if (rawDistances is List) {
        for (final rawDistance in rawDistances) {
          if (rawDistance is! Map) continue;
          final distanceName = rawDistance['name'];
          final checkpoints = rawDistance['checkpoints'];
          if (distanceName is! String || distanceName.isEmpty) continue;
          if (checkpoints is! int) continue;
          distances.add(PaceDistance(distanceName, checkpoints));
        }
      }
      events.add(PaceEvent(name, distances));
    }
    return events;
  }

  /// Переименовывает устаревшую дистанцию Mad Fox Ultra `100M` в `VR` и
  /// приводит число ПП к допустимому диапазону. Стартовые значения известных
  /// дистанций сохраняются.
  static List<PaceEvent> _normalizeEvents(Iterable<PaceEvent> events) {
    return [
      for (final event in events)
        if (event.name.isNotEmpty)
          PaceEvent(event.name, [
            for (final distance in event.distances)
              if (distance.name.isNotEmpty)
                PaceDistance(
                  event.name == PaceCatalog.madFoxEvent &&
                          distance.name == PaceCatalog.legacyVrDistance
                      ? PaceCatalog.vrDistance
                      : distance.name,
                  distance.checkpoints.clamp(1, maxColumns - 2).toInt(),
                  defaultTimes: distance.defaultTimes,
                  defaultDistances: distance.defaultDistances,
                ),
          ]),
    ];
  }
}
