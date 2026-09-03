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

// `SystemDescriptor.has` takes a constructor, so the framework builds the
// system and two declaration windows are open while its fields initialise:
// the event binder and the input registry. What this file pins is that a
// declaration made through a field and the same declaration made through the
// matching `describeX` hook are one declaration - same set, same order, same
// delivery - and that the `late` spelling of either cannot quietly get in.

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

/// The same two dispatchers, both in the hook.
class _HookSystem extends GameSystem with _Noted {
  @override
  String get noted => 'source';

  late final EventDispatcher<_Noted, String> alpha;
  late final EventDispatcher<_Noted, String> beta;

  @override
  void describeEvents(EventDescriptor descriptor) {
    super.describeEvents(descriptor);
    alpha = descriptor.has((listener, event) => listener.onNoted(event));
    beta = descriptor.has(
      (listener, event) => listener.onNoted(event),
      reverse: true,
    );
  }
}

/// One of each on one system: `alpha` on a field, `beta` in the hook.
class _MixedSystem extends GameSystem with _Noted {
  @override
  String get noted => 'source';

  final alpha = Event.of<_Noted, String>(
    (listener, event) => listener.onNoted(event),
  );

  late final EventDispatcher<_Noted, String> beta;

  @override
  void describeEvents(EventDescriptor descriptor) {
    super.describeEvents(descriptor);
    beta = descriptor.has((listener, event) => listener.onNoted(event));
  }
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

class _HookEventGame extends _BareGame {
  @override
  GameState createState() => _EventState<_HookEventGame>(_HookSystem.new);
}

class _MixedEventGame extends _BareGame {
  @override
  GameState createState() => _EventState<_MixedEventGame>(_MixedSystem.new);
}

// --- input ----------------------------------------------------------------

/// Two actions on fields, and nothing in the hook at all.
class _FieldInputSystem extends GameSystem {
  final fire = Input.of(const TriggerBinding(InputKey.spacebar));
  final alt = Input.of(const TriggerBinding(InputKey.enter));
  final unbound = Input.of<bool>();
}

/// The same three in the hook.
class _HookInputSystem extends GameSystem {
  late final Input<bool> fire;
  late final Input<bool> alt;
  late final Input<bool> unbound;

  @override
  void describeInputs(InputDescriptor descriptor) {
    super.describeInputs(descriptor);
    fire = descriptor.has<bool>(const TriggerBinding(InputKey.spacebar));
    alt = descriptor.has<bool>(const TriggerBinding(InputKey.enter));
    unbound = descriptor.has<bool>();
  }
}

/// A field declaration and a hook declaration on one system. The hook also
/// registers a type-level default, which is the thing that has no field form
/// and so is the reason this hook survives at all.
class _MixedInputSystem extends GameSystem {
  final fire = Input.of(const TriggerBinding(InputKey.spacebar));

  late final Input<double> throttle;

  @override
  void describeInputs(InputDescriptor descriptor) {
    super.describeInputs(descriptor);
    descriptor.hasDefaultValue<double>(0.25);
    throttle = descriptor.has<double>();
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

class _HookInputGame extends _BareGame {
  @override
  GameState createState() => _InputState<_HookInputGame>(_HookInputSystem.new);
}

class _MixedInputGame extends _BareGame {
  @override
  GameState createState() =>
      _InputState<_MixedInputGame>(_MixedInputSystem.new);
}

// --- the eager guard ------------------------------------------------------

/// A system whose `late` declarations are written **ahead** of the eager ones.
///
/// That ordering is the point. If a `late` initialiser ran where it is written
/// rather than on first read, `lazyEvent` and `lazyInput` would be the first
/// things in their respective lists, and the assertions below would see them
/// there.
class _LateSystem extends GameSystem with _Noted {
  @override
  String get noted => 'late';

  late final lazyEvent = Event.signal<_Noted>(
    (listener) => listener.onNoted('lazy'),
  );

  late final lazyInput = Input.of(const TriggerBinding(InputKey.escape));

  final eagerEvent = Event.signal<_Noted>(
    (listener) => listener.onNoted('eager'),
  );

  final eagerInput = Input.of(const TriggerBinding(InputKey.spacebar));
}

class _LateState extends GameState<_LateGame> {
  late final _LateSystem source;

  @override
  void onMounted() {}

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    source = descriptor.has(_LateSystem.new);
  }
}

class _LateGame extends _BareGame {
  @override
  GameState createState() => _LateState();
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

