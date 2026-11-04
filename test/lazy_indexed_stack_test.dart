import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/widgets/lazy_indexed_stack.dart';

void main() {
  testWidgets('builds only the active tab at first', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LazyIndexedStack(
          index: 0,
          children: [Text('first'), Text('second')],
        ),
      ),
    );

    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsNothing);
  });

  testWidgets('keeps a tab alive after it was opened once', (tester) async {
    var index = 0;
    late StateSetter setState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setter) {
            setState = setter;
            return LazyIndexedStack(
              index: index,
              children: const [Text('first'), _Counter()],
            );
          },
        ),
      ),
    );

    expect(find.byType(_Counter), findsNothing);

    setState(() => index = 1);
    await tester.pumpAndSettle();
    expect(find.byType(_Counter), findsOneWidget);
    expect(find.text('count: 0'), findsOneWidget);

    await tester.tap(find.byType(_Counter));
    await tester.pumpAndSettle();
    expect(find.text('count: 1'), findsOneWidget);

    setState(() => index = 0);
    await tester.pumpAndSettle();
    expect(find.byType(_Counter, skipOffstage: false), findsOneWidget);
    expect(find.text('count: 1', skipOffstage: false), findsOneWidget);
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _count++),
      child: Text('count: $_count'),
    );
  }
}
