import 'package:flutter/widgets.dart';

/// `IndexedStack`, который строит вкладку только при первом открытии.
///
/// Состояние уже открытых вкладок сохраняется: после первого построения
/// виджет остаётся в дереве, как у обычного `IndexedStack`. Это экономит
/// время запуска и память, пока пользователь не открыл остальные режимы.
class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  late final Set<int> _built = {widget.index};

  @override
  void didUpdateWidget(covariant LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _built.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: [
        for (var index = 0; index < widget.children.length; index++)
          _built.contains(index)
              ? widget.children[index]
              : const SizedBox.shrink(),
      ],
    );
  }
}
