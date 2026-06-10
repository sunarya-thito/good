import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

Future<GameEngine> _createInputEngine() => GameEngine.create({
  TickerSystem.new,
  InputSystem.new,
  CameraSystem.new,
  ScreenSystem.new,
});

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  group('Keyboard', () {
    testWidgets('should detect key presses', (tester) async {
      final engine = await _createInputEngine();
      await tester.pumpWidget(
        Game(engine: engine, child: const GameObjectWidget()),
      );
      await tester.pump();
      final game =
          (tester.element(find.byType(GameObjectWidget)) as GameObject).game;

      await simulateKeyDownEvent(LogicalKeyboardKey.space);
      game.input.update();

      expect(Keyboard.space.isPressed(game), isTrue);

      await simulateKeyUpEvent(LogicalKeyboardKey.space);
      game.input.update();

      expect(Keyboard.space.isPressed(game), isFalse);
      await engine.dispose();
    });

    testWidgets('should track frame-relative state', (tester) async {
      final engine = await _createInputEngine();
      await tester.pumpWidget(
        Game(engine: engine, child: const GameObjectWidget()),
      );
      await tester.pump();
      final game =
          (tester.element(find.byType(GameObjectWidget)) as GameObject).game;

      // Frame 1: Press
      game.ticker.update(0.016);
      await simulateKeyDownEvent(LogicalKeyboardKey.keyA);
      game.input.update();

      expect(Keyboard.keyA.wasPressedThisFrame(game), isTrue);
      expect(Keyboard.keyA.isPressed(game), isTrue);

      // Frame 2: Hold
      game.ticker.update(0.016);
      game.input.update();

      expect(Keyboard.keyA.wasPressedThisFrame(game), isFalse);
      expect(Keyboard.keyA.isPressed(game), isTrue);

      // Frame 3: Release
      game.ticker.update(0.016);
      await simulateKeyUpEvent(LogicalKeyboardKey.keyA);
      game.input.update();

      expect(Keyboard.keyA.wasReleasedThisFrame(game), isTrue);
      expect(Keyboard.keyA.isPressed(game), isFalse);
      await engine.dispose();
    });

    testWidgets('should support multiple game instances with independent state', (
      tester,
    ) async {
      final game1 = await _createInputEngine();
      final game2 = await _createInputEngine();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: Game(engine: game1, child: const GameObjectWidget()),
              ),
              SizedBox(
                width: 100,
                height: 100,
                child: Game(engine: game2, child: const GameObjectWidget()),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      // Press Space
      await simulateKeyDownEvent(LogicalKeyboardKey.space);

      // Update both
      game1.input.update();
      game2.input.update();

      expect(Keyboard.space.isPressed(game1), isTrue);
      expect(Keyboard.space.isPressed(game2), isTrue);

      // Advance frame for game1
      game1.ticker.update(0.016);
      game1.input.update();

      // game1 should see wasPressedThisFrame = false (it was pressed in previous update)
      expect(Keyboard.space.wasPressedThisFrame(game1), isFalse);
      // game2 still in its first frame (where space was pressed)
      expect(Keyboard.space.wasPressedThisFrame(game2), isTrue);

      await game1.dispose();
      await game2.dispose();
    });

    group('InputControl', () {
      testWidgets('should report correctly', (tester) async {
        final engine = await _createInputEngine();
        await tester.pumpWidget(
          Game(engine: engine, child: const GameObjectWidget()),
        );
        await tester.pump();
        final game =
            (tester.element(find.byType(GameObjectWidget)) as GameObject).game;

        final btn = ButtonControl(game);
        expect(btn.isPressed, isFalse);
        expect(btn.wasPressedThisFrame, isFalse);
        expect(btn.wasReleasedThisFrame, isFalse);

        btn.press();
        expect(btn.isPressed, isTrue);
        expect(btn.wasPressedThisFrame, isTrue);
        expect(btn.wasReleasedThisFrame, isFalse);

        game.ticker.update(0.016);
        expect(btn.isPressed, isTrue);
        expect(btn.wasPressedThisFrame, isFalse);
        expect(btn.wasReleasedThisFrame, isFalse);

        btn.release();
        expect(btn.isPressed, isFalse);
        expect(btn.wasPressedThisFrame, isFalse);
        expect(btn.wasReleasedThisFrame, isTrue);

        await engine.dispose();
      });
    });
  });
}
