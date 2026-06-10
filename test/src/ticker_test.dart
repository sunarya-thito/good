import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

class MockTickable extends Component with Tickable {
  int updateCount = 0;
  double lastDt = 0;

  @override
  void onUpdate(double dt) {
    updateCount++;
    lastDt = dt;
  }
}

class MockFixedTickable extends Component with FixedTickable {
  int fixedUpdateCount = 0;
  double lastDt = 0;

  @override
  Future<void> onFixedUpdate(double dt) async {
    fixedUpdateCount++;
    lastDt = dt;
  }
}

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  group('GameLoop', () {
    testWidgets('should increment frameCount and update deltaTime', (
      tester,
    ) async {
      final engine = await GameEngine.create({TickerState.new});
      addTearDown(() => engine.dispose());
      final tickable = MockTickable();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(children: [ComponentWidget(() => tickable)]),
        ),
      );

      final game =
          (tester.element(find.byType(GameObjectWidget)) as GameObject).game;
      final initialFrameCount = game.ticker.frameCount;

      await tester.pump(const Duration(milliseconds: 16));

      expect(game.ticker.frameCount, equals(initialFrameCount + 1));
      expect(game.ticker.deltaTime, closeTo(0.016, 0.001));
      expect(tickable.updateCount, equals(1));
      expect(tickable.lastDt, equals(game.ticker.deltaTime));
    });

    testWidgets('should run multiple FixedUpdate ticks when delta is large', (
      tester,
    ) async {
      final engine = await GameEngine.create({TickerState.new});
      addTearDown(() => engine.dispose());
      final fixedTickable = MockFixedTickable();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [ComponentWidget(() => fixedTickable)],
          ),
        ),
      );
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 61));

      expect(fixedTickable.fixedUpdateCount, equals(3));
      expect(fixedTickable.lastDt, equals(0.02));
    });

    testWidgets('should respect custom fixedDeltaTime', (tester) async {
      final engine = await GameEngine.create({TickerState.new});
      addTearDown(() => engine.dispose());
      final fixedTickable = MockFixedTickable();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [ComponentWidget(() => fixedTickable)],
          ),
        ),
      );
      await tester.pump();

      final game =
          (tester.element(find.byType(GameObjectWidget)) as GameObject).game;
      game.ticker.fixedDeltaTime = 0.01;

      await tester.pump(const Duration(milliseconds: 25));

      expect(fixedTickable.fixedUpdateCount, equals(2));

      await tester.pump(const Duration(milliseconds: 10));
      expect(fixedTickable.fixedUpdateCount, equals(3));
    });

    testWidgets('should maintain accumulator between frames', (tester) async {
      final engine = await GameEngine.create({TickerState.new});
      addTearDown(() => engine.dispose());
      final fixedTickable = MockFixedTickable();

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [ComponentWidget(() => fixedTickable)],
          ),
        ),
      );
      await tester.pump();

      final game =
          (tester.element(find.byType(GameObjectWidget)) as GameObject).game;
      game.ticker.fixedDeltaTime = 0.02;

      await tester.pump(const Duration(milliseconds: 15));
      expect(fixedTickable.fixedUpdateCount, equals(0));

      await tester.pump(const Duration(milliseconds: 15));
      expect(fixedTickable.fixedUpdateCount, equals(1));

      await tester.pump(const Duration(milliseconds: 15));
      expect(fixedTickable.fixedUpdateCount, equals(2));
    });
  });
}
