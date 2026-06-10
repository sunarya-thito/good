import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

class SingleComp extends Component {}

class MultiComp extends Component with MultiComponent {}

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  group('MultiComponent', () {
    testWidgets(
      'should prevent adding multiple components of the same type by default',
      (tester) async {
        final engine = await GameEngine.create({TickerSystem.new});
        addTearDown(() => engine.dispose());
        final a = SingleComp();
        final b = SingleComp();

        await tester.pumpWidget(
          Game(
            engine: engine,
            child: GameObjectWidget(
              children: [
                ComponentWidget(() => a),
                ComponentWidget(() => b),
              ],
            ),
          ),
        );

        expect(tester.takeException(), isAssertionError);
      },
    );

    testWidgets(
      'should allow multiple components of the same type if they implement MultiComponent',
      (tester) async {
        final engine = await GameEngine.create({TickerSystem.new});
        addTearDown(() => engine.dispose());
        final a = MultiComp();
        final b = MultiComp();

        await tester.pumpWidget(
          Game(
            engine: engine,
            child: GameObjectWidget(
              children: [
                ComponentWidget(() => a),
                ComponentWidget(() => b),
              ],
            ),
          ),
        );

        final gameObject =
            tester.element(find.byType(GameObjectWidget)) as GameObject;
        final comps = gameObject.getComponents<MultiComp>();
        expect(comps.length, equals(2));
        expect(comps, containsAll([a, b]));
      },
    );

    testWidgets(
      'imperative addComponent should also enforce MultiComponent rules',
      (tester) async {
        final engine = await GameEngine.create({TickerSystem.new});
        addTearDown(() => engine.dispose());

        await tester.pumpWidget(
          Game(
            engine: engine,
            child: const GameObjectWidget(),
          ),
        );

        final gameObject =
            tester.element(find.byType(GameObjectWidget)) as GameObject;
        gameObject.addComponent(SingleComp());

        expect(
          () => gameObject.addComponent(SingleComp()),
          throwsAssertionError,
        );
      },
    );

    testWidgets(
      'imperative addComponent should allow multiple MultiComponents',
      (tester) async {
        final engine = await GameEngine.create({TickerSystem.new});
        addTearDown(() => engine.dispose());

        await tester.pumpWidget(
          Game(
            engine: engine,
            child: const GameObjectWidget(),
          ),
        );

        final gameObject =
            tester.element(find.byType(GameObjectWidget)) as GameObject;
        final a = MultiComp();
        final b = MultiComp();
        gameObject.addComponent(a);
        gameObject.addComponent(b);

        expect(gameObject.getComponents<MultiComp>(), containsAll([a, b]));
      },
    );
  });
}
