import 'package:flutter/gestures.dart'
    show
        Offset,
        PointerDeviceKind,
        PointerDownEvent,
        PointerHoverEvent,
        kPrimaryMouseButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector2;

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

// Single-copy coverage for the declarative input system, driven through
// Game.startInline(...) exactly as game_state_test.dart
// does: one copy doing both jobs, no timer, runFixedStep() by hand, and
// synthetic device state written through the same InputDevice a GameView
// would write through. The two-isolate half - where the raw block genuinely
// crosses a heap boundary, main -> game - lives in game_isolate_test.dart.

/// Everything every input listener in this file appends to. A plain top-level
/// list rather than closure-captured test state, for the same reason
/// game_state_test.dart uses one.
final List<String> events = <String>[];

// --- the system under test ------------------------------------------------

/// The shape from the design sketch: a movement vector, a trigger, an
/// unbound action, and one action of each type that nothing ever binds.
///
/// Subscriptions happen in `describeInputs` rather than in `onMounted`,
/// because a `GameSystem` does not currently receive `MountEvent` - see the
/// note on `Input.pressed`. A closure created during a one-shot declaration
/// pass is explicitly fine (the no-closure rule).
class _PlayerSystem extends GameSystem with FixedTickable {
  late final Input<Vector2> movement;
  late final Input<bool> triggerSkill;
  late final Input<bool> ping;
  late final Input<Vector2> aim;

  /// What [movement] read the last time this system actually ticked, and how
  /// many ticks it has seen - together these are how the tests check that
  /// resolution happens *before* systems run rather than lazily on read.
  double lastSeenX = double.nan;
  bool lastSeenPressed = false;
  int ticks = 0;

  @override
  void describeInputs(InputDescriptor input) {
    super.describeInputs(input);
    movement = input.has<Vector2>(
      const Vec2Binding(up: .w, down: .s, left: .a, right: .d),
    );
    triggerSkill = input.has<bool>(const TriggerBinding(.spacebar));
    ping = input.has<bool>();
    aim = input.has<Vector2>();

    triggerSkill.pressed += (event) =>
        events.add('skill pressed ${event.value}');
    triggerSkill.released += (event) =>
        events.add('skill released ${event.value}');
    ping.pressed += (event) => events.add('ping pressed');
    ping.released += (event) => events.add('ping released');
    movement.pressed += (event) =>
        events.add('move pressed ${_xy(event.value)}');
    movement.released += (event) =>
        events.add('move released ${_xy(event.value)}');
  }

  @override
  void onFixedUpdate() {
    ticks++;
    lastSeenX = movement.value.x;
    lastSeenPressed = triggerSkill.wasPressedThisFrame;
  }
}

class _InputGameState extends GameState<_InputGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_PlayerSystem());
  }
}

class _InputGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  /// The live descriptor, captured mid-boot so a test can try to declare
  /// against it *after* boot - see 'declaring after boot is refused'.
  InputDescriptor? capturedDescriptor;

  @override
  GameState createState() => _InputGameState();

  @override
  void describeInputs(InputDescriptor input) {
    super.describeInputs(input);
    capturedDescriptor = input;
  }
}

// --- default-value fixtures ----------------------------------------------

/// A game that **forgets `super.describeInputs`**, which is the silent
/// failure `@mustCallSuper` exists to catch: nothing complains at boot, and
/// the first read of an unbound action throws instead of reading `false`.
class _NoSuperGame extends Game {
  @override
  int get pageSize => 4096;

  late final Input<bool> orphan;
  late final Input<bool> ownDefault;

  @override
  GameState createState() => _NoSuperState();

  @override
  // ignore: must_call_super
  void describeInputs(InputDescriptor input) {
    // Deliberately no super.describeInputs(input) - that is the whole point
    // of this fixture. The analyzer flags it, which is why the ignore above
    // has to be written out by hand.
    orphan = input.has<bool>();
    ownDefault = input.has<bool>(null, true);
  }
}

class _NoSuperState extends GameState<_NoSuperGame> {}

/// Registers a `bool` default on top of the one `Game.describeInputs` already
/// shipped - a declare-time error, not a silent overwrite.
class _DuplicateDefaultGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  GameState createState() => _DuplicateDefaultState();

  @override
  void describeInputs(InputDescriptor input) {
    super.describeInputs(input);
    input.hasDefaultValue<bool>(true);
  }
}

class _DuplicateDefaultState extends GameState<_DuplicateDefaultGame> {}

/// A *system* registering a type-level default for a type only it uses, into
/// the one descriptor the whole boot shares - and a `Game`-declared action of
/// that type picking it up even though the Game declared first.
class _LateDefaultSystem extends GameSystem {
  @override
  void describeInputs(InputDescriptor input) {
    super.describeInputs(input);
    input.hasDefaultValue<double>(0.25);
  }
}

class _SharedDescriptorGame extends Game {
  @override
  int get pageSize => 4096;

  late final Input<double> throttle;

  @override
  GameState createState() => _SharedDescriptorState();

  @override
  void describeInputs(InputDescriptor input) {
    super.describeInputs(input);
    // Declared *before* _LateDefaultSystem registers the double default -
    // defaults are matched to actions at seal(), not at has().
    throttle = input.has<double>();
  }
}

class _SharedDescriptorState extends GameState<_SharedDescriptorGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_LateDefaultSystem());
  }
}

// --- pointer fixtures -----------------------------------------------------

/// A pointer position alongside an ordinary button trigger - the two halves
/// of "the mouse", which are deliberately different kinds of thing: the
/// button is one bit like any key, the position is not.
class _CursorSystem extends GameSystem {
  late final Input<CursorPosition> cursor;
  late final Input<bool> click;

  @override
  void describeInputs(InputDescriptor input) {
    super.describeInputs(input);
    cursor = input.has<CursorPosition>(const MouseBinding());
    click = input.has<bool>(const TriggerBinding(.leftMouseButton));

    cursor.pressed += (event) => events.add('cursor pressed');
    cursor.released += (event) => events.add('cursor released');
    click.pressed += (event) => events.add('click pressed');
    click.released += (event) => events.add('click released');
  }
}

