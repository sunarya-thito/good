import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/archetype.dart';
import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/event/state.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/input.dart';
import 'package:good/src/input/input_binding.dart';
import 'package:good/src/input/input_key.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/system.dart';

// `Game.start` and `Game.startInline` take a constructor, so the framework
// builds the game and two declaration windows are open while its fields
// initialise: the state descriptor `Channel.*` reads and the input registry
// `Input.of` reads. What this file pins is that a declaration made through a
// field and the same declaration made through the matching `describeX` hook
// are one declaration - same set, same order, same values - that the `late`
// spelling of either cannot quietly get in, and that a `Game` built while
// somebody else's window is open is refused rather than declaring into it.

abstract class _BareGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  @override
  GameState createState() => _BareState();
}

class _BareState extends GameState<Game> {
  @override
  void onMounted() {}
}

// --- the same three channels, declared each way ---------------------------

class _FieldGame extends _BareGame {
  final score = Channel.int32(3);
  final health = Channel.float64(1.5);
  final alive = Channel.boolean(true);
}

class _HookGame extends _BareGame {
  late final StateChannel<int> score;
  late final StateChannel<double> health;
  late final StateChannel<bool> alive;

  @override
  void describeState(StateDescriptor descriptor) {
    super.describeState(descriptor);
    score = descriptor.hasInt32(3);
    health = descriptor.hasFloat64(1.5);
    alive = descriptor.hasBool(true);
  }
}

/// Both ways at once, with distinct initial values so the two are told apart
/// by what they hold rather than by which object they came off.
class _MixedGame extends _BareGame {
  final fromField = Channel.int32(11);

  late final StateChannel<int> fromHook;

  @override
  void describeState(StateDescriptor descriptor) {
    super.describeState(descriptor);
    fromHook = descriptor.hasInt32(22);
  }
}

// --- an input declared each way -------------------------------------------

class _FieldInputGame extends _BareGame {
  final fire = Input.of(const TriggerBinding(InputKey.spacebar));
  final unbound = Input.of<bool>();
}

class _HookInputGame extends _BareGame {
  late final Input<bool> fire;
  late final Input<bool> unbound;

  @override
  void describeInputs(InputDescriptor input) {
    super.describeInputs(input);
    fire = input.has<bool>(const TriggerBinding(InputKey.spacebar));
    unbound = input.has<bool>();
  }
}

/// The one shape with no field form at all: `hasDefaultValue` hands nothing
/// back, so there is nothing to hold. It keeps `describeInputs` alive on a
/// `Game` however much else moves onto fields.
class _MixedInputGame extends _BareGame {
  final throttleField = Input.of<double>();

  late final Input<double> throttleHook;

  @override
  void describeInputs(InputDescriptor input) {
    super.describeInputs(input);
    input.hasDefaultValue<double>(0.75);
    throttleHook = input.has<double>();
  }
}

// --- the eager guard ------------------------------------------------------

/// A game whose `late` declarations are written **ahead** of the eager ones.
///
/// That ordering is the point. If a `late` initialiser ran where it is
/// written rather than on first read, `lazyChannel` and `lazyInput` would be
/// the first things in their lists, and the assertions below would see them
/// there.
class _LateGame extends _BareGame {
  late final lazyChannel = Channel.int32(99);

  late final lazyInput = Input.of(const TriggerBinding(InputKey.escape));

  final eagerChannel = Channel.int32(5);

  final eagerInput = Input.of(const TriggerBinding(InputKey.spacebar));
}

// --- the wrong-collection hazards -----------------------------------------

/// Declares one of each, so wherever it is built it leaves a trace.
class _Nested extends _BareGame {
  final score = Channel.int32(7);
  final fire = Input.of(const TriggerBinding(InputKey.spacebar));
}

/// A game holding a game. The inner one's fields run while *this* game's
/// windows are open, so without the guard the inner declarations land here.
class _NestingGame extends _BareGame {
  final own = Channel.int32(1);
  final inner = _Nested();
}

/// A game with only an input, built inside a system's constructor - where the
/// system's registry is open and no state descriptor is, so the channel guard
/// would not have caught it.
class _InputOnly extends _BareGame {
  final fire = Input.of(const TriggerBinding(InputKey.spacebar));
}

