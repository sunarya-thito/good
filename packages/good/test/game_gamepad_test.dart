import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart' as pads;
import 'package:vector_math/vector_math_64.dart' show Vector2;

import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/input.dart';
import 'package:good/src/input/input_binding.dart';
import 'package:good/src/input/input_key.dart';
import 'package:good/src/system.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

// GamepadCollector end to end, with no gamepad and no plugin: every test
// drives `handleEvent` with the same normalized events the plugin's own
// stream carries, which is the whole reason that method is public. `attach()`
// adds nothing but the subscription, so what is skipped here is one line.
//
// The key table's own invariants (ids, slots, names, JSON) are checked in
// game_input_test.dart alongside every other key.

/// Builds the event `Gamepads.normalizedEvents` would deliver. `rawEvent` is
/// required by the plugin's type and is not read by anything here.
pads.NormalizedGamepadEvent _event(
  String gamepadId, {
  pads.GamepadButton? button,
  pads.GamepadAxis? axis,
  required double value,
}) {
  return pads.NormalizedGamepadEvent(
    gamepadId: gamepadId,
    timestamp: 0,
    value: value,
    button: button,
    axis: axis,
    rawEvent: pads.GamepadEvent(
      gamepadId: gamepadId,
      timestamp: 0,
      type: button != null ? pads.KeyType.button : pads.KeyType.analog,
      key: 'ignored',
      value: value,
    ),
  );
}

class _PadSystem extends GameSystem with FixedTickable {
  late final Input<bool> confirm;
  late final Input<bool> p1Confirm;
  late final Input<bool> p2Confirm;
  late final Input<Vector2> move;

  @override
  void describeInputs(InputDescriptor descriptor) {
    super.describeInputs(descriptor);
    confirm = descriptor.has<bool>(const TriggerBinding(.padA));
    p1Confirm = descriptor.has<bool>(TriggerBinding(InputKey.padA(1)));
    p2Confirm = descriptor.has<bool>(TriggerBinding(InputKey.padA(2)));
    move = descriptor.has<Vector2>(
      const Vec2Binding(
        up: .padLeftStickUp,
        down: .padLeftStickDown,
        left: .padLeftStickLeft,
        right: .padLeftStickRight,
      ),
    );
  }

  @override
  void onFixedUpdate() {}
}

class _PadGameState extends GameState<_PadGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_PadSystem.new);
  }
}

class _PadGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _PadGameState();
}

