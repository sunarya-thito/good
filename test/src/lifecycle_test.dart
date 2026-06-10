import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

class TestLifecycleComponent extends Component with LifecycleListener {
  int mountedCount = 0;
  int unmountedCount = 0;

  @override
  void onMounted() {
    mountedCount++;
  }

  @override
  void onUnmounted() {
    unmountedCount++;
  }
}

Future<GameEngine> _createEngine() => GameEngine.create({
  TickerSystem.new,
  InputSystem.new,
  CameraSystem.new,
  ScreenSystem.new,
});

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  group('Lifecycle', () {
    late GameEngine engine;
    setUp(() async => engine = await _createEngine());
    tearDown(() async => engine.dispose());

    testWidgets('should call onMounted when added to mounted GameObject', (
      tester,
    ) async {
      await tester.pumpWidget(
        Game(engine: engine, child: const GameObjectWidget()),
      );
      await tester.pump();
      final gameObject =
          tester.element(find.byType(GameObjectWidget)) as GameObject;

      final component = TestLifecycleComponent();
      gameObject.addComponent(component);

      expect(component.mountedCount, equals(1));
      expect(component.unmountedCount, equals(0));
    });

    testWidgets(
      'should call onMounted when GameObject is mounted with component',
      (tester) async {
        final component = TestLifecycleComponent();

        await tester.pumpWidget(
          Game(
            engine: engine,
            child: GameObjectWidget(
              children: [ComponentWidget(() => component)],
            ),
          ),
        );
        await tester.pump();

        expect(component.mountedCount, equals(1));
      },
    );

    testWidgets('should call onUnmounted when component is removed', (
      tester,
    ) async {
      final component = TestLifecycleComponent();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [ComponentWidget(() => component)],
          ),
        ),
      );
      await tester.pump();
      final gameObject =
          tester.element(find.byType(GameObjectWidget)) as GameObject;

      gameObject.removeComponent(component);
      expect(component.unmountedCount, equals(1));
    });

    testWidgets('should call onUnmounted when GameObject is unmounted', (
      tester,
    ) async {
      final component = TestLifecycleComponent();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [ComponentWidget(() => component)],
          ),
        ),
      );
      await tester.pump();

      // Unmount the whole scene
      await tester.pumpWidget(Game(engine: engine, child: const SizedBox()));
      await tester.pump();

      expect(component.unmountedCount, equals(1));
    });

    testWidgets('should propagate lifecycle events to children', (
      tester,
    ) async {
      final parentComponent = TestLifecycleComponent();
      final childComponent = TestLifecycleComponent();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => parentComponent),
              GameObjectWidget(
                children: [ComponentWidget(() => childComponent)],
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(parentComponent.mountedCount, equals(1));
      expect(childComponent.mountedCount, equals(1));

      // Unmount parent
      await tester.pumpWidget(Game(engine: engine, child: const SizedBox()));
      await tester.pump();

      expect(parentComponent.unmountedCount, equals(1));
      expect(childComponent.unmountedCount, equals(1));
    });

    testWidgets('should handle add/remove/add sequence correctly', (
      tester,
    ) async {
      final component = TestLifecycleComponent();

      await tester.pumpWidget(
        Game(engine: engine, child: const GameObjectWidget()),
      );
      await tester.pump();
      final gameObject =
          tester.element(find.byType(GameObjectWidget)) as GameObject;

      gameObject.addComponent(component);
      expect(component.mountedCount, equals(1));

      gameObject.removeComponent(component);
      expect(component.unmountedCount, equals(1));

      gameObject.addComponent(component);
      expect(component.mountedCount, equals(2));
    });
  });
}
