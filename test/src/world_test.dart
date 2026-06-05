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

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  group('RenderWorld', () {
    testWidgets(
      'should render children with camera transform when camera is ready',
      (tester) async {
        final game = GameEngine();

        await tester.pumpWidget(
          Game(
            game: game, // Corrected from engine
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
      },
    );

    testWidgets(
      'should fall back to default rendering when camera is NOT ready',
      (tester) async {
        await tester.pumpWidget(Game(child: SizedBox(width: 100, height: 100)));
        await tester.pump();

        final renderWorld = tester.allRenderObjects
            .whereType<RenderWorld>()
            .firstOrNull;
        expect(renderWorld, isNotNull);
        expect(renderWorld!.game.cameras.isReady, isFalse);
      },
    );

    testWidgets(
      'should correctly transform hit test positions from screen to world space',
      (tester) async {
        bool hit = false;
        await tester.pumpWidget(
          Game(
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
      },
    );
  });
}
