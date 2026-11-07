part of 'calculator_page.dart';

extension _CalculatorInputPart on _CalculatorPageState {
  static bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  static bool _isOperator(String char) {
    return char == '+' ||
        char == '-' ||
        char == '*' ||
        char == '/' ||
        char == '^';
  }

  bool get _endsWithOperand {
    if (_expression.isEmpty) return false;

    final last = _expression[_expression.length - 1];
    return _isDigit(last) ||
        last == '.' ||
        last == ')' ||
        last == '%' ||
        last == ';' ||
        last == 'π' ||
        last == 'e' ||
        last == '!';
  }

  bool get _needsMultiplicationAfterValue {
    if (_expression.isEmpty) return false;

    final last = _expression[_expression.length - 1];
    return last == ')' ||
        last == '%' ||
        last == ';' ||
        last == 'π' ||
        last == 'e' ||
        last == '!';
  }

  String _encodeRational(Rational value) {
    return '@${value.numerator}:${value.denominator};';
  }

  void _haptic() {
    if (kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  void _flash(String key) {
    _flashTimer?.cancel();

    _rebuild(() {
      _redKeys
        ..clear()
        ..add(key);
    });

    _flashTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;

      _rebuild(() {
        _redKeys.clear();
      });
    });
  }

  void _press(String key) {
    _haptic();

    if (key == 'C') {
      _rebuild(() {
        _expression = '';
        _message = null;
        _exactResult = null;
        _justEvaluated = false;
        _resultApproximate = false;
        _resultShowsFraction = false;
      });
      return;
    }

    if (key == '⌫') {
      _rebuild(() {
        _message = null;

        if (_justEvaluated) {
          _expression = '';
          _exactResult = null;
          _justEvaluated = false;
          _resultApproximate = false;
          _resultShowsFraction = false;
          return;
        }

        if (_expression.endsWith('sqrt(')) {
          // Корень удаляется одним нажатием, не оставляя "sqrt".
          _expression = _expression.substring(
            0,
            _expression.length - 'sqrt('.length,
          );
        } else if (_expression.endsWith(';')) {
          // Внутренний маркер точного результата удаляется целиком.
          final markerStart = _expression.lastIndexOf('@');
          if (markerStart >= 0) {
            _expression = _expression.substring(0, markerStart);
          } else if (_expression.isNotEmpty) {
            _expression = _expression.substring(0, _expression.length - 1);
          }
        } else if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
        }
      });
      return;
    }

    if (key == '=') {
      _calculate();
      return;
    }

    if (_justEvaluated) {
      final startsNewExpression =
          _isDigit(key) || key == '.' || key == '(' || key == '√';

      _rebuild(() {
        if (startsNewExpression) {
          _expression = '';
        } else if (_exactResult != null) {
          // Не теряем точность результата при продолжении вычисления.
          _expression = _encodeRational(_exactResult!);
        }

        _justEvaluated = false;
        _exactResult = null;
        _resultApproximate = false;
        _resultShowsFraction = false;
      });
    }

    final accepted = switch (key) {
      '0' ||
      '1' ||
      '2' ||
      '3' ||
      '4' ||
      '5' ||
      '6' ||
      '7' ||
      '8' ||
      '9' => _insertDigit(key),
      '.' => _insertDecimalPoint(),
      '+' || '-' || '×' || '÷' || '^' => _insertOperator(key),
      '(' => _insertOpenParenthesis(),
      ')' => _insertCloseParenthesis(),
      '%' => _insertPercent(),
      '√' => _insertSquareRoot(),
      '000' => _insertTripleZeros(),
      'sin' || 'cos' || 'tan' || 'ln' || 'log' => _insertFunction(key),
      'π' || 'e' => _insertConstant(key),
      'x²' => _insertSquare(),
      '1/x' => _insertReciprocal(),
      'n!' => _insertFactorial(),
      'angle' => _toggleAngle(),
      'Ans' => _insertAnswer(),
      _ => false,
    };