Future<_PadGame> _boot() async {
  final game = await Game.startInline(_PadGame.new);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

void main() {
  group('slots', () {
    test('the first pad heard from takes the first seat', () async {
      final game = await _boot();
      final gamepads = game.gamepads!;

      gamepads.handleEvent(
        _event('xbox-7', button: pads.GamepadButton.a, value: 1),
      );
      expect(
        gamepads.slotOf('xbox-7'),
        1,
        reason: 'slot 0 is the aggregate, so the first real seat is 1',
      );

      gamepads.handleEvent(
        _event('ds-2', button: pads.GamepadButton.b, value: 1),
      );
      expect(gamepads.slotOf('ds-2'), 2);
      expect(
        gamepads.slotOf('xbox-7'),
        1,
        reason:
            'a seat is kept, not reassigned on every event - a saved '
            'binding names a seat, so a seat that moved would be a '
            'keybinding that changed itself',
      );
    });

    test('an unknown pad has no seat until it says something', () async {
      final game = await _boot();
      expect(game.gamepads!.slotOf('never-seen'), isNull);
    });

    test('slot 0 is any pad', () async {
      final game = await _boot();
      final system = run.state.getSystem<_PadSystem>();
      final gamepads = game.gamepads!;

      gamepads.handleEvent(
        _event('pad-b', button: pads.GamepadButton.a, value: 1),
      );
      run.state.runFixedStep();
      expect(
        system.confirm.value,
        isTrue,
        reason:
            'the single-player case: .padA binds slot 0, and whichever '
            'pad the player picked up drives it with no setup',
      );
      expect(system.p1Confirm.value, isTrue, reason: 'and its own seat too');
      expect(system.p2Confirm.value, isFalse);
    });

    test('slot 0 stays held while any pad holds it', () async {
      final game = await _boot();
      final system = run.state.getSystem<_PadSystem>();
      final gamepads = game.gamepads!;

      gamepads.handleEvent(
        _event('one', button: pads.GamepadButton.a, value: 1),
      );
      gamepads.handleEvent(
        _event('two', button: pads.GamepadButton.a, value: 1),
      );
      gamepads.handleEvent(
        _event('one', button: pads.GamepadButton.a, value: 0),
      );
      run.state.runFixedStep();

      expect(system.p1Confirm.value, isFalse);
      expect(system.p2Confirm.value, isTrue);
      expect(
        system.confirm.value,
        isTrue,
        reason:
            'slot 0 is an OR, not a copy of whoever wrote last - one '
            'player letting go must not release the button for the other',
      );

      gamepads.handleEvent(
        _event('two', button: pads.GamepadButton.a, value: 0),
      );
      run.state.runFixedStep();
      expect(
        system.confirm.value,
        isFalse,
        reason: 'and it clears once nobody is holding it',
      );
    });

    test('releasing a seat clears what it was holding', () async {
      final game = await _boot();
      final system = run.state.getSystem<_PadSystem>();
      final gamepads = game.gamepads!;

      gamepads.handleEvent(
        _event('yanked', button: pads.GamepadButton.a, value: 1),
      );
      run.state.runFixedStep();
      expect(system.confirm.value, isTrue);

      gamepads.releaseSlot(1);
      run.state.runFixedStep();

      expect(system.p1Confirm.value, isFalse);
      expect(
        system.confirm.value,
        isFalse,
        reason:
            'a pad unplugged mid-press would otherwise hold that button '
            'down forever - there is no disconnect event to notice it by, '
            'so releasing the seat has to do it',
      );
      expect(
        gamepads.slotOf('yanked'),
        isNull,
        reason: 'and the seat is free for whoever plugs in next',
      );
    });

    test('a pad beyond capacity is inert rather than sharing a seat', () async {
      final game = await _boot();
      final gamepads = game.gamepads!;
      for (var i = 1; i < GamepadKey.slotCount; i++) {
        gamepads.handleEvent(
          _event('pad$i', button: pads.GamepadButton.a, value: 1),
        );
      }

      expect(
        () => gamepads.handleEvent(
          _event('extra', button: pads.GamepadButton.a, value: 1),
        ),
        throwsA(isA<AssertionError>()),
        reason:
            'in a debug build it says so - handing this pad someone '
            'else\'s seat would give two players one controller, which is a '
            'worse failure than a controller that does nothing',
      );
    });
  });

  group('buttons', () {
    test('the two vocabularies are mapped where they disagree', () async {
      final game = await _boot();
      final gamepads = game.gamepads!;
      final device = game.inputDevice!;

      // leftBumper/leftShoulder and back/select are the two places the
      // plugin's names and this engine's names differ, which is exactly
      // where a name-matching translation would silently drop them.
      gamepads.handleEvent(
        _event('p', button: pads.GamepadButton.leftBumper, value: 1),
      );
      expect(device.isDown(InputKey.padLeftShoulder), isTrue);

      gamepads.handleEvent(
        _event('p', button: pads.GamepadButton.back, value: 1),
      );
      expect(device.isDown(InputKey.padSelect), isTrue);

      gamepads.handleEvent(
        _event('p', button: pads.GamepadButton.dpadLeft, value: 1),
      );
      expect(device.isDown(InputKey.padLeft), isTrue);
      expect(device.isDown(InputKey.padRight), isFalse);
    });

    test('every button the plugin can report has a bit here', () async {
      final game = await _boot();
      final gamepads = game.gamepads!;
      final device = game.inputDevice!;

      for (final button in pads.GamepadButton.values) {
        gamepads.handleEvent(_event('p', button: button, value: 1));
      }

      var held = 0;
      for (final key in InputKey.all) {
        if (key is GamepadKey && key.slot == 1 && device.isDown(key)) held++;
      }
      expect(
        held,
        pads.GamepadButton.values.length,
        reason:
            'a button that mapped to nothing would be one the player '
            'can press and no game can bind - the translation is allowed '
            'to be partial, but nothing should be falling through it '
            'today',
      );
    });

    test('a button release clears the bit', () async {
      final game = await _boot();
      final gamepads = game.gamepads!;
      final device = game.inputDevice!;

      gamepads.handleEvent(_event('p', button: pads.GamepadButton.y, value: 1));
      expect(device.isDown(InputKey.padY), isTrue);
      gamepads.handleEvent(_event('p', button: pads.GamepadButton.y, value: 0));
      expect(device.isDown(InputKey.padY), isFalse);
    });

    test('a press edge lands on exactly one tick, like any key', () async {
      final game = await _boot();
      final system = run.state.getSystem<_PadSystem>();

      game.gamepads!.handleEvent(
        _event('p', button: pads.GamepadButton.a, value: 1),
      );
      run.state.runFixedStep();
      expect(system.confirm.wasPressedThisFrame, isTrue);

      run.state.runFixedStep();
      expect(system.confirm.wasPressedThisFrame, isFalse);
      expect(
        system.confirm.value,
        isTrue,
        reason:
            'still held, just no longer an edge - a gamepad button is '
            'not a special case anywhere above the collector',
      );
    });
  });

  group('sticks and triggers', () {
    test('a stick past the deadzone drives a Vec2Binding', () async {
      final game = await _boot();
      final system = run.state.getSystem<_PadSystem>();
      final gamepads = game.gamepads!;

      gamepads.handleEvent(
        _event('p', axis: pads.GamepadAxis.leftStickX, value: 1),
      );
      run.state.runFixedStep();
      expect(
        system.move.value,
        Vector2(1, 0),
        reason:
            'four thresholded bits are exactly what Vec2Binding '
            'composes, which is the whole reason the sticks are in the '
            'button vocabulary at all',
      );

      gamepads.handleEvent(
        _event('p', axis: pads.GamepadAxis.leftStickY, value: 1),
      );
      run.state.runFixedStep();
      expect(
        system.move.value,
        Vector2(1, 1),
        reason:
            'the plugin reports +1 as up, and a Vec2Binding puts up at '
            '+y - the same convention a keyboard W gets',
      );
    });

    test('inside the deadzone is at rest', () async {
      final game = await _boot();
      final system = run.state.getSystem<_PadSystem>();
      final gamepads = game.gamepads!;

      gamepads.handleEvent(
        _event('p', axis: pads.GamepadAxis.leftStickX, value: 0.4),
      );
      run.state.runFixedStep();
      expect(
        system.move.value,
        Vector2(0, 0),
        reason:
            'a stick that has drifted a little is a stick at rest - '
            'without this, a worn controller walks the player into a wall '
            'while nobody is touching it',
      );
    });

    test('swinging an axis across releases the direction it left', () async {
      final game = await _boot();
      final system = run.state.getSystem<_PadSystem>();
      final gamepads = game.gamepads!;

      gamepads.handleEvent(
        _event('p', axis: pads.GamepadAxis.leftStickX, value: -1),
      );
      run.state.runFixedStep();
      expect(system.move.value, Vector2(-1, 0));

      // One event, both bits: the plugin reports an axis' new value, not a
      // press and a release, so writing only the newly-held side would leave
      // the stick held left *and* right.
      gamepads.handleEvent(
        _event('p', axis: pads.GamepadAxis.leftStickX, value: 1),
      );
      run.state.runFixedStep();
      expect(system.move.value, Vector2(1, 0));
      expect(game.inputDevice!.isDown(InputKey.padLeftStickLeft), isFalse);
    });

    test('the deadzone is settable', () async {
      final game = await _boot();
      final system = run.state.getSystem<_PadSystem>();
      game.gamepads!.stickDeadzone = 0.2;

      game.gamepads!.handleEvent(
        _event('p', axis: pads.GamepadAxis.leftStickX, value: 0.4),
      );
      run.state.runFixedStep();
      expect(system.move.value, Vector2(1, 0));
    });

    test('a trigger crosses its own threshold', () async {
      final game = await _boot();
      final device = game.inputDevice!;
      final gamepads = game.gamepads!;

      gamepads.handleEvent(
        _event('p', axis: pads.GamepadAxis.rightTrigger, value: 0.2),
      );
      expect(device.isDown(InputKey.padRightTrigger), isFalse);

      gamepads.handleEvent(
        _event('p', axis: pads.GamepadAxis.rightTrigger, value: 0.9),
      );
      expect(
        device.isDown(InputKey.padRightTrigger),
        isTrue,
        reason:
            'a trigger is analog on every modern pad, so a digital '
            'binding needs a point at which it counts as pulled',
      );

      // Some platforms report the trigger as a digital button as well. Both
      // paths write the same bit, so they agree rather than fight.
      gamepads.handleEvent(
        _event('p', button: pads.GamepadButton.rightTrigger, value: 1),
      );
      expect(device.isDown(InputKey.padRightTrigger), isTrue);
    });
  });

  group('lifetime', () {
    test('there is a collector exactly when there is a device', () async {
      // Hand-constructed and never started, which is the only way to hold a
      // game before its bring-up now that `startInline` is the thing that
      // builds it.
      expect(
        _PadGame().gamepads,
        isNull,
        reason: 'nothing exists before start()',
      );

      final game = await Game.startInline(_PadGame.new);
      run = game;
      expect(game.gamepads, isNotNull);
      expect(
        game.gamepads!.isAttached,
        isFalse,
        reason:
            'created, but not listening to the OS - GameView attaches '
            'it when it mounts, so a headless game holds no subscription',
      );

      await run.stop();
      expect(
        game.gamepads,
        isNull,
        reason:
            'the collector writes through the device, and the device '
            'is gone with the storage it wrote into',
      );
    });
  });
}