class _GameBuildingSystem extends GameSystem {
  _GameBuildingSystem() {
    _InputOnly();
  }
}

class _SystemHostGame extends _BareGame {
  @override
  GameState createState() => _SystemHostState();
}

class _SystemHostState extends GameState<_SystemHostGame> {
  @override
  void onMounted() {}

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_GameBuildingSystem.new);
  }
}

// --- the isolate-crossing fixture -----------------------------------------

/// One channel from a field and one from the hook, both written on the game
/// isolate. Index is a channel's identity across the boundary, so reading a
/// consistent pair on main is what shows the two sources share one numbering.
class _CrossingGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  final fromField = Channel.int32();

  late final StateChannel<int> fromHook;

  @override
  void describeState(StateDescriptor descriptor) {
    super.describeState(descriptor);
    fromHook = descriptor.hasInt32();
  }

  @override
  GameState createState() => _CrossingState();
}

class _CrossingState extends GameState<_CrossingGame> {
  @override
  void onMounted() {}

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_CrossingSystem.new);
  }
}

class _CrossingSystem extends GameSystem with FixedTickable {
  @override
  void onFixedUpdate() {
    final game = getGame<_CrossingGame>();
    // Two different steps, so a channel reading the other one's storage shows
    // up as a mismatch rather than as a coincidence.
    game.fromField.value = game.fromField.value + 1;
    game.fromHook.value = game.fromHook.value + 100;
  }
}

Future<T> _boot<T extends Game>(T Function() create) async {
  final game = await Game.startInline(create);
  addTearDown(() async {
    if (game.isRunning) await game.stop();
  });
  return game;
}

void _reset() {
  SceneRegistry.reset();
  ArchetypeRegistry.reset();
  ComponentTypeRegistry.reset();
}

