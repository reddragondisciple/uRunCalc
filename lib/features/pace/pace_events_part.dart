part of 'pace_view.dart';

extension _PaceEventsPart on _PaceViewState {
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
    await _deleteRemovedTracks();
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

    if (result.checkpoints < 1 ||
        result.checkpoints > _PaceViewState._maxColumns - 2) {
      _showMessage(
        AppStrings.paceCheckpointsRange(_PaceViewState._maxColumns - 2),
      );
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
      final distanceKey = trackDistanceKey(event, distance);
      // Разобранный трек удалённой дистанции больше не должен занимать память.
      _parsedTrackCache.removeWhere(
        (cachedKey, _) => cachedKey.startsWith('$distanceKey/'),
      );
      if (files == null) continue;
      try {
        await files.deleteDistance(distanceKey);
      } catch (error) {
        debugPrint(
          'uRunCalc: не удалось удалить трек $event/$distance: $error',
        );
      }
    }
  }

  /// Меню-шестерёнка: колонки, горный режим, треки, стоянки, окружение.
  Future<void> _showSettingsMenu() async {
    await PaceSettingsMenu.show(
      context,
      state: PaceSettingsState(
        mountainMode: _mountainEnabled,
        showStopsInPace: _showStopsInPace,
        activeSlotLabel: _activeTrackSlotLabel,
        surfaceEnabled: _environment.surfaceEnabled,
        weatherEnabled: _environment.weatherEnabled,
        shoesEnabled: _environment.shoesEnabled,
      ),
      actions: PaceSettingsActions(
        onColumns: _showColumnsDialog,
        onMountainChanged: _setMountainMode,
        onImportGpx: _importGpxFlow,
        onTrackSlot: _chooseTrackSlot,
        onStopsModeChanged: _setStopsInPace,
        onSurface: _showSurfaceDialog,
        onWeather: _showWeatherDialog,
        onShoes: _showShoesDialog,
      ),
    );
  }

  /// Покрытие, влажность, болота и броды считаются автоматически по треку.
  /// Диалог пока только подтверждает включение: ручного ввода пока нет.
  Future<void> _showSurfaceDialog() async {
    if (!_requireTrackForEnvironment()) return;

    final apply = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(AppStrings.environmentSurfaceTitle),
          content: const Text(AppStrings.environmentSurfaceHint),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(AppStrings.cancel),
            ),
            if (_environment.surfaceEnabled)
              TextButton(
                key: const ValueKey('environment-surface-disable'),
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text(AppStrings.environmentDisable),
              ),
            FilledButton(
              key: const ValueKey('environment-surface-apply'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(AppStrings.apply),
            ),
          ],
        );
      },
    );

    if (!mounted || apply == null) return;
    _update(() {
      _environment = _environment.copyWith(surfaceEnabled: apply);
    });
    unawaited(_refreshEnvironment());
  }

  /// Погода: дата и время старта плюс переключатель укатанного снега.
  Future<void> _showWeatherDialog() async {
    if (!_requireTrackForEnvironment()) return;

    final initial = _environmentStartLocal();
    var date = DateTime(initial.year, initial.month, initial.day);
    var time = TimeOfDay(hour: initial.hour, minute: initial.minute);
    var groomed = _environment.groomedSnow;

    final result = await showDialog<_WeatherDialogResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(AppStrings.environmentWeatherTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(AppStrings.environmentWeatherHint),
                    const SizedBox(height: 12),
                    ListTile(
                      key: const ValueKey('environment-weather-date'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: const Text(AppStrings.environmentStartDate),
                      subtitle: Text(_formatDate(date)),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() => date = picked);
                        }
                      },
                    ),
                    if (_beyondForecast(date))
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          AppStrings.environmentNoForecastHint,
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ),
                    ListTile(
                      key: const ValueKey('environment-weather-time'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule_outlined),
                      title: const Text(AppStrings.environmentStartTime),
                      subtitle: Text(_formatTime(time)),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: dialogContext,
                          initialTime: time,
                        );
                        if (picked != null) {
                          setDialogState(() => time = picked);
                        }
                      },
                    ),
                    SwitchListTile(
                      key: const ValueKey('environment-weather-groomed'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text(AppStrings.environmentGroomedSnow),
                      subtitle: const Text(
                        AppStrings.environmentGroomedSnowHint,
                      ),
                      value: groomed,
                      onChanged: (value) =>
                          setDialogState(() => groomed = value),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(AppStrings.cancel),
                ),
                if (_environment.weatherEnabled)
                  TextButton(
                    key: const ValueKey('environment-weather-disable'),
                    onPressed: () => Navigator.pop(
                      dialogContext,
                      const _WeatherDialogResult.disabled(),
                    ),
                    child: const Text(AppStrings.environmentDisable),
                  ),
                FilledButton(
                  key: const ValueKey('environment-weather-apply'),
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    _WeatherDialogResult(
                      date: date,
                      time: time,
                      groomed: groomed,
                    ),
                  ),
                  child: const Text(AppStrings.apply),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;
    if (result.disabled) {
      _update(() {
        _environment = _environment.copyWith(weatherEnabled: false);
      });
      unawaited(_refreshEnvironment());
      return;
    }
    final startLocal = DateTime(
      result.date!.year,
      result.date!.month,
      result.date!.day,
      result.time!.hour,
      result.time!.minute,
    );
    _update(() {
      _environment = _environment.copyWith(
        weatherEnabled: true,
        groomedSnow: result.groomed,
        startUtc: startLocal.toUtc(),
      );
    });
    unawaited(_refreshEnvironment());
  }

  /// Кроссовки: один глобальный множитель на всю таблицу.
  Future<void> _showShoesDialog() async {
    var shoe = _environment.shoe;

    final result = await showDialog<({bool disabled, ShoeKind? shoe})>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(AppStrings.environmentShoesTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(AppStrings.environmentShoesHint),
                    const SizedBox(height: 8),
                    RadioGroup<ShoeKind>(
                      groupValue: shoe,
                      onChanged: (value) => setDialogState(() => shoe = value),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final kind in ShoeKind.values)
                            RadioListTile<ShoeKind>(
                              key: ValueKey('environment-shoe-${kind.name}'),
                              contentPadding: EdgeInsets.zero,
                              title: Text(_shoeLabel(kind)),
                              value: kind,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(AppStrings.cancel),
                ),
                if (_environment.shoesEnabled)
                  TextButton(
                    key: const ValueKey('environment-shoes-disable'),
                    onPressed: () => Navigator.pop(dialogContext, (
                      disabled: true,
                      shoe: null,
                    )),
                    child: const Text(AppStrings.environmentDisable),
                  ),
                FilledButton(
                  key: const ValueKey('environment-shoes-apply'),
                  onPressed: shoe == null
                      ? null
                      : () => Navigator.pop(dialogContext, (
                          disabled: false,
                          shoe: shoe,
                        )),
                  child: const Text(AppStrings.apply),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;
    _update(() {
      _environment = result.disabled
          ? _environment.copyWith(shoesEnabled: false)
          : _environment.copyWith(shoesEnabled: true, shoe: result.shoe);
    });
    unawaited(_refreshEnvironment());
  }

  /// Дальше 16 дней Open-Meteo прогноза не даёт: будут климатические нормы.
  bool _beyondForecast(DateTime date) => beyondForecastWindow(date);

  bool _requireTrackForEnvironment() {
    if (_loadedTrack != null) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppStrings.environmentNoTrack)),
    );
    return false;
  }

  /// Пересчитывает окружение, только если пользователь включил хотя бы одну
  /// галочку. Иначе сеть не трогаем.
  void _refreshEnvironmentIfEnabled() {
    if (_environment.anyEnabled) unawaited(_refreshEnvironment());
  }

  /// Пересчитывает окружение после применения галочек. Сеть может отвечать
  /// долго, поэтому показываем индикатор и не блокируем ввод.
  Future<void> _refreshEnvironment() async {
    final request = ++_environmentRequest;
    final parsed = _loadedTrack;
    final settings = _environment;
    if (parsed == null || !settings.anyEnabled) {
      if (!mounted) return;
      _update(() {
        _environmentData = EnvironmentData(settings: settings);
        _environmentLoading = false;
      }, persist: false);
      _recomputeMountainPlan();
      return;
    }

    final profile = _factorProfile ??= await FactorProfileStore().load();
    if (!mounted || request != _environmentRequest) return;
    _update(() => _environmentLoading = true, persist: false);

    try {
      var data = await _environmentService.compute(
        parsed: parsed,
        settings: settings,
        profile: profile,
        flatPaceSecPerKm: _flatPaceForEnvironment(),
      );
      if (!mounted || request != _environmentRequest) return;

      // Время прибытия зависит от множителей, а погода — от времени.
      // Пока план меняется заметнее 1%, уточняем времена (обычно 2 прохода).
      if (settings.weatherEnabled &&
          settings.startUtc != null &&
          _mountainEnabled) {
        for (var pass = 0; pass < 2; pass++) {
          final before = _plannedElapsedSec();
          _environmentData = data;
          _recomputeMountainPlan();
          final after = _plannedElapsedSec();
          if (before == null || after == null || after <= 0) break;
          if (pass > 0 && (after - before).abs() / after < 0.01) break;

          data = await _environmentService.compute(
            parsed: parsed,
            settings: settings,
            profile: profile,
            flatPaceSecPerKm: _flatPaceForEnvironment(),
            movingSecAt: _arrivalSecAt,
          );
          if (!mounted || request != _environmentRequest) return;
        }
      }

      _update(() {
        _environmentData = data;
        _environmentLoading = false;
      }, persist: false);
      _recomputeMountainPlan();
      if (data.warning != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(data.warning!)));
      }
    } catch (error) {
      debugPrint('uRunCalc: окружение не рассчитано: $error');
      if (!mounted || request != _environmentRequest) return;
      _update(() {
        _environmentData = EnvironmentData(
          settings: settings,
          warning: 'Не удалось рассчитать окружение',
        );
        _environmentLoading = false;
      }, persist: false);
    }
  }

  /// Плоский темп для оценки времени прибытия: из опоры плана, иначе из
  /// текущей таблицы, иначе 6:00/км.
  double _flatPaceForEnvironment() {
    final anchor = _planAnchor;
    final anchored = anchor?.flatPaceSec;
    if (anchored != null && anchored > 0) return anchored;
    final distance = _totalTableDistance;
    final elapsed = _plannedElapsedSec();
    if (distance != null && distance > 0 && elapsed != null && elapsed > 0) {
      return elapsed / distance;
    }
    return 360;
  }

  /// Суммарное время плана в секундах от первой до последней колонки.
  /// `null` — времена не заполнены, уточнять нечего.
  double? _plannedElapsedSec() {
    if (_columns < 2 || _planTimes.length < _columns) return null;
    final first = _parseTimeBuffer(_planTimes[0]);
    if (first == null) return null;
    var previous = first;
    var elapsedMinutes = 0;
    for (var i = 1; i < _columns; i++) {
      final current = _parseTimeBuffer(_planTimes[i]);
      if (current == null) return null;
      var delta = current - previous;
      // Переход через полночь; сегменты длиннее 12 ч не укорачиваем.
      if (delta < -12 * 60) delta += 24 * 60;
      if (delta < 0) return null;
      elapsedMinutes += delta;
      previous = current;
    }
    return elapsedMinutes * 60.0;
  }

  /// Секунды от старта до расстояния [distanceM] по текущему плану.
  /// Между ПП время интерполируется; без плана — плоский темп.
  double _arrivalSecAt(double distanceM) {
    final flat = distanceM / 1000 * _flatPaceForEnvironment();
    if (_columns < 2 || _planTimes.length < _columns) return flat;

    final first = _parseTimeBuffer(_planTimes[0]);
    if (first == null) return flat;
    var previous = first;
    final elapsed = <double>[0];
    for (var i = 1; i < _columns; i++) {
      final current = _parseTimeBuffer(_planTimes[i]);
      if (current == null) return flat;
      var delta = current - previous;
      if (delta < -12 * 60) delta += 24 * 60;
      if (delta < 0) return flat;
      elapsed.add(elapsed.last + delta * 60);
      previous = current;
    }

    final km = distanceM / 1000;
    for (var i = 1; i < _columns; i++) {
      final fromKm = parseDecimal(_tableDistances[i - 1]) ?? 0;
      final toKm = parseDecimal(_tableDistances[i]) ?? 0;
      if (toKm <= fromKm) continue;
      if (km <= toKm) {
        final t = ((km - fromKm) / (toKm - fromKm)).clamp(0.0, 1.0);
        return elapsed[i - 1] + (elapsed[i] - elapsed[i - 1]) * t;
      }
    }
    return elapsed.last;
  }

  /// Время старта для диалога погоды: сохранённое, иначе из трека, иначе
  /// текущее. Время суток из полей плана важнее времени трека.
  DateTime _environmentStartLocal() {
    final saved = _environment.startUtc?.toLocal();
    if (saved != null) return saved;

    final trackStart = _trackStartLocal();
    final fallback = trackStart ?? DateTime.now();
    final hours = int.tryParse(_startHours);
    final minutes = int.tryParse(_startMinutes);
    if (hours == null || minutes == null) return fallback;
    return DateTime(
      fallback.year,
      fallback.month,
      fallback.day,
      hours.clamp(0, 23),
      minutes.clamp(0, 59),
    );
  }

  DateTime? _trackStartLocal() {
    final track = _loadedTrack;
    if (track == null || !track.track.hasTime) return null;
    final first = track.track.timesSec.first;
    if (first.isNaN) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      (first * 1000).round(),
      isUtc: true,
    ).toLocal();
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _shoeLabel(ShoeKind kind) => switch (kind) {
    ShoeKind.road => AppStrings.shoeRoad,
    ShoeKind.trail => AppStrings.shoeTrail,
    ShoeKind.minimal => AppStrings.shoeMinimal,
  };

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
                    onPressed: columns < _PaceViewState._maxColumns
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

  /// Строка состояния окружения: загрузка, покрытие OSM и предупреждения.
  /// Без включённых галочек места не занимает.
  Widget _buildEnvironmentStatus() {
    if (!_environment.anyEnabled) return const SizedBox.shrink();
    if (_environmentLoading) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 6),
            Text(
              AppStrings.environmentLoading,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }
    final data = _environmentData;
    if (data == null) return const SizedBox.shrink();

    final parts = <String>[
      if (_environment.surfaceEnabled)
        data.rasterCoverage > 0
            ? AppStrings.environmentCoverageWithRaster(
                (data.surfaceCoverage * 100).round(),
                (data.rasterCoverage * 100).round(),
              )
            : AppStrings.environmentCoverage(
                (data.surfaceCoverage * 100).round(),
              ),
      if (_environment.weatherEnabled && data.weather.isNotEmpty)
        AppStrings.environmentWeatherRange(
          _temperatureRange(data.weather, (s) => s.tempC),
          _temperatureRange(data.weather, (s) => s.apparentC),
        ),
      if (data.warning != null) data.warning!,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        parts.join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
      ),
    );
  }

  /// «16…22» или «18» для одного значения.
  String _temperatureRange(
    List<WeatherSample> samples,
    double Function(WeatherSample) value,
  ) {
    var min = value(samples.first);
    var max = min;
    for (final sample in samples) {
      final current = value(sample);
      if (current < min) min = current;
      if (current > max) max = current;
    }
    final low = min.round();
    final high = max.round();
    return low == high ? '$low' : '$low…$high';
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
            loading: _environmentLoading,
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
        if (_columns > _PaceViewState._baseColumns) ...[
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
    final elevation = _hasElevationData ? _elevationSegments : null;
    final elevationPairs = <String>[
      if (elevation != null)
        for (var index = 0; index < _columns; index++)
          index == 0
              ? ''
              : formatElevationPair(
                  elevation.ascentM[index],
                  elevation.descentM[index],
                ),
    ];

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
      activeTrack: _activeTrackSlotLabel,
      elevationPairs: elevationPairs,
      totalAscent: elevation == null
          ? ''
          : formatElevationMeters(elevation.totalAscentM),
      totalDescent: elevation == null
          ? ''
          : formatElevationMeters(elevation.totalDescentM),
      profile: _hasElevationData ? _elevationProfile() : const [],
      elevationKms: [
        for (var index = 0; index < _columns; index++)
          parseDecimal(_tableDistances[index]) ?? 0,
      ],
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
    bool loading = false,
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
            if (loading)
              SizedBox(
                width: iconOnly ? 20 : 15,
                height: iconOnly ? 20 : 15,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            else
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
}

/// Результат диалога погоды. `disabled` отделяет «Отключить» от «Отмены»:
/// отмена возвращает `null` и не меняет состояние.
class _WeatherDialogResult {
  const _WeatherDialogResult({
    required this.date,
    required this.time,
    required this.groomed,
  }) : disabled = false;

  const _WeatherDialogResult.disabled()
    : date = null,
      time = null,
      groomed = false,
      disabled = true;

  final DateTime? date;
  final TimeOfDay? time;
  final bool groomed;
  final bool disabled;
}
