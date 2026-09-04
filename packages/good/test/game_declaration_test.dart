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
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';

part 'game_declaration_test.g.dart';

// `Game.start` and `Game.startInline` take a constructor, so the framework
// builds the game and reads its declarations off the constructed object. That
// read runs before `describeState` and before `describeInputs`, so a channel
// or an action a hook assigns is unassigned when the collector reaches it -
// which is what leaves the field as the only form for anything a game keeps.
// A hook can still register what nothing holds, and `hasDefaultValue` is that.
//
// What this file pins is the field form on a `Game`: the values it declares,
// that each channel is storage of its own, that the numbering survives the
// isolate boundary, and that a `Game` built inside another constructor
// declares onto its own fields.

abstract class _BareGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  /// Named here as well as installed in `main`, because the two reach
  /// different isolates: `main` runs on this one and a spawned copy reads
  /// this getter. Every game here but the crossing one inherits it.
  @override
  List<GeneratedDeclarations> get declarations =>
      const <GeneratedDeclarations>[_gameDeclarationTestDeclarations];

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

/// The one shape with no field form at all: `hasDefaultValue` hands nothing
/// back, so there is nothing to hold and nothing for a collector to read. It
/// keeps `describeInputs` alive on a `Game` however much else moves onto
/// fields.
class _MixedInputGame extends _BareGame {
  final throttleField = Input.of<double>();

  @override
  void describeInputs(InputDescriptor input) {
    super.describeInputs(input);
    input.hasDefaultValue<double>(0.75);
  }
}

// --- the wrong-collection hazards -----------------------------------------

/// Declares one of each, so wherever it is built it leaves a trace.
class _Nested extends _BareGame {
  final score = Channel.int32(7);
  final fire = Input.of(const TriggerBinding(InputKey.spacebar));
}

/// A game holding a game. There was a guard against this once, counting games
/// against an open declaration window; the windows are gone and so is it. A
/// collector is keyed by the class it reads, so the inner one's fields are
/// read off the inner one and nesting has nothing left to corrupt.
class _NestingGame extends _BareGame {
  final own = Channel.int32(1);
  final inner = _Nested();
}

/// A game with only an input, built inside a system's constructor. That was
/// the case the channel guard missed, because what used to be open there
/// belonged to the system; with nothing open at all it lands nowhere.
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

/// Two channels, both written on the game isolate. Index is a channel's
/// identity across the boundary, so reading a consistent pair on main is what
/// shows the two copies agree about which index is which.
class _CrossingGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  final first = Channel.int32();
  final second = Channel.int32();

  /// Named here as well as installed in `main`, because the two reach
  /// different isolates: `main` runs on this one and a spawned copy reads
  /// this getter.
  @override
  List<GeneratedDeclarations> get declarations =>
      const <GeneratedDeclarations>[_gameDeclarationTestDeclarations];

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
  _installDeclarations();

  tearDown(_reset);

  group('a channel on a Game field', () {
    test('declares one channel per field, at its declared value', () async {
      final game = await _boot(_FieldGame.new);

      expect(
        game.stateChannelCount,
        3,
        reason:
            'three fields, three channels - a count of two would mean one '
            'field never reached the list at all',
      );
      expect(
        <Object>[game.score.value, game.health.value, game.alive.value],
        <Object>[3, 1.5, true],
        reason: 'and each is carrying the value its own initialiser named',
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
      'the two copies share one numbering across the isolate boundary',
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
    test('declares one action per field, bound or not', () async {
      final game = await _boot(_FieldInputGame.new);

      expect(
        game.inputActionCount,
        2,
        reason:
            'an unbound action is a declared state and takes a slot, so the '
            'count is two rather than one',
      );
      expect(game.fire.binding, isNotNull);
      expect(game.unbound.binding, isNull);
      expect(game.fire.value, isFalse, reason: 'the shipped bool default');
    });

    test('takes a type default the hook registers after it', () async {
      final game = await _boot(_MixedInputGame.new);

      expect(game.inputActionCount, 1);
      expect(
        game.throttleField.value,
        0.75,
        reason:
            'the field declared before describeInputs ran at all, and '
            'defaults are matched at seal() once every source has spoken - '
            'which is what keeps hasDefaultValue usable from the hook while '
            'the actions themselves move onto fields',
      );
    });
  });

  group('a Game built while somebody else is being constructed', () {
    test('a game inside a game constructor keeps its own fields', () async {
      final game = await _boot(_NestingGame.new);

      expect(
        game.stateChannelCount,
        1,
        reason:
            'the one Channel field the outer game declares. Measured before '
            'the guard existed and while the windows were open, this was 2 - '
            'the inner game\'s - and the inner game held none of its own',
      );
      expect(
        game.own.value,
        1,
        reason: 'its own initialiser, not the 7 the inner one named',
      );
      expect(
        game.inputActionCount,
        0,
        reason: 'and the inner game\'s Input.of did not land here either',
      );
      expect(
        collectDeclarations(game.inner),
        orderedEquals(<Matcher>[same(game.inner.score), same(game.inner.fire)]),
        reason:
            'while the inner game still holds both of them. This is the '
            'property the deleted guard was protecting, and a collector keyed '
            'by the class it reads gives it for free - there is no ambient '
            'owner left for a field to be attributed to',
      );
    });

    test(
      'a game inside a system constructor lands nothing on the host',
      () async {
        final game = await _boot(_SystemHostGame.new);

        expect(
          game.inputActionCount,
          0,
          reason:
              'the system constructor built a game holding one Input.of and '
              'dropped it. Measured before the guard existed, the host held '
              'that action and the game held none - the case the channel '
              'guard missed, since what was open there was the system\'s',
        );
        expect(
          game.stateChannelCount,
          0,
          reason: 'and nothing else arrived from it either',
        );
      },
    );

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
