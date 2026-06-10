import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/element.dart';

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  group('Hot Reload Test', () {
    testWidgets('should update component properties after widget update', (
      tester,
    ) async {
      final engine = await GameEngine.create({TickerState.new});
      addTearDown(() => engine.dispose());
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            tag: 'test',
            children: [
              ComponentWidget(
                SpriteRenderer.new.withInitialValues(
                  (c) => c.color = const ui.Color(0xFFFF0000),
                ),
                update: (c) => c.color = const ui.Color(0xFFFF0000),
              ),
            ],
          ),
        ),
      );

      expect(
        (tester.element(find.byType(GameObjectWidget).first) as GameObject)
            .getComponent<SpriteRenderer>()
            .color,
        equals(const ui.Color(0xFFFF0000)),
      );

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            tag: 'test',
            children: [
              ComponentWidget(
                SpriteRenderer.new.withInitialValues(
                  (c) => c.color = const ui.Color(0xFF00FF00),
                ),
                update: (c) => c.color = const ui.Color(0xFF00FF00),
              ),
            ],
          ),
        ),
      );

      final currentColor =
          (tester.element(find.byType(GameObjectWidget).first) as GameObject)
              .getComponent<SpriteRenderer>()
              .color;

      expect(
        currentColor,
        equals(const ui.Color(0xFF00FF00)),
        reason:
            'Component properties should update when widget.components() changes',
      );
    });

    testWidgets('should preserve GameObject position after reassemble', (
      tester,
    ) async {
      final engine = await GameEngine.create({TickerState.new});
      addTearDown(() => engine.dispose());
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            tag: 'test',
            children: [ComponentWidget(ObjectTransform.new)],
          ),
        ),
      );

      final element = tester.element(find.byType(GameObjectWidget).first);
      final transform =
          (element as GameObject).getComponent<ObjectTransform>();
      transform.position = Vector2(50, 60);

      // ignore: invalid_use_of_protected_member
      element.reassemble();

      expect(transform.position.x, closeTo(50.0, 0.0001));
      expect(transform.position.y, closeTo(60.0, 0.0001));
    });

    testWidgets('should preserve state when children are shuffled with keys', (
      tester,
    ) async {
      final engine = await GameEngine.create({TickerState.new});
      addTearDown(() => engine.dispose());
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              GameObjectWidget(
                key: const ValueKey('a'),
                children: [
                  ComponentWidget(
                    SpriteRenderer.new.withInitialValues(
                      (c) => c.color = const ui.Color(0xFFFF0000),
                    ),
                    update: (c) => c.color = const ui.Color(0xFFFF0000),
                  ),
                ],
              ),
              GameObjectWidget(
                key: const ValueKey('b'),
                children: [
                  ComponentWidget(
                    SpriteRenderer.new.withInitialValues(
                      (c) => c.color = const ui.Color(0xFF00FF00),
                    ),
                    update: (c) => c.color = const ui.Color(0xFF00FF00),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final compA =
          (tester.element(find.byKey(const ValueKey('a'))) as GameObjectElement)
              .getComponent<SpriteRenderer>();
      expect(compA.color, equals(const ui.Color(0xFFFF0000)));

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              GameObjectWidget(
                key: const ValueKey('b'),
                children: [
                  ComponentWidget(
                    SpriteRenderer.new.withInitialValues(
                      (c) => c.color = const ui.Color(0xFF00FF00),
                    ),
                    update: (c) => c.color = const ui.Color(0xFF00FF00),
                  ),
                ],
              ),
              GameObjectWidget(
                key: const ValueKey('a'),
                children: [
                  ComponentWidget(
                    SpriteRenderer.new.withInitialValues(
                      (c) => c.color = const ui.Color(0xFFFF0000),
                    ),
                    update: (c) => c.color = const ui.Color(0xFFFF0000),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final compA2 =
          (tester.element(find.byKey(const ValueKey('a'))) as GameObjectElement)
              .getComponent<SpriteRenderer>();
      expect(compA2, same(compA));
      expect(compA2.color, equals(const ui.Color(0xFFFF0000)));
    });

    testWidgets('should preserve state with GlobalKey across tree changes', (
      tester,
    ) async {
      final engine = await GameEngine.create({TickerState.new});
      addTearDown(() => engine.dispose());
      final heroKey = GlobalKey();
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: Column(
            children: [
              GameObjectWidget(
                key: heroKey,
                tag: 'hero',
                children: [
                  ComponentWidget(ObjectTransform.new),
                  ComponentWidget(
                    SpriteRenderer.new.withInitialValues(
                      (c) => c.color = const ui.Color(0xFF0000FF),
                    ),
                    update: (c) => c.color = const ui.Color(0xFF0000FF),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final hero = tester.element(find.byKey(heroKey)) as GameObject;
      hero.getComponent<ObjectTransform>().position = Vector2(123, 456);

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: Column(
            children: [
              // ignore: avoid_unnecessary_containers
              Container(
                child: GameObjectWidget(
                  key: heroKey,
                  tag: 'hero',
                  children: [
                    ComponentWidget(ObjectTransform.new),
                    ComponentWidget(
                      SpriteRenderer.new.withInitialValues(
                        (c) => c.color = const ui.Color(0xFF0000FF),
                      ),
                      update: (c) => c.color = const ui.Color(0xFF0000FF),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      final heroAfter = tester.element(find.byKey(heroKey)) as GameObject;
      expect(heroAfter, same(hero));
      final heroPos = heroAfter.getComponent<ObjectTransform>().position;
      expect(heroPos.x, closeTo(123.0, 0.0001));
      expect(heroPos.y, closeTo(456.0, 0.0001));
    });

    testWidgets(
      'should reset/swap state when children are shuffled WITHOUT keys',
      (tester) async {
        final engine = await GameEngine.create({TickerState.new});
        addTearDown(() => engine.dispose());
        await tester.pumpWidget(
          Game(
            engine: engine,
            child: GameObjectWidget(
              children: [
                GameObjectWidget(
                  children: [
                    ComponentWidget(
                      SpriteRenderer.new.withInitialValues(
                        (c) => c.color = const ui.Color(0xFFFF0000),
                      ),
                      update: (c) => c.color = const ui.Color(0xFFFF0000),
                    ),
                  ],
                ),
                GameObjectWidget(
                  children: [
                    ComponentWidget(
                      SpriteRenderer.new.withInitialValues(
                        (c) => c.color = const ui.Color(0xFF00FF00),
                      ),
                      update: (c) => c.color = const ui.Color(0xFF00FF00),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

        final element0 =
            tester.elementList(find.byType(GameObjectWidget)).elementAt(1)
                as GameObjectElement;
        final comp0 = element0.getComponent<SpriteRenderer>();
        expect(comp0.color, equals(const ui.Color(0xFFFF0000)));

        await tester.pumpWidget(
          Game(
            engine: engine,
            child: GameObjectWidget(
              children: [
                GameObjectWidget(
                  children: [
                    ComponentWidget(
                      SpriteRenderer.new.withInitialValues(
                        (c) => c.color = const ui.Color(0xFF00FF00),
                      ),
                      update: (c) => c.color = const ui.Color(0xFF00FF00),
                    ),
                  ],
                ),
                GameObjectWidget(
                  children: [
                    ComponentWidget(
                      SpriteRenderer.new.withInitialValues(
                        (c) => c.color = const ui.Color(0xFFFF0000),
                      ),
                      update: (c) => c.color = const ui.Color(0xFFFF0000),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

        final element0After =
            tester.elementList(find.byType(GameObjectWidget)).elementAt(1)
                as GameObjectElement;
        final comp0After = element0After.getComponent<SpriteRenderer>();

        expect(element0After, same(element0));
        expect(comp0After, same(comp0));
        expect(comp0After.color, equals(const ui.Color(0xFF00FF00)));
      },
    );
  });
}
