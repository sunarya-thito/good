import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

class CompA extends Component {}

class CompB extends Component {}

class CompC extends Component {}

class MyGameState extends GameState<MyGameWidget> {
  @override
  Iterable<Widget> build(BuildContext context) => const [];
}

class MyGameWidget extends StatefulGameWidget {
  const MyGameWidget({super.key});
  @override
  GameState createState() => MyGameState();
}

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  group('Component', () {
    testWidgets('should find components by type', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      final a = CompA();
      final b = CompB();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [ComponentWidget(() => a), ComponentWidget(() => b)],
          ),
        ),
      );
      final gameObject =
          tester.element(find.byType(GameObjectWidget)) as GameObject;

      expect(gameObject.getComponent<CompA>(), equals(a));
      expect(gameObject.getComponent<CompB>(), equals(b));
      expect(gameObject.tryGetComponent<CompC>(), isNull);
      expect(() => gameObject.getComponent<CompC>(), throwsStateError);
    });

    testWidgets(
      'should only keep one component of the same type (last one wins)',
      (tester) async {
        final engine = await GameEngine.create({TickerSystem.new});
        addTearDown(() => engine.dispose());
        final a1 = CompA();
        final a2 = CompA();

        await tester.pumpWidget(
          Game(
            engine: engine,
            child: GameObjectWidget(
              children: [ComponentWidget(() => a1), ComponentWidget(() => a2)],
            ),
          ),
        );
        expect(tester.takeException(), isAssertionError);
      },
    );

    testWidgets('should find components in children', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      final a = CompA();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              GameObjectWidget(
                children: [ComponentWidget(() => a)],
              ),
            ],
          ),
        ),
      );
      final parentObject =
          tester.element(find.byType(GameObjectWidget).first) as GameObject;

      expect(parentObject.getComponentsInChildren<CompA>(), contains(a));
    });

    testWidgets('should find components in parents', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      final a = CompA();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => a),
              const GameObjectWidget(),
            ],
          ),
        ),
      );
      final childObject =
          tester.element(find.byType(GameObjectWidget).last) as GameObject;

      expect(childObject.getComponentInParent<CompA>(), equals(a));
    });

    testWidgets('should access stateObject correctly', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      final comp = CompA();
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: const MyGameWidget(),
        ),
      );
      final gameObject =
          tester.element(find.byType(MyGameWidget)) as GameObject;
      gameObject.addComponent(comp);

      final state = comp.stateObject<MyGameState>();
      expect(state, isA<MyGameState>());
    });

    testWidgets('should allow adding components from within a component', (
      tester,
    ) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      final b = CompB();
      final a = CompA();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [ComponentWidget(() => a)],
          ),
        ),
      );

      a.addComponent(b);
      expect(a.gameObject.getComponent<CompB>(), equals(b));
    });
  });
}
