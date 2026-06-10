import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/ticker.dart';

Future<GameEngine> _createInputEngine() => GameEngine.create({
      TickerState.new,
      InputSystem.new,
      CameraSystem.new,
      ScreenSystem.new,
    });

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();

  group('Input', () {
    testWidgets('InputAction should transition phases for button type',
        (tester) async {
      final engine = await _createInputEngine();
      final action = InputAction()
        ..name = 'test'
        ..type = InputActionType.button;

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [ComponentWidget(() => action)],
          ),
        ),
      );
      await tester.pump();

      final game =
          (tester.element(find.byType(GameObjectWidget)) as GameObject).game;

      final control = ButtonControl(game);
      action.bindings = [InputBinding(control)];

      action.enable();
      expect(action.phase, equals(InputActionPhase.waiting));

      control.press();
      game.input.update();

      expect(action.phase, equals(InputActionPhase.performed));
      expect(action.wasPressedThisFrame, isTrue);
      expect(action.wasPerformedThisFrame, isTrue);

      control.release();
      game.input.update();

      expect(action.phase, equals(InputActionPhase.waiting));
      expect(action.wasCompletedThisFrame, isTrue);

      await engine.dispose();
    });

    testWidgets('InputAction should transition phases for value type',
        (tester) async {
      final engine = await _createInputEngine();
      final action = InputAction()
        ..name = 'test'
        ..type = InputActionType.value;

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [ComponentWidget(() => action)],
          ),
        ),
      );
      await tester.pump();

      final game =
          (tester.element(find.byType(GameObjectWidget)) as GameObject).game;
      final control = ButtonControl(game);
      action.bindings = [InputBinding(control)];

      action.enable();

      control.press();
      game.input.update();
      expect(action.phase, equals(InputActionPhase.started));

      game.input.update();
      expect(action.phase, equals(InputActionPhase.performed));

      control.release();
      game.input.update();
      expect(action.phase, equals(InputActionPhase.waiting));

      await engine.dispose();
    });

    testWidgets('CompositeBinding should calculate direction correctly',
        (tester) async {
      final engine = await _createInputEngine();

      await tester.pumpWidget(
          Game(engine: engine, child: const SizedBox()));
      final game = (tester.widget(find.byType(GameLoop)) as GameLoop).game;

      final up = ButtonControl(game);
      final down = ButtonControl(game);
      final left = ButtonControl(game);
      final right = ButtonControl(game);

      final binding = InputBinding.composite(
        up: InputBinding(up),
        down: InputBinding(down),
        left: InputBinding(left),
        right: InputBinding(right),
      );

      final state = binding.createState(game);
      expect((state.read() as Vector2).x, equals(0.0));
      expect((state.read() as Vector2).y, equals(0.0));

      up.press();
      right.press();
      expect((state.read() as Vector2).x, equals(1.0));
      expect((state.read() as Vector2).y, equals(1.0));

      up.release();
      expect((state.read() as Vector2).x, equals(1.0));
      expect((state.read() as Vector2).y, equals(0.0));

      await engine.dispose();
    });

    testWidgets('InputAction events should be triggered', (tester) async {
      final engine = await _createInputEngine();
      final action = InputAction()..name = 'test';

      await tester.pumpWidget(
        Game(
          engine: engine,
          child: GameObjectWidget(
            children: [ComponentWidget(() => action)],
          ),
        ),
      );
      await tester.pump();

      final game =
          (tester.element(find.byType(GameObjectWidget)) as GameObject).game;
      final control = ButtonControl(game);
      action.bindings = [InputBinding(control)];
      action.enable();

      int startedCount = 0;
      int performedCount = 0;
      int canceledCount = 0;

      action.started += (_) => startedCount++;
      action.performed += (_) => performedCount++;
      action.canceled += (_) => canceledCount++;

      control.press();
      game.input.update();
      expect(startedCount, equals(1));
      expect(performedCount, equals(1));

      control.release();
      game.input.update();
      expect(canceledCount, equals(1));

      await engine.dispose();
    });

    testWidgets(
      'InputAction should handle dynamic enable/disable registration',
      (tester) async {
        final engine = await _createInputEngine();
        final action = InputAction()..name = 'test';
        action.enabled = false;

        await tester.pumpWidget(
          Game(
            engine: engine,
            child: GameObjectWidget(
              children: [ComponentWidget(() => action)],
            ),
          ),
        );
        await tester.pump();

        final game =
            (tester.element(find.byType(GameObjectWidget)) as GameObject).game;
        final control = ButtonControl(game);
        action.bindings = [InputBinding(control)];

        // Should NOT be registered yet
        control.press();
        game.input.update();
        expect(action.phase, equals(InputActionPhase.waiting));

        // Enable while mounted
        action.enabled = true;
        game.input.update(); // Process phase
        expect(action.phase, equals(InputActionPhase.performed));

        // Disable while mounted
        action.enabled = false;
        expect(action.phase, equals(InputActionPhase.waiting));

        control.release();
        game.input.update();
        // Should not transition since unregistered
        expect(action.phase, equals(InputActionPhase.waiting));

        await engine.dispose();
      },
    );
  });
}
