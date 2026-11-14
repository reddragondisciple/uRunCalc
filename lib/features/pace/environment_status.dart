import 'package:flutter/foundation.dart';

/// Строка состояния окружения, которую экран Pace/Ultra отдаёт верхней
/// панели с кнопкой режима.
///
/// Виджет таблицы не знает, где именно рисуется текст: он только обновляет
/// контроллер. Так статус можно перенести из-под кнопок в свободное место
/// справа от переключателя режимов.
class EnvironmentStatusController extends ChangeNotifier {
  String? _text;
  bool _loading = false;

  String? get text => _text;
  bool get loading => _loading;

  bool get isEmpty => !_loading && (_text == null || _text!.isEmpty);

  void update({String? text, bool loading = false}) {
    if (_text == text && _loading == loading) return;
    _text = text;
    _loading = loading;
    notifyListeners();
  }

  void clear() => update(text: null, loading: false);
}
