// flutter_test exports an unrelated EventDispatcher (its pointer-event test
// harness), so the engine's has to win here by name - same reason as
// event_scope_test.dart.
import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;

import 'package:good/src/archetype.dart';
import 'package:good/src/event.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/system.dart';

// Declaring an event on the field that holds it, beside declaring it in
// `describeEvents`.
//
// The two forms have to be the same declaration. A dispatcher built from a
// field initialiser runs during the constructor, one built from the hook runs
// after it, and between those two moments sit a scene registration and an
// `Isolate.spawn` - so the binder that catches the first has to be the one the
// second appends to, or an owner mixing the forms would end up with two
// listener lists that disagree.
//
// What this file pins is that it does not: same owners, same composition,
// same delivery, whichever way each dispatcher was declared.

/// The listener half. Writes into a shared log so *order* is observable and
/// not just membership.
mixin _Noted on GameListener {
  String get noted;

  static final List<String> log = <String>[];

  void onNoted(String event) => _Noted.log.add('$event:$noted');
}

class _NotedSystem extends GameSystem with _Noted {
  @override
  String get noted => 'system';
}

class _UnitA extends EntityStruct with _Noted {
  @override
  String get noted => 'unitA';
}

class _UnitB extends EntityStruct with _Noted {
  @override
  String get noted => 'unitB';

  /// A prefab declaring on its own field, which works because the scene below
  /// registers it with a constructor the framework calls.
  final own = Event.signal<_Noted>((listener) => listener.onNoted('own'));
}

class _NotedScene extends SceneStruct with _Noted {
  @override
  String get noted => 'scene';

  late final _UnitA a;
  late final _UnitB b;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    a = descriptor.has(_UnitA.new);
    b = descriptor.has(_UnitB.new);
  }
}

/// Every dispatcher on a field.
class _FieldState extends GameState<_FieldGame> with _Noted {
  @override
  String get noted => 'state';

  final alpha = Event.of<_Noted, String>(
    (listener, event) => listener.onNoted(event),
  );

  final beta = Event.of<_Noted, String>(
    (listener, event) => listener.onNoted(event),
    reverse: true,
  );

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_NotedSystem.new);
  }
}

/// The same two dispatchers, both in the hook.
class _HookState extends GameState<_HookGame> with _Noted {
  @override
  String get noted => 'state';

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

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_NotedSystem.new);
  }
}

/// One of each, on one owner: `alpha` on a field, `beta` in the hook.
class _MixedState extends GameState<_MixedGame> with _Noted {
  @override
  String get noted => 'state';

  final alpha = Event.of<_Noted, String>(
    (listener, event) => listener.onNoted(event),
  );

  late final EventDispatcher<_Noted, String> beta;

  @override
  void describeEvents(EventDescriptor descriptor) {
    super.describeEvents(descriptor);
    beta = descriptor.has((listener, event) => listener.onNoted(event));
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_NotedSystem.new);
  }
}

abstract class _NotedGame extends Game {
  @override
  int get pageSize => 4096;

  late final _NotedScene level;

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    level = descriptor.has(_NotedScene());
  }
}

class _FieldGame extends _NotedGame {
  @override
  GameState createState() => _FieldState();
}

class _HookGame extends _NotedGame {
  @override
  GameState createState() => _HookState();
}

class _MixedGame extends _NotedGame {
  @override
  GameState createState() => _MixedState();
}

/// An owner outside the engine's four hosts, so the binder can be driven by
/// hand and the collect pass observed without a boot.
class _Pair extends GameListenerBase with EventBus, _Noted {
  @override
  String get noted => 'pair';

  /// Declared first and `late`, which is the shape the engine forbids. If a
  /// `late` initialiser ran when the field was written rather than when it is
  /// read, this one would be in the binder ahead of [eager].
  late final lazy = Event.signal<_Noted>(
    (listener) => listener.onNoted('lazy'),
  );

  final eager = Event.signal<_Noted>((listener) => listener.onNoted('eager'));
}

Future<Game> _boot(_NotedGame game) async {
  final run = await Game.startInline(game);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return run;
}