class _MouseGameState extends GameState<_MouseGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_CursorSystem());
  }
}

class _MouseGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _MouseGameState();
}

// --- helpers --------------------------------------------------------------

Future<T> _boot<T extends Game>(T game) async {
  run = await Game.startInline(game);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

String _xy(Vector2 v) => '${v.x.toInt()},${v.y.toInt()}';

/// Presses [keys], then runs exactly one fixed step - i.e. exactly one
/// resolution. Everything about edges is about what happens between two of
/// these.
void _pressAndStep(Game game, List<InputKey> keys) {
  for (final key in keys) {
    game.inputDevice!.press(key);
  }
  run.state.runFixedStep();
}

void _releaseAndStep(Game game, List<InputKey> keys) {
  for (final key in keys) {
    game.inputDevice!.release(key);
  }
  run.state.runFixedStep();
}

void main() {
  setUp(events.clear);

  group('the key table', () {
    test('every key sits at the index its id names', () {
      for (var i = 0; i < InputKey.all.length; i++) {
        expect(
          InputKey.all[i].id,
          i,
          reason:
              'id is a bit position in the raw device block and the ids '
              'are written by hand, so a gap or a duplicate here would '
              'silently alias two keys onto one bit - "${InputKey.all[i].name}" '
              'is at index $i',
        );
      }
    });

    test('no two keys share a name', () {
      final names = <String>{};
      for (final key in InputKey.all) {
        expect(
          names.add(key.name),
          isTrue,
          reason:
              '"${key.name}" appears twice, and names are what a saved '
              'binding is restored by - one of the two would never load',
        );
      }
    });

    test('a gamepad button is one key per slot', () {
      expect(
        GamepadButton.values.length,
        GamepadKey.buttonCount,
        reason:
            'the stride between two slots is written out by hand '
            'because the id arithmetic has to be a constant expression - '
            'if it drifts from the button list, slot 2 starts overlapping '
            'slot 1',
      );
      for (var i = 0; i < GamepadButton.values.length; i++) {
        expect(
          GamepadButton.values[i].index,
          i,
          reason:
              'the index is the offset within a slot, and it is '
              'written by hand too',
        );
      }
      expect(
        InputKey.padUp.id,
        GamepadKey.firstId,
        reason: 'the gamepad block starts where the hand-written keys stop',
      );
      expect(
        InputKey.all.length,
        GamepadKey.firstId + GamepadKey.slotCount * GamepadKey.buttonCount,
      );
    });

    test('the same button on another slot is another bit', () {
      final slot0 = InputKey.padA;
      final slot2 = InputKey.padA(2);
      expect(slot2.id, slot0.id + 2 * GamepadKey.buttonCount);
      expect(slot2.slot, 2);
      expect(
        slot2.button,
        GamepadButton.a,
        reason: 'the tear-off changes the seat and nothing else',
      );
      expect(slot2 == slot0, isFalse);
    });

    test('a slotted key equals a directly built one', () {
      expect(
        InputKey.padLeft(1),
        InputKey.all[GamepadKey.firstId + GamepadKey.buttonCount + 2],
        reason:
            'a slot number known at runtime cannot produce a const, so '
            'these are two instances - and a rebinding screen comparing a '
            'saved key against a declared one needs them to compare equal '
            'anyway, which is why == is by id',
      );
      expect(InputKey.padLeft(1).hashCode, isNot(InputKey.padLeft.hashCode));
    });

    test('a gamepad key round-trips with its slot', () {
      final key = InputKey.padY(3);
      final restored = InputKey.fromJson(key.toJson());
      expect(restored, key);
      expect((restored as GamepadKey).slot, 3);

      expect(
        InputKey.padY.toJson().containsKey('slot'),
        isFalse,
        reason:
            'slot 0 is the default and the common case, so it stays out '
            'of the file - a single-player keybinding should not be full of '
            'zeroes',
      );
      expect(InputKey.fromJson(InputKey.padY.toJson()), InputKey.padY);
    });

    test('an impossible slot in a save file is refused', () {
      expect(
        () => InputKey.fromJson(<String, Object?>{
          'kind': 'gamepad',
          'name': 'padA',
          'slot': GamepadKey.slotCount,
        }),
        throwsFormatException,
        reason:
            'a seat that does not exist would resolve to a bit past the '
            'end of the block - better to say so than to read someone '
            'else\'s button',
      );
      expect(
        () => InputKey.fromJson(<String, Object?>{
          'kind': 'gamepad',
          'name': 'padA',
          'slot': 'two',
        }),
        throwsFormatException,
      );
    });

    test('mouse buttons are keys like any other', () {
      expect(InputKey.leftMouseButton, isA<MouseButtonKey>());
      expect(InputKey.w, isA<KeyboardKey>());
      expect(
        const TriggerBinding(.leftMouseButton),
        isA<InputBinding<bool>>(),
        reason:
            'a mouse button binds exactly like a keyboard key - both are '
            'one held-or-not bit, which is why the mouse is split in two: '
            'its buttons are keys, and only its position needed a binding of '
            'its own (MouseBinding, below)',
      );
    });
  });

  group('Vec2Binding composition', () {
    test('each key drives its own axis, with up as +y', () async {
      final game = await _boot(_InputGame());
      final movement = run.state.getSystem<_PlayerSystem>().movement;

      _pressAndStep(game, [InputKey.d]);
      expect(movement.value, Vector2(1, 0), reason: 'right is +x');

      _releaseAndStep(game, [InputKey.d]);
      _pressAndStep(game, [InputKey.a]);
      expect(movement.value, Vector2(-1, 0), reason: 'left is -x');

      _releaseAndStep(game, [InputKey.a]);
      _pressAndStep(game, [InputKey.w]);
      expect(
        movement.value,
        Vector2(0, 1),
        reason:
            'up is +y: world +y is up in both dimensions, so a binding '
            'named "up" has to increase it. Getting this backwards is the '
            'inversion that compiles - the player walks the wrong way and '
            'nothing reports an error',
      );

      _releaseAndStep(game, [InputKey.w]);
      _pressAndStep(game, [InputKey.s]);
      expect(movement.value, Vector2(0, -1), reason: 'down is -y');
    });

    test('diagonals add, and are deliberately not normalized', () async {
      final game = await _boot(_InputGame());
      final movement = run.state.getSystem<_PlayerSystem>().movement;

      _pressAndStep(game, [InputKey.w, InputKey.d]);
      expect(
        movement.value,
        Vector2(1, 1),
        reason:
            'the two axes compose; normalizing here would be a policy '
            'decision the binding has no business making for the game',
      );
      expect(movement.value.length, closeTo(1.4142135, 1e-6));
    });

    test('opposing keys cancel to exactly zero', () async {
      final game = await _boot(_InputGame());
      final movement = run.state.getSystem<_PlayerSystem>().movement;

      _pressAndStep(game, [InputKey.a, InputKey.d]);
      expect(
        movement.value,
        Vector2(0, 0),
        reason:
            'holding both horizontal keys must stand still, not pick '
            'whichever was pressed last - the axis is a difference, not a '
            'priority list',
      );

      _pressAndStep(game, [InputKey.w, InputKey.s]);
      expect(
        movement.value,
        Vector2(0, 0),
        reason: 'and the same on the vertical axis, with all four held',
      );
    });

    test(
      'the value is one Vector2 the action owns, mutated in place',
      () async {
        final game = await _boot(_InputGame());
        final movement = run.state.getSystem<_PlayerSystem>().movement;

        _pressAndStep(game, [InputKey.d]);
        final first = movement.value;
        _releaseAndStep(game, [InputKey.d]);
        _pressAndStep(game, [InputKey.a]);

        expect(
          identical(movement.value, first),
          isTrue,
          reason:
              'a fresh Vector2 per read (or per resolution) would be a '
              'heap allocation per action per tick - the no-allocation rule. The '
              'reference is stable and its contents are what change',
        );
        expect(
          first,
          Vector2(-1, 0),
          reason:
              'and the reference a caller kept from last tick now reads '
              'this tick\'s value, which is exactly why the doc says not to '
              'hold it',
        );
      },
    );
  });

  group('edge detection', () {
    test('wasPressedThisFrame is true on exactly one resolution', () async {
      final game = await _boot(_InputGame());
      final skill = run.state.getSystem<_PlayerSystem>().triggerSkill;

      expect(
        skill.wasPressedThisFrame,
        isFalse,
        reason: 'nothing has resolved yet, so no edge has happened',
      );

      _pressAndStep(game, [InputKey.spacebar]);
      expect(skill.value, isTrue);
      expect(
        skill.wasPressedThisFrame,
        isTrue,
        reason: 'the raw state went from up to down across this resolution',
      );
      expect(skill.wasReleasedThisFrame, isFalse);

      run.state.runFixedStep();
      expect(skill.value, isTrue, reason: 'still held');
      expect(
        skill.wasPressedThisFrame,
        isFalse,
        reason:
            'held across ticks is not a press - an edge is a change, '
            'and nothing changed on this resolution',
      );
    });

    test('wasReleasedThisFrame mirrors it on the way up', () async {
      final game = await _boot(_InputGame());
      final skill = run.state.getSystem<_PlayerSystem>().triggerSkill;

      _pressAndStep(game, [InputKey.spacebar]);
      run.state.runFixedStep();

      _releaseAndStep(game, [InputKey.spacebar]);
      expect(skill.value, isFalse);
      expect(skill.wasReleasedThisFrame, isTrue);
      expect(skill.wasPressedThisFrame, isFalse);

      run.state.runFixedStep();
      expect(
        skill.wasReleasedThisFrame,
        isFalse,
        reason:
            'and a release, like a press, is true for exactly the one '
            'resolution it happened on',
      );
      expect(skill.wasPressedThisFrame, isFalse);
    });

    test(
      'a press and a release inside one resolution collapse to nothing',
      () async {
        final game = await _boot(_InputGame());
        final skill = run.state.getSystem<_PlayerSystem>().triggerSkill;

        game.inputDevice!
          ..press(InputKey.spacebar)
          ..release(InputKey.spacebar);
        run.state.runFixedStep();

        expect(skill.wasPressedThisFrame, isFalse);
        expect(skill.wasReleasedThisFrame, isFalse);
        expect(
          events,
          isEmpty,
          reason:
              'edges are a diff of raw state against the previous '
              'resolution, so a tap shorter than a fixed step is never seen. '
              'Documented on Input rather than papered over with sticky bits',
        );
      },
    );
  });

  group('pressed / released streams', () {
    test(
      'each fires on its own edge and never both on one resolution',
      () async {
        final game = await _boot(_InputGame());

        _pressAndStep(game, [InputKey.spacebar]);
        expect(events, [
          'skill pressed true',
        ], reason: 'exactly one event, and it carries the value at the edge');

        run.state.runFixedStep();
        expect(
          events,
          ['skill pressed true'],
          reason:
              'a held key produces no further edges, so a quiet '
              'resolution is genuinely quiet',
        );

        _releaseAndStep(game, [InputKey.spacebar]);
        expect(
          events,
          ['skill pressed true', 'skill released false'],
          reason:
              'released fires once, with the post-edge value - the two '
              'streams are separate precisely so a listener never has to work '
              'out which edge it just saw',
        );
      },
    );

    test(
      'a vector action fires on actuation, not on every value change',
      () async {
        final game = await _boot(_InputGame());

        _pressAndStep(game, [InputKey.d]);
        expect(events, ['move pressed 1,0']);

        // Direction changes, but the action never stops being held.
        _pressAndStep(game, [InputKey.w]);
        _releaseAndStep(game, [InputKey.d]);
        expect(
          events,
          ['move pressed 1,0'],
          reason:
              'the value went (1,0) -> (1,-1) -> (0,-1) without the '
              'action ever being released, and a "value changed" callback '
              'would have fired three times for one continuous input',
        );

        _releaseAndStep(game, [InputKey.w]);
        expect(events, [
          'move pressed 1,0',
          'move released 0,0',
        ], reason: 'letting go of the last held key is the release edge');
      },
    );

    test('an unbound action fires nothing at all', () async {
      final game = await _boot(_InputGame());
      final system = run.state.getSystem<_PlayerSystem>();

      // Every key on the keyboard, held for two resolutions.
      for (final key in InputKey.all) {
        game.inputDevice!.press(key);
      }
      run.state.runFixedStep();
      run.state.runFixedStep();

      expect(
        events.where((e) => e.startsWith('ping')),
        isEmpty,
        reason:
            'nothing produces this action\'s value, so there is no edge '
            'for it to have - an unbound action is a declared, legitimate '
            'state, not a half-declaration that should misbehave',
      );
      expect(system.ping.wasPressedThisFrame, isFalse);
      expect(system.ping.value, isFalse, reason: 'it reads its default');
    });

    test('a listener can be removed with -=', () async {
      final game = await _boot(_InputGame());
      final skill = run.state.getSystem<_PlayerSystem>().triggerSkill;
      void extra(InputEvent<bool> event) => events.add('extra');
      skill.pressed += extra;

      _pressAndStep(game, [InputKey.spacebar]);
      expect(events, ['skill pressed true', 'extra']);

      skill.pressed -= extra;
      _releaseAndStep(game, [InputKey.spacebar]);
      _pressAndStep(game, [InputKey.spacebar]);
      expect(events, [
        'skill pressed true',
        'extra',
        'skill released false',
        'skill pressed true',
      ]);
    });

    test('assigning some other stream is a programmer error', () async {
      await _boot(_InputGame());
      final system = run.state.getSystem<_PlayerSystem>();
      expect(
        () => system.triggerSkill.pressed = system.ping.pressed,
        throwsAssertionError,
        reason:
            'the setter exists only so `+=` compiles; a real assignment '
            'would silently drop every listener already subscribed',
      );
    });
  });

  group('rebinding', () {
    test('direct assignment takes effect on the next resolution', () async {
      final game = await _boot(_InputGame());
      final skill = run.state.getSystem<_PlayerSystem>().triggerSkill;

      skill.binding = const TriggerBinding(.enter);
      _pressAndStep(game, [InputKey.spacebar]);
      expect(
        skill.value,
        isFalse,
        reason: 'the old key is nothing to this action any more',
      );
      expect(events, isEmpty);

      _pressAndStep(game, [InputKey.enter]);
      expect(skill.value, isTrue);
      expect(skill.wasPressedThisFrame, isTrue);
      expect(events, ['skill pressed true']);
    });

    test('copyWith tweaks one axis and leaves the rest alone', () async {
      final game = await _boot(_InputGame());
      final movement = run.state.getSystem<_PlayerSystem>().movement;

      // `movement.binding` is statically an InputBinding<Vector2>, so the
      // concrete type has to be named to reach copyWith - see the note in
      // InputBinding's doc.
      movement.binding = (movement.binding! as Vec2Binding).copyWith(
        right: .arrowRight,
      );

      _pressAndStep(game, [InputKey.d]);
      expect(
        movement.value,
        Vector2(0, 0),
        reason: 'the axis that was replaced no longer answers to its old key',
      );

      _pressAndStep(game, [InputKey.arrowRight, InputKey.w]);
      expect(
        movement.value,
        Vector2(1, 1),
        reason:
            'the new right key drives x, and the three axes copyWith '
            'did not mention still drive what they always did',
      );
    });

    test('rebinding while held releases on the next resolution', () async {
      final game = await _boot(_InputGame());
      final skill = run.state.getSystem<_PlayerSystem>().triggerSkill;

      _pressAndStep(game, [InputKey.spacebar]);
      expect(events, ['skill pressed true']);

      skill.binding = const TriggerBinding(.enter);
      run.state.runFixedStep();
      expect(
        events,
        ['skill pressed true', 'skill released false'],
        reason:
            'the action is no longer held, and reporting that keeps '
            'every pressed paired with a released',
      );
    });

    test('an action declared unbound can be bound at runtime', () async {
      final game = await _boot(_InputGame());
      final system = run.state.getSystem<_PlayerSystem>();

      system.ping.binding = const TriggerBinding(.f5);
      _pressAndStep(game, [InputKey.f5]);
      expect(system.ping.value, isTrue);
      expect(
        events,
        ['ping pressed'],
        reason:
            'binding is the whole runtime half of the input system: an '
            'action nobody has assigned a key to yet is normal, and this is '
            'how a rebinding screen finishes the job',
      );

      // And a vector action, which needs storage created at bind time rather
      // than at declare time.
      system.aim.binding = const Vec2Binding(
        up: .arrowUp,
        down: .arrowDown,
        left: .arrowLeft,
        right: .arrowRight,
      );
      _pressAndStep(game, [InputKey.arrowLeft]);
      expect(
        system.aim.value,
        Vector2(-1, 0),
        reason:
            'an action bound after declaration still gets its own '
            'mutable storage rather than writing into the shared default',
      );
      expect(
        run.state.getSystem<_PlayerSystem>().movement.value,
        isNot(same(system.aim.value)),
        reason: 'and it is its own storage, not another action\'s',
      );
    });

    test('unbinding stops it dead and fires nothing', () async {
      final game = await _boot(_InputGame());
      final skill = run.state.getSystem<_PlayerSystem>().triggerSkill;

      _pressAndStep(game, [InputKey.spacebar]);
      events.clear();

      skill.binding = null;
      run.state.runFixedStep();
      expect(skill.value, isFalse, reason: 'back to the declared default');
      expect(
        events,
        isEmpty,
        reason:
            'an unbound action fires nothing - stated on Input.binding '
            'rather than quietly synthesizing a release nobody asked for',
      );
    });
  });

  group('default values', () {
    test('the Game ships defaults for bool and Vector2', () async {
      await _boot(_InputGame());
      final system = run.state.getSystem<_PlayerSystem>();

      expect(
        system.ping.value,
        isFalse,
        reason: 'Game.describeInputs registers hasDefaultValue<bool>(false)',
      );
      expect(
        system.aim.value,
        Vector2.zero(),
        reason:
            'and hasDefaultValue<Vector2>(Vector2.zero()), which is '
            'what makes the two shipped binding types work with no ceremony',
      );
    });

    test('an action with no default anywhere throws, naming itself', () async {
      final game = await _boot(_NoSuperGame());

      Object? thrown;
      try {
        game.orphan.value;
      } catch (error) {
        thrown = error;
      }
      expect(
        thrown,
        isStateError,
        reason:
            'zero and false are real values to a game, so inventing one '
            'here would turn a forgotten declaration into a number that is '
            'quietly wrong',
      );
      expect(
        thrown.toString(),
        allOf(
          contains('#0'),
          contains('_NoSuperGame'),
          contains('Input<bool>'),
        ),
        reason:
            'the message has to identify which action - there is no '
            'user-supplied name (rule 6 says the field name is the name, and '
            'a field name is not something the framework can see), so the '
            'declaring type and declaration index are what it can offer',
      );
    });

    test('a per-action default is enough on its own', () async {
      final game = await _boot(_NoSuperGame());
      expect(
        game.ownDefault.value,
        isTrue,
        reason:
            'declared with has<bool>(null, true) - the action\'s own '
            'default needs no type-level fallback behind it',
      );
    });

    test(
      'forgetting super.describeInputs loses the shipped defaults',
      () async {
        final game = await _boot(_NoSuperGame());
        expect(
          () => game.orphan.value,
          throwsStateError,
          reason:
              'worth its own test precisely because it is silent: nothing '
              'fails at boot, and the game runs until something reads an '
              'unbound action. That is what @mustCallSuper is guarding',
        );
      },
    );

    test('a per-action default wins over the type-level one', () async {
      final game = await _boot(_PrecedenceGame());
      expect(game.loud.value, isTrue, reason: 'its own default');
      expect(
        game.quiet.value,
        isFalse,
        reason: 'no default of its own, so the type-level fallback applies',
      );
    });

    test('one descriptor is shared, so a system can register a type default '
        'an earlier declaration uses', () async {
      final game = await _boot(_SharedDescriptorGame());
      expect(
        game.throttle.value,
        0.25,
        reason:
            'the action was declared by the Game, before the system '
            'that registered the double default even ran - defaults are '
            'matched at seal(), once every source has spoken',
      );
    });

    test('registering a type default twice fails at declare time', () async {
      final game = _DuplicateDefaultGame();
      await expectLater(
        Game.startInline(game),
        throwsStateError,
        reason:
            'two sources each setting the fallback for one type disagree, '
            'and "last one wins" would make the answer depend on system '
            'declaration order - so it is an error, not an overwrite',
      );
    });
  });

  group('resolution', () {
    test('runs before any system, so a tick sees this tick\'s input', () async {
      final game = await _boot(_InputGame());
      final system = run.state.getSystem<_PlayerSystem>();

      _pressAndStep(game, [InputKey.d, InputKey.spacebar]);
      expect(system.ticks, 1);
      expect(
        system.lastSeenX,
        1,
        reason:
            'the system read movement.value during its own '
            'onFixedUpdate and got the state the player was in when this '
            'tick started - not last tick\'s',
      );
      expect(
        system.lastSeenPressed,
        isTrue,
        reason:
            'and saw the press edge on the tick it happened, which is '
            'only true because resolution runs at the top of runFixedStep',
      );
    });

    test(
      'a write landing mid-tick cannot change what the tick resolved',
      () async {
        final game = await _boot(_InputGame());
        final device = game.inputDevice!;

        device.setViewSize(800, 600);
        run.state.runFixedStep();
        expect(game.viewWidth, 800);

        // `Game.viewWidth` reads `InputState` *live*, so this is the path any
        // system takes when it asks the view size mid-tick - CameraProjection
        // and MousePickingSystem both do. Meanwhile the Flutter isolate keeps
        // publishing: InputDevice publishes on every change, and three of them
        // walk TripleBuffer's slots all the way back around to the one this
        // tick attached to.
        device
          ..setViewSize(801, 600)
          ..setViewSize(802, 600)
          ..setViewSize(803, 600);

        expect(
          game.viewWidth,
          800,
          reason:
              'the tick copied its 40 bytes at the top of runFixedStep, so '
              'what it resolved stays put for the whole tick. Holding the slot '
              'pointer instead, the third publish rewrites the very slot being '
              'read and this reports 803 - a value from a tick that has not '
              'started yet',
        );

        run.state.runFixedStep();
        expect(
          game.viewWidth,
          803,
          reason:
              'and the next tick picks up everything that landed in '
              'between - the copy is per tick, not a subscription',
        );
      },
    );

    test(
      'a game whose device nobody writes to reads defaults forever',
      () async {
        await _boot(_InputGame());
        final system = run.state.getSystem<_PlayerSystem>();

        for (var i = 0; i < 5; i++) {
          run.state.runFixedStep();
        }
        expect(system.movement.value, Vector2(0, 0));
        expect(system.triggerSkill.value, isFalse);
        expect(
          events,
          isEmpty,
          reason:
              'a headless game has no keyboard attached, and reporting '
              'nothing held is the truth rather than a bug',
        );
      },
    );

    test('the device is on the copy Flutter runs on', () async {
      final game = await _boot(_InputGame());
      expect(
        game.inputDevice,
        isNotNull,
        reason:
            'inline: one copy does both jobs, so it owns both ends of '
            'the raw block',
      );
      expect(game.inputActionCount, 4);
      game.inputDevice!.press(InputKey.w);
      expect(game.inputDevice!.isDown(InputKey.w), isTrue);
      expect(game.inputDevice!.isDown(InputKey.s), isFalse);
    });

    test('the write end goes away with the storage at stop()', () async {
      final game = _InputGame();
      run = await Game.startInline(game);
      expect(game.inputDevice, isNotNull);
      await run.stop();
      expect(
        game.inputDevice,
        isNull,
        reason:
            'there is nowhere to put a keystroke once the buffer it '
            'would be written into has been freed',
      );
    });
  });

  group('declaration window', () {
    test('declaring an input after boot is refused', () async {
      final game = await _boot(_InputGame());
      // The *real* descriptor, kept from the boot pass.
      final descriptor = game.capturedDescriptor!;
      expect(() => descriptor.has<bool>(), throwsStateError);
      expect(
        () => descriptor.has<bool>(const TriggerBinding(.f1)),
        throwsStateError,
      );
      expect(() => descriptor.hasDefaultValue<int>(0), throwsStateError);
      expect(
        game.inputActionCount,
        4,
        reason:
            'and nothing was appended to the declared set - both copies '
            'must end up with the same one, and the other one is no longer '
            'listening',
      );
    });
  });

  group('serialization', () {
    test('an InputKey round-trips by name', () {
      for (final key in <InputKey>[
        InputKey.w,
        InputKey.spacebar,
        InputKey.numpadEnter,
        InputKey.leftMouseButton,
        InputKey.forwardMouseButton,
      ]) {
        final json = key.toJson();
        expect(
          InputKey.fromJson(json),
          same(key),
          reason:
              'keys are canonical const values, so a restored key is '
              'the very same object - "${key.name}"',
        );
        expect(json['name'], key.name);
      }
    });

    test('a key is restored by name, not by id', () {
      // The id is a bit position that both isolate copies agree on because
      // they run the same build; a save file outlives the build.
      expect(
        InputKey.w.toJson().containsKey('id'),
        isFalse,
        reason:
            'writing the bit index would make inserting a key in the '
            'middle of the table silently rebind every saved keybinding',
      );
    });

    test('TriggerBinding round-trips', () {
      const binding = TriggerBinding(.enter);
      expect(TriggerBinding.fromJson(binding.toJson()), binding);
      expect(
        TriggerBinding.fromJson(
          const TriggerBinding(.rightMouseButton).toJson(),
        ),
        const TriggerBinding(.rightMouseButton),
        reason: 'a mouse button survives the trip like any other key',
      );
    });

    test('Vec2Binding round-trips all four axes', () {
      const binding = Vec2Binding(up: .w, down: .s, left: .a, right: .d);
      final restored = Vec2Binding.fromJson(binding.toJson());
      expect(restored, binding);
      expect(
        restored.right,
        same(InputKey.d),
        reason:
            'each axis comes back as the key it went in as, in its own '
            'slot - a transposition here would be invisible to a `==` that '
            'only compared the set of keys',
      );
    });

    test('a restored binding is assignable straight onto an action', () async {
      final game = await _boot(_InputGame());
      final skill = run.state.getSystem<_PlayerSystem>().triggerSkill;
      // The whole save/restore story, as a user writes it: their own JSON,
      // their own key, no framework-owned format and nothing to register.
      final saved = <String, Object?>{'skill': skill.binding!.toJson()};
      skill.binding = null;
      skill.binding = TriggerBinding.fromJson(
        saved['skill']! as Map<String, Object?>,
      );

      _pressAndStep(game, [InputKey.spacebar]);
      expect(
        skill.value,
        isTrue,
        reason:
            'a keybinding is data: it survives a round trip through the '
            'game\'s own save file and works again on the other side',
      );
    });

    test('unparseable JSON says what it wanted', () {
      expect(
        () => InputKey.fromJson(<String, Object?>{
          'kind': 'gamepad',
          'name': 'a',
        }),
        throwsFormatException,
      );
      expect(
        () => InputKey.fromJson(<String, Object?>{
          'kind': 'keyboard',
          'name': 'nope',
        }),
        throwsFormatException,
      );
      expect(
        () => TriggerBinding.fromJson(<String, Object?>{'key': 'w'}),
        throwsFormatException,
        reason:
            'a bare string where a serialized key belongs is a save file '
            'from a different shape, and saying so beats a bare cast error',
      );
    });
  });

  group('pointer position', () {
    test('screen and view coordinates cross independently', () async {
      final game = await _boot(_MouseGame());
      final cursor = run.state.getSystem<_CursorSystem>().cursor;
      final device = game.inputDevice!;

      // A view inset from the window's top-left: the two spaces differ by
      // exactly that inset, which is the whole reason both are carried.
      device.setViewSize(800, 600);
      device.movePointer(screenX: 130, screenY: 240, viewX: 30, viewY: 40);
      run.state.runFixedStep();

      expect(
        cursor.value.screenSpace,
        Vector2(130, 240),
        reason:
            'window coordinates, for anything that has to line up with '
            'the rest of the app',
      );
      expect(
        cursor.value.viewSpace,
        Vector2(30, 40),
        reason:
            'the same pointer relative to the view - captured on the '
            'Flutter side rather than reconstructed here, which would need '
            'the view origin on the wire too',
      );
      expect(cursor.value.viewSize, Vector2(800, 600));
    });

    test('a real hover event fills both spaces from one event', () async {
      final game = await _boot(_MouseGame());
      final cursor = run.state.getSystem<_CursorSystem>().cursor;

      // How Flutter itself produces a local position: the event is
      // transformed by the receiving render object's own transform, so a
      // GameView whose top-left sits at (200, 200) in the window sees this.
      game.inputDevice!.handlePointerEvent(
        const PointerHoverEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(300, 210),
        ).transformed(Matrix4.translationValues(-200, -200, 0)),
      );
      run.state.runFixedStep();

      expect(
        cursor.value.screenSpace,
        Vector2(300, 210),
        reason: 'PointerEvent.position is window space',
      );
      expect(
        cursor.value.viewSpace,
        Vector2(100, 10),
        reason:
            'PointerEvent.localPosition is already relative to the '
            'widget the Listener wraps, which is the GameView - this is the '
            'path GameView actually drives, and movePointer only exists so '
            'a host with no widget can drive the same one',
      );
    });

    test('a touch event moves nothing', () async {
      final game = await _boot(_MouseGame());
      final cursor = run.state.getSystem<_CursorSystem>().cursor;

      game.inputDevice!.handlePointerEvent(
        const PointerHoverEvent(position: Offset(50, 50)),
      );
      run.state.runFixedStep();

      expect(
        cursor.value.screenSpace,
        Vector2.zero(),
        reason:
            'the default kind here is touch, and a finger is not a '
            'mouse: letting one move the cursor would make a tap read as a '
            'hover that never ends',
      );
    });

    test('the position is one instance, mutated in place', () async {
      final game = await _boot(_MouseGame());
      final cursor = run.state.getSystem<_CursorSystem>().cursor;

      game.inputDevice!.movePointer(screenX: 1, screenY: 2);
      run.state.runFixedStep();
      final first = cursor.value;
      final firstVector = first.viewSpace;

      game.inputDevice!.movePointer(screenX: 7, screenY: 8);
      run.state.runFixedStep();

      expect(
        identical(cursor.value, first),
        isTrue,
        reason:
            'reading a pointer sixty times a second must not allocate '
            '(the no-allocation rule) - the action owns one CursorPosition for its '
            'whole life, the same way Input<Vector2> owns one vector',
      );
      expect(
        identical(cursor.value.viewSpace, firstVector),
        isTrue,
        reason: 'and the vectors inside it are owned too, not replaced',
      );
      expect(
        cursor.value.viewSpace,
        Vector2(7, 8),
        reason:
            'mutated in place still means the values update - and '
            'omitting viewX/viewY means "the view is the window"',
      );
    });

    test('an unmoved pointer holds its last position', () async {
      final game = await _boot(_MouseGame());
      final cursor = run.state.getSystem<_CursorSystem>().cursor;

      game.inputDevice!.movePointer(screenX: 9, screenY: 9, viewX: 5, viewY: 5);
      run.state.runFixedStep();
      run.state.runFixedStep();

      expect(
        cursor.value.viewSpace,
        Vector2(5, 5),
        reason:
            'a pointer that stopped moving is still somewhere - unlike '
            'a key there is no released state to fall back to, so the last '
            'published position has to keep resolving',
      );
    });

    test('moving fires no press or release edge', () async {
      final game = await _boot(_MouseGame());

      game.inputDevice!.movePointer(screenX: 1, screenY: 1);
      run.state.runFixedStep();
      game.inputDevice!.movePointer(screenX: 500, screenY: 500);
      run.state.runFixedStep();

      expect(
        run.state.getSystem<_CursorSystem>().cursor.wasPressedThisFrame,
        isFalse,
      );
      expect(
        events,
        isEmpty,
        reason:
            'MouseBinding.isActuated is always false, because a '
            'position has no pressed state to detect an edge against. Bind '
            'a button if you want the click - which is exactly what makes '
            'leftMouseButton an ordinary TriggerBinding instead of part of '
            'this',
      );
    });

    test('a button on the same mouse is an ordinary trigger', () async {
      final game = await _boot(_MouseGame());
      final click = run.state.getSystem<_CursorSystem>().click;

      game.inputDevice!.press(InputKey.leftMouseButton);
      run.state.runFixedStep();
      expect(click.value, isTrue);
      expect(click.wasPressedThisFrame, isTrue);

      game.inputDevice!.release(InputKey.leftMouseButton);
      run.state.runFixedStep();
      expect(click.wasReleasedThisFrame, isTrue);
      expect(
        events,
        <String>['click pressed', 'click released'],
        reason:
            'the button half of the mouse edge-detects exactly like a '
            'key, and the position half stays silent through both',
      );
    });

    test('before any pointer event everything reads zero', () async {
      await _boot(_MouseGame());
      run.state.runFixedStep();

      final position = run.state.getSystem<_CursorSystem>().cursor.value;
      expect(position.screenSpace, Vector2.zero());
      expect(position.viewSpace, Vector2.zero());
      expect(
        position.viewSize,
        Vector2.zero(),
        reason:
            'a game with no widget has no view to measure, and zero is '
            'the honest answer - a consumer dividing by it gets a NaN it '
            'can see, rather than a plausible wrong number from a size the '
            'engine invented',
      );
    });

    test('the view size publishes only when it actually changes', () async {
      final game = await _boot(_MouseGame());
      final cursor = run.state.getSystem<_CursorSystem>().cursor;
      final device = game.inputDevice!;

      device.setViewSize(1024, 768);
      device.movePointer(screenX: 4, screenY: 4);
      run.state.runFixedStep();
      expect(cursor.value.viewSize, Vector2(1024, 768));

      // A rebuild at the same size: LayoutBuilder reports every layout, so
      // this is the common case, and it must not burn a publish - a
      // TripleBuffer only guarantees a reader against the writer publishing
      // twice underneath it, and a resize storm of identical sizes would eat
      // that margin for nothing.
      final quiet = device.publishedAddress;
      for (var i = 0; i < 20; i++) {
        device.setViewSize(1024, 768);
        device.movePointer(screenX: 4, screenY: 4);
      }
      expect(
        device.publishedAddress,
        quiet,
        reason:
            'the published slot only moves on a publish, so twenty '
            'writes that changed nothing not moving it is the whole claim',
      );

      device.setViewSize(1024, 769);
      expect(
        device.publishedAddress,
        isNot(quiet),
        reason:
            'and one real change still publishes - a check that only '
            'proves nothing publishes would pass on a device that never '
            'published at all',
      );

      run.state.runFixedStep();
      expect(cursor.value.viewSize, Vector2(1024, 769));
      expect(cursor.value.screenSpace, Vector2(4, 4));
    });

    test(
      'a size that survives the float32 round-trip still publishes',
      () async {
        final game = await _boot(_MouseGame());
        final cursor = run.state.getSystem<_CursorSystem>().cursor;

        // 0.1 is not representable in float32, so the mirror stores something
        // slightly different from what was passed. The change check compares
        // *after* that rounding, which is what keeps a genuine change from
        // being mistaken for a no-op - and vice versa.
        game.inputDevice!.movePointer(screenX: 0.1, screenY: 0.2);
        run.state.runFixedStep();
        expect(cursor.value.screenSpace.x, closeTo(0.1, 1e-6));
        expect(cursor.value.screenSpace.y, closeTo(0.2, 1e-6));
      },
    );

    test('MouseBinding round-trips through JSON', () {
      const binding = MouseBinding();
      expect(
        MouseBinding.fromJson(binding.toJson()),
        binding,
        reason:
            'there is no state to restore, but a rebinding screen has '
            'to serialize every binding uniformly rather than '
            'special-casing the one that happens to be empty',
      );
      expect(binding.copyWith(), binding);
      expect(binding.hashCode, const MouseBinding().hashCode);
    });
  });

  // #160. An OS that takes focus away sends no key-up, so the block goes on
  // reporting the press for as long as the game runs. The seams that call
  // this - the visibility observer and the last view going away - are pinned
  // in game_widget_test.dart, because both need a widget tree; what is here
  // is what `releaseAll` itself does to the block.
  //
  // Every test below asserts the held state *before* the release. One that
  // checked only the released half would pass against a device nothing was
  // ever pressed on, which is the whole failure it exists to catch.
  group('releaseAll', () {
    test('a key held across it stops being held', () async {
      final game = await _boot(_InputGame());
      final movement = run.state.getSystem<_PlayerSystem>().movement;
      final device = game.inputDevice!;

      _pressAndStep(game, [InputKey.w]);
      expect(device.isDown(InputKey.w), isTrue);
      expect(
        movement.value,
        Vector2(0, 1),
        reason:
            'the control - walking north has to be true first, or the '
            'zero afterwards says nothing about anything being released',
      );

      device.releaseAll();
      run.state.runFixedStep();

      expect(device.isDown(InputKey.w), isFalse);
      expect(
        movement.value,
        Vector2.zero(),
        reason:
            'and the game-side resolution follows, which is the half a '
            'player would notice: the character stops walking',
      );
    });

    test('a mouse button held across it stops being held', () async {
      final game = await _boot(_MouseGame());
      final click = run.state.getSystem<_CursorSystem>().click;
      final device = game.inputDevice!;

      // Through the real pointer path rather than `press`, so what is being
      // cleared is a bit `handlePointerEvent` set from a button mask - the
      // way it actually gets set with a finger on a real mouse.
      device.handlePointerEvent(
        const PointerDownEvent(
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryMouseButton,
        ),
      );
      run.state.runFixedStep();
      expect(click.value, isTrue);

      device.releaseAll();
      run.state.runFixedStep();

      expect(click.value, isFalse);
      expect(device.isDown(InputKey.leftMouseButton), isFalse);
    });

    test('a pad button goes too, aggregate slot and all', () async {
      final game = await _boot(_InputGame());
      final device = game.inputDevice!;

      device.setGamepadButton(1, GamepadButton.a, true);
      expect(
        device.isDown(InputKey.padA),
        isTrue,
        reason:
            'slot 0 is the OR of the real slots, so a press on seat one '
            'shows up here - and it is the bit a single-player game binds',
      );

      device.releaseAll();

      expect(device.isDown(InputKey.padA), isFalse);
      expect(
        device.isDown(InputKey.padA(1)),
        isFalse,
        reason:
            'the seat itself, not just the aggregate - leaving the real '
            'bit set would let the next unrelated pad event recompute the '
            'OR back to held',
      );
    });

    test('the cursor does not jump to the corner', () async {
      final game = await _boot(_MouseGame());
      final cursor = run.state.getSystem<_CursorSystem>().cursor;
      final device = game.inputDevice!;

      device.setViewSize(800, 600);
      device.movePointer(screenX: 130, screenY: 240, viewX: 30, viewY: 40);
      device.press(InputKey.leftMouseButton);
      run.state.runFixedStep();
      expect(cursor.value.screenSpace, Vector2(130, 240));

      device.releaseAll();
      run.state.runFixedStep();

      expect(device.isDown(InputKey.leftMouseButton), isFalse);
      expect(
        cursor.value.screenSpace,
        Vector2(130, 240),
        reason:
            'where the cursor is is not something anyone is holding '
            'down, and zeroing it would teleport whatever is aiming at it '
            'to the window corner - a visible jump bought for nothing',
      );
      expect(cursor.value.viewSize, Vector2(800, 600));
    });

    test('releasing nothing costs no publish', () async {
      final game = await _boot(_MouseGame());
      final device = game.inputDevice!;

      final quiet = device.publishedAddress;
      device.releaseAll();
      expect(
        device.publishedAddress,
        quiet,
        reason:
            'the observer sees a hidden app twice on the way down, so a '
            'release that always published would put two publishes on a '
            'path where nothing changed',
      );

      device.press(InputKey.w);
      final afterPress = device.publishedAddress;
      device.releaseAll();
      expect(
        device.publishedAddress,
        isNot(afterPress),
        reason:
            'and one that had something to clear still publishes - a '
            'check that only proved nothing publishes would pass on a '
            'releaseAll with no body at all',
      );
    });
  });
}

/// Own-default-versus-type-default precedence, with both on the same `Game`
/// so nothing about declaration order between sources is involved.
class _PrecedenceGame extends Game {
  @override
  int get pageSize => 4096;

  late final Input<bool> loud;
  late final Input<bool> quiet;

  @override
  GameState createState() => _PrecedenceState();

  @override
  void describeInputs(InputDescriptor input) {
    super.describeInputs(input);
    loud = input.has<bool>(null, true);
    quiet = input.has<bool>();
  }
}

class _PrecedenceState extends GameState<_PrecedenceGame> {}