void main() {
  tearDown(_reset);

  group('a channel on a Game field', () {
    test('declares the same set the describeState hook does', () async {
      final fields = await _boot(_FieldGame.new);
      final fieldValues = <Object>[
        fields.score.value,
        fields.health.value,
        fields.alive.value,
      ];
      expect(
        fields.stateChannelCount,
        3,
        reason:
            'the fields actually declared - three channels, or the two lists '
            'below could be equal for the wrong reason',
      );
      await fields.stop();
      _reset();

      final hook = await _boot(_HookGame.new);
      expect(
        <Object>[hook.score.value, hook.health.value, hook.alive.value],
        fieldValues,
        reason:
            'the same three channels carrying the same three declared '
            'initial values, whichever way they were declared',
      );
      expect(hook.stateChannelCount, 3);
    });

    test('is storage of its own, not a view onto a neighbour', () async {
      final game = await _boot(_FieldGame.new);

      game.score.value = 41;
      game.health.value = 2.5;
      game.alive.value = false;

      expect(
        <Object>[game.score.value, game.health.value, game.alive.value],
        <Object>[41, 2.5, false],
      );
    });

    test('composes with the hook', () async {
      final game = await _boot(_MixedGame.new);

      expect(game.stateChannelCount, 2);
      expect(
        <int>[game.fromField.value, game.fromHook.value],
        <int>[11, 22],
        reason:
            'both landed, and each kept its own declared initial value - a '
            'shared index would have one of them reading the other',
      );

      game.fromField.value = 1;
      game.fromHook.value = 2;
      expect(<int>[game.fromField.value, game.fromHook.value], <int>[1, 2]);
    });

    test(
      'the two sources share one numbering across the isolate boundary',
      () async {
        final game = await Game.start(_CrossingGame.new);
        addTearDown(() async {
          if (game.isRunning) await game.stop();
        });

        // Seeded before `ready`, so both read their declared initial value
        // the instant start() returns.
        expect(<int>[game.fromField.value, game.fromHook.value], <int>[0, 0]);

        final settled = Completer<void>();
        void listener() {
          if (!settled.isCompleted && game.fromHook.value >= 300) {
            settled.complete();
          }
        }

        game.fromHook.addListener(listener);
        addTearDown(() => game.fromHook.removeListener(listener));
        await settled.future.timeout(const Duration(seconds: 20));

        final steps = game.fromHook.value ~/ 100;
        expect(
          game.fromField.value,
          steps,
          reason:
              'the game isolate added 1 to one channel and 100 to the other; '
              'main reading a consistent pair is what shows both copies '
              'agree about which index is which',
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });

  group('an input on a Game field', () {
    test('declares the same set the describeInputs hook does', () async {
      final fields = await _boot(_FieldInputGame.new);
      expect(
        fields.inputActionCount,
        2,
        reason:
            'the fields actually declared, so the comparison below means '
            'something',
      );
      expect(fields.fire.binding, isNotNull);
      expect(fields.unbound.binding, isNull);
      expect(fields.fire.value, isFalse, reason: 'the shipped bool default');
      await fields.stop();
      _reset();

      final hook = await _boot(_HookInputGame.new);
      expect(hook.inputActionCount, 2);
      expect(hook.fire.binding, isNotNull);
      expect(hook.unbound.binding, isNull);
      expect(hook.fire.value, isFalse);
    });

    test('takes a type default the hook registers after it', () async {
      final game = await _boot(_MixedInputGame.new);

      expect(game.inputActionCount, 2);
      expect(
        game.throttleField.value,
        0.75,
        reason:
            'the field declared before describeInputs ran at all, and '
            'defaults are matched at seal() once every source has spoken - '
            'which is what keeps hasDefaultValue usable from the hook while '
            'the actions themselves move onto fields',
      );
      expect(game.throttleHook.value, 0.75);
    });
  });

  group('the initialisers are eager', () {
    test('a late channel is missing from the declared list', () async {
      final game = await _boot(_LateGame.new);

      expect(
        game.stateChannelCount,
        1,
        reason:
            'the eager one declared, so the window was open and working and '
            'the throw below is the closed-window guard rather than an '
            'earlier failure that took the whole object down',
      );
      expect(game.eagerChannel.value, 5);

      expect(
        () => game.lazyChannel,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no game being constructed'),
          ),
        ),
        reason:
            'written first and still not in the list: a late initialiser '
            'runs on first read, long after the descriptor closed',
      );

      expect(
        game.stateChannelCount,
        1,
        reason:
            'and it added nothing on the way out - the throw is the guard, '
            'not a half-declaration that landed anyway',
      );
    });

    test('a late input is missing from the declared actions', () async {
      final game = await _boot(_LateGame.new);
      final declared = game.inputActionCount;

      expect(
        game.eagerInput.binding,
        isNotNull,
        reason: 'the eager one declared, so the registry was open',
      );

      expect(
        () => game.lazyInput,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no game or system being constructed'),
          ),
        ),
      );

      expect(game.inputActionCount, declared);
    });
  });

  group('a Game built while somebody else is declaring', () {
    test('a game inside a game constructor is refused', () async {
      await expectLater(
        Game.startInline(_NestingGame.new),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('2 games finished constructing'),
              contains('inside another Game'),
            ),
          ),
        ),
        reason:
            'without the count this boots and runs: measured before the '
            'guard existed, the outer game came out holding 2 channels and 1 '
            'action - the inner ones - and the inner game held none of '
            'either while its own handle read the outer storage',
      );
    });

    test('a game inside a system constructor is refused', () async {
      await expectLater(
        Game.startInline(_SystemHostGame.new),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('a Game was constructed while'),
              contains('_GameBuildingSystem'),
            ),
          ),
        ),
        reason:
            'the registry open there belongs to the system, so an Input.of '
            'on a field of that game declares on the host: measured before '
            'the guard, the host held the 1 action and the game held 0',
      );
    });

    test('a prebuilt game handed through a closure is refused', () async {
      final game = await _boot(_FieldGame.new);

      expect(
        () => Game.startInline(() => game),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('has already been started'),
          ),
        ),
        reason:
            'nothing was open around that construction, and the refusal has '
            'to land before the empty windows are hung on it or the running '
            'run loses the registry its actions live in',
      );
      expect(
        game.stateChannelCount,
        3,
        reason: 'and the running game kept everything it declared',
      );
    });
  });
}
