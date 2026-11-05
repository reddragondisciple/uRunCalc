/// Тексты интерфейса uRunCalc.
///
/// Пока приложение одноязычное: здесь собраны русские значения по умолчанию.
/// Это промежуточный шаг перед `flutter_localizations`: экраны постепенно
/// перестают содержать литералы, а язык и тексты не меняются.
class AppStrings {
  AppStrings._();

  // Общие.
  static const String appName = 'uRunCalc';
  static const String cancel = 'Отмена';
  static const String ok = 'ОК';
  static const String reset = 'Сброс';
  static const String add = 'Добавить';
  static const String save = 'Сохранить';
  static const String apply = 'Применить';
  static const String close = 'Закрыть';
  static const String longPressClear = 'Долгое нажатие очищает поле';

  // Simple.
  static const String simpleEnterExpression = 'Введите выражение';
  static const String simpleEvaluationFailed = 'Не удалось вычислить';
  static const String simpleHistoryCleared = 'История очищена';

  // Ошибки вычислений.
  static const String errorDivisionByZero = 'Деление на ноль';
  static const String errorExponentTooLarge = 'Слишком большая степень';
  static const String errorNumberTooLarge = 'Слишком большое число';
  static const String errorNegativeSquareRoot =
      'Корень из отрицательного числа';
  static const String errorInvalidResult = 'Некорректный результат';
  static const String errorResultTooLarge = 'Результат слишком велик';
  static const String errorExtraCharacters = 'Лишние символы';
  static const String errorLogUndefined = 'Логарифм не определён';
  static const String errorTanUndefined = 'Тангенс не определён';
  static const String errorUnknownFunction = 'Неизвестная функция';
  static const String errorFactorialIntegers =
      'Факториал только для целых неотрицательных чисел';
  static const String errorInvalidExactNumber = 'Некорректное точное число';
  static const String errorNumberExpected = 'Ожидалось число';
  static const String errorMissingClosingParen =
      'Не хватает закрывающей скобки';

  // Info.
  static const String infoTagline =
      'Калькулятор темпа для трейловых ультрамарафонов';
  static const String infoAuthor = 'Автор проекта';
  static const String infoCopyHint = 'Нажмите на ссылку, чтобы скопировать её';
  static const String infoLinkCopied = 'Ссылка скопирована';

  // Time.
  static const String timeTabDifference = 'Разница';
  static const String timeTabAddSubtract = 'Сложить/вычесть';
  static const String timeTabConverter = 'Конвертер';

  static const String timeStart = 'Начало';
  static const String timeEnd = 'Конец';
  static const String timeDateTime = 'Дата и время';
  static const String timeDuration = 'Длительность';
  static const String timeResult = 'Результат';
  static const String timeTime = 'Время';

  static const String timeDays = 'дни';
  static const String timeHours = 'часы';
  static const String timeMinutes = 'мин';
  static const String timeSeconds = 'сек';

  static const String timeEnterTime = 'Введите время';
  static const String timeDatePattern = 'дд.мм.гггг';

  static const String timeTotalDays = 'Всего дней';
  static const String timeTotalHours = 'Всего часов';
  static const String timeTotalMinutes = 'Всего минут';
  static const String timeTotalSeconds = 'Всего секунд';

  // Pace и Ultra: верхний блок и клавиатура.
  static const String paceCalcPace = 'Темп';
  static const String paceCalcDistance = 'Расстояние';
  static const String paceCalcTime = 'Время';

  static const String paceRowLimit = 'Лимит';
  static const String paceRowDistance = 'Расстояние, км';
  static const String paceRowSegmentPace = 'Темп сегмента';
  static const String paceRowPlan = 'План';
  static const String paceRowPlanPace = 'Плановый темп';
  static const String paceRowStops = 'Стоянки';
  static const String paceStopsTitle = 't stops';
  static const String paceStopsHint = 'Стоянка, мин';
  static const String paceRowWater = 'Вода';
  static const String paceRowFood = 'Еда';
  static const String paceRowElevation = 'Подъём';

  static const String paceHintMinutes = 'мин';
  static const String paceHintSeconds = 'сек';
  static const String paceHintDay = 'дни';
  static const String paceHintHours = 'часы';
  static const String paceHintKm = 'км';
  static const String paceHintPace = 'мин/км';

