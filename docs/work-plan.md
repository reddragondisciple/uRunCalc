# План работ uRunCalc

Документ фиксирует результаты аудита и порядок исправлений. Обновляйте статусы
и чекбоксы по мере выполнения, чтобы следующая сессия начиналась без повторного
анализа.

- Дата аудита: 2026-11-06
- Базовая точка: `master` @ `a3a2690`
- Окружение: Flutter 3.47.7 stable, Dart 3.13.5
- Легенда: `[x]` — сделано и проверено, `[ ]` — не сделано, `[~]` — в работе.

---

## Спринт 1. Зелёный CI и воспроизводимые тесты

**Статус: выполнен.** Цель — любой чистый checkout проходит format + analyze +
test без локальных файлов.

- [x] Прогнать `dart format lib test` (4 файла: `lib/core/app_strings.dart`,
      `lib/features/pace/pace_view.dart`, `test/plan_math_test.dart`,
      `test/widget_test.dart`).
- [x] Скопировать реальные GPX-треки в `test/fixtures/`:
      `GRUT100 - T100.gpx`, `MFU K40.gpx`, `VR100.gpx`, `WBU L120.gpx`.
- [x] Переписать пути в тестах с корня на `test/fixtures/`:
      `test/gpx_parser_test.dart`, `test/gpx_metrics_test.dart`,
      `test/checkpoint_matching_test.dart`, `test/elevation_profile_test.dart`,
      `test/track_start_test.dart`.
- [x] Добавить `/*.gpx` в `.gitignore`: личные треки в корне больше не попадают
      в коммит, фикстуры лежат в `test/fixtures/`.
- [x] Зафиксировать версию Flutter в `.github/workflows/ci.yml`
      (`flutter-version: '3.47.7'`), чтобы `dart format` не «плавал».
- [x] Обновить `docs/gpx-mountain-mode-progress.md`: 347 тестов, фикстуры
      включают реальные треки.

**Проверка спринта:**

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Дополнительно — прогон в чистом checkout:

```bash
git archive HEAD | tar -x -C /tmp/opencode/uruncalc-clean
cd /tmp/opencode/uruncalc-clean && flutter pub get && flutter test
```

---

## Спринт 2. Корректность горного режима и асинхронного слоя

**Статус: выполнен.** Порядок задач важен: T2.1 и T2.2 трогают один и тот же
метод загрузки трека, их делали вместе.

### T2.1. Гонка в `_ensureTrackLoaded`

- Файл: `lib/features/pace/pace_view.dart` (~4124).
- Проблема:
  - `if (_loadingTrack) return;` отбрасывает новый запрос — при переключении
    дистанции/слота во время чтения нужный трек не загрузится;
  - после `await files.read(...)` результат применяется по старому `key` без
    сверки с текущими `selectedEvent/selectedDistance/active`.
- Что сделать:
  1. Хранить «последний запрошенный ключ» (`_pendingTrackKey`) и/или счётчик
     поколения загрузки.
  2. Если загрузка уже идёт — запомнить новый ключ и после завершения текущей
     запустить загрузку актуального.
  3. После каждого `await` сверять ключ с текущим; устаревший результат не
     применять.
  4. В `finally` сбрасывать флаг и запускать отложенный запрос.
- Критерии готовности:
  - переключение дистанции во время медленного чтения заканчивается треком,
    соответствующим текущей дистанции;
  - нет «чужих» высот и повторных вечных загрузок;
  - добавлен тест с фейковым хранилищем и задержкой чтения.

### T2.2. Включение горного режима подгружает трек и пересчитывает план

- Файл: `lib/features/pace/pace_view.dart`, `_setMountainMode` (~199).
- Проблема: метод меняет только флаг. Если состояние восстановлено с выключенным
  горным режимом, но с метаданными трека, после включения ряд высот пуст.
- Что сделать:
  1. При `enabled == true` вызывать `_ensureTrackLoaded()`.
  2. Пересчитывать план: сразу (если трек уже загружен) и после успешной
     загрузки трека.
  3. Пересчёт после загрузки лучше разместить в `_ensureTrackLoaded` — это
     автоматически покроет импорт GPX (T2.4) и смену слота.
