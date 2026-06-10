import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

class CompA extends Component with LifecycleListener {
  bool mounted = false;
  CompB? foundB;
  int mountCount = 0;

  @override
  void onMounted() {
    mounted = true;
    mountCount++;
    foundB = tryGetComponent<CompB>();
  }

  @override
  void onUnmounted() {
    mounted = false;
  }
}

class CompB extends Component with LifecycleListener {
  bool mounted = false;
  CompA? foundA;
  int mountCount = 0;

  @override
  void onMounted() {
    mounted = true;
    mountCount++;
    foundA = tryGetComponent<CompA>();
  }

  @override
  void onUnmounted() {
    mounted = false;
  }
}

class ConfigurableComp extends Component {
  int value = 0;
}

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  group('ComponentWidget', () {
    testWidgets('should add component when mounted', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      final a = CompA();
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => a),
            ],
          ),
        ),
      );

      final gameObject =
          tester.element(find.byType(GameObjectWidget)) as GameObject;
      expect(gameObject.getComponent<CompA>(), equals(a));
      expect(a.mounted, isTrue);
    });

    testWidgets('should remove component when unmounted', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      final a = CompA();
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => a),
            ],
          ),
        ),
      );

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: const GameObjectWidget(
            children: [],
          ),
        ),
      );

      expect(a.mounted, isFalse);
    });

    testWidgets(
      'components should find each other in onMounted regardless of order',
      (tester) async {
        final engine = await GameEngine.create({TickerSystem.new});
        addTearDown(() => engine.dispose());
        final a = CompA();
        final b = CompB();

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

        expect(
          a.foundB,
          equals(b),
          reason: 'CompA should find CompB even if mounted first',
        );
        expect(b.foundA, equals(a), reason: 'CompB should find CompA');
      },
    );

    testWidgets('should apply parameters and update them', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      int value = 10;
      final comp = ConfigurableComp();

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return Game(
              engine: engine,
              child: GameObjectWidget(
                children: [
                  ComponentWidget(
                    () => comp,
                    update: (c) => c.value = value,
                  ),
                  GestureDetector(
                    onTap: () => setState(() => value = 20),
                    child: const Text(
                      'Button',
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );

      expect(comp.value, equals(10));

      await tester.tap(find.byType(GestureDetector));
      await tester.pump();

      expect(comp.value, equals(20));
    });

    testWidgets(
      'should not recreate component on rebuild if factory returns same instance',
      (tester) async {
        final engine = await GameEngine.create({TickerSystem.new});
        addTearDown(() => engine.dispose());
        final a = CompA();

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return Game(
                engine: engine,
                child: GameObjectWidget(
                  children: [
                    ComponentWidget(() => a),
                    GestureDetector(
                      onTap: () => setState(() {}),
                      child: const Text(
                        'Rebuild',
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );

        expect(a.mountCount, equals(1));

        await tester.tap(find.byType(GestureDetector));
        await tester.pump();

        expect(a.mountCount, equals(1));
      },
    );

    testWidgets('should work in nested GameWidgets', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      final a = CompA();
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            name: 'Parent',
            children: [
              GameObjectWidget(
                name: 'Child',
                children: [
                  ComponentWidget(() => a),
                ],
              ),
            ],
          ),
        ),
      );

      final childObject =
          tester.element(find.byProps((p) => p['name'] == 'Child'))
              as GameObject;
      expect(childObject.getComponent<CompA>(), equals(a));
      expect(a.gameObject.name, equals('Child'));
    });

    testWidgets('should recreate component if key changes', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      final a1 = CompA();
      final a2 = CompA();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => a1, key: const ValueKey('a')),
            ],
          ),
        ),
      );

      expect(a1.mounted, isTrue);

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => a2, key: const ValueKey('b')),
            ],
          ),
        ),
      );

      expect(a1.mounted, isFalse);
      expect(a2.mounted, isTrue);
    });
  });
}

extension on CommonFinders {
  Finder byProps(bool Function(Map<String, dynamic> props) match) {
    return find.byElementPredicate((element) {
      final widget = element.widget;
      if (widget is GameWidget) {
        return match({'name': widget.name, 'layer': widget.layer});
      }
      return false;
    });
  }
}
