// flutter_test exports an unrelated EventDispatcher (its pointer-event test
// harness), so the engine's has to win here by name - same reason as
// event_declaration_test.dart.
import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;

import 'package:good/src/archetype.dart';
import 'package:good/src/event.dart';
import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/input.dart';
import 'package:good/src/input/input_binding.dart';
import 'package:good/src/input/input_key.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/system.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';

part 'system_declaration_test.g.dart';

// A system is an `@system` field of a `GameState`, and the boot pass reads it
// off the constructed state through the generated collector. That read is
// what rules the hook forms out for anything a system has to keep: it runs
// before `describeEvents` and before `describeInputs`, so a field a hook
// assigns is unassigned when the collector reaches it. What is left for a
// hook is a declaration nothing holds - `hasDefaultValue`, which hands
// nothing back and has no field form at all.
//
// What this file pins is the field form on a system: the marker is what makes
// a field a declaration and an unmarked one is a legal spare, its events
// reach the system's own composition and not the state's, its actions declare
// in the order they are written, and the one surviving hook composes with
// them.

/// The listener half of the event tests. Writes into a shared log so *order*
/// is observable and not just membership.
mixin _Noted on GameListener {
  String get noted;

  static final List<String> log = <String>[];

  void onNoted(String event) => _Noted.log.add('$event:$noted');
}

// Two bystanders that hear a system's event. They are the state's
// composition, not the source system's, so a dispatcher that had landed in
// the state's binder would collect them and one scoped to the system will
// not. Two classes rather than two instances because a system is keyed by
// `runtimeType` and a duplicate is refused.
class _EarA extends GameSystem with _Noted {
  @override
  String get noted => 'earA';
}

class _EarB extends GameSystem with _Noted {
  @override
  String get noted => 'earB';
}

/// The system under test, declaring its event on the field that holds it.
class _FieldSystem extends GameSystem with _Noted {
  @override
  String get noted => 'source';

  final alpha = Event.of<_Noted, String>(
    (listener, event) => listener.onNoted(event),
  );

  final beta = Event.of<_Noted, String>(
    (listener, event) => listener.onNoted(event),
    reverse: true,
  );
}

class _EventState<G extends Game> extends GameState<G> {
  _EventState(this._source);

  final GameSystem Function() _source;

  @override
  void onMounted() {}

  @system
  late final source = _source();
  @system
  final earA = _EarA();
  @system
  final earB = _EarB();
}

class _FieldEventGame extends _BareGame {
  @override
  GameState createState() => _EventState<_FieldEventGame>(_FieldSystem.new);
}

// --- input ----------------------------------------------------------------

/// Two actions on fields, and nothing in the hook at all.
class _FieldInputSystem extends GameSystem {
  final fire = Input.of(const TriggerBinding(InputKey.spacebar));
  final alt = Input.of(const TriggerBinding(InputKey.enter));
  final unbound = Input.of<bool>();
}

/// A field declaration beside the one hook call that has no field form:
/// `hasDefaultValue` hands nothing back, so there is nothing to hold and
/// nothing for a collector to read - which is why this hook survives.
class _MixedInputSystem extends GameSystem {
  final fire = Input.of(const TriggerBinding(InputKey.spacebar));

  final throttle = Input.of<double>();

  @override
  void describeInputs(InputDescriptor descriptor) {
    super.describeInputs(descriptor);
    descriptor.hasDefaultValue<double>(0.25);
  }
}

class _InputState<G extends Game> extends GameState<G> {
  _InputState(this._source);

  final GameSystem Function() _source;

  @override
  void onMounted() {}

  @system
  late final source = _source();
}

class _FieldInputGame extends _BareGame {
  @override
  GameState createState() =>
      _InputState<_FieldInputGame>(_FieldInputSystem.new);
}

class _MixedInputGame extends _BareGame {
  @override
  GameState createState() =>
      _InputState<_MixedInputGame>(_MixedInputSystem.new);
}

// --- the marker ------------------------------------------------------------

/// Counts its own fixed ticks, so "declared" and "not declared" are told
/// apart by whether it ran rather than by asking a registry.
class _Counting extends GameSystem with FixedTickable {
  int ticks = 0;

  @override
  void onFixedUpdate() => ticks++;
}

class _MarkedSystem extends _Counting {}

class _SpareSystem extends _Counting {}

/// One marked field and one unmarked one, holding the same kind of thing.
///
/// The two lines are the whole point: they are the same shape and the same
/// kind of value, and only the marker separates a declaration from a field
/// that happens to hold a system.
class _MarkerState extends GameState<_MarkerGame> {
  @override
  void onMounted() {}

  @system
  final marked = _MarkedSystem();

  final spare = _SpareSystem();
}

class _MarkerGame extends _BareGame {
  @override
  GameState createState() => _MarkerState();
}

/// Two `@system` fields of one type, which is refused.
class _TwinState extends GameState<_TwinGame> {
  @override
  void onMounted() {}

  @system
  final first = _MarkedSystem();

