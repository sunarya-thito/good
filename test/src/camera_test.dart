import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

void main() {
  group('Camera', () {
    testWidgets('should resolve Camera.main by highest depth', (tester) async {
      final engine = await GameEngine.create({
        TickerSystem.new,
        CameraSystem.new,
      });
      addTearDown(() => engine.dispose());
      final cam1 = Camera()..depth = 10;
      final cam2 = Camera()..depth = 20;

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: Column(
            children: [
              Expanded(
                child: GameObjectWidget(
                  children: [
                    ComponentWidget(ObjectTransform.new),
                    ComponentWidget(() => cam1),
                  ],
                ),
              ),
              Expanded(
                child: GameObjectWidget(
                  children: [
                    ComponentWidget(ObjectTransform.new),
                    ComponentWidget(() => cam2),
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

      expect(game.cameras.main, same(cam2));
      expect(game.cameras.allCameras.length, equals(2));

      cam1.depth = 30;
      game.cameras.registerCamera(cam1);
      expect(game.cameras.main, same(cam1));
    });

    testWidgets('should calculate worldToScreenPoint correctly', (
      tester,
    ) async {
      final engine = await GameEngine.create({
        TickerSystem.new,
        CameraSystem.new,
      });
      addTearDown(() => engine.dispose());
      final cam = Camera()..orthographicSize = 5;
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => cam),
              ComponentWidget(ObjectTransform.new),
            ],
          ),
        ),
      );
      await tester.pump();

      final screenPoint = cam.worldToScreenPoint(
        Vector2.zero(),
        const Size(800, 600),
      );
      expect(screenPoint.x, closeTo(400, 0.001));
      expect(screenPoint.y, closeTo(300, 0.001));

      final screenPoint2 = cam.worldToScreenPoint(
        Vector2(5, 5),
        const Size(800, 600),
      );
      expect(screenPoint2.x, closeTo(700, 0.001));
      expect(screenPoint2.y, closeTo(0, 0.001));
    });

    testWidgets('should calculate screenToWorldPoint correctly', (
      tester,
    ) async {
      final engine = await GameEngine.create({
        TickerSystem.new,
        CameraSystem.new,
      });
      addTearDown(() => engine.dispose());
      final cam = Camera()..orthographicSize = 5;
      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => cam),
              ComponentWidget(ObjectTransform.new),
            ],
          ),
        ),
      );
      await tester.pump();

      final worldPoint = cam.screenToWorldPoint(
        Vector2(700, 0),
        const Size(800, 600),
      );
      expect(worldPoint.x, closeTo(5, 0.001));
      expect(worldPoint.y, closeTo(5, 0.001));
    });

    testWidgets('should respect camera transform (camera movement)', (
      tester,
    ) async {
      final engine = await GameEngine.create({
        TickerSystem.new,
        CameraSystem.new,
      });
      addTearDown(() => engine.dispose());
      final cam = Camera()..orthographicSize = 5;
      final camTransform = ObjectTransform()..localPosition = Vector2(10, 0);

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => cam),
              ComponentWidget(() => camTransform),
            ],
          ),
        ),
      );
      await tester.pump();

      final screenPoint = cam.worldToScreenPoint(
        Vector2(10, 0),
        const Size(800, 600),
      );
      expect(screenPoint.x, closeTo(400, 0.001));
      expect(screenPoint.y, closeTo(300, 0.001));
    });
  });
}
