import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart' as pads;
import 'package:vector_math/vector_math_64.dart' show Vector2;

import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/input.dart';
import 'package:good/src/input/input_axis.dart';
import 'package:good/src/input/input_binding.dart';
import 'package:good/src/input/input_key.dart';
import 'package:good/src/input/input_state.dart';
import 'package:good/src/system.dart';

/// The live run under test - one inline run per isolate, as every other input
/// suite in this directory does.
late Game run;

// The analog path (#192): the axis block, the two bindings that read it, and
// the collector writing an axis and its thresholded bits from one event.
//
// Every assertion here has to be able to tell *proportional* from
// *thresholded*, which is the failure this whole path exists to fix. "Pushing
// left reads left" passes against four bits, so the load-bearing shape below
// is always a mid-range push reading mid-range - and where a value straddles
// GamepadCollector.stickDeadzone, the same push is asserted against both
// readings at once.

final List<String> events = <String>[];

/// The float32 the block stores for [value] - what a double read back out of
/// it compares equal to. 0.35 is not representable, so an exact expectation
/// would fail on the storage rather than on anything under test.
double _f32(double value) {
  _round[0] = value;
  return _round[0];
}

final Float32List _round = Float32List(1);

/// Builds the event `Gamepads.normalizedEvents` would deliver, exactly as
/// game_gamepad_test.dart does - `rawEvent` is required by the plugin's type
/// and nothing reads it.
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

/// One system reading the *same left stick* both ways, plus a trigger as a
/// double and an on-screen stick. Having both readings of one control side by
/// side is what makes "thresholded, not proportional" a failing assertion
/// rather than a passing one.
class _AnalogSystem extends GameSystem with FixedTickable {
  _AnalogSystem() {
    stick.pressed += (event) => events.add('stick pressed');
    stick.released += (event) => events.add('stick released');
  }

  final stick = Input.of<Vector2>(
    const StickBinding(x: .padLeftStickX, y: .padLeftStickY),
  );

  final thresholded = Input.of<Vector2>(
    const Vec2Binding(
      up: .padLeftStickUp,
      down: .padLeftStickDown,
      left: .padLeftStickLeft,
      right: .padLeftStickRight,
    ),
  );

  final touch = Input.of<Vector2>(
    const StickBinding(x: .virtualLeftStickX, y: .virtualLeftStickY),
  );

  final throttle = Input.of<double>(const AxisBinding(.padRightTrigger), 0.0);

  final pull = Input.of<double>(const AxisBinding(.padLeftTrigger), 0.0);

  @override
  void onFixedUpdate() {}
}

class _AnalogGameState extends GameState<_AnalogGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_AnalogSystem.new);
  }
}

class _AnalogGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _AnalogGameState();
}

