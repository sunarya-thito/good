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

part 'event_scope_test.g.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

// Scoped, boot-collected dispatch.
//
// Dispatch used to be a *walk*: from object to object at runtime, type-testing
// every candidate on the way, so a class that could never accept an event was
// still visited and still checked, every single time one was fired. The walk
// now happens once, at boot - `describeEvents` creates the dispatchers and
// `collectListeners` fills them - so by the time an event is dispatched the
// receiver list is already correct and dispatch is an indexed `for`.
//
// What that buys, and what this file pins down, is *scope*. A dispatcher
// belongs to whoever declared it and collects from that owner's composition
// and no further. Declared on a `GameState` it reaches everything beneath -
// systems, scenes, and the prefabs those scenes registered. Declared on a
// prefab it reaches that prefab and nothing else, which is the mechanism a
// per-struct `onMounted(Entity)` will be built out of.

/// The listener half: a plain mixin on [GameListener], exactly the shape
/// `Tickable`/`FixedTickable` have.
mixin _Ping on GameListener {
  int pings = 0;
  void onPing() => pings++;
}

// There is no event class. Delivery is the closure passed to `hasSignal`
// below, captured once at declare time, so firing allocates nothing.

class _PingSystem extends GameSystem with _Ping {}

/// A system that is *not* a `_Ping` - it must never be collected, and after
/// boot it is never looked at again either.
class _DeafSystem extends GameSystem {}

class _PingUnit extends EntityStruct with _Ping {}

/// A prefab that declares a dispatcher of its own. Its dispatcher collects
/// from its own composition only, which is one object: itself.
class _SelfishUnit extends EntityStruct with _Ping {
  // On the field, which works because `_PingScene` registers this one with
  // `descriptor.has(_SelfishUnit.new)` - a constructor the framework calls.
  final ping = Event.signal<_Ping>((listener) => listener.onPing());
}

class _PingScene extends SceneStruct with _Ping {
  late final _PingUnit unit;
  late final _SelfishUnit selfish;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    unit = descriptor.has(_PingUnit.new);
    selfish = descriptor.has(_SelfishUnit.new);
  }
}

class _PingState extends GameState<_PingGame> with _Ping {
  final ping = Event.signal<_Ping>((listener) => listener.onPing());

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_PingSystem.new);
    descriptor.has(_DeafSystem.new);
  }
}

class _PingGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  late final _PingScene level;

  /// Reached through the state - `describeSystems` is a `GameState` pass now.
  _PingSystem get pinger => run.state.getSystem<_PingSystem>();

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
        5,
        reason:
            'the state itself, the one _Ping system, the scene, and the '
            "scene's two prefabs - resolved during start(), with nothing "
            'dispatched yet',
      );
    });

    test('a non-listener is not collected, so it is never visited', () async {
      await _boot();
      final state = run.state as _PingState;
      state.ping.call();

      expect(
        state.ping.listenerCount,
        5,
        reason:
            '_DeafSystem is not a _Ping. Under the old walk it was still '
            'reached and still type-tested on every dispatch; now it is not '
            'in the list at all',
      );
    });
  });

  group('an event declared on the GameState reaches the whole composition', () {
    test('down through systems, scenes and prefabs', () async {
      final game = await _boot();
      final state = run.state as _PingState;

      state.ping.call();

      expect(state.pings, 1, reason: 'the owner collects itself');
      expect(game.pinger.pings, 1, reason: 'GameState offers its systems');
      expect(game.level.pings, 1, reason: 'and its declared scenes');
      expect(
        game.level.unit.pings,
        1,
        reason:
            'and each scene offers the prefabs it registered - this is '
            'the Game -> Scenes -> Entities broadcast, walked once at boot '
            'instead of once per event',
      );
      expect(game.level.selfish.pings, 1);
    });

    test('every listener is hit exactly once per dispatch', () async {
      final game = await _boot();
      final state = run.state as _PingState;

      state.ping.call();
      state.ping.call();

      expect(
        game.level.unit.pings,
        2,
        reason:
            'the composition walk can legitimately reach one listener by '
            'two routes; the dispatcher dedupes on identity so a double '
            'delivery cannot happen',
      );
    });
  });

  group('an event declared lower down stays there', () {
    test(
      "a prefab's own dispatcher reaches that prefab and nothing else",
      () async {
        final game = await _boot();
        final selfish = game.level.selfish;

        expect(
          selfish.ping.listenerCount,
          1,
          reason:
              'a prefab composes nothing further, so its dispatcher is the '
              'narrowest scope there is',
        );

        selfish.ping.call();

        expect(selfish.pings, 1);
        expect(game.level.unit.pings, 0, reason: 'not its sibling prefab');
        expect(game.level.pings, 0, reason: 'not upwards to its scene');
        expect(game.pinger.pings, 0, reason: 'and not sideways to systems');
        expect((run.state as _PingState).pings, 0);
      },
    );

    test('the same listener type is two independent dispatchers', () async {
      final game = await _boot();
      final state = run.state as _PingState;

      expect(
        state.ping,
        isNot(same(game.level.selfish.ping)),
        reason:
            'scope is per declaring owner, not per listener type - two '
            'owners declaring EventDispatcher<_Ping> get two lists',
      );
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
        5,
        reason:
            'but it is still in the list - enablement is runtime state, '
            'so it is a bool read at dispatch rather than a re-collection',
      );
      expect(
        game.level.unit.pings,
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
