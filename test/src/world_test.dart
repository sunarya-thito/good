import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'package:flutter/widgets.dart';
import 'package:goo2d/src/world.dart';

class _MockPointerReceiver extends Component with PointerReceiver {
  final void Function() onDown;
  _MockPointerReceiver(this.onDown);

  @override
  void onPointerDown(PointerDownEvent event) => onDown();
}

Future<GameEngine> _createBaseEngine() => GameEngine.create({
  TickerSystem.new,
  InputSystem.new,
  CameraSystem.new,
  ScreenSystem.new,
});

Future<GameEngine> _createPhysicsEngine() => GameEngine.create({
  TickerSystem.new,
  InputSystem.new,
  () => PhysicsSystem(forceDirectWorker: true),
  CameraSystem.new,
  ScreenSystem.new,
});

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  group('RenderWorld', () {
    testWidgets(
      'should render children with camera transform when camera is ready',
      (tester) async {
        final game = await _createBaseEngine();

        await tester.pumpWidget(
          Game(
            engine: game,
            child: GameObjectWidget(
              tag: 'MainCamera',
              children: [
                ComponentWidget(Camera.new),
                ComponentWidget(
                  ObjectTransform.new,
                  update: (c) => c.position = Vector2(100, 200),
                ),
              ],
            ),
          ),
        );
        await tester.pump();

        expect(game.cameras.isReady, isTrue);

        final camera = game.cameras.main;
        final pos = camera.gameObject.getComponent<ObjectTransform>().position;
        expect(pos.x, closeTo(100, 0.0001));
        expect(pos.y, closeTo(200, 0.0001));

        await game.dispose();
      },
    );

    testWidgets(
      'should fall back to default rendering when camera is NOT ready',
      (tester) async {
        final engine = await _createBaseEngine();
        await tester.pumpWidget(
          Game(engine: engine, child: SizedBox(width: 100, height: 100)),
        );
        await tester.pump();

        final renderWorld = tester.allRenderObjects
            .whereType<RenderWorldSpace>()
            .firstOrNull;
        expect(renderWorld, isNotNull);
        expect(renderWorld!.game.cameras.isReady, isFalse);

        await engine.dispose();
      },
    );

    testWidgets(
      'should correctly transform hit test positions from screen to world space',
      (tester) async {
        bool hit = false;
        final engine = await _createPhysicsEngine();

        await tester.pumpWidget(
          Game(
            engine: engine,
            child: GameObjectWidget(
              tag: 'MainCamera',
              children: [
                ComponentWidget(
                  Camera.new,
                  update: (c) => c.orthographicSize = 5.0,
                ),
                ComponentWidget(
                  ObjectTransform.new,
                  update: (c) => c.position = Vector2.zero(),
                ),
                ComponentWidget(() => _MockPointerReceiver(() => hit = true)),
                ComponentWidget(Rigidbody.new),
                ComponentWidget(
                  BoxCollider.new,
                  update: (c) => c.size = Vector2(100, 100),
                ),
              ],
            ),
          ),
        );
        await tester.pump();

        await tester.tapAt(const Offset(400, 300));
        expect(hit, isTrue);

        await engine.dispose();
      },
    );
  });
}