  @system
  final second = _MarkedSystem();
}

class _TwinGame extends _BareGame {
  @override
  GameState createState() => _TwinState();
}

abstract class _BareGame extends Game {
  @override
  int get pageSize => 4096;
}

Future<Game> _boot(Game Function() create) async {
  final run = await Game.startInline(create);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return run;
}

void _reset() {
  SceneRegistry.reset();
  ArchetypeRegistry.reset();
  ComponentTypeRegistry.reset();
}

void main() {
  _installDeclarations();

  setUp(_Noted.log.clear);
  tearDown(_reset);

  group('an event on a system field', () {
    test('collects the system composition and not the state one', () async {
      final run = await _boot(_FieldEventGame.new);
      final source =
          (run.state as _EventState<_FieldEventGame>).source as _FieldSystem;

      expect(
        source.alpha.listenerCount,
        1,
        reason:
            'the system itself, which is a _Noted, and nothing else. The two '
            'ears are the states composition, not this systems - a '
            'dispatcher that had landed in the states binder would have '
            'collected all three',
      );
      expect(source.beta.listenerCount, source.alpha.listenerCount);
    });

    test('both directions deliver, and to the same one listener', () async {
      final run = await _boot(_FieldEventGame.new);
      final source =
          (run.state as _EventState<_FieldEventGame>).source as _FieldSystem;

      source.alpha('alpha');
      source.beta('beta');

      expect(
        _Noted.log,
        <String>['alpha:source', 'beta:source'],
        reason:
            '`reverse: true` turns the order of a list around and does not '
            'change what is in it - and a one-entry list is the same either '
            'way, which is what the count above is for',
      );
    });
  });

  group('an input on a system field', () {
    test('declares its actions in the order they are written', () async {
      final run = await _boot(_FieldInputGame.new);
      final source =
          (run.state as _InputState<_FieldInputGame>).source
              as _FieldInputSystem;

      expect(
        source.fire.binding,
        const TriggerBinding(InputKey.spacebar),
        reason:
            'field order is declaration order, so the first field holds the '
            'first binding rather than whichever action something read first',
      );
      expect(source.alt.binding, const TriggerBinding(InputKey.enter));
      expect(
        source.unbound.binding,
        isNull,
        reason:
            'an unbound action is a declared state, so it takes a slot and '
            'holds no binding',
      );
    });

    test('an unbound field action still reads its default', () async {
      final run = await _boot(_FieldInputGame.new);
      final source =
          (run.state as _InputState<_FieldInputGame>).source
              as _FieldInputSystem;

      expect(
        source.unbound.value,
        false,
        reason:
            'the type-level default Game.describeInputs registers for bool, '
            'resolved by the seal that runs after every source has declared '
            '- a field declaration goes through the same seal',
      );
    });

    test('a field action reads a default the hook registered', () async {
      final run = await _boot(_MixedInputGame.new);
      final source =
          (run.state as _InputState<_MixedInputGame>).source
              as _MixedInputSystem;

      expect(source.fire.binding, isNotNull);
      expect(
        source.throttle.value,
        0.25,
        reason:
            'hasDefaultValue has no field form, so the hook is what declares '
            'it - and the seal applied it to an action the field initialiser '
            'had already declared, which is the composition that matters now '
            'the other hook forms are gone',
      );
    });
  });

  group('@system is what declares a system, in both directions', () {
    test('a marked field is declared, bound and ticked', () async {
      final run = await _boot(_MarkerGame.new);
      final state = run.state as _MarkerState;

      expect(
        state.getSystem<_MarkedSystem>(),
        same(state.marked),
        reason:
            'the object the run holds is the object the field holds - the '
            'collector reads the field, it does not build a second one',
      );
      state.advance(const Duration(milliseconds: 40));
      expect(state.marked.ticks, greaterThan(0));
      expect(state.marked.state, same(state));
    });

    test('an unmarked field holding a system declares nothing', () async {
      final run = await _boot(_MarkerGame.new);
      final state = run.state as _MarkerState;

      expect(
        () => state.getSystem<_SpareSystem>(),
        throwsArgumentError,
        reason:
            'holding a spare is ordinary code and stays legal, which is half '
            'the reason the marker exists. `final spare = _SpareSystem();` is '
            'spelled exactly like the marked line above it and the type says '
            'nothing about the difference',
      );
      state.advance(const Duration(milliseconds: 40));
      expect(
        state.spare.ticks,
        0,
        reason: 'it is in no dispatcher, so nothing ever calls it',
      );
      expect(
        state.declaredSystems,
        isNot(contains(state.spare)),
        reason: 'and it is not in the tick order at all',
      );
    });

    test('two marked fields of one system type are refused', () {
      expect(
        Game.startInline(_TwinGame.new),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('_MarkedSystem'), contains('twice')),
          ),
        ),
        reason:
            'a system is reached by its type, so a second one of a type is '
            'not reachable at all and sits at its own place in the tick order '
            'while every compareTo naming its type applies to both',
      );
    });
  });
}
