import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

class MockRenderable extends Component with Renderable {
  int renderCount = 0;
  Canvas? lastCanvas;

  @override
  void render(Canvas canvas) {
    renderCount++;
    lastCanvas = canvas;
  }
}

class MockRenderable2 extends MockRenderable {}

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  group('Render', () {
    testWidgets('should call render on Renderable components', (tester) async {
      final engine = await GameEngine.create({TickerState.new});
      addTearDown(() => engine.dispose());
      final renderable = MockRenderable();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [ComponentWidget(() => renderable)],
          ),
        ),
      );
      await tester.pump();

      expect(renderable.renderCount, greaterThan(0));
      expect(renderable.lastCanvas, isNotNull);
    });

    testWidgets('should call render on multiple Renderable components', (
      tester,
    ) async {
      final engine = await GameEngine.create({TickerState.new});
      addTearDown(() => engine.dispose());
      final r1 = MockRenderable();
      final r2 = MockRenderable2();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => r1),
              ComponentWidget(() => r2),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(r1.renderCount, greaterThan(0));
      expect(r2.renderCount, greaterThan(0));
    });

    testWidgets('should propagate canvas to children in hierarchy', (
      tester,
    ) async {
      final engine = await GameEngine.create({TickerState.new});
      addTearDown(() => engine.dispose());
      final parentR = MockRenderable();
      final childR = MockRenderable();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [
              ComponentWidget(() => parentR),
              GameObjectWidget(
                children: [ComponentWidget(() => childR)],
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(parentR.renderCount, greaterThan(0));
      expect(childR.renderCount, greaterThan(0));
    });
  });
}