  // Pace и Ultra: мероприятия и дистанции.
  static const String paceEventTitle = 'Мероприятие';
  static const String paceEventAdd = '+ Добавить мероприятие';
  static const String paceEventRemove = '− Удалить мероприятие';
  static const String paceEventNew = 'Новое мероприятие';
  static const String paceEventRemoveTitle = 'Удалить мероприятие';
  static const String paceEventExists = 'Такое мероприятие уже есть';
  static const String paceEventCannotRemoveLast =
      'Нельзя удалить последнее мероприятие';

  static const String paceDistanceAdd = '+ Добавить дистанцию';
  static const String paceDistanceRemove = '− Удалить дистанцию';
  static const String paceDistanceNone = 'Нет дистанций';
  static const String paceDistanceExists = 'Такая дистанция уже есть';
  static const String paceDistanceCannotRemoveLast =
      'Нельзя удалить последнюю дистанцию';
  static const String paceDistanceName = 'Название';
  static const String paceDistanceCheckpoints = 'Количество ПП';

  // Pace и Ultra: таблица и итоги.
  static const String paceColumnsTitle = 'Колонки таблицы';
  static const String paceColumnsSemantic = 'Добавить или убрать колонки';
  static const String paceSettingsSemantic = 'Настройки таблицы';
  static const String paceSettingsTitle = 'Настройки таблицы';
  static const String paceSettingsColumns = '+− ПП';
  static const String paceSettingsMountain = 'Горный режим';
  static const String paceSettingsImportGpx = 'Загрузить трек GPX';
  static const String paceSettingsTrackSlot = 'Основной / резервный трек';
  static const String paceSettingsManualElevation = 'Править высоты вручную';

  static const String elevationChartTitle = 'Карта высот';
  static const String elevationChartNoData = 'Нет данных о высоте';
  static const String elevationChartWholeDistance = '← вся дистанция';
  static const String elevationChartClose = 'Закрыть';
  static const String elevationChartHint =
      'Тап по профилю — подсказка, двойной тап или «Сегмент» — фокус на участке';
  static const String elevationChartSegmentFocus = 'Сегмент';
  static const String elevationChartLegend = 'Уклон, окно 100 м';
  static const String elevationChartAltitudeUnit = 'м';

  static String elevationChartAxisKm(String km) => '$km км';

  static String elevationChartPoint({
    required String km,
    required String ele,
    required String grade,
  }) => '$km км · $ele м · $grade';

  static String elevationChartSegment({
    required String ascent,
    required String descent,
  }) => 'Набор $ascent м · сброс $descent м';

  static String elevationChartSummary({
    required String ascent,
    required String descent,
  }) => 'Набор $ascent м, сброс $descent м';

  static String paceElevationSegmentTitle(String from, String to) =>
      'Участок $from – $to';
  static const String paceSettingsStopsModeDeferred =
      'Темп сегмента: с учётом стоянок (отложено)';
  static const String paceSettingsExportTcx = 'Выгрузить план TCX';
  static const String paceSettingsExportTcxHint = 'скоро';
  static const String paceTrackPrimary = 'Основной';
  static const String paceTrackBackup = 'Резервный';
  static const String paceTrackImportTitle = 'Загрузить трек';
  static const String paceTrackImportSlot = 'В какой слот загрузить';
  static const String paceTrackPickCancelled = 'Файл не выбран';
  static const String paceTrackReadError = 'Не удалось прочитать файл';
  static const String paceTrackParseErrorPrefix = 'Трек не загружен: ';
  static const String paceTrackImportModeTitle = 'Что обновить из трека';
  static const String paceTrackImportFinishOnly = 'Только общую дистанцию';
  static const String paceTrackImportCheckpoints =
      'Финиш и чекпойнты (сравнить)';
  static const String paceTrackImportFinishOnlyHint =
      'Меняется только финиш, остальные ПП не трогаем.';
  static const String paceTrackImportOverwriteTitle = 'Заменить трек?';
  static const String paceTrackImportOverwriteBody =
      'В выбранном слоте уже есть трек. Заменить его новым файлом?';
  static const String paceTrackImportReplace = 'Заменить';
  static const String paceTrackImportFinishBeforeLast =
      'Финиш трека раньше последнего ПП. Проверьте трек или таблицу.';
  static const String paceTrackImportNonMonotonic =
      'После импорта расстояния перестали возрастать. Изменения не применены.';
  static const String paceTrackImportApplied = 'Трек загружен';
  static const String paceTrackImportNeedsUnlock =
      'Таблица заблокирована. Разблокировать и загрузить трек?';
  static const String paceTrackImportUnlockAction = 'Разблокировать';
  static const String paceTrackCompareTitle = 'Сравнение с треком';
  static const String paceTrackCompareColumn = 'Колонка';
  static const String paceTrackCompareNow = 'Сейчас, км';
  static const String paceTrackCompareTrack = 'По треку, км';
  static const String paceTrackCompareDelta = 'Δ, км';
  static const String paceTrackCompareApply = 'Применить';
  static const String paceTrackCompareNoMatch = 'нет совпадения';
  static const String paceTrackStartPromptTitle = 'Старт трека';
  static const String paceTrackStartPromptBody =
      'Трек начинается далеко от точки Start. Что считать стартом?';
  static const String paceTrackStartAtPoint = 'Ближайшая точка трека';
  static const String paceTrackStartAsIs = 'Начало трека как есть';
  static const String paceTrackStartLabel = 'Старт';
  static const String paceTrackFinishLabel = 'Финиш';