    test('delivery is identical to the hook form, both directions', () async {
      final fieldRun = await _boot(_FieldEventGame.new);
      final fieldSource =
          (fieldRun.state as _EventState<_FieldEventGame>).source
              as _FieldSystem;
      fieldSource.alpha('alpha');
      fieldSource.beta('beta');
      final fromFields = List<String>.of(_Noted.log);

      await fieldRun.stop();
      _reset();
      _Noted.log.clear();

      final hookRun = await _boot(_HookEventGame.new);
      final hookSource =
          (hookRun.state as _EventState<_HookEventGame>).source as _HookSystem;
      hookSource.alpha('alpha');
      hookSource.beta('beta');

      expect(
        fromFields,
        _Noted.log,
        reason:
            'same listeners, same order, both directions. Where a dispatcher '
            'was declared does not reach delivery',
      );
      expect(
        fromFields,
        <String>['alpha:source', 'beta:source'],
        reason:
            'and the log is what it should be, so the two cannot be equal '
            'for the wrong reason',
      );
    });

    test('one system can use both forms at once', () async {
      final run = await _boot(_MixedEventGame.new);
      final source =
          (run.state as _EventState<_MixedEventGame>).source as _MixedSystem;

      expect(
        source.beta.listenerCount,
        source.alpha.listenerCount,
        reason:
            'the hook appended to the binder the field declaration already '
            'filled rather than getting one of its own',
      );
      expect(source.alpha.listenerCount, 1);
    });
  });

  group('an input on a system field', () {
    test('declares the same actions the hook declares', () async {
      final fieldRun = await _boot(_FieldInputGame.new);
      final fieldCount = fieldRun.inputActionCount;
      final fieldSource =
          (fieldRun.state as _InputState<_FieldInputGame>).source
              as _FieldInputSystem;
      final fieldBindings = <InputBinding<bool>?>[
        fieldSource.fire.binding,
        fieldSource.alt.binding,
        fieldSource.unbound.binding,
      ];

      await fieldRun.stop();
      _reset();

      final hookRun = await _boot(_HookInputGame.new);
      final hookSource =
          (hookRun.state as _InputState<_HookInputGame>).source
              as _HookInputSystem;

      expect(
        fieldCount,
        hookRun.inputActionCount,
        reason:
            'three actions either way, on top of whatever the Game declares '
            'for itself',
      );
      expect(
        fieldBindings,
        <InputBinding<bool>?>[
          hookSource.fire.binding,
          hookSource.alt.binding,
          hookSource.unbound.binding,
        ],
        reason: 'same bindings in the same order, including the unbound one',
      );
      expect(
        fieldBindings.first,
        isNotNull,
        reason:
            'and the list is not three nulls, which would make the two equal '
            'for the wrong reason',
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

    test('a field and a hook compose on one system', () async {
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
            'it - and the seal applied it to an action declared in the same '
            'hook, on a system whose other action came off a field',
      );
    });
  });

  group('the initialisers are eager', () {
    test('a late event is missing from the collected list', () async {
      final run = await _boot(_LateGame.new);
      final source = (run.state as _LateState).source;

      expect(
        source.eagerEvent.listenerCount,
        1,
        reason:
            'the window was open and working, so the throw below is the '
            'closed-window guard and not an earlier failure that took the '
            'whole object down',
      );

      expect(
        () => source.lazyEvent,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no event owner being constructed'),
          ),
        ),
        reason:
            'declared first and still not in the binder: a late initialiser '
            'runs on first read, long after the binder closed',
      );
    });

    test('a late input is missing from the declared actions', () async {
      final run = await _boot(_LateGame.new);
      final source = (run.state as _LateState).source;
      final declared = run.inputActionCount;

      expect(
        source.eagerInput.binding,
        isNotNull,
        reason:
            'the eager one declared, so the registry was open during the '
            'constructor',
      );

      expect(
        () => source.lazyInput,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no game or system being constructed'),
          ),
        ),
      );

      expect(
        run.inputActionCount,
        declared,
        reason:
            'and it added nothing on the way out - the throw is the guard, '
            'not a half-declaration that landed anyway',
      );
    });
  });
}
