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
import 'package:good/src/random.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/system.dart';

// `Game.start` and `Game.startInline` take a constructor, so the framework
// builds the game and two declaration windows are open while its fields
// initialise: the state descriptor `Channel.*` reads and the input registry
// `Input.of` reads. What this file pins is what a field declaration produces
// - the right set, in the right order, with the declared initial values -
// that the `late` spelling of either cannot quietly get in, and that a `Game`
// built while somebody else's window is open is refused rather than
// declaring into it.
//
// `describeInputs` is still here because `hasDefaultValue` hands nothing back
// and so has no field form. `Channel.*` is the only way to declare a channel.

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

// --- a random stream declared on a field -----------------------------------

/// Two streams and a seed the game states, so a second run of the same class
/// has to produce the same two sequences and the two streams have to differ
/// from each other.
class _RandomFieldGame extends _BareGame {
  _RandomFieldGame({this.randomSeed = 4242});

  @override
  final int randomSeed;

  final first = RandomStream.of();
  final second = RandomStream.of();
}

/// A stream written *before* the eager one, `late`, so a `late` initialiser
/// that ran where it is written would take index 0.
class _LateRandomGame extends _BareGame {
  late final lazyStream = RandomStream.of();

  final eagerStream = RandomStream.of();
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

/// Two channels, both written on the game isolate and stepped by different
/// amounts. Index is a channel's identity across the boundary, so reading a
/// consistent pair on main is what shows both copies agree about the
/// numbering the field initialisers produced.
class _CrossingGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  final first = Channel.int32();

  final second = Channel.int32();

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
    game.first.value = game.first.value + 1;
    game.second.value = game.second.value + 100;
  }
}

/// Thrown out of a constructor tear-off to stop a boot after the fields
/// have declared and before anything resolves.
class _AbandonBoot implements Exception {
  const _AbandonBoot();
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
    test('declares one channel per field, carrying its initial value', () async {
      final fields = await _boot(_FieldGame.new);

      expect(
        fields.stateChannelCount,
        3,
        reason:
            'three fields, three channels - a shared or dropped declaration '
            'shows up here before the values below are asked for',
      );
      expect(
        <Object>[fields.score.value, fields.health.value, fields.alive.value],
        <Object>[3, 1.5, true],
        reason:
            'each carrying the initial value its own declaration named, so '
            'two channels sharing one index would read as a repeat',
      );
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

    test(
      'the declared channels share one numbering across the isolate boundary',
      () async {
        final game = await Game.start(_CrossingGame.new);
        addTearDown(() async {
          if (game.isRunning) await game.stop();
        });

        // Seeded before `ready`, so both read their declared initial value
        // the instant start() returns.
        expect(<int>[game.first.value, game.second.value], <int>[0, 0]);

        final settled = Completer<void>();
        void listener() {
          if (!settled.isCompleted && game.second.value >= 300) {
            settled.complete();
          }
        }

        game.second.addListener(listener);
        addTearDown(() => game.second.removeListener(listener));
        await settled.future.timeout(const Duration(seconds: 20));

        final steps = game.second.value ~/ 100;
        expect(
          game.first.value,
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

  group('a random stream on a Game field', () {
    test('is numbered and seeded from the game, not from the field', () async {
      final game = await _boot(_RandomFieldGame.new);

      expect(
        game.randomStreamCount,
        2,
        reason:
            'two fields, two streams - a dropped declaration shows up here '
            'before the sequences below are asked for',
      );

      final first = <int>[for (var i = 0; i < 8; i++) game.first.nextInt(1000)];
      final second = <int>[
        for (var i = 0; i < 8; i++) game.second.nextInt(1000),
      ];

      expect(
        first,
        isNot(second),
        reason:
            'the declaration index is mixed into the seed, so two streams '
            'from one seed are independent - equal sequences would mean both '
            'fields resolved to the same index',
      );

      await game.stop();
      _reset();

      final again = await _boot(_RandomFieldGame.new);
      expect(
        <int>[for (var i = 0; i < 8; i++) again.first.nextInt(1000)],
        first,
        reason:
            'the same seed and the same declaration order replay identically '
            '- that is the whole contract of a declared stream',
      );
      expect(
        <int>[for (var i = 0; i < 8; i++) again.second.nextInt(1000)],
        second,
      );
    });

    test('a different seed moves both streams', () async {
      final game = await _boot(_RandomFieldGame.new);
      final base = <int>[for (var i = 0; i < 8; i++) game.first.nextInt(1000)];
      await game.stop();
      _reset();

      final other = await _boot(() => _RandomFieldGame(randomSeed: 99));
      expect(
        <int>[for (var i = 0; i < 8; i++) other.first.nextInt(1000)],
        isNot(base),
        reason:
            'randomSeed is an overridable getter, so it is read at boot and '
            'not by the field initialiser that declared the stream',
      );
    });

    test('a stream is unusable before its game has started', () async {
      late _RandomFieldGame built;
      // Constructed by the framework, so the window is open and the fields
      // declare - and then the boot is abandoned before anything resolves.
      await expectLater(
        Game.startInline(() {
          built = _RandomFieldGame();
          throw const _AbandonBoot();
        }),
        throwsA(isA<_AbandonBoot>()),
      );

      expect(
        () => built.first.nextInt(6),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('before the game that declared it started'),
          ),
        ),
        reason:
            'a declaration collects and nothing else: the seed and the index '
            'arrive at boot, and a draw before that has no sequence to be on',
      );
    });

    test('a late stream is missing from the declared list', () async {
      final game = await _boot(_LateRandomGame.new);

      expect(
        game.randomStreamCount,
        1,
        reason:
            'the eager one declared, so the registry was open and working '
            'and the throw below is the closed-window guard',
      );
      expect(game.eagerStream.nextInt(1000), isA<int>());

      expect(
        () => game.lazyStream,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no game being constructed'),
          ),
        ),
        reason:
            'written first and still not in the list: a late initialiser '
            'runs on first read, long after boot derived every stream',
      );

      expect(game.randomStreamCount, 1);
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
