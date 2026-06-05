import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

class MockScreenReceiver extends Component
    with ScreenCollidable, OuterScreenCollidable {
  int enterCount = 0;
  int exitCount = 0;
  int outerEnterCount = 0;
  int outerExitCount = 0;

  @override
  void onEnterScreen() => enterCount++;
  @override
  void onExitScreen() => exitCount++;
  @override
  void onOuterScreenEnter() => outerEnterCount++;
  @override
  void onOuterScreenExit() => outerExitCount++;
}

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  group('Screen', () {
    testWidgets(
      'should detect onEnterScreen and onExitScreen based on camera view',
      (tester) async {
        final receiver = MockScreenReceiver();
        final collider = BoxCollider()..size = Vector2(2, 2);
        final transform = ObjectTransform()..localPosition = Vector2(100, 0);

        await tester.pumpWidget(
          Game(
            child: Column(
              children: [
                Expanded(
                  child: GameObjectWidget(
                    tag: 'MainCamera',
                    children: [
                      ComponentWidget(Camera.new),
                      ComponentWidget(ObjectTransform.new),
                    ],
                  ),
                ),
                Expanded(
                  child: GameObjectWidget(
                    children: [
                      ComponentWidget(() => receiver),
                      ComponentWidget(() => collider),
                      ComponentWidget(() => transform),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
        await tester.pump();

        final game =
            (tester.element(find.byType(GameObjectWidget).first) as GameObject)
                .game;

        // Initial state: outside
        game.screen.screenSize = const Size(800, 600);
        game.screenPhysics?.update();
        expect(receiver.enterCount, equals(0));

        // Move into center
        transform.localPosition = Vector2.zero();
        game.screen.screenSize = const Size(800, 600);
        game.screenPhysics?.update();
        expect(receiver.enterCount, equals(1));

        // Move out
        transform.localPosition = Vector2(20, 0);
        game.screen.screenSize = const Size(800, 600);
        game.screenPhysics?.update();
        expect(receiver.exitCount, equals(1));
      },
    );

    testWidgets('should detect OuterScreen events when partially exiting', (
      tester,
    ) async {
      final receiver = MockScreenReceiver();
      final collider = BoxCollider()..size = Vector2(4, 4);
      final transform = ObjectTransform()..localPosition = Vector2.all(0);

      await tester.pumpWidget(
        Game(
          child: Column(
            children: [
              Expanded(
                child: GameObjectWidget(
                  tag: 'MainCamera',
                  children: [
                    ComponentWidget(Camera.new),
                    ComponentWidget(ObjectTransform.new),
                  ],
                ),
              ),
              Expanded(
                child: GameObjectWidget(
                  children: [
                    ComponentWidget(() => receiver),
                    ComponentWidget(() => collider),
                    ComponentWidget(() => transform),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      final game =
          (tester.element(find.byType(GameObjectWidget).first) as GameObject)
              .game;

      // Starts fully inside
      game.screen.screenSize = const Size(800, 600);
      game.screenPhysics?.update();
      receiver.outerExitCount = 0;
      expect(receiver.outerEnterCount, equals(0));

      // Move so it's partially outside
      transform.localPosition = Vector2(12, 0);
      game.screen.screenSize = const Size(800, 600);
      game.screenPhysics?.update();
      expect(receiver.outerEnterCount, equals(1));

      // Move back fully inside
      transform.localPosition = Vector2.zero();
      game.screen.screenSize = const Size(800, 600);
      game.screenPhysics?.update();
      expect(receiver.outerExitCount, equals(1));
    });

    testWidgets('should fallback to screen space if no camera is enabled', (
      tester,
    ) async {
      final receiver = MockScreenReceiver();
      final collider = BoxCollider()
        ..size = Vector2(10, 10)
        ..offset = Vector2(5, 5);
      final transform = ObjectTransform()..localPosition = Vector2(-20, -20);

      await tester.pumpWidget(
        Game(
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => receiver),
              ComponentWidget(() => collider),
              ComponentWidget(() => transform),
            ],
          ),
        ),
      );
      await tester.pump();

      final game =
          (tester.element(find.byType(GameObjectWidget).first) as GameObject)
              .game;
      expect(game.physics?.activeColliders.length, equals(1));

      game.screen.screenSize = const Size(800, 600);
      game.screenPhysics?.update();
      expect(receiver.enterCount, equals(0));

      transform.localPosition = Vector2(10, 10);
      game.screen.screenSize = const Size(800, 600);
      game.screenPhysics?.update();
      expect(receiver.enterCount, equals(1));
    });
  });
}