  static const String paceScaleFit = 'Масштаб: вписать';
  static const String paceScaleActual = 'Масштаб: 1:1';

  static const String paceTotalTime = 'Общее время';
  static const String paceLimitPace = 'Темп в лимит';
  static const String pacePlannedTime = 'Итоговое время';
  static const String pacePlannedPace = 'Итоговый темп';

  static const String paceTotalTimeDescription =
      'Общее время по данным строки «Лимит»: сумма переходов от старта '
      'до последнего заполненного пункта.';
  static const String paceLimitPaceDescription =
      'Итоговый темп всей дистанции по данным строки «Лимит».';
  static const String pacePlannedPaceDescription =
      'Итоговый темп по данным строки «План».';
  static const String pacePlannedTimeDescription =
      'Длительность плана: разница между плановым стартом и плановым '
      'финишем.';

  static const String paceLongPressColumn = 'Долгое нажатие выделяет колонку';
  static const String paceEnterText = 'Введите текст';

  // Pace и Ultra: фиксация и печать.
  static const String paceLockTitle = 'Фиксация';
  static const String paceLockTable = 'Зафиксировать таблицу';
  static const String paceUnlockTable = 'Разблокировать таблицу';
  static const String paceLockLimits = 'Зафиксировать лимиты';
  static const String paceUnlockLimits = 'Разблокировать лимиты';
  static const String paceLockAll = 'Зафиксировать все';
  static const String paceUnlockAll = 'Разблокировать все';
  static const String paceLockPaper = 'Зафиксировать в бумаге';

  static const String pacePrintTitle = 'Печать таблицы';
  static const String pacePrintOrientation = 'Ориентация страницы:';
  static const String pacePrintPortrait = 'Вертикально';
  static const String pacePrintLandscape = 'Горизонтально';
  static const String pacePrintDescription =
      'Печать откроет системный диалог: можно выбрать сетевой '
      'принтер или сохранить документ в PDF.';
  static const String pacePrintAction = 'Печать';

  // Pace и Ultra: плановые расчёты.
  static const String paceEnterPlannedTime = 'Введите итоговое время';
  static const String paceEnterPlannedPace = 'Введите итоговый темп';
  static const String paceFillDistance =
      'Заполните расстояние в ряду «Расстояние, км»';
  static const String paceFillStartTime = 'Заполните время старта';
  static const String paceInputModeTitle = 'Как введён темп?';
  static const String paceInputModeFlat = 'Плоские данные';
  static const String paceInputModeAdjusted = 'Уже с поправкой на высоты';
  static const String paceInputStopsLabel = 'Стоянки, мин';
  static const String paceInputPreviewFlat = 'Плоский';
  static const String paceInputPreviewCalc = 'расчётный';
  static const String paceInputPreviewTotal = 'итог';
  static const String paceInputPreviewStops = 'со стоянками';
  static const String paceInputMinutesShort = 'мин';
  static const String paceInputPreviewUnavailable = 'Предпросмотр недоступен';
  static const String paceRecalcTitle = 'Пересчитать план?';
  static const String paceRecalcAction = 'Пересчитать';

