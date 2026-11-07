part of 'pace_view.dart';

extension _PaceMountainPart on _PaceViewState {
  /// Переключает горный режим. Данные таблицы не теряются при выключении —
  /// только скрываются ряды. При включении подгружаем трек и пересчитываем
  /// план: состояние могло быть восстановлено с выключенным режимом.
  void _setMountainMode(bool enabled) {
    _update(() {
      _mountainEnabled = enabled;
      if (enabled) _recomputeMountainPlan();
    });
    if (enabled) unawaited(_ensureTrackLoaded());
  }

  void _setStopsInPace(bool enabled) {
    _update(() => _showStopsInPace = enabled);
  }

  /// Выбор основного/резервного слота. Сам трек пока не переключается:
  /// это сделает импорт (следующий шаг).
  Future<void> _chooseTrackSlot() async {
    final next = _activeTrackSlot == 'backup' ? 'primary' : 'backup';
    _update(() {
      _tracks = _withActive(_tracks, next);
      // Старый слот больше не актуален: не показываем его высоты, пока
      // читается новый трек.
      _loadedTrack = null;
      _loadedTrackKey = null;
    });
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

    final PickedTrackFile? picked;
    try {
      picked = await TrackFilePicker.pick();
    } on TrackFilePickException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
      return;
    }
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

  Future<void> _initTrackFiles() async {
    // На web нет `path_provider` и файловой системы: треки недоступны,
    // приложение продолжает работать без горного режима.
    if (kIsWeb) return;

    try {
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
    } catch (error) {
      // Нет каталога/разрешений — это не повод ронять экран.
      debugPrint('uRunCalc: хранилище треков недоступно: $error');
    }
    if (!mounted) return;
    // Загрузка трека могла стартовать раньше, чем появилось хранилище.
    unawaited(_ensureTrackLoaded());
  }

  String _currentTrackKey() =>
      '${trackDistanceKey(_controller.selectedEvent, _controller.selectedDistance)}'
      '/${_tracks.active}';

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
  ///
  /// Во время `await` пользователь может сменить дистанцию или слот. Поэтому
  /// после чтения ключ сверяется с текущим, а устаревший результат не
  /// применяется: вместо этого загружается актуальный трек.
  Future<void> _ensureTrackLoaded() async {
    if (_loadingTrack) {
      _trackLoadQueued = true;
      return;
    }

    _loadingTrack = true;
    try {
      while (mounted) {
        final files = _trackFiles;
        final meta = _tracks.activeTrack;
        final key = _currentTrackKey();
        if (files == null || meta == null || !_mountainEnabled) return;
        if (_loadedTrackKey == key) return;

        final content = await files.read(
          distanceKey: trackDistanceKey(
            _controller.selectedEvent,
            _controller.selectedDistance,
          ),
          fileName: meta.relativePath,
        );
        if (!mounted) return;

        // Пока читали, выбор мог измениться — этот результат уже не нужен.
        if (key != _currentTrackKey()) {
          _trackLoadQueued = true;
          continue;
        }

        if (content == null) {
          // Файла нет: запоминаем ключ, чтобы не перечитывать его на каждый
          // запрос. Импорт сбрасывает ключ и попробует снова.
          _update(() {
            _loadedTrack = null;
            _loadedTrackKey = key;
          }, persist: false);
          return;
        }

        final parsed = parseTrackFile(
          PickedTrackFile(name: meta.originalName, content: content),
        );
        if (parsed.parsed == null) {
          // Битый файл: ведём себя как с отсутствующим.
          _update(() {
            _loadedTrack = null;
            _loadedTrackKey = key;
          }, persist: false);
          return;
        }
        if (!mounted) return;
        if (key != _currentTrackKey()) {
          _trackLoadQueued = true;
          continue;
        }

        _update(() {
          _loadedTrack = parsed.parsed!.measuredFromStartIfOffset(meta.offsetM);
          _loadedTrackKey = key;
          // Новый трек меняет высоты сегментов — план пересчитывается.
          _recomputeMountainPlan();
        }, persist: false);
        return;
      }
    } catch (error) {
      debugPrint('uRunCalc: не удалось прочитать трек: $error');
    } finally {
      _loadingTrack = false;
      if (_trackLoadQueued) {
        _trackLoadQueued = false;
        unawaited(_ensureTrackLoaded());
      }
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
        : SizedBox(
            width: _columns * _PaceViewState._fixedCellWidth,
            child: row,
          );
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
}
