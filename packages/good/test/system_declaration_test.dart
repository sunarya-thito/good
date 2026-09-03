// flutter_test exports an unrelated EventDispatcher (its pointer-event test
// harness), so the engine's has to win here by name - same reason as
// event_declaration_test.dart.
import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;

import 'package:good/src/archetype.dart';
import 'package:good/src/declare.dart';
import 'package:good/src/event.dart';
import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/input.dart';
import 'package:good/src/input/input_binding.dart';
import 'package:good/src/input/input_key.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/system.dart';

// `GameSystem.of` takes a constructor, so the framework builds the
// system and two declaration windows are open while its fields initialise:
// the event binder and the input registry. What this file pins is that a
// declaration made through a field and the same declaration made another way
// - an event from the constructor body - are one declaration: same set, same
// order, same delivery. And that the `late` spelling of either cannot quietly
// get in.

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

/// The same two dispatchers, both from the constructor body.
class _BodySystem extends GameSystem with _Noted {
  _BodySystem() {
    alpha = events.has((listener, event) => listener.onNoted(event));
    beta = events.has(
      (listener, event) => listener.onNoted(event),
      reverse: true,
    );
  }

  @override
  String get noted => 'source';

  late final EventDispatcher<_Noted, String> alpha;
  late final EventDispatcher<_Noted, String> beta;
}

/// One of each on one system: `alpha` on a field, `beta` in the body.
class _MixedSystem extends GameSystem with _Noted {
  _MixedSystem() {
    beta = events.has((listener, event) => listener.onNoted(event));
  }

  @override
  String get noted => 'source';

  final alpha = Event.of<_Noted, String>(
    (listener, event) => listener.onNoted(event),
  );

  late final EventDispatcher<_Noted, String> beta;
}

class _EventState<G extends Game> extends GameState<G> {
  /// The tear-off comes in as a constructor parameter and the declaration is
  /// made in the initialiser list, because a field initialiser cannot read a
  /// sibling field. It is still eager, which is what puts it inside the
  /// window `_bootMain` opens around `createState`.
  _EventState(GameSystem Function() source) : source = GameSystem.of(source);

  final SystemHandle<GameSystem> source;

  final earA = GameSystem.of(_EarA.new);
  final earB = GameSystem.of(_EarB.new);

  @override
  void onMounted() {}
}

class _FieldEventGame extends _BareGame {
  @override
  GameState createState() => _EventState<_FieldEventGame>(_FieldSystem.new);
}

class _BodyEventGame extends _BareGame {
  @override
  GameState createState() => _EventState<_BodyEventGame>(_BodySystem.new);
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

/// An action on a field and a type-level fallback in the getter beside it -
/// the two halves of input, which are declared in different places because one
/// hands back a handle and the other hands back nothing.
class _MixedInputSystem extends GameSystem {
  final fire = Input.of(const TriggerBinding(InputKey.spacebar));

  final throttle = Input.of<double>();

  @override
  List<InputDefault<Object?>> get inputDefaults => <InputDefault<Object?>>[
    const InputDefault<double>(0.25),
  ];
}

class _InputState<G extends Game> extends GameState<G> {
  _InputState(GameSystem Function() source) : source = GameSystem.of(source);

  final SystemHandle<GameSystem> source;

  @override
  void onMounted() {}
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
  final source = GameSystem.of(_LateSystem.new);

  @override
  void onMounted() {}
}

class _LateGame extends _BareGame {
  @override
  GameState createState() => _LateState();
}

// --- who declares, and in what order -------------------------------------

/// Logged in execution order, so the ordering assertions read the tick and not
/// a list some resolve pass returned.
final List<String> ran = <String>[];

class _BaseSystem extends GameSystem with FixedTickable {
  @override
  void onFixedUpdate() => ran.add('base');
}

class _MixedInSystem extends GameSystem with FixedTickable {
  @override
  void onFixedUpdate() => ran.add('mixin');
}

class _SubSystem extends GameSystem with FixedTickable {
  @override
  void onFixedUpdate() => ran.add('sub');
}

class _InheritedBaseState extends GameState<_InheritedGame> {
  final base = GameSystem.of(_BaseSystem.new);

  @override
  void onMounted() {}
}

mixin _ContributingState on GameState<_InheritedGame> {
  final mixedIn = GameSystem.of(_MixedInSystem.new);
}

class _InheritedState extends _InheritedBaseState with _ContributingState {
  final sub = GameSystem.of(_SubSystem.new);
}

class _InheritedGame extends _BareGame {
  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _InheritedState();
}

// --- the owner a build closure is handed ---------------------------------

/// What a `GameSystem.owned` closure built, so the test can tell which
/// override decided it.
class _OwnedSystem extends GameSystem {
  _OwnedSystem(this.tag);

