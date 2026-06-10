import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

void main() {
  group('ScreenTransform', () {
    testWidgets(
      'should render children in screen space even when camera is moved',
      (
        tester,
      ) async {
        final engine = await GameEngine.create({
          TickerSystem.new,
          CameraSystem.new,
        });
        addTearDown(() => engine.dispose());
        bool hit = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Game(
              engine: engine,
              child: GameObjectWidget(
                children: [
                  GameObjectWidget(
                    name: 'CameraObject',
                    tag: 'MainCamera',
                    children: [
                      ComponentWidget(
                        Camera.new,
                        update: (c) => c.orthographicSize = 1000.0,
                      ),
                      ComponentWidget(
                        ObjectTransform.new,
                        update: (c) => c.position = Vector2(5000, 5000),
                      ),
                    ],
                  ),
                  GameObjectWidget(
                    name: 'HUDObject',
                    children: [
                      ComponentWidget(ScreenTransform.new),
                      GameObjectWidget(
                        name: 'Button',
                        children: [
                          ComponentWidget(ObjectTransform.new),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => hit = true,
                            child: const SizedBox(
                              width: 100,
                              height: 100,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tapAt(const Offset(50, 50));
        expect(
          hit,
          isTrue,
          reason:
              'HUD should be hit at screen coordinates regardless of camera position',
        );
      },
    );

    testWidgets('should handle nested ScreenTransforms by applying identity', (
      tester,
    ) async {
      final engine = await GameEngine.create({
        TickerSystem.new,
        CameraSystem.new,
      });
      addTearDown(() => engine.dispose());
      bool hit = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Game(
            engine: engine,
            child: GameObjectWidget(
              children: [
                GameObjectWidget(
                  tag: 'MainCamera',
                  children: [
                    ComponentWidget(
                      Camera.new,
                      update: (c) => c.orthographicSize = 1000.0,
                    ),
                    ComponentWidget(
                      ObjectTransform.new,
                      update: (c) => c.position = Vector2(5000, 5000),
                    ),
                  ],
                ),
                GameObjectWidget(
                  name: 'OuterHUD',
                  children: [
                    ComponentWidget(ScreenTransform.new),
                    GameObjectWidget(
                      name: 'InnerHUD',
                      children: [
                        ComponentWidget(ScreenTransform.new),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => hit = true,
                          child: const SizedBox(width: 100, height: 100),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tapAt(const Offset(50, 50));
      expect(
        hit,
        isTrue,
        reason:
            'Nested ScreenTransform should still be hit at screen coordinates',
      );
    });

    testWidgets('should respect BoxConstraints', (tester) async {
      final engine = await GameEngine.create({
        TickerSystem.new,
        CameraSystem.new,
      });
      addTearDown(() => engine.dispose());
      Size? reportedSize;
      await tester.pumpWidget(
        MaterialApp(
          home: Game(
            engine: engine,
            child: GameObjectWidget(
              name: 'Root',
              children: [
                GameObjectWidget(
                  name: 'HUD',
                  children: [
                    ComponentWidget(
                      ScreenTransform.new,
                      update: (c) =>
                          c.constraints = const BoxConstraints.tightFor(
                            width: 200,
                            height: 100,
                          ),
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        reportedSize = constraints.biggest;
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        reportedSize,
        const Size(200, 100),
        reason:
            'ScreenTransform should enforce its constraints on children when allowed by parent',
      );
    });
  });
}