    if (!accepted) {
      _flash(key);
    }
  }

  bool _insertDigit(String digit) {
    var addition = digit;

    if (_needsMultiplicationAfterValue) {
      addition = '*$digit';
    }

    _rebuild(() {
      _expression += addition;
      _message = null;
    });

    return true;
  }

  bool _insertDecimalPoint() {
    if (_needsMultiplicationAfterValue) {
      return false;
    }

    var index = _expression.length - 1;

    while (index >= 0 &&
        (_isDigit(_expression[index]) || _expression[index] == '.')) {
      if (_expression[index] == '.') return false;
      index--;
    }

    _rebuild(() {
      if (_expression.isEmpty ||
          _isOperator(_expression[_expression.length - 1]) ||
          _expression.endsWith('(')) {
        _expression += '0.';
      } else {
        _expression += '.';
      }
      _message = null;
    });

    return true;
  }

  bool _insertOperator(String key) {
    final operator = switch (key) {
      '×' => '*',
      '÷' => '/',
      _ => key,
    };

    if (_expression.isEmpty) {
      if (operator != '-') return false;
    } else {
      final last = _expression[_expression.length - 1];

      // Унарный минус разрешён в начале, после оператора и после "(",
      // но только один: 1+-2 можно, 1+--2 — нет.
      if (operator == '-' && (_isOperator(last) || last == '(')) {
        if (last == '-') return false;

        _rebuild(() {
          _expression += '-';
          _message = null;
        });
        return true;
      }

      if (!_endsWithOperand) return false;
    }

    _rebuild(() {
      if (operator == '^') {
        // Дробь в основании степени показываем в скобках: (1/2)^2.
        _expression = _parenthesizeTrailingFraction(_expression);
      }
      _expression += operator;
      _message = null;
    });

    return true;
  }

  String _parenthesizeTrailingFraction(String expression) {
    final start = _lastAdditiveTermStart(expression);
    final term = expression.substring(start);

    if (!_isFractionTerm(term)) return expression;

    return '${expression.substring(0, start)}($term)';
  }

  int _lastAdditiveTermStart(String expression) {
    var depth = 0;

    for (var index = expression.length - 1; index >= 0; index--) {
      final char = expression[index];

      if (char == ')') {
        depth++;
      } else if (char == '(') {
        depth--;
      } else if (depth == 0 && (char == '+' || char == '-')) {
        final previous = index == 0 ? null : expression[index - 1];
        final unary =
            previous == null || _isOperator(previous) || previous == '(';

        if (!unary) return index + 1;
      }
    }

    return 0;
  }

  bool _isFractionTerm(String term) {
    if (term.isEmpty) return false;

    if (term.startsWith('@') && term.endsWith(';')) {
      try {
        return !ExpressionParser(term).parse().isInteger;
      } on FormatException {
        return true;
      }
    }

    var depth = 0;

    for (var index = 0; index < term.length; index++) {
      final char = term[index];

      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
      } else if (depth == 0 && char == '/') {
        return true;
      }
    }

    return false;
  }

  bool _insertOpenParenthesis() {
    _rebuild(() {
      if (_endsWithOperand) {
        _expression += '*';
      }
      _expression += '(';
      _message = null;
    });

    return true;
  }

  bool _insertCloseParenthesis() {
    if (!_endsWithOperand) return false;

    var openCount = 0;
    var closeCount = 0;

    for (final char in _expression.split('')) {
      if (char == '(') openCount++;
      if (char == ')') closeCount++;
    }

    if (closeCount >= openCount) return false;

    _rebuild(() {
      _expression += ')';
      _message = null;
    });

    return true;
  }

  bool _insertPercent() {
    if (!_endsWithOperand || _expression.endsWith('%')) {
      return false;
    }

    _rebuild(() {
      _expression += '%';
      _message = null;
    });

    return true;
  }

  bool _insertSquareRoot() {
    _rebuild(() {
      if (_endsWithOperand) {
        _expression += '*';
      }
      _expression += 'sqrt(';
      _message = null;
    });

    return true;
  }

  bool _insertTripleZeros() {
    if (!_endsWithOperand) return false;

    _rebuild(() {
      if (_needsMultiplicationAfterValue) {
        _expression += '*1000';
      } else {
        _expression += '000';
      }
      _message = null;
    });

    return true;
  }

  bool _insertFunction(String name) {
    _rebuild(() {
      if (_endsWithOperand) {
        _expression += '*';
      }
      _expression += '$name(';
      _message = null;
    });

    return true;
  }

  bool _insertConstant(String symbol) {
    _rebuild(() {
      if (_endsWithOperand) {
        _expression += '*';
      }
      _expression += symbol;
      _message = null;
    });

    return true;
  }

  bool _insertSquare() {
    if (!_endsWithOperand) return false;

    _rebuild(() {
      _expression = _parenthesizeTrailingFraction(_expression);
      _expression += '^2';
      _message = null;
    });

    return true;
  }

  bool _insertFactorial() {
    if (!_endsWithOperand || _expression.endsWith('!')) return false;

    _rebuild(() {
      _expression += '!';
      _message = null;
    });

    return true;
  }

  bool _insertReciprocal() {
    if (!_endsWithOperand) {
      _rebuild(() {
        if (_expression.isNotEmpty &&
            !_isOperator(_expression[_expression.length - 1]) &&
            !_expression.endsWith('(')) {
          _expression += '*';
        }
        _expression += '1/(';
        _message = null;
      });

      return true;
    }

    final start = _lastAdditiveTermStart(_expression);
    final term = _expression.substring(start);
    final wrapped = term.startsWith('(') && term.endsWith(')')
        ? term
        : '($term)';

    _rebuild(() {
      _expression = '${_expression.substring(0, start)}1/$wrapped';
      _message = null;
    });

    return true;
  }

  bool _insertAnswer() {
    if (_history.isEmpty) return false;

    _rebuild(() {
      if (_endsWithOperand) {
        _expression += '*';
      }
      _expression += _encodeRational(_history.last.value);
      _message = null;
    });

    return true;
  }

  bool _toggleAngle() {
    _rebuild(() {
      _angleInDegrees = !_angleInDegrees;
      _message = null;
    });

    return true;
  }

  void _calculate() {
    if (_expression.isEmpty) {
      _rebuild(() {
        _message = AppStrings.simpleEnterExpression;
      });
      return;
    }

    if (_justEvaluated) return;

    try {
      final result = ExpressionParser(
        _expression,
        degrees: _angleInDegrees,
      ).parseResult();
      final value = result.value;
      final showsFraction = !result.approximate && value.isDisplayableFraction;
      final entry = _HistoryEntry(
        expression: _expression,
        value: value,
        approximate: result.approximate,
        text: historyText(_expression, value, result.approximate),
      );

      _rebuild(() {
        _history.add(entry);

        // Храним последние восемь вычислений.
        if (_history.length > 8) {
          _history.removeAt(0);
        }

        _expression = _encodeRational(value);
        _exactResult = value;
        _justEvaluated = true;
        _resultApproximate = result.approximate;
        _resultShowsFraction = showsFraction;
        _message = null;
      });
    } on FormatException catch (error) {
      _rebuild(() {
        _message = error.message.toString();
      });
    } catch (_) {
      _rebuild(() {
        _message = AppStrings.simpleEvaluationFailed;
      });
    }
  }

  void _clearHistory() {
    if (_history.isEmpty) return;

    _rebuild(() {
      _history.clear();
    });

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(AppStrings.simpleHistoryCleared),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _reuseHistory(_HistoryEntry entry) {
    // После результата поле визуально занято, но нового ввода ещё нет:
    // в этом случае подставляем выражение из истории. Если пользователь
    // уже что-то набрал, не затираем ввод, а дописываем итоговое значение.
    final replaceExpression = _expression.isEmpty || _justEvaluated;

    _rebuild(() {
      if (replaceExpression) {
        _expression = entry.expression;
      } else {
        if (_endsWithOperand) {
          _expression += '*';
        }
        _expression += _encodeRational(entry.value);
      }

      _message = null;
      _exactResult = null;
      _justEvaluated = false;
      _resultApproximate = false;
      _resultShowsFraction = false;
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_mode == CalculatorMode.pace ||
        _mode == CalculatorMode.ultra ||
        _mode == CalculatorMode.time ||
        _mode == CalculatorMode.info) {
      return KeyEventResult.ignored;
    }

    final logicalKey = event.logicalKey;
    if (logicalKey == LogicalKeyboardKey.enter ||
        logicalKey == LogicalKeyboardKey.numpadEnter) {
      _press('=');
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.backspace ||
        logicalKey == LogicalKeyboardKey.delete) {
      _press('⌫');
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.escape) {
      _press('C');
      return KeyEventResult.handled;
    }

    final character = event.character ?? logicalKey.keyLabel;
    if (character.length != 1) return KeyEventResult.ignored;

    final key = switch (character) {
      '0' ||
      '1' ||
      '2' ||
      '3' ||
      '4' ||
      '5' ||
      '6' ||
      '7' ||
      '8' ||
      '9' => character,
      '+' => '+',
      '-' => '-',
      '*' || 'x' || 'X' => '×',
      '/' => '÷',
      '^' => '^',
      '%' => '%',
      '(' => '(',
      ')' => ')',
      '.' || ',' => '.',
      '=' => '=',
      'r' || 'R' => '√',
      'c' || 'C' => 'C',
      _ => null,
    };

    if (key == null) return KeyEventResult.ignored;

    _press(key);
    return KeyEventResult.handled;
  }
}