  final String tag;
}

class _OwnerState extends GameState<_OwnerGame> {
  /// Names the *state*, not `this`: the closure has no receiver, so the owner
  /// is what makes [pick] dispatch on the subclass below.
  final owned = GameSystem.owned((_OwnerState state) => state.pick());

  _OwnedSystem pick() => _OwnedSystem('base');

  @override
  void onMounted() {}
}

class _OverridingState extends _OwnerState {
  @override
  _OwnedSystem pick() => _OwnedSystem('override');
}

class _OwnerGame extends _BareGame {
  @override
  GameState createState() => _OwnerState();
}

class _OverridingGame extends _OwnerGame {
  @override
  GameState createState() => _OverridingState();
}

/// A `GameSystem.owned` whose declared owner type the state does not satisfy.
mixin _WrongOwner on GameState<Game> {}

class _MismatchState extends GameState<_MismatchGame> {
  final owned = GameSystem.owned(
    (_WrongOwner owner) => _OwnedSystem('unreachable'),
  );

  @override
  void onMounted() {}
}

class _MismatchGame extends _BareGame {
  @override
  GameState createState() => _MismatchState();
}

/// A state whose *field initialiser* throws, for the window-cleanup test.
///
/// The system is declared first, so the window is not merely opened when the
/// throw happens - it has something in it.
class _ThrowingState extends GameState<_ThrowingGame> {
  final ear = GameSystem.of(_EarA.new);

  final boom = _explode();

  @override
  void onMounted() {}
}

int _explode() => throw StateError('while the state was being built');

class _ThrowingGame extends _BareGame {
  @override
  GameState createState() => _ThrowingState();
}

abstract class _BareGame extends Game {
  @override
  int get pageSize => 4096;
}

/// A system nothing declares, for the diagnostics `getSystem` and
/// `setSystemEnabled` produce when asked for one.
class _Undeclared extends GameSystem {}

class _NamingState extends GameState<_NamingGame> {
  final earA = GameSystem.of(_EarA.new);
}

class _NamingGame extends Game {
  @override
  GameState createState() => _NamingState();
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
          (run.state as _EventState<_FieldEventGame>).source.value as _FieldSystem;

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

