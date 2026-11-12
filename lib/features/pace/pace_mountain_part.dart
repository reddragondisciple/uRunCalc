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

  /// Разбор файла в фоновом изоляте. На нативных платформах показываем
  /// модальный индикатор: большие треки разбираются заметное время.
  Future<TrackParseResult> _parseTrackWithProgress(
    PickedTrackFile picked,
  ) async {
    if (kIsWeb) return parseTrackFileAsync(picked);

    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Expanded(child: Text(AppStrings.paceTrackParsing)),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      return await parseTrackFileAsync(picked);
    } catch (error) {
      debugPrint('uRunCalc: не удалось разобрать трек: $error');
      return const TrackParseResult(error: AppStrings.paceTrackReadError);
    } finally {
      if (mounted) navigator.pop();
    }
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
      _clearDerivedTrackCache();
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

    final parsed = await _parseTrackWithProgress(picked);
    if (!mounted) return;
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

    // Импорт уже разобрал файл: сразу кладём результат в кэш и показываем
    // его, чтобы не читать и не разбирать тот же GPX второй раз.
    final cacheKey = _currentTrackKey();
    final slotPrefix = '$key/$slot/';
    _parsedTrackCache.removeWhere(
      (cachedKey, _) => cachedKey.startsWith(slotPrefix),
    );
    _parsedTrackCache[cacheKey] = track;
    _trimTrackCache();
    _update(() {
      _loadedTrack = track;
      _loadedTrackKey = cacheKey;
      _clearDerivedTrackCache();
      _recomputeMountainPlan();
    }, persist: false);
    _refreshEnvironmentIfEnabled();
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

  /// Ключ текущего трека: дистанция, слот и метаданные файла. Импорт меняет
  /// `importedAtMs`, поэтому старый загруженный трек не считается актуальным.
  String _currentTrackKey() {
    final meta = _tracks.activeTrack;
    return '${trackDistanceKey(_controller.selectedEvent, _controller.selectedDistance)}'
        '/${_tracks.active}/${meta?.relativePath ?? ''}'
        '/${meta?.importedAtMs ?? 0}';
  }

  /// Сбрасывает производные от трека значения при смене/удалении трека.
  void _clearDerivedTrackCache() {
    _cachedElevation = null;
    _cachedElevationTrack = null;
    _cachedElevationColumns = -1;
    _cachedPlanSegments = null;
    _cachedPlanTrack = null;
    _cachedPlanEnvironment = null;
    _cachedPlanColumns = -1;
    _cachedProfile = null;
    _cachedProfileTrack = null;
    // Окружение привязано к треку: после его смены старые множители
    // недействительны и будут пересчитаны заново.
    _environmentData = null;
    _environmentLoading = false;
    _environmentRequest++;
  }

  void _trimTrackCache() {
    while (_parsedTrackCache.length > _PaceViewState._parsedTrackCacheLimit) {
      _parsedTrackCache.remove(_parsedTrackCache.keys.first);
    }
  }

  void _touchTrackCache(String key, ParsedTrack parsed) {
    _parsedTrackCache.remove(key);
    _parsedTrackCache[key] = parsed;
  }

  /// D+/D− по сегментам текущей таблицы. `null`, если трека нет или он не
  /// загружен; тогда ряд показывает прочерк.
  ///
  /// Результат кэшируется: за один кадр геттер вызывается для ряда, итогов и
  /// полосы профиля, а полный проход по точкам трека не бесплатный.
  ElevationSegments? get _elevationSegments {
    final parsed = _loadedTrack;
    if (parsed == null) return null;
    if (identical(parsed, _cachedElevationTrack) &&
        _cachedElevationColumns == _columns &&
        listEquals(_cachedElevationDistances, _tableDistances)) {
      return _cachedElevation;
    }
    final value = elevationForColumns(
      parsed: parsed,
      columnDistancesKm: [
        for (final value in _tableDistances) parseDecimal(value) ?? 0,
      ],
    );
    _cachedElevationTrack = parsed;
    _cachedElevationColumns = _columns;
    _cachedElevationDistances = List<String>.of(_tableDistances);
    _cachedElevation = value;
    return value;
  }

  /// Есть ли по текущему треку высоты, которыми можно поделиться в таблице.
  bool get _hasElevationData => _loadedTrack?.track.hasElevation ?? false;

  /// Профиль для карты строится один раз на трек: открытие окна и встроенная
  /// полоса используют один и тот же список точек.
  List<ProfilePoint> _elevationProfile() {
    final parsed = _loadedTrack;
    if (parsed == null) return const [];
    if (identical(parsed, _cachedProfileTrack) && _cachedProfile != null) {
      return _cachedProfile!;
    }
    final profile = buildElevationProfile(parsed, maxPoints: 1000);
    _cachedProfileTrack = parsed;
    _cachedProfile = profile;
    return profile;
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

        // Возврат на уже разобранную дистанцию/слот: файл не читаем.
        final cached = _parsedTrackCache[key];
        if (cached != null) {
          _touchTrackCache(key, cached);
          _update(() {
            _loadedTrack = cached;
            _loadedTrackKey = key;
            _clearDerivedTrackCache();
            _recomputeMountainPlan();
          }, persist: false);
          _refreshEnvironmentIfEnabled();
          return;
        }

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
            _clearDerivedTrackCache();
          }, persist: false);
          _refreshEnvironmentIfEnabled();
          return;
        }

        // Кандидаты ПП нужны только диалогу импорта — при загрузке таблицы
        // не тратим на них время.
        final parsed = await parseTrackFileAsync(
          PickedTrackFile(name: meta.originalName, content: content),
          withCandidates: false,
        );
        if (!mounted) return;
        if (key != _currentTrackKey()) {
          _trackLoadQueued = true;
          continue;
        }
        if (parsed.parsed == null) {
          // Битый файл: ведём себя как с отсутствующим.
          _update(() {
            _loadedTrack = null;
            _loadedTrackKey = key;
            _clearDerivedTrackCache();
          }, persist: false);
          _refreshEnvironmentIfEnabled();
          return;
        }

        final loaded = parsed.parsed!.measuredFromStartIfOffset(meta.offsetM);
        _parsedTrackCache[key] = loaded;
        _trimTrackCache();
        _update(() {
          _loadedTrack = loaded;
          _loadedTrackKey = key;
          _clearDerivedTrackCache();
          // Новый трек меняет высоты сегментов — план пересчитывается.
          _recomputeMountainPlan();
        }, persist: false);
        _refreshEnvironmentIfEnabled();
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
  ///
  /// Во встроенной полосе подпись «Старт» не нужна: она конкурирует с
  /// подписями высот. В полном окне карты подпись остаётся.
  ElevationMarker? _elevationMarker(
    int index,
    double? km, {
    bool includeStartLabel = true,
  }) {
    if (km == null) return null;
    final note = index < _notes.length ? _notes[index].trim() : '';
    return ElevationMarker(
      km: km,
      label: index == 0
          ? (includeStartLabel ? AppStrings.paceTrackStartLabel : '')
          : (note.isEmpty ? 'CP$index' : note),
    );
  }

  /// Данные для карты по текущему треку и дистанциям.
  ElevationChartData _elevationChartData({bool includeStartLabel = true}) {
    final elevation = _elevationSegments;
    final kms = <double?>[for (final v in _tableDistances) parseDecimal(v)];
    return ElevationChartData(
      profile: _elevationProfile(),
      markers: [
        for (var i = 0; i < kms.length; i++)
          ?_elevationMarker(i, kms[i], includeStartLabel: includeStartLabel),
      ],
      totalAscentM: elevation?.totalAscentM ?? 0,
      totalDescentM: elevation?.totalDescentM ?? 0,
      boundariesKm: [for (final km in kms) ?km],
      environment: _environmentData,
    );
  }

  /// Открывает окно карты. [focusColumn] — колонка ПП, по которой тапнули:
  /// окно сразу показывает сегмент `focusColumn−1 → focusColumn`.
  void _openElevationChart({int? focusColumn}) {
    double? fromKm;
    double? toKm;
    if (focusColumn != null && focusColumn > 0 && focusColumn < _columns) {
      final a = parseDecimal(_tableDistances[focusColumn - 1]);
      final b = parseDecimal(_tableDistances[focusColumn]);
      if (a != null && b != null && b > a) {
        fromKm = a;
        toKm = b;
      }
    }
    unawaited(
      showElevationChart(
        context,
        _elevationChartData(),
        initialFromKm: fromKm,
        initialToKm: toKm,
      ),
    );
  }

  /// Раскрывает/сворачивает встроенную полосу профиля. Без трека с высотами
  /// полоса не раскрывается: в окне останется «нет данных».
  void _toggleElevationRow() {
    if (!_hasElevationData) return;
    _hideKeyboard();
    unawaited(HapticFeedback.selectionClick());
    _update(() => _elevationRowOpen = !_elevationRowOpen, persist: false);
  }

  /// Левая половина видимой области таблицы. При горизонтальной прокрутке
  /// половина считается от экрана, а не от полной ширины всех колонок.
  bool _isLeftHalfOfVisibleTable(Offset globalPosition) {
    final box =
        _tableViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    return box.globalToLocal(globalPosition).dx < box.size.width / 2;
  }

  /// Клетка ряда высот: тап слева раскрывает полосу, тап справа открывает
  /// окно с фокусом на сегменте. Долгое нажатие всегда открывает окно.
  Widget _elevationTapArea({required int column, required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        if (_isLeftHalfOfVisibleTable(details.globalPosition)) {
          _toggleElevationRow();
        } else {
          _openElevationChart(focusColumn: column);
        }
      },
      onLongPress: () => _openElevationChart(focusColumn: column),
      child: child,
    );
  }

  /// Встроенная полоса профиля под рядом высот. Тап открывает полное окно.
  ///
  /// [width] ограничивает полосу колонками таблицы в ландшафте, чтобы она не
  /// заезжала на колонку `Total`.
  Widget _elevationStripRow({required double height, double? width}) {
    final data = _elevationChartData(includeStartLabel: false);
    final hasProfile = data.profile.isNotEmpty;
    final strip = SizedBox(
      height: height,
      width: width ?? double.infinity,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openElevationChart(),
        child: Container(
          key: const ValueKey('pace-elevation-chart-inline'),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            border: Border.all(color: Colors.grey.shade800),
          ),
          child: hasProfile
              ? CustomPaint(
                  size: Size.infinite,
                  painter: ElevationProfilePainter(
                    profile: data.profile,
                    fromKm: data.profile.first.km,
                    toKm: data.profile.last.km,
                    markers: data.markers,
                  ),
                )
              : Center(
                  child: Text(
                    AppStrings.elevationChartNoData,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                ),
        ),
      ),
    );
    return width == null
        ? strip
        : Align(alignment: Alignment.centerLeft, child: strip);
  }

  /// Клетки ряда подъём–спуск. Первая клетка служебная: `↑↓`.
  List<Widget> _elevationCells() {
    final elevation = _elevationSegments;
    return List.generate(_columns, (index) {
      if (index == 0) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleElevationRow,
          onLongPress: () => _openElevationChart(),
          child: _interactiveCell(
            key: 'pace-elevation-label',
            text: '↑↓',
            result: true,
            color: Colors.grey,
          ),
        );
      }
      final text = elevation == null
          ? ''
          : formatElevationPair(
              elevation.ascentM[index],
              elevation.descentM[index],
            );
      return _elevationTapArea(
        column: index,
        child: _interactiveCell(
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
        ),
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
          // Служебная клетка раскрытия: итоговый ряд не делится 50/50,
          // иначе «набор» и «сброс» перестали бы читаться.
          SizedBox(
            width: _PaceViewState._elevationToggleWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: _interactiveCell(
                key: 'pace-elevation-toggle',
                text: '↕',
                result: true,
                fontSize: 14,
                color: Colors.grey,
                onTap: _toggleElevationRow,
                onLongPress: () => _openElevationChart(),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: _interactiveCell(
                key: 'pace-elevation-total-up',
                text: AppStrings.paceTotalAscentLine(ascent),
                result: true,
                fontSize: 14,
                onTap: () => _openElevationChart(),
                onLongPress: () => _openElevationChart(),
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
                onTap: () => _openElevationChart(),
                onLongPress: () => _openElevationChart(),
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
      onTap: () => _openElevationChart(),
      onLongPress: () => _openElevationChart(),
    );
  }
}
