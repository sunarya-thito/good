// flutter_test exports an unrelated EventDispatcher (its pointer-event test
// harness), so the engine's has to win here by name.
import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;

import 'package:good/src/archetype.dart';
import 'package:good/src/event.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/system.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';

part 'event_reach_test.g.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

// Boot-collected dispatch, and who ends up in a list.
//
// Dispatch used to be a *walk*: from object to object at runtime, type-testing
// every candidate on the way, so a class that could never accept an event was
// still visited and still checked, every single time one was fired. The walk
// now happens once, at boot - `describeEvents` creates the dispatchers and
// `collectListeners` fills them - so by the time an event is dispatched the
// receiver list is already correct and dispatch is an indexed `for`.
//
// There is one collect pass and one binder for the whole game, so membership
// is decided by listener type and by nothing else. An event declared on a
// system reaches what one declared on the state reaches; a class that is not
// a `GameListener` - a `SceneStruct`, an `EntityStruct` - is in no list at all.

/// The listener half: a plain mixin on [GameListener], exactly the shape
/// `Tickable`/`FixedTickable` have.
mixin _Ping on GameListener {
  int pings = 0;
  void onPing() => pings++;
}

// There is no event class. Delivery is the closure passed to `Event.signal`
// below, captured once at declare time, so firing allocates nothing.

class _PingSystem extends GameSystem with _Ping {}

/// A system that is *not* a `_Ping` - it must never be collected, and after
/// boot it is never looked at again either.
class _DeafSystem extends GameSystem {}

/// A system that declares a dispatcher of its own.
class _SelfishSystem extends GameSystem with _Ping {
  final ping = Event.signal<_Ping>((listener) => listener.onPing());
}

class _PingUnit extends EntityStruct {}

class _PingScene extends SceneStruct {
  @prefab
  final unit = _PingUnit();
}

class _PingState extends GameState<_PingGame> with _Ping {
  final ping = Event.signal<_Ping>((listener) => listener.onPing());

  @system
  final pingSystem = _PingSystem();
  @system
  final deafSystem = _DeafSystem();
  @system
  final selfishSystem = _SelfishSystem();
}

class _PingGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  late final _PingScene level;

  /// Reached through the state - a system is an `@system` field of one.
  _PingSystem get pinger => run.state.getSystem<_PingSystem>();
  _SelfishSystem get selfish => run.state.getSystem<_SelfishSystem>();

  @override
  GameState createState() => _PingState();

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    level = descriptor.has(_PingScene());
  }
}

Future<_PingGame> _boot() async {
  final game = await Game.startInline(_PingGame.new);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

void main() {
  _installDeclarations();

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('collection happens at boot', () {
    test('the listener list is settled before the first dispatch', () async {
      await _boot();
      final state = run.state as _PingState;

      expect(
        state.ping.listenerCount,
        3,
        reason:
            'the state itself and the two _Ping systems - resolved during '
            'start(), with nothing dispatched yet',
      );
    });

    test('a non-listener is not collected, so it is never visited', () async {
      await _boot();
      final state = run.state as _PingState;
      state.ping.call();

      expect(
        state.ping.listenerCount,
        3,
        reason:
            '_DeafSystem is not a _Ping. Under the old walk it was still '
            'reached and still type-tested on every dispatch; now it is not '
            'in the list at all',
      );
    });
  });

  group('an event reaches every listener, whoever declared it', () {
    test('the state and every system', () async {
      final game = await _boot();
      final state = run.state as _PingState;

      state.ping.call();

      expect(state.pings, 1, reason: 'the owner collects itself');
      expect(game.pinger.pings, 1, reason: 'GameState offers its systems');
      expect(game.selfish.pings, 1);
    });

    test('and a system\'s own event reaches exactly the same set', () async {
      final game = await _boot();
      final state = run.state as _PingState;

      game.selfish.ping.call();

      expect(
        game.selfish.ping.listenerCount,
        state.ping.listenerCount,
        reason:
            'one binder, one collect pass. A dispatcher does not know which '
            'object holds the field it lives on',
      );
      expect(state.pings, 1, reason: 'upwards to the state');
      expect(game.pinger.pings, 1, reason: 'and sideways to a sibling system');
      expect(game.selfish.pings, 1);
    });

    test('every listener is hit exactly once per dispatch', () async {
      final game = await _boot();
      final state = run.state as _PingState;

      state.ping.call();
      state.ping.call();

      expect(
        game.pinger.pings,
        2,
        reason:
            'the composition walk can legitimately reach one listener by '
            'two routes - a system is offered by the state and again by '
            'itself - and the dispatcher dedupes on identity',
      );
    });

    test('two owners declaring one listener type get two lists', () async {
      final game = await _boot();
      final state = run.state as _PingState;

      expect(
        state.ping,
        isNot(same(game.selfish.ping)),
        reason:
            'a dispatcher is per declaration, not per listener type - what '
            'is shared is the audience, not the object',
      );

      game.selfish.ping.call();

      expect(state.pings, 1, reason: 'fired one, and only one, of the two');
    });
  });

  group('a struct is not a listener', () {
    test('so nothing about a scene or a prefab is collected', () async {
      final game = await _boot();
      final state = run.state as _PingState;

      expect(
        state.ping.listenerCount,
        3,
        reason:
            'the scene and its prefab exist and are declared - they are just '
            'not GameListeners, so no list can hold them. A struct hears its '
            'own bring-up through onSceneMounted/onEntityMounted instead',
      );
      expect(game.level.declaredPrefabs, hasLength(1));
    });
  });

  group('listensToEvents is the one thing boot cannot bake', () {
    test('a disabled system stays collected and declines', () async {
      final game = await _boot();
      final state = run.state as _PingState;
      run.state.disableSystem<_PingSystem>();

      state.ping.call();

      expect(game.pinger.pings, 0, reason: 'disabled means it declines');
      expect(
        state.ping.listenerCount,
        3,
        reason:
            'but it is still in the list - enablement is runtime state, '
            'so it is a bool read at dispatch rather than a re-collection',
      );
      expect(
        game.selfish.pings,
        1,
        reason: 'and one listener declining does not stop the loop',
      );
    });

    test('re-enabling needs no re-collection', () async {
      final game = await _boot();
      final state = run.state as _PingState;

      run.state.disableSystem<_PingSystem>();
      state.ping.call();
      run.state.enableSystem<_PingSystem>();
      state.ping.call();

      expect(game.pinger.pings, 1);
    });
  });
}