Future<_AnalogGame> _boot() async {
  final game = await Game.startInline(_AnalogGame.new);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

_AnalogSystem get _system => run.state.getSystem<_AnalogSystem>();

void main() {
  setUp(events.clear);

  group('the axis table', () {
    test('every axis sits at its own index', () {
      for (var i = 0; i < InputAxis.all.length; i++) {
        expect(
          InputAxis.all[i].id,
          i,
          reason:
              'InputAxis.all is indexed by id and the fixed ids are written '
              'by hand, so a gap or a duplicate here is an axis reading '
              'another axis\'s float: ${InputAxis.all[i]}',
        );
      }
    });

    test('the hand-written slot arithmetic matches the table', () {
      expect(
        GamepadAxis.axisCount,
        GamepadAnalog.values.length,
        reason:
            'axisCount is written out because the id formula has to be a '
            'constant expression - if it drifts, slot n reads slot n+1',
      );
      expect(
        GamepadAxis.firstId,
        InputAxis.all.length - GamepadAxis.axisCount * GamepadKey.slotCount,
        reason: 'the gamepad block starts right after the unslotted axes',
      );
      for (var i = 0; i < GamepadAnalog.values.length; i++) {
        expect(GamepadAnalog.values[i].index, i);
      }
    });

    test('a slotted axis is the same control on another seat', () {
      final p2 = InputAxis.padLeftStickX(2);
      expect(p2.analog, GamepadAnalog.leftStickX);
      expect(p2.slot, 2);
      expect(
        p2.id,
        GamepadAxis.firstId + 2 * GamepadAxis.axisCount,
        reason: 'firstId + slot * axisCount + index',
      );
      expect(
        p2 == InputAxis.padLeftStickX(2),
        isTrue,
        reason:
            'call() builds a fresh instance, so equality has to be by float '
            'and not by identity - a rebinding screen compares a saved axis '
            'against a declared one',
      );
      expect(p2 == InputAxis.padLeftStickX, isFalse);
    });

    test('the sticks and the trigger axes are distinct floats', () {
      final ids = InputAxis.all.map((axis) => axis.id).toSet();
      expect(ids.length, InputAxis.all.length);
      final names = InputAxis.all.map((axis) => axis.name).toSet();
      expect(names.length, InputAxis.all.length);
    });

    test('an axis round-trips through JSON, slot included', () {
      expect(
        InputAxis.fromJson(InputAxis.padLeftStickY.toJson()),
        InputAxis.padLeftStickY,
      );
      expect(
        InputAxis.fromJson(InputAxis.virtualRightStickX.toJson()),
        InputAxis.virtualRightStickX,
      );
      final p3 = InputAxis.padRightStickY(3);
      final restored = InputAxis.fromJson(p3.toJson()) as GamepadAxis;
      expect(restored, p3);
      expect(restored.slot, 3);
      expect(
        p3.toJson()['name'],
        'padRightStickY',
        reason:
            'the slot is its own field, so a settings screen can move a '
            'player to another seat without rewriting the axis',
      );
    });

    test('an axis and a key of the same name are different things', () {
      expect(
        InputAxis.padLeftTrigger.toJson()['kind'],
        isNot(InputKey.padLeftTrigger.toJson()['kind']),
        reason:
            'both vocabularies spell the left trigger "padLeftTrigger" - one '
            'as a bit past a threshold, one as a pull. A save file has to be '
            'able to say which',
      );
    });
  });

  group('the block', () {
    test('the axis section is floats appended after the pointer', () {
      expect(
        InputState.contactIntOffset,
        InputState.bitBlockBytes + 28 + InputAxis.count * 4,
        reason:
            'bits, then the pointer\'s seven floats, then one float per axis',
      );
      expect(InputAxis.count, greaterThan(0));
    });

    test('the contact table is appended after the axes', () {
      expect(
        InputState.byteLengthFor(4),
        InputState.contactIntOffset +
            4 *
                (InputState.contactIntStride +
                    InputState.contactCoordStride) *
                4,
        reason: 'four ints and four floats per contact slot, after the axes',
      );
      expect(
        InputState.byteLengthFor(8) - InputState.byteLengthFor(4),
        InputState.byteLengthFor(4) - InputState.contactIntOffset,
        reason: 'the table grows linearly in the contact count',
      );
    });

    test('the pointer and the axes do not share floats', () async {
      final game = await _boot();
      final device = game.inputDevice!;

      device.setVirtualAxis(InputAxis.virtualLeftStickX, 0.5);
      device.setVirtualAxis(InputAxis.virtualLeftStickY, 0.25);
      // Writes the pointer's own floats, the last of which sits immediately
      // before the axis section - so an offset that is one float short has
      // the two blocks overlapping, and moving the mouse silently recentres
      // a stick.
      device.movePointer(screenX: 12, screenY: 34);
      run.state.runFixedStep();

      expect(_system.touch.value.x, 0.5);
      expect(_system.touch.value.y, 0.25);
    });

    test('nothing published reads as rest, not as noise', () async {
      await _boot();
      expect(
        _system.stick.value,
        Vector2.zero(),
        reason:
            'a game with no widget attached has no stick to push, which is '
            'the same answer isDown gives for a key',
      );
    });
  });

  group('a stick is read proportionally', () {
    test('rest reads exactly zero', () async {
      final game = await _boot();
      game.inputDevice!.setGamepadAxis(1, GamepadAnalog.leftStickX, 0);
      run.state.runFixedStep();
      expect(_system.stick.value.x, 0.0);
      expect(_system.stick.value.y, 0.0);
    });

    test('full deflection reads 1, and the other way -1', () async {
      final game = await _boot();
      game.inputDevice!.setGamepadAxis(1, GamepadAnalog.leftStickX, 1);
      run.state.runFixedStep();
      expect(_system.stick.value.x, 1.0);

      game.inputDevice!.setGamepadAxis(1, GamepadAnalog.leftStickX, -1);
      run.state.runFixedStep();
      expect(_system.stick.value.x, -1.0);
    });

    test('a stick pushed a third of the way reads a third', () async {
      final game = await _boot();
      game.inputDevice!.setGamepadAxis(1, GamepadAnalog.leftStickX, 0.35);
      run.state.runFixedStep();

      expect(
        _system.stick.value.x,
        closeTo(0.35, 1e-6),
        reason:
            'this is the assertion the whole path exists for. Four '
            'thresholded bits can only answer 0 or 1 here, so a binding that '
            'is secretly still reading them fails this and passes every '
            '"pushing right reads right" test ever written',
      );
      expect(
        _f32(0.35),
        isNot(0.35),
        reason:
            'the block stores float32, so the tolerance above is the storage '
            'and not slack in the assertion - an exact expectation would '
            'fail on the round trip rather than on anything under test',
      );
    });

    test('+1 is up, matching the world and Vec2Binding', () async {
      final game = await _boot();
      game.inputDevice!.setGamepadAxis(1, GamepadAnalog.leftStickY, 0.5);
      run.state.runFixedStep();
      expect(
        _system.stick.value.y,
        0.5,
        reason:
            'a stick pushed up gives +y, so adding the vector to a '
            'transformOffset moves the thing the way the player pushed - the '
            'inversion that compiles is the one this pins down',
      );
    });

    test('the vector is the action\'s own instance, tick after tick', () async {
      final game = await _boot();
      game.inputDevice!.setGamepadAxis(1, GamepadAnalog.leftStickX, 0.2);
      run.state.runFixedStep();
      final first = _system.stick.value;

      game.inputDevice!.setGamepadAxis(1, GamepadAnalog.leftStickX, 0.9);
      run.state.runFixedStep();
      expect(
        identical(_system.stick.value, first),
        isTrue,
        reason:
            'resolution writes into storage the action owns - a fresh '
            'Vector2 per tick is a heap object per action per tick',
      );
      expect(_system.stick.value.x, closeTo(0.9, 1e-6));
    });
  });

  group('proportional and thresholded are both available', () {
    test('a half-pushed stick reads half, and held', () async {
      final game = await _boot();
      final gamepads = game.gamepads!;

      // 0.5 is exactly GamepadCollector.stickDeadzone, so the bit path calls
      // this held. The analog path has to disagree by degree, not by
      // direction.
      gamepads.handleEvent(
        _event('pad-a', axis: pads.GamepadAxis.leftStickX, value: 0.5),
      );
      run.state.runFixedStep();

      expect(
        _system.thresholded.value.x,
        1.0,
        reason:
            'unchanged: the deadzone still turns half travel into a held '
            'bit, and every game binding the *Stick* keys keeps reading '
            'exactly what it read before',
      );
      expect(
        _system.stick.value.x,
        0.5,
        reason:
            'the same event, read as an axis, is a half - if this ever '
            'reads 1.0 the analog value has been routed through the '
            'threshold and nothing has been gained',
      );
    });

    test('a barely-pushed stick reads something, and not held', () async {
      final game = await _boot();
      final gamepads = game.gamepads!;

      gamepads.handleEvent(
        _event('pad-a', axis: pads.GamepadAxis.leftStickX, value: 0.2),
      );
      run.state.runFixedStep();

      expect(
        _system.thresholded.value.x,
        0.0,
        reason: 'below the deadzone, so no bit - unchanged behaviour',
      );
      expect(
        _system.stick.value.x,
        closeTo(0.2, 1e-6),
        reason:
            'the deadzone shapes the bits and not the axis: a game that '
            'wants its own deadzone needs the value that was actually '
            'reported',
      );
    });

    test('a trigger is a bit and a pull at once', () async {
      final game = await _boot();
      final gamepads = game.gamepads!;

      gamepads.handleEvent(
        _event('pad-a', axis: pads.GamepadAxis.rightTrigger, value: 0.4),
      );
      run.state.runFixedStep();
      expect(
        game.inputDevice!.isDown(InputKey.padRightTrigger),
        isFalse,
        reason: 'below triggerThreshold - the bit is unchanged',
      );
      expect(_system.throttle.value, closeTo(0.4, 1e-6));

      gamepads.handleEvent(
        _event('pad-a', axis: pads.GamepadAxis.rightTrigger, value: 0.75),
      );
      run.state.runFixedStep();
      expect(game.inputDevice!.isDown(InputKey.padRightTrigger), isTrue);
      expect(
        _system.throttle.value,
        closeTo(0.75, 1e-6),
        reason:
            'past the threshold the bit says "pressed" and says nothing '
            'else; three quarters is what the axis is for',
      );
      expect(
        _system.pull.value,
        0.0,
        reason: 'the other trigger has its own float and was never touched',
      );
    });

    test('every stick axis reaches its own float', () async {
      final game = await _boot();
      final gamepads = game.gamepads!;

      gamepads.handleEvent(
        _event('pad-a', axis: pads.GamepadAxis.leftStickX, value: 0.1),
      );
      gamepads.handleEvent(
        _event('pad-a', axis: pads.GamepadAxis.leftStickY, value: 0.2),
      );
      gamepads.handleEvent(
        _event('pad-a', axis: pads.GamepadAxis.rightStickX, value: 0.3),
      );
      gamepads.handleEvent(
        _event('pad-a', axis: pads.GamepadAxis.rightStickY, value: 0.4),
      );
      run.state.runFixedStep();

      final device = game.inputDevice!;
      expect(device.axisOf(InputAxis.padLeftStickX), closeTo(0.1, 1e-6));
      expect(device.axisOf(InputAxis.padLeftStickY), closeTo(0.2, 1e-6));
      expect(device.axisOf(InputAxis.padRightStickX), closeTo(0.3, 1e-6));
      expect(
        device.axisOf(InputAxis.padRightStickY),
        closeTo(0.4, 1e-6),
        reason:
            'four axes, four floats - a shared or transposed index shows up '
            'as one of these reading another\'s number',
      );
    });
  });

  group('slots', () {
    test('slot 0 carries whichever pad is pushed furthest', () async {
      final game = await _boot();
      final device = game.inputDevice!;

      device.setGamepadAxis(1, GamepadAnalog.leftStickX, 0.25);
      run.state.runFixedStep();
      expect(
        _system.stick.value.x,
        closeTo(0.25, 1e-6),
        reason:
            'the binding names no slot, so a single-player game reads '
            'whichever pad was picked up - the axis half of what .padA does',
      );

      device.setGamepadAxis(2, GamepadAnalog.leftStickX, -0.8);
      run.state.runFixedStep();
      expect(
        _system.stick.value.x,
        closeTo(-0.8, 1e-6),
        reason:
            'furthest from rest wins, which is the OR of the bit path said '
            'about something with a magnitude',
      );

      device.setGamepadAxis(2, GamepadAnalog.leftStickX, 0);
      run.state.runFixedStep();
      expect(
        _system.stick.value.x,
        closeTo(0.25, 1e-6),
        reason:
            'recomputed from the other slots, not accumulated - a slot going '
            'back to rest must stop holding the aggregate off centre',
      );
    });

    test('a seat writes its own float and nobody else\'s', () async {
      final game = await _boot();
      final device = game.inputDevice!;

      device.setGamepadAxis(1, GamepadAnalog.leftStickX, 0.6);
      expect(device.axisOf(InputAxis.padLeftStickX(1)), closeTo(0.6, 1e-6));
      expect(device.axisOf(InputAxis.padLeftStickX(2)), 0.0);
      expect(device.axisOf(InputAxis.padLeftStickX(3)), 0.0);
    });

    test('an unplugged pad stops pushing', () async {
      final game = await _boot();
      final gamepads = game.gamepads!;

      gamepads.handleEvent(
        _event('pad-a', axis: pads.GamepadAxis.leftStickX, value: 1),
      );
      run.state.runFixedStep();
      expect(_system.stick.value.x, 1.0);

      gamepads.releaseSlot(gamepads.slotOf('pad-a')!);
      run.state.runFixedStep();
      expect(
        _system.stick.value.x,
        0.0,
        reason:
            'a pad unplugged mid-push leaves its stick pushed forever '
            'otherwise - the same bug releaseSlot already fixed for buttons',
      );
    });

    test('losing focus returns every axis to rest', () async {
      final game = await _boot();
      final device = game.inputDevice!;

      device.setGamepadAxis(1, GamepadAnalog.leftStickY, -1);
      device.setVirtualAxis(InputAxis.virtualLeftStickX, 0.7);
      run.state.runFixedStep();
      expect(_system.stick.value.y, -1.0);

      device.releaseAll();
      run.state.runFixedStep();
      expect(
        _system.stick.value.y,
        0.0,
        reason:
            'nothing is being pushed by a window nobody is looking at, and '
            'a latest-value block would go on saying it was forever',
      );
      expect(_system.touch.value.x, 0.0);
    });
  });

  group('an on-screen stick', () {
    test('reaches a binding exactly as a pad does', () async {
      final game = await _boot();
      final device = game.inputDevice!;

      device.setVirtualAxis(InputAxis.virtualLeftStickX, -0.4);
      device.setVirtualAxis(InputAxis.virtualLeftStickY, 0.6);
      run.state.runFixedStep();

      expect(
        _system.touch.value.x,
        closeTo(-0.4, 1e-6),
        reason:
            'a thumb half way to the edge of a drawn joystick is a half, '
            'which is the entire reason #191 needs this',
      );
      expect(_system.touch.value.y, closeTo(0.6, 1e-6));
      expect(
        _system.stick.value,
        Vector2.zero(),
        reason: 'a virtual axis is its own float, not a pad\'s',
      );
    });

    test('the binding cannot tell which kind of source wrote it', () async {
      final game = await _boot();
      final device = game.inputDevice!;

      device.setVirtualAxis(InputAxis.virtualLeftStickX, 0.5);
      device.setGamepadAxis(1, GamepadAnalog.leftStickX, 0.5);
      run.state.runFixedStep();

      expect(_system.touch.value.x, _system.stick.value.x);
      expect(
        _system.touch.binding.runtimeType,
        _system.stick.binding.runtimeType,
        reason:
            'one binding type serves both, so swapping an on-screen stick '
            'for a real one is a change of which axes are named',
      );
    });
  });

  group('edges', () {
    test('leaving rest is a press, coming back is a release', () async {
      final game = await _boot();
      final device = game.inputDevice!;

      device.setGamepadAxis(1, GamepadAnalog.leftStickX, 0.1);
      run.state.runFixedStep();
      expect(_system.stick.wasPressedThisFrame, isTrue);

      device.setGamepadAxis(1, GamepadAnalog.leftStickX, 0.9);
      run.state.runFixedStep();
      expect(
        _system.stick.wasPressedThisFrame,
        isFalse,
        reason: 'still pushed - pushing harder is not a second press',
      );

      device.setGamepadAxis(1, GamepadAnalog.leftStickX, 0);
      run.state.runFixedStep();
      expect(_system.stick.wasReleasedThisFrame, isTrue);
      expect(events, <String>['stick pressed', 'stick released']);
    });

    test('a trigger read as a double edges on any pull at all', () async {
      final game = await _boot();
      final device = game.inputDevice!;

      device.setGamepadAxis(1, GamepadAnalog.rightTrigger, 0.05);
      run.state.runFixedStep();
      expect(
        _system.throttle.wasPressedThisFrame,
        isTrue,
        reason:
            'no threshold lives in the binding, which is #192\'s open '
            'question and deliberately not answered here',
      );
    });
  });

  group('bindings are values', () {
    test('a stick binding round-trips through JSON', () {
      const binding = StickBinding(x: .padLeftStickX, y: .padLeftStickY);
      expect(StickBinding.fromJson(binding.toJson()), binding);

      final slotted = StickBinding(
        x: InputAxis.padRightStickX(2),
        y: InputAxis.padRightStickY(2),
      );
      final restored = StickBinding.fromJson(slotted.toJson());
      expect(restored, slotted);
      expect((restored.x as GamepadAxis).slot, 2);
    });

    test('an axis binding round-trips through JSON', () {
      const binding = AxisBinding(.padLeftTrigger);
      expect(AxisBinding.fromJson(binding.toJson()), binding);
      expect(
        AxisBinding.fromJson(const AxisBinding(.virtualLeftStickY).toJson()),
        const AxisBinding(.virtualLeftStickY),
      );
    });

    test('a rebinding screen can swap one axis', () {
      const binding = StickBinding(x: .padLeftStickX, y: .padLeftStickY);
      expect(
        binding.copyWith(x: InputAxis.virtualLeftStickX),
        const StickBinding(x: .virtualLeftStickX, y: .padLeftStickY),
      );
      expect(
        const AxisBinding(.padLeftTrigger)
            .copyWith(axis: InputAxis.padRightTrigger),
        const AxisBinding(.padRightTrigger),
      );
    });

    test('two bindings on the same axes are equal and hash alike', () {
      const a = StickBinding(x: .padLeftStickX, y: .padLeftStickY);
      const b = StickBinding(x: .padLeftStickX, y: .padLeftStickY);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(const StickBinding(x: .padLeftStickY, y: .padLeftStickX)),
      );
    });

    test('a malformed axis field says which field', () {
      expect(
        () => StickBinding.fromJson(<String, Object?>{'x': 3, 'y': 4}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('"x"'),
          ),
        ),
      );
      expect(
        () => InputAxis.fromJson(<String, Object?>{
          'kind': 'gamepadAxis',
          'name': 'padNoSuchStick',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
