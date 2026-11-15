import 'package:flutter/foundation.dart';

/// Состояние кнопки печати раскладки в верхней панели.
///
/// Сам экран Pace владеет данными раскладки, а кнопка живёт в строке режимов.
/// Контроллер передаёт доступность и действие печати между ними.
class PaceSplitPrintController extends ChangeNotifier {
  bool _available = false;
  Future<void> Function()? _onPrint;

  /// Есть ли готовая раскладка для печати.
  bool get available => _available;

  /// Обновляет состояние. Вызывается после кадра, чтобы не уведомлять
  /// слушателей во время построения дерева.
  void update({required bool available, Future<void> Function()? onPrint}) {
    if (_available == available && _onPrint == onPrint) return;
    _available = available;
    _onPrint = onPrint;
    notifyListeners();
  }

  /// Прячет кнопку: раскладки нет или открыт другой режим.
  void clear() {
    if (!_available && _onPrint == null) return;
    _available = false;
    _onPrint = null;
    notifyListeners();
  }

  /// Открывает диалог печати, если раскладка готова.
  Future<void> print() async {
    await _onPrint?.call();
  }
}
