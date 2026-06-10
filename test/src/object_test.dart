import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

class MockComponent extends Component with LifecycleListener {
  bool mountedCalled = false;
  bool unmountedCalled = false;

  @override
  void onMounted() {
    mountedCalled = true;
  }

  @override
  void onUnmounted() {
    unmountedCalled = true;
  }
}

class TestEvent extends Event<TestEventListener> {
  bool dispatched = false;
  @override
  void dispatch(TestEventListener listener) {
    dispatched = true;
    listener.onTestEvent();
  }
}

mixin TestEventListener implements EventListener {
  void onTestEvent();
}

class EventComponent extends Component with TestEventListener {
  bool eventReceived = false;
  @override
  void onTestEvent() {
    eventReceived = true;
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

  group('GameObject', () {
    late GameEngine engine;
    setUp(() async => engine = await _createEngine());
    tearDown(() async => engine.dispose());

    testWidgets('should add and remove components correctly', (tester) async {
      final component = MockComponent();
      late GameObject gameObject;

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            key: GlobalKey(),
            children: [ComponentWidget(() => component)],
          ),
        ),
      );
      await tester.pump();

      final element =
          tester.element(find.byType(GameObjectWidget)) as GameElement;
      gameObject = element;

      expect(gameObject.components, contains(component));
      expect(component.mountedCalled, isTrue);

      gameObject.removeComponent(component);
      expect(gameObject.components, isNot(contains(component)));
      expect(component.unmountedCalled, isTrue);
    });

    testWidgets('should broadcast events to components', (tester) async {
      final eventComponent = EventComponent();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [ComponentWidget(() => eventComponent)],
          ),
        ),
      );
      await tester.pump();

      final gameObject =
          tester.element(find.byType(GameObjectWidget)) as GameObject;
      final event = TestEvent();

      gameObject.broadcastEvent(event);

      expect(event.dispatched, isTrue);
      expect(eventComponent.eventReceived, isTrue);
    });

    testWidgets('should broadcast events to children', (tester) async {
      final parentEventComponent = EventComponent();
      final childEventComponent = EventComponent();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => parentEventComponent),
              GameObjectWidget(
                children: [ComponentWidget(() => childEventComponent)],
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      final parentObject =
          tester.element(
                find
                    .byWidgetPredicate(
                      (w) => w is GameObjectWidget && w.name == null,
                    )
                    .first,
              )
              as GameObject;

      parentObject.broadcastEvent(TestEvent());

      expect(parentEventComponent.eventReceived, isTrue);
      expect(childEventComponent.eventReceived, isTrue);
    });

    testWidgets('should retrieve components correctly', (tester) async {
      final component = MockComponent();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(children: [ComponentWidget(() => component)]),
        ),
      );
      await tester.pump();

      final gameObject =
          tester.element(find.byType(GameObjectWidget)) as GameObject;

      expect(gameObject.getComponent<MockComponent>(), equals(component));
      expect(gameObject.tryGetComponent<MockComponent>(), equals(component));
      expect(gameObject.getComponents<MockComponent>(), contains(component));
    });

    testWidgets('should throw error when getComponent fails', (tester) async {
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: const GameObjectWidget(children: []),
        ),
      );
      await tester.pump();

      final gameObject =
          tester.element(find.byType(GameObjectWidget)) as GameObject;

      expect(() => gameObject.getComponent<MockComponent>(), throwsStateError);
    });
  });
}