void main() {
  setUp(_Noted.log.clear);

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('a field and a hook declare the same thing', () {
    test('the collected lists are the same size', () async {
      final run = await _boot(_FieldGame());
      final state = run.state as _FieldState;

      expect(
        state.alpha.listenerCount,
        5,
        reason:
            'the state, the one system, the scene and its two prefabs - the '
            'same composition walk a hook-declared dispatcher gets, reached '
            'through a binder that was open during the constructor',
      );
      expect(state.beta.listenerCount, state.alpha.listenerCount);
    });

    test('delivery order is identical, forward and reverse', () async {
      final fieldRun = await _boot(_FieldGame());
      (fieldRun.state as _FieldState).alpha('alpha');
      (fieldRun.state as _FieldState).beta('beta');
      final fromFields = List<String>.of(_Noted.log);

      await fieldRun.stop();
      SceneRegistry.reset();
      ArchetypeRegistry.reset();
      ComponentTypeRegistry.reset();
      _Noted.log.clear();

      final hookRun = await _boot(_HookGame());
      (hookRun.state as _HookState).alpha('alpha');
      (hookRun.state as _HookState).beta('beta');

      expect(
        fromFields,
        _Noted.log,
        reason:
            'same listeners, same order, both directions. Order is the order '
            'collectListeners offered candidates in, and where a dispatcher '
            'was declared does not enter into that',
      );
      expect(
        fromFields.first,
        'alpha:state',
        reason:
            'and the log is not empty, which would make the two equal for '
            'the wrong reason',
      );
      expect(fromFields.length, 10);
    });

    test('one owner can use both forms at once', () async {
      final run = await _boot(_MixedGame());
      final state = run.state as _MixedState;

      expect(
        state.beta.listenerCount,
        state.alpha.listenerCount,
        reason:
            'the hook appended to the binder the field declarations already '
            'filled rather than getting one of its own',
      );

      state.alpha('alpha');
      final fromField = List<String>.of(_Noted.log);
      _Noted.log.clear();
      state.beta('beta');

      expect(
        _Noted.log,
        fromField.map((entry) => entry.replaceFirst('alpha:', 'beta:')),
        reason: 'and the two lists hold the same listeners in the same order',
      );
    });

    test('a prefab declares on its own field too', () async {
      final game = _FieldGame();
      await _boot(game);

      expect(
        game.level.b.own.listenerCount,
        1,
        reason:
            "a prefab's dispatcher reaches that prefab and nothing else, "
            'whichever way it was declared',
      );
      game.level.b.own.call();
      expect(_Noted.log, <String>['own:unitB']);
    });
  });

  group('the initialiser has to be eager', () {
    test('a late field is missing from the collected list', () {
      final pair = EventBinder.open(_Pair.new);
      EventBinder.bind(pair);

      expect(
        pair.eager.listenerCount,
        1,
        reason:
            'the eager sibling declared and was collected, so the binder was '
            'open and working during the constructor - which is what makes '
            'the throw below the closed-window guard and not some earlier '
            'failure that took the whole object down',
      );

      pair.eager.call();
      expect(
        _Noted.log,
        <String>['eager:pair'],
        reason:
            'one dispatcher delivered, and there is no second one to deliver '
            'from: `lazy` was declared first and is still not in the list',
      );

      expect(
        () => pair.lazy,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('An Event was declared'),
          ),
        ),
        reason:
            'reading it is the first time its initialiser runs, and by then '
            'the binder is closed. A dispatcher built there would hold an '
            'empty list forever and deliver to nobody',
      );

      expect(
        pair.eager.listenerCount,
        1,
        reason: 'and the failed read added nothing to the owner it failed in',
      );
    });

    test('an owner the framework did not construct says so', () {
      expect(
        _Pair.new,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('An Event was declared'),
              contains('descriptor.has(Mote.new)'),
            ),
          ),
        ),
        reason:
            'the eager field runs during the constructor, and there is no '
            'binder open around a bare `_Pair()` - the same rule Field.* and '
            'Param.* state, said in the same place',
      );
    });
  });

  group('binding is once', () {
    test('a second collect pass is refused rather than doubling a list', () {
      final pair = EventBinder.open(_Pair.new);
      EventBinder.bind(pair);

      expect(
        () => EventBinder.bind(pair),
        throwsStateError,
        reason:
            'the late final dispatchers this replaced threw when assigned '
            'twice. A final field would not notice, and every listener would '
            'then receive every event twice',
      );
      expect(pair.eager.listenerCount, 1);
    });
  });
}
