import 'pace_catalog.dart';
import 'pace_state_codec.dart';
import 'pace_table_data.dart';

/// Хранит мероприятия, выбранную таблицу и снимки всех таблиц Pace/Ultra.
///
/// Контроллер не знает о Flutter: текущая таблица приходит и уходит снимками
/// [PaceTableData], а виджет сам раскладывает снимок по полям ввода. Это
/// позволяет покрывать переключение таблиц unit-тестами.
class PaceStateController {
  PaceStateController({
    required List<PaceEvent> events,
    required this.selectedEvent,
    required this.selectedDistance,
    Map<String, PaceTableData> tables = const {},
  }) : events = List<PaceEvent>.of(events),
       _tables = Map<String, PaceTableData>.of(tables);

  /// Состояние по умолчанию: первое мероприятие и его первая дистанция.
  factory PaceStateController.defaults() {
    final events = PaceCatalog.defaults();
    return PaceStateController(
      events: events,
      selectedEvent: events.first.name,
      selectedDistance: events.first.distances.first.name,
    );
  }

  final List<PaceEvent> events;
  String selectedEvent;
  String selectedDistance;
  final Map<String, PaceTableData> _tables;

  /// Сохранение разрешено только после загрузки состояния.
  bool stateLoaded = false;

  /// Удалённые дистанции `(мероприятие, дистанция)`. Виджет после удаления
  /// чистит их треки на диске и очищает список.
  final List<(String, String)> _removedDistances = [];

  /// Забирает список удалённых дистанций, чтобы удалить их треки на диске.
  List<(String, String)> takeRemovedDistances() {
    final result = List<(String, String)>.of(_removedDistances);
    _removedDistances.clear();
    return result;
  }

  String get eventLabel => '$selectedEvent · $selectedDistance';

  PaceDistance? get currentDistance =>
      PaceCatalog.findDistance(events, selectedEvent, selectedDistance);

  PaceTableData? tableFor(String event, String distance) =>
      _tables[PaceStateCodec.tableKey(event, distance)];

  PaceTableData? get currentTable => tableFor(selectedEvent, selectedDistance);

  /// Запоминает снимок открытой таблицы. Для состояния без дистанции
  /// (`—`) сохранять нечего.
  void saveCurrent(PaceTableData table) {
    if (selectedDistance == PaceCatalog.noDistance) return;
    _tables[PaceStateCodec.tableKey(selectedEvent, selectedDistance)] = table;
  }

  Map<String, dynamic> encode({PaceTableData? snapshot}) {
    return PaceStateCodec.encodeUltra(
      events: events,
      selectedEvent: selectedEvent,
      selectedDistance: selectedDistance,
      tables: _tables,
      currentTable: snapshot,
    );
  }

  /// Применяет восстановленное из хранилища состояние.
  void apply(PaceUltraState state) {
    events
      ..clear()
      ..addAll(state.events);
    selectedEvent = state.selectedEvent;
    selectedDistance = state.selectedDistance;
    _tables
      ..clear()
      ..addAll(state.tables);
  }

  /// Подключает стартовые значения к известным дистанциям.
  void prepareDefaults() => PaceCatalog.prepareDistanceDefaults(events);

  PaceEvent eventNamed(String name) => events.firstWhere(
    (event) => event.name == name,
    orElse: () => events.first,
  );

  void select(PaceEvent event, PaceDistance distance) {
    selectedEvent = event.name;
    selectedDistance = distance.name;
  }

  /// Добавляет мероприятие. Возвращает `false`, если такое уже есть.
  bool addEvent(String name) {
    if (events.any((event) => event.name == name)) return false;
    events.add(PaceEvent(name, []));
    return true;
  }

  /// Удаляет мероприятие вместе с его таблицами. Последнее мероприятие
  /// удалить нельзя. При удалении выбранного мероприятия выбор переходит
  /// на первое оставшееся.
  bool removeEvent(String name) {
    if (events.length <= 1) return false;

    final before = events.length;
    events.removeWhere((event) => event.name == name);
    if (events.length == before) return false;

    _tables.removeWhere(
      (key, _) => key.startsWith(PaceStateCodec.tableKeyPrefix(name)),
    );

    if (selectedEvent == name) {
      final first = events.first;
      selectedEvent = first.name;
      selectedDistance = first.distances.isNotEmpty
          ? first.distances.first.name
          : PaceCatalog.noDistance;
    }
    return true;
  }

  /// Добавляет дистанцию. Возвращает `false`, если такая уже есть.
  bool addDistance(PaceEvent event, String name, int checkpoints) {
    if (event.distances.any((distance) => distance.name == name)) return false;
    event.distances.add(PaceDistance(name, checkpoints));
    return true;
  }

  /// Удаляет дистанцию вместе с её таблицей. Последнюю дистанцию удалить
  /// нельзя. При удалении выбранной дистанции выбор переходит на первую
  /// оставшуюся.
  bool removeDistance(PaceEvent event, String name) {
    if (event.distances.length <= 1) return false;

    final before = event.distances.length;
    event.distances.removeWhere((distance) => distance.name == name);
    if (event.distances.length == before) return false;

    _tables.remove(PaceStateCodec.tableKey(event.name, name));
    _removedDistances.add((event.name, name));

    if (selectedEvent == event.name && selectedDistance == name) {
      selectedDistance = event.distances.first.name;
    }
    return true;
  }
}
