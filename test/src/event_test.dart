import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

mixin TestListener on Component implements EventListener {
  int eventCount = 0;
  void onTestEvent();
}

class TestEvent extends Event<TestListener> {
  const TestEvent();
  @override
  void dispatch(TestListener listener) => listener.onTestEvent();
}

class TestComponent extends Component with TestListener {
  @override
  void onTestEvent() => eventCount++;
}

class TestComponent2 extends TestComponent {}

class TestBehavior extends Behavior with TestListener {
  @override
  void onTestEvent() => eventCount++;
}

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  group('Event', () {
    testWidgets('should dispatch event to component', (tester) async {
      final engine = await GameEngine.create({TickerState.new});
      addTearDown(() => engine.dispose());
      final comp = TestComponent();
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [ComponentWidget(() => comp)],
          ),
        ),
      );
      await tester.pump();
      final gameObject =
          tester.element(find.byType(GameObjectWidget)) as GameObject;

      gameObject.broadcastEvent(const TestEvent());
      expect(comp.eventCount, equals(1));
    });

    testWidgets('should dispatch event to multiple components', (tester) async {
      final engine = await GameEngine.create({TickerState.new});
      addTearDown(() => engine.dispose());
      final comp1 = TestComponent();
      final comp2 = TestComponent2();
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => comp1),
              ComponentWidget(() => comp2),
            ],
          ),
        ),
      );
      await tester.pump();
      final gameObject =
          tester.element(find.byType(GameObjectWidget)) as GameObject;

      gameObject.broadcastEvent(const TestEvent());
      expect(comp1.eventCount, equals(1));
      expect(comp2.eventCount, equals(1));
    });

    testWidgets('should respect Behavior.enabled', (tester) async {
      final engine = await GameEngine.create({TickerState.new});
      addTearDown(() => engine.dispose());
      final behavior = TestBehavior()..enabled = false;
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [ComponentWidget(() => behavior)],
          ),
        ),
      );
      await tester.pump();
      final gameObject =
          tester.element(find.byType(GameObjectWidget)) as GameObject;

      gameObject.broadcastEvent(const TestEvent());
      expect(behavior.eventCount, equals(0));

      behavior.enabled = true;
      gameObject.broadcastEvent(const TestEvent());
      expect(behavior.eventCount, equals(1));
    });

    testWidgets('should broadcast to children', (tester) async {
      final engine = await GameEngine.create({TickerState.new});
      addTearDown(() => engine.dispose());
      final parentComp = TestComponent();
      final childComp = TestComponent();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => parentComp),
              GameObjectWidget(
                children: [ComponentWidget(() => childComp)],
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      final parentObject =
          tester.element(find.byType(GameObjectWidget).first) as GameObject;

      parentObject.broadcastEvent(const TestEvent());
      expect(parentComp.eventCount, equals(1));
      expect(childComp.eventCount, equals(1));
    });

    testWidgets('should only send to children with sendEvent', (tester) async {
      final engine = await GameEngine.create({TickerState.new});
      addTearDown(() => engine.dispose());
      final parentComp = TestComponent();
      final childComp = TestComponent();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => parentComp),
              GameObjectWidget(
                children: [ComponentWidget(() => childComp)],
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      final parentObject =
          tester.element(find.byType(GameObjectWidget).first) as GameObject;

      parentObject.sendEvent(const TestEvent());
      expect(parentComp.eventCount, equals(0));
      expect(childComp.eventCount, equals(1));
    });
  });
}