    test('delivery is identical to the body form, both directions', () async {
      final fieldRun = await _boot(_FieldEventGame.new);
      final fieldSource =
          (fieldRun.state as _EventState<_FieldEventGame>).source.value
              as _FieldSystem;
      fieldSource.alpha('alpha');
      fieldSource.beta('beta');
      final fromFields = List<String>.of(_Noted.log);

      await fieldRun.stop();
      _reset();
      _Noted.log.clear();

      final bodyRun = await _boot(_BodyEventGame.new);
      final bodySource =
          (bodyRun.state as _EventState<_BodyEventGame>).source.value as _BodySystem;
      bodySource.alpha('alpha');
      bodySource.beta('beta');

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
          (run.state as _EventState<_MixedEventGame>).source.value as _MixedSystem;

      expect(
        source.beta.listenerCount,
        source.alpha.listenerCount,
        reason:
            'the body appended to the binder the field declaration already '
            'filled rather than getting one of its own',
      );
      expect(source.alpha.listenerCount, 1);
    });
  });

  group('an input on a system field', () {
    test('declares one action per field, in field order', () async {
      final run = await _boot(_FieldInputGame.new);
      final source =
          (run.state as _InputState<_FieldInputGame>).source.value
              as _FieldInputSystem;

      expect(
        run.inputActionCount,
        3,
        reason:
            'three fields, three actions, on top of whatever the Game '
            'declares for itself - which is none here',
      );
      expect(
        <InputKey?>[
          (source.fire.binding! as TriggerBinding).key,
          (source.alt.binding! as TriggerBinding).key,
        ],
        <InputKey>[InputKey.spacebar, InputKey.enter],
        reason:
            'each field got its own binding, in the order the initialisers '
            'ran - two actions sharing one would read as a repeat here',
      );
      expect(
        source.unbound.binding,
        isNull,
        reason: 'and the unbound one is genuinely unbound, not defaulted',
      );
    });

    test('an unbound field action still reads its default', () async {
      final run = await _boot(_FieldInputGame.new);
      final source =
          (run.state as _InputState<_FieldInputGame>).source.value
              as _FieldInputSystem;

      expect(
        source.unbound.value,
        false,
        reason:
            'the type-level fallback boot registers for bool, resolved by '
            'the seal that runs after every source has declared - a field '
            'declaration goes through the same seal',
      );
    });

    test('a system\'s own inputDefaults reaches its own actions', () async {
      final run = await _boot(_MixedInputGame.new);
      final source =
          (run.state as _InputState<_MixedInputGame>).source.value
              as _MixedInputSystem;

      expect(source.fire.binding, isNotNull);
      expect(
        source.throttle.value,
        0.25,
        reason:
            'a type-level fallback hands nothing back, so it is a getter and '
            'not a declaration - and the seal applied it to an action the '
            'same system declared on a field, which ran first',
      );
    });
  });

  group('the initialisers are eager', () {
    test('a late event is missing from the collected list', () async {
      final run = await _boot(_LateGame.new);
      final source = (run.state as _LateState).source.value;

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
      final source = (run.state as _LateState).source.value;
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

  group('declaration order is field initialiser order', () {
    test('a base class runs after the subclass that inherits it', () async {
      ran.clear();
      final run = await _boot(_InheritedGame.new);
      run.state.advance(const Duration(milliseconds: 10));

      expect(
        ran,
        <String>['sub', 'mixin', 'base'],
        reason:
            'Dart runs the most derived class initialisers, then its mixins '
            'in reverse `with` order, then the superclass. Declaration order '
            'is execution order for systems that state no opinion, so a base '
            "class's systems run last - the reverse of the base-first super "
            'chain the describeSystems hook produced. A system that cares '
            'says so with Order.of()',
      );
    });
  });

  group('the declaration window', () {
    test('refuses a system declared with no state being built', () {
      expect(
        () => GameSystem.of(_EarA.new),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('no GameState being constructed'),
              contains('createState'),
            ),
          ),
        ),
        reason:
            'the window is opened around createState and nowhere else, so a '
            'system named on a Game, a scene or a prefab reports itself '
            'rather than landing on whatever ran last',
      );
    });

    test('closes even when createState throws', () async {
      await expectLater(
        Game.startInline(_ThrowingGame.new),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('while the state was being built'),
          ),
        ),
      );
      _reset();

      // The window is popped in a `finally`, so the stack is empty again and
      // the refusal above still fires. Popped outside one, the dead game's
      // level stays on the stack - and because the level a declaration lands
      // in is the innermost, a system named anywhere at all would quietly
      // join a state that never finished being built and never runs.
      expect(
        () => GameSystem.of(_EarB.new),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no GameState being constructed'),
          ),
        ),
      );
    });
  });

  group('a declaration with nothing built behind it', () {
    test('says so rather than handing back a system', () {
      // A state built the way `_bootMain` builds one, and stopped there. That
      // is the presentation copy exactly: the declarations were made, the
      // spawn carried them, and `_bootGame` - which is what calls a
      // tear-off - only ever runs on the other side.
      DeclarationContext.pushSystems();
      final _NamingState mirror;
      try {
        mirror = EventBinder.open(_NamingState.new);
      } finally {
        DeclarationContext.popSystems();
      }

      expect(mirror.earA.isBuilt, isFalse);
      expect(
        () => mirror.earA.value,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('declared but not built on this copy'),
          ),
        ),
        reason:
            'a system built where this handle was declared would carry a '
            'query numbered out of a component table nothing over there fills',
      );
    });
  });

  group('a build closure handed the owner', () {
    test('is handed the state the declaration is a field of', () async {
      final run = await _boot(_OwnerGame.new);
      expect(
        run.state.getSystem<_OwnedSystem>().tag,
        'base',
      );
    });

    test('dispatches on the state runtime type, so an override wins', () async {
      final run = await _boot(_OverridingGame.new);
      expect(
        run.state.getSystem<_OwnedSystem>().tag,
        'override',
        reason:
            'this is what a bare tear-off cannot do - a field initialiser has '
            'no `this` to call an override point on, and passing the owner in '
            'is what keeps the call virtual',
      );
    });

    test('names both types when the state is not the declared owner', () async {
      await expectLater(
        Game.startInline(_MismatchGame.new),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('_WrongOwner'), contains('_MismatchState')),
          ),
        ),
      );
    });
  });

  group('asking for a system nobody declared', () {
    test('names the state that holds the pass, not the game', () async {
      final run = await _boot(_NamingGame.new);
      final state = run.state as _NamingState;

      expect(state.getSystem<_EarA>(), isA<_EarA>());

      expect(
        () => state.getSystem<_Undeclared>(),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('_Undeclared is not declared by'),
              contains('_NamingState'),
              isNot(contains('_NamingGame')),
            ),
          ),
        ),
        reason:
            'a system is declared on a GameState field. A message naming the '
            'Game sends a reader to a class that declares none',
      );

      expect(
        () => state.disableSystem<_Undeclared>(),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('_NamingState'),
          ),
        ),
      );
    });

    test('a system built by hand names the pass that binds one', () {
      expect(
        () => _Undeclared().state,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('GameSystem.of'),
              isNot(contains('Game.of')),
            ),
          ),
        ),
      );
    });
  });
}