  static const String pacePlanRewriteKeepStart =
      'Плановые данные будут переписаны, кроме времени старта. '
      'Средний темп рассчитается по введённому времени и расстоянию.';
  static const String pacePlanRewriteUseLimit =
      'Плановые данные будут переписаны. Время старта будет взято из '
      'ряда «Лимит». Средний темп рассчитается по введённому времени '
      'и расстоянию.';
  static const String pacePlanRewriteKeepStartPace =
      'Плановые данные будут переписаны, кроме времени старта. '
      'Плановый темп будет заполнен введённым значением.';
  static const String pacePlanRewriteUseLimitPace =
      'Плановые данные будут переписаны. Время старта будет взято из '
      'ряда «Лимит». Плановый темп будет заполнен введённым значением.';

  // Pace и Ultra: статусы и семантика.
  static const String pacePlanBehind = 'Позже плана';
  static const String paceBehindLimit = 'Позже лимита';
  static const String paceCloseToLimit = 'Близко к лимиту';

  static String paceDistanceTitle(String event) => 'Дистанция $event';

  static String paceDistanceRemoveTitle(String event) =>
      'Удалить дистанцию · $event';

  static String paceCheckpoints(int count) => '$count ПП';

  static String paceDistanceOption(String name, int count) =>
      '$name ($count ПП)';

  static String paceCheckpointsRange(int max) =>
      'Количество ПП должно быть от 1 до $max';

  static String paceNoteTitle(String column) => 'Заметка: $column';

  static String paceEventSemantic(String label) => 'Событие: $label';

  static String paceLimitSemantic(String time) => 'Лимит, $time';

  static String pacePlanSemantic(String time) => 'План, $time';

  static String pacePrintFailed(Object error) =>
      'Не удалось подготовить печать: $error';

  static String paceTotalTimeLine(String value) => 'Общее время - $value';

  static String paceTotalAscentLine(String value) => 'Набор - $value';

  static String paceTotalDescentLine(String value) => 'Сброс - $value';

  static String paceLimitPaceLine(String value) => 'Темп в лимит - $value';

  static String pacePlannedPaceLine(String value) =>
      'Итоговый темп - $value';

  static String pacePlannedTimeLine(String value) =>
      'Итоговое время - $value';

  // Подписи клавиш для screen reader.
  static const String keyClearHistory =
      'Очистить. Долгое нажатие — очистить историю';
  static const String keyResetField = 'Сбросить поле';
  static const String keyDelete = 'Удалить';
  static const String keyDoubleZero = 'Два нуля';
  static const String keyTripleZero = 'Три нуля';
  static const String keyDone = 'Готово';
  static const String keyColon = 'Двоеточие';
  static const String keyDot = 'Точка';
  static const String keyFractionSlash = 'Дробная черта';
  static const String keySquareRoot = 'Квадратный корень';
  static const String keyPower = 'Степень';
  static const String keyDivide = 'Разделить';
  static const String keyMultiply = 'Умножить';
  static const String keyPercent = 'Процент';
  static const String keyEquals = 'Равно';
  static const String keyOpenParen = 'Открывающая скобка';
  static const String keyCloseParen = 'Закрывающая скобка';
  static const String keySine = 'Синус';
  static const String keyCosine = 'Косинус';
  static const String keyTangent = 'Тангенс';
  static const String keyNaturalLog = 'Натуральный логарифм';
  static const String keyDecimalLog = 'Десятичный логарифм';
  static const String keyPi = 'Число пи';
  static const String keyExponent = 'Экспонента';
  static const String keySquare = 'Квадрат';
  static const String keyReciprocal = 'Обратное число';
  static const String keyFactorial = 'Факториал';
  static const String keyAngleToggle = 'Переключить градусы и радианы';
  static const String keyPreviousResult = 'Предыдущий результат';

  // PDF-таблица.
  static const String printPlanTitle = 'uRunCalc — таблица плана';
  static const String printTimeLimit = 'Время (лимит)';

  static String printPage(int page, int total) => 'Страница $page из $total';

  static String printLimitSummary(String time, String pace) =>
      'Общее время: $time    Темп в лимит: $pace';

  static String printPlanSummary(String pace, String time) =>
      'Итоговый темп: $pace    Итоговое время: $time';
}
