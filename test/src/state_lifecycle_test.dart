import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/element.dart';

class LifecycleTracker {
  int initCount = 0;
  int disposeCount = 0;
  int buildCount = 0;
  int didUpdateCount = 0;
  int didChangeDepsCount = 0;
  int reassembleCount = 0;
}

class TestStatefulWidget extends StatefulGameWidget {
  final LifecycleTracker tracker;
  final Widget? child;
  final int value;

  const TestStatefulWidget({
    super.key,
    required this.tracker,
    this.child,
    this.value = 0,
  });

  @override
  GameState createState() => _TestState();
}

class _TestState extends GameState<TestStatefulWidget> {
  @override
  void initState() {
    super.initState();
    widget.tracker.initCount++;
    expect(mounted, isTrue);
    expect(context, isNotNull);
  }

  @override
  void didUpdateWidget(TestStatefulWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.tracker.didUpdateCount++;
    expect(mounted, isTrue);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.tracker.didChangeDepsCount++;
    expect(mounted, isTrue);
  }

  @override
  void reassemble() {
    super.reassemble();
    widget.tracker.reassembleCount++;
  }

  @override
  void dispose() {
    widget.tracker.disposeCount++;
    // In Flutter, mounted is still true during dispose()
    // but becomes false AFTER super.dispose() or at the end of unmount.
    // In our implementation, we clear it AFTER dispose() in element.dart.
    expect(mounted, isTrue);
    super.dispose();
  }

  @override
  Iterable<Widget> build(BuildContext context) {
    widget.tracker.buildCount++;
    // Register dependency on Directionality
    Directionality.of(context);
    return widget.child != null ? [widget.child!] : const [];
  }
}

Future<GameEngine> _createEngine() => GameEngine.create({
  TickerSystem.new,
  InputSystem.new,
  CameraSystem.new,
  ScreenSystem.new,
});

void main() {
  testWidgets('GameState should follow strict Flutter lifecycle invariants', (
    tester,
  ) async {
    final engine = await _createEngine();
    final tracker = LifecycleTracker();

    // 1. Mount
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Game(
          engine: engine,
          child: TestStatefulWidget(tracker: tracker, value: 1),
        ),
      ),
    );

    final state =
        (tester.element(find.byType(TestStatefulWidget)) as GameObjectElement)
                .state
            as _TestState;

    expect(tracker.initCount, equals(1));
    expect(tracker.didChangeDepsCount, equals(1));
    expect(tracker.buildCount, equals(1));
    expect(state.mounted, isTrue);

    // 2. Update widget
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Game(
          engine: engine,
          child: TestStatefulWidget(tracker: tracker, value: 2),
        ),
      ),
    );

    expect(tracker.initCount, equals(1));
    expect(tracker.didUpdateCount, equals(1));
    expect(tracker.buildCount, equals(2));

    // 3. Reassemble (Hot Reload simulation)
    // ignore: invalid_use_of_protected_member
    tester.element(find.byType(TestStatefulWidget)).reassemble();
    expect(tracker.reassembleCount, equals(1));

    // 4. Unmount
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Game(engine: engine, child: const SizedBox()),
      ),
    );

    expect(tracker.disposeCount, equals(1));
    expect(state.mounted, isFalse);

    // 5. Verify setState fails after dispose
    expect(() => state.setState(() {}), throwsAssertionError);

    await engine.dispose();
  });

  testWidgets(
    'GameState should receive didChangeDependencies when InheritedWidget changes',
    (tester) async {
      final engine = await _createEngine();
      final tracker = LifecycleTracker();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Game(
            engine: engine,
            child: TestStatefulWidget(tracker: tracker),
          ),
        ),
      );

      expect(tracker.didChangeDepsCount, equals(1));

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Game(
            engine: engine,
            child: TestStatefulWidget(tracker: tracker),
          ),
        ),
      );

      expect(tracker.didChangeDepsCount, equals(1));

      // Change Directionality
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: Game(
            engine: engine,
            child: TestStatefulWidget(tracker: tracker),
          ),
        ),
      );

      expect(tracker.didChangeDepsCount, equals(2));

      await engine.dispose();
    },
  );
}