- Критерии готовности:
  - сценарий «горный режим выключен → включили» показывает высоты и план;
  - импорт и смена слота тоже обновляют план;
  - тест на восстановление состояния с треком и выключенным режимом.

### T2.3. Ручная правка времени плана не должна затираться

- Файлы: `lib/features/pace/pace_view.dart` (`_appendPlanTime` ~1605,
  удаление символа для `tablePlanTime` ~1939, `_recomputeMountainPlan` ~1677),
  `lib/features/gpx/plan_math.dart` (`manualMovingSec`, ~301).
- Проблема: правка времени плана не вызывает `_markManualAnchor()`, поэтому
  `_finishInput()` → `_recomputeMountainPlan()` перезаписывает её при
  flat/target-якорях. Параметр `manualMovingSec` в проде не передаётся.
- Что сделать:
  1. Вызывать `_markManualAnchor()` при вводе и удалении символа в
     `tablePlanTime` (по аналогии с `_planPaces`).
  2. Явно зафиксировать семантику manual-якоря: ручные значения не
     пересчитываются. Либо задокументировать ранний выход
     `_recomputeMountainPlan`, либо прокинуть `manualMovingSec`, если пересчёт
     всё-таки нужен.
  3. Не ломать `test/plan_anchor_test.dart`.
- Критерии готовности:
  - ввод времени плана → уход фокуса не меняет введённое значение;
  - ручные темп и время ведут себя одинаково;
  - тест на «правка → `_finishInput` → значение сохранилось».

### T2.4. Пересчёт GAP-плана после импорта GPX

- Файл: `lib/features/pace/pace_view.dart`, конец `_importGpxFlow` (~330–343).
- Проблема: импорт применяет дистанции и трек, включает горный режим, но план
  не пересчитывает.
- Что сделать: после успешной загрузки трека вызывать
  `_recomputeMountainPlan()` (см. T2.2 — лучше централизованно в
  `_ensureTrackLoaded`).
- Критерии готовности:
  - после импорта при включённом горном режиме план соответствует новому треку;
  - при ручном якоре план не перезаписывается.

### T2.5. Удаление мероприятия удаляет каталоги треков

- Файлы: `lib/features/pace/pace_state_controller.dart` (`removeEvent` ~110),
  `lib/features/pace/pace_view.dart` (`_removeEvent` ~2269,
  `_deleteRemovedTracks` ~2408).
- Проблема: `removeEvent` не складывает дистанции в `_removedDistances`, а
  `_removeEvent` не вызывает `_deleteRemovedTracks()` — треки остаются на диске.
- Что сделать:
  1. Перед удалением мероприятия собрать все его дистанции и добавить в
     `_removedDistances`.
  2. После `removeEvent` в UI вызвать `await _deleteRemovedTracks()`.
  3. Проверить, что удаление последнего мероприятия по-прежнему запрещено.
- Критерии готовности:
  - после удаления мероприятия его каталоги треков удалены;
  - ошибки файловой системы не блокируют UI;
  - тест на контроллер + тест на очистку хранилища.

### T2.6. Защита от перезаписи раннего ввода при восстановлении состояния

- Файл: `lib/features/pace/pace_view.dart`, `_loadPaceState` (~504).
- Проблема: `await _store.load()` может завершиться после того, как пользователь
  уже начал вводить данные; `_applyState` затрёт ввод.
- Что сделать:
  1. Ввести флаг/счётчик изменений (`_stateDirty` или версия состояния),
     который выставляется в `_update` после старта загрузки.
  2. В `_loadPaceState` перед `_applyState` проверить: если пользователь уже
     что-то менял — не применять восстановленные значения (но выставить
     `stateLoaded = true`).
  3. Не ломать сценарий обычного холодного старта.
- Критерии готовности:
  - ввод до завершения загрузки не теряется;
  - холодный старт по-прежнему восстанавливает состояние;
  - тест с задержанным `PaceStore` и вводом в процессе.

**Результат спринта 2 (2026-11-06):**

