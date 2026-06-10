import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

void main() {
  group('CameraView', () {
    testWidgets('should render children through tagged camera', (tester) async {
      final engine = await GameEngine.create({
        TickerSystem.new,
        CameraSystem.new,
      });
      addTearDown(() => engine.dispose());
      const camTag = 'SecondaryCamera';
      final cam = Camera()..backgroundColor = const Color(0xFFFF0000);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Game(
            engine: engine,
            child: Stack(
              children: [
                GameObjectWidget(
                  tag: camTag,
                  children: [
                    ComponentWidget(ObjectTransform.new),
                    ComponentWidget(() => cam),
                  ],
                ),
                const Positioned(
                  bottom: 0,
                  right: 0,
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: CameraView(cameraTag: camTag),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CameraView), findsOneWidget);

      final cameraView = tester.widget<CameraView>(find.byType(CameraView));
      expect(cameraView.cameraTag, equals(camTag));
    });
  });
}
