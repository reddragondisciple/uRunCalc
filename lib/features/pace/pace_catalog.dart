/// Дистанция мероприятия.
class PaceDistance {
  PaceDistance(
    this.name,
    this.checkpoints, {
    this.defaultTimes = const [],
    this.defaultDistances = const [],
  });

  final String name;
  final int checkpoints;

  /// Значения, которыми заполняется новая таблица дистанции.
  final List<String> defaultTimes;
  final List<String> defaultDistances;
}

/// Мероприятие со списком дистанций.
class PaceEvent {
  PaceEvent(this.name, this.distances);

  final String name;
  final List<PaceDistance> distances;
}

/// Стартовые мероприятия, дистанции и значения таблиц.
class PaceCatalog {
  PaceCatalog._();

  static const String madFoxEvent = 'Mad Fox Ultra';
  static const String legacyVrDistance = '100M';
  static const String vrDistance = 'VR';
  static const String noDistance = '—';

  static const List<String> _grutT100Times = [
    '0500',
    '0700',
    '0800',
    '1000',
    '1700',
    '2035',
    '2200',
    '2300',
  ];

  static const List<String> _grutT100Distances = [
    '',
    '11',
    '18.8',
    '30',
    '70.2',
    '94',
    '102.2',
    '109.5',
  ];

  static const List<String> _madFoxVrTimes = [
    '1600',
    '2100',
    '2350',
    '0300',
    '0640',
    '0930',
    '1245',
    '1500',
    '1730',
    '1900',
    '2200',
  ];

  static const List<String> _madFoxVrDistances = [
    '',
    '20.3',
    '32.2',
    '47.3',
    '72',
    '90.7',
    '111.2',
    '125.8',
    '139.6',
    '148.5',
    '165.2',
  ];

  /// Данные для дистанции K40 в Mad Fox Ultra (время).
  static const List<String> _madFoxK40Times = ['1030', '1330', '1530', '1830'];

  /// Дистанции для K40 в Mad Fox Ultra (в км).
  static const List<String> _madFoxK40Distances = ['', '14.8', '24', '40.7'];

  static List<PaceEvent> defaults() => [
    PaceEvent('GRUT', [
      PaceDistance(
        'T100',
        6,
        defaultTimes: _grutT100Times,
        defaultDistances: _grutT100Distances,
      ),
      PaceDistance('T80', 6),
      PaceDistance('T50', 4),
    ]),
    PaceEvent(madFoxEvent, [
      PaceDistance(
        vrDistance,
        9,
        defaultTimes: _madFoxVrTimes,
        defaultDistances: _madFoxVrDistances,
      ),
      PaceDistance('50M', 5),
      PaceDistance('K70', 4),
      PaceDistance(
        'K40',
        2,
        defaultTimes: _madFoxK40Times,
        defaultDistances: _madFoxK40Distances,
      ),
    ]),
  ];

  /// Переименовывает старую дистанцию `100M` в `VR` и подключает стартовые
  /// данные к известным дистанциям, загруженным из старого хранилища.
  static void prepareDistanceDefaults(List<PaceEvent> events) {
    for (final event in events) {
      for (var index = 0; index < event.distances.length; index++) {
        final distance = event.distances[index];
        final isLegacyVr =
            event.name == madFoxEvent && distance.name == legacyVrDistance;
        final name = isLegacyVr ? vrDistance : distance.name;
        if (!isLegacyVr &&
            (distance.defaultTimes.isNotEmpty ||
                distance.defaultDistances.isNotEmpty)) {
          continue;
        }

        List<String>? times;
        List<String>? distances;
        if (event.name == 'GRUT' && name == 'T100') {
          times = _grutT100Times;
          distances = _grutT100Distances;
        } else if (event.name == madFoxEvent && name == vrDistance) {
          times = _madFoxVrTimes;
          distances = _madFoxVrDistances;
        }

        if (times == null || distances == null) {
          if (isLegacyVr) {
            event.distances[index] = PaceDistance(
              vrDistance,
              distance.checkpoints,
            );
          }
          continue;
        }

        event.distances[index] = PaceDistance(
          name,
          distance.checkpoints,
          defaultTimes: times,
          defaultDistances: distances,
        );
      }
    }
  }

  static PaceDistance? findDistance(
    List<PaceEvent> events,
    String eventName,
    String distanceName,
  ) {
    for (final event in events) {
      if (event.name != eventName) continue;
      for (final distance in event.distances) {
        if (distance.name == distanceName) return distance;
      }
    }
    return null;
  }
}
