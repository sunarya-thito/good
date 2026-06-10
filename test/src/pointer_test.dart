import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

class MockPointerReceiver extends Component with PointerReceiver {
  int downCount = 0;
  int upCount = 0;
  Offset? lastPosition;

  @override
  void onPointerDown(PointerDownEvent event) {
    downCount++;
    lastPosition = event.localPosition;
  }

  @override
  void onPointerUp(PointerUpEvent event) {
    upCount++;
  }
}

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  group('Pointer', () {
    testWidgets('should dispatch events to PointerReceiver when hit', (
      tester,
    ) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      final receiver = MockPointerReceiver();
      final collider = BoxCollider()
        ..size = Vector2(100, 100)
        ..offset = Vector2(50, 50);

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: Center(
            child: GameObjectWidget(
              children: [
                ComponentWidget(
                  ScreenTransform.new,
                  update: (c) => c.constraints = const BoxConstraints.tightFor(
                    width: 100,
                    height: 100,
                  ),
                ),
                ComponentWidget(() => receiver),
                ComponentWidget(() => collider),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final widgetCenter = tester.getCenter(find.byType(GameObjectWidget));

      await tester.tapAt(widgetCenter);
      await tester.pump();

      expect(receiver.downCount, equals(1));
      expect(receiver.upCount, equals(1));
    });

    testWidgets('should NOT dispatch events when NOT hit', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      final receiver = MockPointerReceiver();
      final collider = BoxCollider()
        ..size = Vector2(50, 50)
        ..offset = Vector2(25, 25);

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: Center(
            child: GameObjectWidget(
              children: [
                ComponentWidget(
                  ScreenTransform.new,
                  update: (c) => c.constraints = const BoxConstraints.tightFor(
                    width: 100,
                    height: 100,
                  ),
                ),
                ComponentWidget(() => receiver),
                ComponentWidget(() => collider),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final widgetTopLeft = tester.getTopLeft(find.byType(GameObjectWidget));
      await tester.tapAt(widgetTopLeft + const Offset(75, 75));
      await tester.pump();

      expect(receiver.downCount, equals(0));
    });

    testWidgets('should handle move and hover events', (tester) async {
      final engine = await GameEngine.create({TickerSystem.new});
      addTearDown(() => engine.dispose());
      final receiver = MockPointerReceiver();
      final collider = BoxCollider()
        ..size = Vector2(100, 100)
        ..offset = Vector2(50, 50);

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: Center(
            child: GameObjectWidget(
              children: [
                ComponentWidget(
                  ScreenTransform.new,
                  update: (c) => c.constraints = const BoxConstraints.tightFor(
                    width: 100,
                    height: 100,
                  ),
                ),
                ComponentWidget(() => receiver),
                ComponentWidget(() => collider),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final center = tester.getCenter(find.byType(GameObjectWidget));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: center);
      await tester.pump();

      await gesture.moveTo(center + const Offset(10, 10));
      await tester.pump();
    });
  });
}
