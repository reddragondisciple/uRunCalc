import 'package:flutter/foundation.dart';

/// Состояние кнопки с шестерёнкой рядом с печатью в строке режимов Pace.
///
/// Сам экран Pace владеет настройками, а кнопка живёт в строке режимов.
/// Контроллер передаёт доступность и действие открытия опций.
class PaceOptionsController extends ChangeNotifier {
  bool _available = false;
  Future<void> Function()? _onOpen;

  /// Можно ли открыть опции Pace.
  bool get available => _available;

  /// Обновляет состояние после кадра, чтобы не уведомлять слушателей во
  /// время построения дерева.
  void update({required bool available, Future<void> Function()? onOpen}) {
    if (_available == available && _onOpen == onOpen) return;
    _available = available;
    _onOpen = onOpen;
    notifyListeners();
  }

  /// Прячет кнопку: открыт другой режим.
  void clear() {
    if (!_available && _onOpen == null) return;
    _available = false;
    _onOpen = null;
    notifyListeners();
  }

  /// Открывает диалог опций, если он доступен.
  Future<void> open() async {
    await _onOpen?.call();
  }
}
