// flutter_test exports an unrelated EventDispatcher (its pointer-event test
// harness), so the engine's has to win here by name - same reason as
// event_declaration_test.dart.
import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;

import 'package:good/src/archetype.dart';
import 'package:good/src/event.dart';
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

// `SystemDescriptor.has` takes a constructor, so the framework builds the
// system and reads its declarations off the constructed object. That read is
// what rules the hook forms out for anything a system has to keep: it runs
// before `describeEvents` and before `describeInputs`, so a field the hook
// assigns is unassigned when the collector reaches it. What is left for a
// hook is a declaration nothing holds - `hasDefaultValue`, which hands
// nothing back and has no field form at all.
//
// What this file pins is the field form on a system: its events reach the
// system's own composition and not the state's, its actions declare in the
// order they are written, and the one surviving hook composes with them.

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

  late final GameSystem source;

  @override
  void onMounted() {}

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    source = descriptor.has(_source);
    descriptor.has(_EarA.new);
    descriptor.has(_EarB.new);
  }
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

  late final GameSystem source;

  @override
  void onMounted() {}

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    source = descriptor.has(_source);
  }
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
}
