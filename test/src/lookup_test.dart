import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

class ComponentA extends Component {}

class ComponentB extends Component {}

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  group('Lookup Methods', () {
    testWidgets('getComponentInChildren should find component in self', (
      tester,
    ) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      final compA = ComponentA();
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            name: 'Root',
            children: [ComponentWidget(() => compA)],
          ),
        ),
      );
      await tester.pump();
      final root = tester.element(find.byType(GameObjectWidget)) as GameObject;

      expect(root.getComponentInChildren<ComponentA>(), equals(compA));
      expect(root.tryGetComponentInChildren<ComponentA>(), equals(compA));
    });

    testWidgets('getComponentInChildren should find component in children', (
      tester,
    ) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      final compA = ComponentA();
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            name: 'Parent',
            children: [
              GameObjectWidget(
                name: 'Child',
                children: [ComponentWidget(() => compA)],
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      final parent =
          tester.element(
                find.byWidgetPredicate(
                  (w) => w is GameObjectWidget && w.name == 'Parent',
                ),
              )
              as GameObject;

      expect(parent.getComponentInChildren<ComponentA>(), equals(compA));
      expect(parent.tryGetComponentInChildren<ComponentA>(), equals(compA));
    });

    testWidgets('getComponentInParent should include self', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      final compA = ComponentA();
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            name: 'Root',
            children: [ComponentWidget(() => compA)],
          ),
        ),
      );
      await tester.pump();
      final root = tester.element(find.byType(GameObjectWidget)) as GameObject;

      expect(root.getComponentInParent<ComponentA>(), equals(compA));
    });

    testWidgets('getComponentInParent should find in parent', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      final compA = ComponentA();
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            name: 'Parent',
            children: [
              ComponentWidget(() => compA),
              GameObjectWidget(name: 'Child'),
            ],
          ),
        ),
      );
      await tester.pump();
      final child =
          tester.element(
                find.byWidgetPredicate(
                  (w) => w is GameObjectWidget && w.name == 'Child',
                ),
              )
              as GameObject;

      expect(child.getComponentInParent<ComponentA>(), equals(compA));
    });

    testWidgets('getComponentsInParent should find all', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      final compA1 = ComponentA();
      final compA2 = ComponentA();
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            name: 'Parent',
            children: [
              ComponentWidget(() => compA1),
              GameObjectWidget(
                name: 'Child',
                children: [ComponentWidget(() => compA2)],
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      final child =
          tester.element(
                find.byWidgetPredicate(
                  (w) => w is GameObjectWidget && w.name == 'Child',
                ),
              )
              as GameObject;

      final comps = child.getComponentsInParent<ComponentA>().toList();
      expect(comps.length, equals(2));
      expect(comps, containsAll([compA1, compA2]));
    });

    testWidgets('GameObject.find should find by name', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            name: 'Root',
            children: [GameObjectWidget(name: 'Target')],
          ),
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(GameObjectWidget).first);

      final found = GameObject.find(context, 'Target');
      expect(found, isNotNull);
      expect(found!.name, equals('Target'));
    });

    testWidgets('GameObject.find should find by path', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            name: 'A',
            children: [
              GameObjectWidget(
                name: 'B',
                children: [GameObjectWidget(name: 'C')],
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(GameObjectWidget).first);

      final found = GameObject.find(context, 'A/B/C');
      expect(found, isNotNull);
      expect(found!.name, equals('C'));
    });

    testWidgets('GameObject.find should find absolute path', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            name: 'A',
            children: [GameObjectWidget(name: 'B')],
          ),
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(GameObjectWidget).first);

      final found = GameObject.find(context, '/A/B');
      expect(found, isNotNull);
      expect(found!.name, equals('B'));
    });

    testWidgets('findChild should handle path', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            name: 'A',
            children: [
              GameObjectWidget(
                name: 'B',
                children: [GameObjectWidget(name: 'C')],
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      final a =
          tester.element(
                find.byWidgetPredicate(
                  (w) => w is GameObjectWidget && w.name == 'A',
                ),
              )
              as GameObject;

      final found = a.findChild('B/C');
      expect(found, isNotNull);
      expect(found!.name, equals('C'));
    });

    testWidgets('findWithTag should work', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(tag: 'Player', name: 'Hero'),
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(GameObjectWidget).first);

      final found = GameObject.findWithTag(context, 'Player');
      expect(found, isNotNull);
      expect(found!.name, equals('Hero'));
    });
  });
}
