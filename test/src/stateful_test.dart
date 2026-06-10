import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/element.dart';

class MockStatefulWidget extends StatefulGameWidget {
  final VoidCallback? onInit;
  final VoidCallback? onDispose;
  final List<Widget> children;

  const MockStatefulWidget({
    super.key,
    this.onInit,
    this.onDispose,
    this.children = const [],
  });

  @override
  GameState createState() => _MockState();
}

class _MockState extends GameState<MockStatefulWidget> {
  int buildCount = 0;
  int initCount = 0;
  int disposeCount = 0;

  @override
  void initState() {
    super.initState();
    initCount++;
    widget.onInit?.call();
  }

  @override
  void dispose() {
    disposeCount++;
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Iterable<Widget> build(BuildContext context) {
    buildCount++;
    return widget.children;
  }
}

Future<GameEngine> _createEngine() => GameEngine.create({
      TickerState.new,
      InputSystem.new,
      CameraSystem.new,
      ScreenSystem.new,
    });

void main() {
  testWidgets('StatefulGameWidget lifecycle', (tester) async {
    final engine = await _createEngine();
    int initCalled = 0;
    int disposeCalled = 0;

    await tester.pumpWidget(
      Game(
        engine: engine,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: MockStatefulWidget(
                onInit: () => initCalled++,
                onDispose: () => disposeCalled++,
                children: [const GameObjectWidget(key: ValueKey('child'))],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final element =
        tester.element(find.byType(MockStatefulWidget)) as GameObjectElement;
    final state = element.state as _MockState;

    expect(state.initCount, equals(1));
    expect(initCalled, equals(1));
    expect(state.buildCount, equals(1));
    expect(find.byKey(const ValueKey('child')), findsOneWidget);

    // Update widget
    await tester.pumpWidget(
      Game(
        engine: engine,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: MockStatefulWidget(
                onInit: () => initCalled++,
                onDispose: () => disposeCalled++,
                children: [const GameObjectWidget(key: ValueKey('child2'))],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(state.initCount, equals(1)); // Should not re-init
    expect(state.buildCount, equals(2));
    expect(find.byKey(const ValueKey('child2')), findsOneWidget);

    // Dispose
    await tester.pumpWidget(Game(engine: engine, child: const SizedBox()));
    await tester.pump();
    expect(state.disposeCount, equals(1));
    expect(disposeCalled, equals(1));

    await engine.dispose();
  });

  testWidgets('GameState.setState should trigger rebuild', (tester) async {
    final engine = await _createEngine();

    await tester.pumpWidget(
      Game(
        engine: engine,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: MockStatefulWidget(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final element =
        tester.element(find.byType(MockStatefulWidget)) as GameObjectElement;
    final state = element.state as _MockState;
    expect(state.buildCount, equals(1));

    state.setState(() {});
    await tester.pump();
    expect(state.buildCount, equals(2));

    await engine.dispose();
  });
}
