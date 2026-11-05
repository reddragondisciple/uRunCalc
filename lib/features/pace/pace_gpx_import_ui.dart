import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../gpx/checkpoint_matching.dart';
import '../gpx/gpx_import.dart';
import '../gpx/gpx_parser.dart';
import '../gpx/gpx_track.dart';
import '../gpx/parsed_track.dart';
import '../gpx/plan_math.dart';
import '../gpx/track_metrics.dart';

/// Выбранный файл трека: имя и содержимое.
class PickedTrackFile {
  const PickedTrackFile({required this.name, required this.content});

  final String name;
  final String content;
}

/// Выбор файла через системный диалог (`file_selector`).
///
/// Фильтр по расширению `.gpx` на iOS и Android ненадёжен, поэтому разрешаем
/// любой файл: содержимое проверяет парсер и выдаёт понятную ошибку.
class TrackFilePicker {
  TrackFilePicker._();

  /// Возвращает `null`, если пользователь отменил выбор.
  static Future<PickedTrackFile?> pick() async {
    final XFile? file = await openFile(
      confirmButtonText: AppStrings.paceTrackImportTitle,
    );
    if (file == null) return null;
    final content = await file.readAsString();
    return PickedTrackFile(name: file.name, content: content);
  }
}

/// Разбирает GPX и готовит данные для сравнения. Ошибку формата
/// возвращает строкой, которую можно показать пользователю.
({ParsedTrack? parsed, String? error}) parseTrackFile(PickedTrackFile file) {
  try {
    final track = parseGpx(file.content);
    final metrics = computeTrackMetrics(track);
    final candidates = buildCandidates(track, metrics);
    final whole = computeSegments(metrics, [0, metrics.totalDistance2d]).single;
    return (
      parsed: ParsedTrack(
        track: track,
        metrics: metrics,
        candidates: candidates,
        totalAscentM: whole.ascentM,
        totalDescentM: whole.descentM,
      ),
      error: null,
    );
  } on GpxFormatException catch (error) {
    return (parsed: null, error: error.message);
  } on FileSystemException {
    return (parsed: null, error: AppStrings.paceTrackReadError);
  }
}

/// Выбор режима импорта: только финиш или финиш с чекпойнтами.
Future<GpxImportMode?> showImportModeDialog(BuildContext context) {
  return showDialog<GpxImportMode>(
    context: context,
    builder: (dialogContext) {
      return SimpleDialog(
        title: const Text(AppStrings.paceTrackImportModeTitle),
        children: [
          SimpleDialogOption(
            key: const ValueKey('gpx-mode-finish'),
            onPressed: () =>
                Navigator.pop(dialogContext, GpxImportMode.finishOnly),
            child: const Text(AppStrings.paceTrackImportFinishOnly),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(AppStrings.paceTrackImportFinishOnlyHint),
          ),
          SimpleDialogOption(
            key: const ValueKey('gpx-mode-checkpoints'),
            onPressed: () =>
                Navigator.pop(dialogContext, GpxImportMode.checkpoints),
            child: const Text(AppStrings.paceTrackImportCheckpoints),
          ),
        ],
      );
    },
  );
}

/// Подтверждение замены трека в занятом слоте.
Future<bool> confirmTrackOverwrite(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text(AppStrings.paceTrackImportOverwriteTitle),
        content: const Text(AppStrings.paceTrackImportOverwriteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(AppStrings.paceTrackImportReplace),
          ),
        ],
      );
    },
  );
  return result == true;
}

/// Подтверждение разблокировки таблицы перед импортом.
Future<bool> confirmUnlockForImport(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        content: const Text(AppStrings.paceTrackImportNeedsUnlock),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(AppStrings.paceTrackImportUnlockAction),
          ),
        ],
      );
    },
  );
  return result == true;
}