- `_ensureTrackLoaded` получил очередь запросов (`_trackLoadQueued`) и сверку
  ключа после каждого `await`; устаревший трек не применяется. Ключ
  отсутствующего/битого файла кэшируется, чтобы не читать его повторно.
- `_setMountainMode(true)` вызывает `_ensureTrackLoaded()` и сразу
  пересчитывает план; успешная загрузка трека пересчитывает план
  централизованно, поэтому импорт GPX и смена слота тоже обновляют план.
- Правка времени плана в колонках `> 0` помечает manual-якорь; правка старта
  плана (колонка 0) намеренно не фиксирует опору, чтобы план пересчитался.
- `removeEvent` собирает дистанции в `_removedDistances`, UI вызывает
  `_deleteRemovedTracks()`.
- `_loadPaceState` не применяет сохранённое состояние, если пользователь уже
  что-то изменил (`_stateTouched`); для теста добавлен
  `debugPaceStateLoaderOverride`.
- Тесты: новый `test/sprint2_mountain_test.dart` (5 сценариев) и 2 теста в
  `test/pace_state_controller_test.dart`. Всего 354 теста, analyze чист.

**Проверка спринта 2:**

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
# точечно:
flutter test test/sprint2_mountain_test.dart test/pace_state_controller_test.dart
```

Ручной сценарий: импорт GPX → смена дистанции → смена слота → включение/
выключение горного режима → правка времени плана → удаление мероприятия.

---

## Спринт 3. Релизная готовность и безопасность данных

**Статус: выполнен (2026-11-07).**

- [x] Android release: собственный keystore (`key.properties` + `signingConfigs`).
      `android/app/build.gradle.kts` читает `android/key.properties`; без него
      release подписывается отладочным ключом с предупреждением в логе.
      Добавлены `android/key.properties.example` и правила `.gitignore`.
- [x] Сменить `applicationId`/namespace с `com.example.calculator_app` на
      `com.reddragondisciple.uruncalc`; `MainActivity` перенесён в пакет
      `com.reddragondisciple.uruncalc`.
- [x] Сменить bundle ID `com.example.*` в iOS/macOS и идентификаторы
      Linux/Windows; метаданные Windows (`Runner.rc`) обновлены.
- [x] Android: `allowBackup="false"` и `fullBackupContent="false"` — треки и
      таблицы не попадают в облачный бэкап.
- [x] Добавить `LICENSE` (проприетарная, all rights reserved).
- [x] «Править высоты вручную»: пункт меню и заглушка `_manualElevationFlow`
      удалены до реализации ручных D+/D−; тест проверяет отсутствие пункта.
- [x] `_initTrackFiles`: ранний выход на web (`kIsWeb`) и `try/catch` вокруг
      `path_provider`; экран работает без хранилища треков.
- [x] Безопасное чтение файла: лимит 50 МБ проверяется по `XFile.length()` до
      чтения, `try/catch` вокруг `openFile`/`readAsString`, понятное сообщение;
      `DirectoryTrackFileStore.read` не читает файл больше лимита.
- [x] Обновить `README`/`docs` под финальные идентификаторы, подпись и лицензию.

**Результат спринта 3 (2026-11-07):**

- Создан локальный ключ `android/key.jks` (alias `uruncalc`, RSA 2048, 10 000
  дней) и `android/key.properties`; оба файла не коммитятся. Пароль выдан
  пользователю в чате — его нужно сохранить вместе с ключом.
- Единый идентификатор `com.reddragondisciple.uruncalc` на всех платформах.
- `flutter build apk --release` — 59.6 МБ, пакет `com.reddragondisciple.uruncalc`,
  подпись `CN=uRunCalc` (проверено `apksigner verify --print-certs`).
- `flutter build web --release` проходит; импорт GPX на web осознанно
  недоступен (нет файловой системы).
- Новый `test/track_file_limits_test.dart` (7 тестов): границы лимита,
  защита `DirectoryTrackFileStore`, текст ошибки выбора файла. Виджет-тест
  меню дополнен проверкой скрытого пункта ручных высот.
- Всего 362 теста, `flutter analyze` чист.

**Проверка:** `flutter build apk --release`, `flutter build web --release`,
ручной импорт большого/битого GPX.

---

## Спринт 4. Качество и поддержка (после релиза)

**Статус: в работе (2026-11-07).**

- [x] Декомпозиция `lib/features/pace/pace_view.dart` (4917 строк) и
      `lib/main.dart` (1235 строк); сократить `part`-связность.

  **Результат (2026-11-07):**
  - `lib/main.dart` — 32 строки: только `main`, `CalculatorApp` и реэкспорт
    debug-хуков. Экран калькулятора вынесен в самостоятельную библиотеку
    `lib/features/calculator/calculator_page.dart` (~1190 строк).
  - `InfoView`, `ExpressionView`, `TimeView`, `PaceView` больше не являются
    `part`-файлами `main.dart` — это отдельные библиотеки со своими импортами.
  - Общие помощники форматирования (`displayText`, `groupDigits`,
    `formatDecimal`, `decimalSymbol`, `historyText`) вынесены в
    `lib/core/value_format.dart`, `expressionTextStyle` — публичный стиль в
    `expression_view.dart`.
  - `lib/features/pace/pace_view.dart` уменьшен с 5055 до ~1090 строк; логика
    разложена по part-файлам библиотеки (расширения на `_PaceViewState`):
    `pace_mountain_part.dart` (~490), `pace_plan_part.dart` (~910),
    `pace_events_part.dart` (~830), `pace_table_part.dart` (~1610).
  - UI вынесен в самостоятельные виджеты без доступа к состоянию экрана:
    `calculator_keypad.dart` (клавиатура), `calculator_display.dart`
    (история/ввод/предпросмотр), `pace_keyboard.dart`, `pace_cells.dart`
    (`PaceInteractiveCell`, `PaceWrappedTextContent`, `waterSpans`).
  - `calculator_page.dart` уменьшен с ~1190 до ~1015 строк.
  - Новый `test/ui_widgets_test.dart` (5 тестов) проверяет новые виджеты
    отдельно от экранов.
  - Поведение не менялось: `flutter analyze` чист, все 367 тестов проходят.

  **Продолжение декомпозиции (2026-11-07):**
  - `pace_view.dart` 1092 → 543 строки: снимок/загрузка/сброс таблицы
    вынесены в `pace_table_state_part.dart` (~185), вычисляемые значения,
    форматирование и подсветки — в `pace_values_part.dart` (~375).
  - `pace_table_part.dart` 1609 → 912: верхний калькулятор Pace —
    `pace_calculator_part.dart` (~267), построение клеток и рядов —
    `pace_table_cells_part.dart` (~436).
  - `pace_plan_part.dart` 913 → 452: ввод с клавиатуры, фокус, прокрутка к
    активной ячейке и буферы — `pace_input_part.dart` (~464).
  - `calculator_page.dart` 1015 → 316: логика выражения и клавиатурных
    событий — `calculator_input_part.dart` (~639, extension с обёрткой
    `_rebuild` над защищённым `setState`); выбор режима — самостоятельные
    `calculator_mode.dart` и `calculator_mode_bar.dart`.
  - Новый виджет-тест `CalculatorModeBar` в `test/ui_widgets_test.dart`.
    Всего 368 тестов, `flutter analyze` чист.
- [ ] Локализация: `flutter_localizations` + `intl`, перевести системные строки
      Material.
- [ ] Поднять покрытие UI: `pace_gpx_import_ui.dart` (29.6%),
      `info_view.dart` (53.3%), `pace_settings_menu.dart` (58.7%).
- [ ] Производительность: парсинг GPX в изолят, кэш профиля высот, ограничение
      размера файла.
- [ ] Обновить `xml` 7.0.1 → 7.1.0 (проверить changelog).

---

## Журнал сессии 2026-11-07

Базовая точка на входе: `master` @ `a3a2690`, 362 теста, analyze чист, но
изменения спринтов 1–3 лежали незакоммиченными.

**Сделано за сессию:**

1. **Коммит `0365230` — спринты 1–3.** Зафиксированы зелёный CI, фикстуры,
   горный режим, release-подпись, `allowBackup=false`, `LICENSE`, лимит 50 МБ.
   Ключи (`android/key.jks`, `key.properties`) и корневые `*.gpx` остались
   вне git.
2. **Коммит `c2f3d12` — декомпозиция.**
   - `main.dart` 1235 → 32 строки; калькулятор → `calculator_page.dart`.
   - `InfoView`, `ExpressionView`, `TimeView`, `PaceView` — самостоятельные
     библиотеки, `part`-связность с `main.dart` убрана.
   - Форматирование → `core/value_format.dart`.
   - `pace_view.dart` 5055 → ~1090 строк; логика в part-файлах
     `pace_mountain_part`, `pace_plan_part`, `pace_events_part`,
     `pace_table_part`.
3. **Коммит `1cfebf3` — UI-виджеты.**
   - `CalculatorKeypad`, `CalculatorDisplay`, `PaceKeyboard`, `PaceInteractiveCell`,
     `PaceWrappedTextContent`, `waterSpans`.
   - `calculator_page.dart` ~1190 → ~1015, `pace_table_part.dart` ~1790 → ~1609.
   - `test/ui_widgets_test.dart` — 5 новых тестов.
4. **Продолжение декомпозиции (без изменения поведения).**
   - `pace_view.dart` 1092 → 543: `pace_table_state_part.dart` (снимок,
     загрузка, сброс, изменение размера таблицы), `pace_values_part.dart`
     (вычисляемые значения, форматирование, подсветки, дни).
   - `pace_table_part.dart` 1609 → 912: `pace_calculator_part.dart` (верхний
     калькулятор Pace), `pace_table_cells_part.dart` (клетки и ряды).
   - `pace_plan_part.dart` 913 → 452: `pace_input_part.dart` (фокус, ввод,
     буферы, прокрутка).
   - `calculator_page.dart` 1015 → 316: `calculator_input_part.dart` (ввод
     выражения), `calculator_mode.dart` + `calculator_mode_bar.dart`.
   - `test/ui_widgets_test.dart` — тест `CalculatorModeBar`.

**Состояние на конец сессии:**

- 368 тестов проходят, `flutter analyze` чист, форматирование чистое;
- изменения декомпозиции закоммичены (`ef41560`), дерево чистое;
- документация: этот файл и `docs/gpx-mountain-mode-progress.md` (368 тестов).

**Что осталось по спринту 4:**

- декомпозиция закрыта: крупнейшие файлы — `pace_table_part.dart` (912) и
  `pace_events_part.dart` (833); дальнейшее дробление — только по мере роста;
- локализация `flutter_localizations` + `intl`;
- покрытие UI-тестами (`pace_gpx_import_ui.dart`, `info_view.dart`,
  `pace_settings_menu.dart`);
- парсинг GPX в изоляте, кэш профиля высот;
- обновление `xml` 7.0.1 → 7.1.0.

---

## Как начать следующую сессию

1. Прочитать этот файл: «Журнал сессии 2026-11-07» и раздел «Спринт 4».
2. Убедиться, что спринты 1–3 и текущие правки зелёные:

   ```bash
   git status
   dart format --output=none --set-exit-if-changed lib test
   flutter analyze && flutter test   # ожидается 368 тестов
   ```

3. Спринты 1–3 закрыты. В спринте 4 декомпозиция закрыта (см. журнал),
   UI-виджеты и part-файлы Pace/Calculator разделены. Следующие пункты:
   локализация, покрытие UI-тестами, изолят для GPX, обновление `xml`.
4. После каждого пункта отмечать `[x]` здесь и в
   `docs/gpx-mountain-mode-progress.md`, если пункт относится к горному режиму;
   результаты сессии дописывать в «Журнал сессии».

## Definition of Done для любого пункта

- Есть тест, воспроизводящий проблему (или объяснение, почему тест невозможен).
- `dart format --set-exit-if-changed lib test` — чисто.
- `flutter analyze` — без замечаний.
- `flutter test` — все тесты проходят.
- Пункт отмечен в этом файле.
