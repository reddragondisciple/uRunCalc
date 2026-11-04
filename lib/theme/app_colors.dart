import 'package:flutter/material.dart';

/// Семантические цвета интерфейса uRunCalc.
///
/// Значения совпадают с прежними литералами, поэтому визуально приложение не
/// меняется: константы лишь дают цветам понятные имена и позволяют менять
/// палитру в одном месте.
abstract final class AppColors {
  /// Основной фон таблиц, клавиатуры и панелей.
  static const Color background = Colors.black;

  /// Фон клавиатуры и приподнятых панелей.
  static const Color surface = Color(0xFF111111);

  /// Фон итоговых клеток.
  static const Color surfaceRaised = Color(0xFF1B1B1B);

  /// Акцент активных кнопок и выделенных элементов.
  static const Color accent = Color(0xFFFF9800);

  /// Зелёный цвет фокуса и базового темпа.
  static const Color focus = Color(0xFF4CAF50);

  /// Оранжевый цвет результата и подписей итогов.
  static const Color result = Color(0xFFFFB74D);

  /// Красный цвет ошибки: план позже лимита, самый быстрый темп.
  static const Color danger = Colors.red;

  /// Жёлтый цвет предупреждения: план близко к лимиту.
  static const Color warning = Colors.yellow;

  /// Янтарный цвет второго по скорости темпа.
  static const Color secondary = Colors.amber;
}