/// Сравнительная таблица: колонка, сейчас, по треку, Δ и флажок.
///
/// Возвращает выбор колонок, которые применить, или `null` при отмене.
Future<List<ColumnChoice>?> showCheckpointCompareDialog(
  BuildContext context, {
  required List<String> labels,
  required List<double> currentKm,
  required List<ColumnSuggestion> suggestions,
}) {
  final checked = [for (final s in suggestions) s.checked];
  return showDialog<List<ColumnChoice>>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text(AppStrings.paceTrackCompareTitle),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < suggestions.length; i++)
                      _CompareRow(
                        label: labels[i],
                        currentKm: currentKm[i],
                        suggestion: suggestions[i],
                        checked: checked[i],
                        onChanged: suggestions[i].pass == null
                            ? null
                            : (value) => setState(() => checked[i] = value),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(AppStrings.cancel),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext, [
                    for (var i = 0; i < suggestions.length; i++)
                      ColumnChoice(
                        column: i,
                        pass: checked[i] ? suggestions[i] : null,
                      ),
                  ]);
                },
                child: const Text(AppStrings.paceTrackCompareApply),
              ),
            ],
          );
        },
      );
    },
  );
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.label,
    required this.currentKm,
    required this.suggestion,
    required this.checked,
    required this.onChanged,
  });

  final String label;
  final double currentKm;
  final ColumnSuggestion suggestion;
  final bool checked;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final pass = suggestion.pass;
    final trackKm = pass == null ? null : pass.distanceM / 1000;
    final delta = trackKm == null ? null : trackKm - currentKm;
    final subtitle = trackKm == null
        ? AppStrings.paceTrackCompareNoMatch
        : '${suggestion.candidate?.rawName ?? ''}: '
              '${trackKm.toStringAsFixed(2)} км'
              '  Δ ${delta! >= 0 ? '+' : ''}${delta.toStringAsFixed(2)}';
    return CheckboxListTile(
      key: ValueKey('gpx-compare-$label'),
      dense: true,
      value: checked && pass != null,
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
      title: Text('$label  ${currentKm.toStringAsFixed(2)} км'),
      subtitle: Text(subtitle),
    );
  }
}

/// Что считать стартом, если начало трека далеко от точки Start.
enum TrackStartChoice { nearestPoint, trackAsIs }

/// Вопрос о старте трека, если расстояние Start → начало трека больше 200 м.
Future<TrackStartChoice?> askTrackStart(BuildContext context) {
  return showDialog<TrackStartChoice>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text(AppStrings.paceTrackStartPromptTitle),
        content: const Text(AppStrings.paceTrackStartPromptBody),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, TrackStartChoice.trackAsIs),
            child: const Text(AppStrings.paceTrackStartAsIs),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, TrackStartChoice.nearestPoint),
            child: const Text(AppStrings.paceTrackStartAtPoint),
          ),
        ],
      );
    },
  );
}

/// Текст ошибки применения импорта для пользователя.
String importErrorText(GpxImportError error) {
  switch (error) {
    case GpxImportError.finishBeforeLastCheckpoint:
      return AppStrings.paceTrackImportFinishBeforeLast;
    case GpxImportError.nonMonotonicDistances:
      return AppStrings.paceTrackImportNonMonotonic;
  }
}

/// Результат диалога «плоские / с поправкой».
class PlanInputChoice {
  const PlanInputChoice({required this.mode, required this.stopsMin});

  final PlanInputMode mode;

  /// Суммарные стоянки, минуты (0 — без стоянок).
  final int stopsMin;
}

/// Диалог ввода итога (§7.3): переключатель, стоянки и предпросмотр.
/// [previewFor] строит текст предпросмотра по выбранному режиму и стоянкам.
Future<PlanInputChoice?> showPlanInputDialog(
  BuildContext context, {
  required String Function(PlanInputMode mode, int stopsMin) previewFor,
}) {
  return showDialog<PlanInputChoice>(
    context: context,
    builder: (dialogContext) {
      return _PlanInputDialog(previewFor: previewFor);
    },
  );
}

class _PlanInputDialog extends StatefulWidget {
  const _PlanInputDialog({required this.previewFor});

  final String Function(PlanInputMode mode, int stopsMin) previewFor;

  @override
  State<_PlanInputDialog> createState() => _PlanInputDialogState();
}

class _PlanInputDialogState extends State<_PlanInputDialog> {
  PlanInputMode _mode = PlanInputMode.withAdjustment;
  final _stopsController = TextEditingController(text: '0');

  @override
  void dispose() {
    _stopsController.dispose();
    super.dispose();
  }

  int get _stopsMin => int.tryParse(_stopsController.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.paceInputModeTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<PlanInputMode>(
            key: const ValueKey('plan-input-mode'),
            segments: const [
              ButtonSegment(
                value: PlanInputMode.flatData,
                label: Text(AppStrings.paceInputModeFlat),
              ),
              ButtonSegment(
                value: PlanInputMode.withAdjustment,
                label: Text(AppStrings.paceInputModeAdjusted),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) =>
                setState(() => _mode = selection.first),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('plan-input-stops'),
            controller: _stopsController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: AppStrings.paceInputStopsLabel,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text(
            widget.previewFor(_mode, _stopsMin),
            key: const ValueKey('plan-input-preview'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(AppStrings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            PlanInputChoice(mode: _mode, stopsMin: _stopsMin),
          ),
          child: const Text(AppStrings.paceRecalcAction),
        ),
      ],
    );
  }
}
