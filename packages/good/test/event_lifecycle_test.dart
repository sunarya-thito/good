import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;

import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/event/lifecycle.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/system.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';

part 'event_lifecycle_test.g.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

// Lifecycle at all three levels, and which half of the split each one is.
//
// An owner answering for itself is a virtual. `GameState.onMounted()`,
// `SceneStruct.onSceneMounted(Scene)` and `EntityStruct.onEntityMounted(Entity)`
// are all that shape: the framework is the only caller, there is one receiver,
// and the receiver is the thing the call is about - so it never has to ask
// whether the scene or the entity was one of its own.
//
// Anything *else* wanting to know is an event, and events are global.
// `GameLifecycleListener`, `SceneLoadListener` and `EntitySpawnListener` are
// mixed into a `GameSystem` or the `GameState`, one list per event for the
// whole game, and a listener there expects to filter.

mixin _Marked on Component {
  final mark = Field.uint8(7);

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Marked>();
  }
}

class _Unit extends EntityStruct with _Marked {}

/// Game-level listener. A `GameSystem` is collected into every dispatcher in
/// the game, so this is what hearing the game come up looks like.
class _Watcher extends GameSystem with GameLifecycleListener {
  final List<String> log = <String>[];

  @override
  void onGameMounted() => log.add('game+');

  @override
  void onGameUnmounted() => log.add('game-');
}

/// Listens to nothing - never collected anywhere.
class _Bystander extends GameSystem {}

/// The world-observation half, all four hooks on one system.
class _Observing extends GameSystem
    with SceneLoadListener, EntitySpawnListener {
  final List<String> observed = <String>[];

  @override
  void onSceneLoaded(Scene scene) {
    observed.add('scene.loaded');
    log.add('observer.sceneLoaded');
  }

  @override
  void onSceneUnloaded(Scene scene) {
    observed.add('scene.unloaded');
    log.add('observer.sceneUnloaded');
  }

  @override
  void onEntitySpawned(Entity entity) {
    observed.add('entity.spawned');
    log.add('observer.entitySpawned');
  }

  @override
  void onEntityDespawned(Entity entity) {
    observed.add('entity.despawned');
    log.add('observer.entityDespawned');
  }
}

class _Level extends SceneStruct {
  @sub
  final unit = _Unit();
  Entity? spawned;

  @override
  void onSceneMounted(Scene scene) {
    spawned = scene.addEntity(unit);
    log.add('level.onMounted');
  }
}

/// Ordering probe shared by the fixtures below.
final List<String> log = <String>[];

/// A scene that records its own mounts. It only ever hears about **itself**,
/// which is the property under test.
class _Observer extends SceneStruct {
  final List<Scene> heard = <Scene>[];

  @override
  void onSceneMounted(Scene scene) {
    heard.add(scene);
    log.add('observer.onSceneMounted');
  }
}

class _NosyScene extends SceneStruct {
  @sub
  final unit = _Unit();

  @override
  void onSceneMounted(Scene scene) => log.add('scene.mounted');

  @override
  void onSceneUnmounted(Scene scene) => log.add('scene.unmounted');
}

/// A struct hearing its **own** entities, through the hook the engine calls
/// about them. There is no mixin and no dispatcher: one receiver, one caller.
class _Tracked extends EntityStruct with _Marked {
  final List<Entity> mine = <Entity>[];
  final List<Entity> gone = <Entity>[];

  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    mine.add(entity);
    log.add('tracked.mounted');
  }

  @override
  void onEntityUnmounted(Entity entity) {
    super.onEntityUnmounted(entity);
    gone.add(entity);
    log.add('tracked.unmounted');
  }
}

class _Indexed extends EntityStruct with _Marked {}

/// The system half of the same question: it sees every entity in the game and
/// filters, which is what watching the world costs and what it buys.
class _Census extends GameSystem with EntitySpawnListener {
  final List<Entity> mounted = <Entity>[];
  final List<Entity> unmounted = <Entity>[];

  /// Read during despawn, to prove the row is still live at that point.
  final List<int> marksAtUnmount = <int>[];

  @override
  void onEntitySpawned(Entity entity) {
    if (!entity.has<_Marked>()) return;
    mounted.add(entity);
  }

  @override
  void onEntityDespawned(Entity entity) {
    if (!entity.has<_Marked>()) return;
    unmounted.add(entity);
    marksAtUnmount.add(entity<_Marked>().component.mark[entity]);
  }
}

class _TrackedScene extends SceneStruct {
  @sub
  final tracked = _Tracked();
  @sub
  final indexed = _Indexed();
}

class _LifecycleState extends GameState<_LifecycleGame> {
  @override
  void onMounted() {
    loadScene(game.level);
    loadScene(game.observer);
  }

  @system
  final watcher = _Watcher();
  @system
  final census = _Census();
  @system
  final bystander = _Bystander();
  @system
  final observing = _Observing();
}

class _LifecycleGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  late final _Level level;
  late final _Observer observer;
  late final _NosyScene nosyScene;
  late final _TrackedScene trackedScene;

  /// Reached through the state, because that is where systems live. They were
  /// `late final` fields on this class, assigned during a declaration pass -
  /// a system is an `@system` field of the `GameState` now, so a field here
  /// would be written on a copy that never declares one.
  _Watcher get watcher => run.state.getSystem<_Watcher>();
  _Census get census => run.state.getSystem<_Census>();
  _Observing get observing => run.state.getSystem<_Observing>();

  @override
  GameState createState() => _LifecycleState();

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    level = descriptor.has(_Level());
    observer = descriptor.has(_Observer());
    nosyScene = descriptor.has(_NosyScene());
    trackedScene = descriptor.has(_TrackedScene());
  }
}

Future<_LifecycleGame> _boot() async {
  final game = await Game.startInline(_LifecycleGame.new);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

void main() {
  _installDeclarations();

  setUp(log.clear);

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('game lifecycle, declared on GameState', () {
    test('a system hears the game come up - the capability that used to be '
        'declarable and dead', () async {
      final game = await _boot();

      expect(
        game.watcher.log,
        contains('game+'),
        reason:
            'a GameSystem mixing in the old LifecycleListener compiled '
            'fine and never fired, because the dispatch walk only ever '
            'reached the GameState',
      );
      expect(game.watcher.log.where((e) => e == 'game+').length, 1);
    });

    test('after every scene is mounted, so the world already exists', () async {
      final game = await _boot();

      expect(log, contains('level.onMounted'));
      expect(game.level.spawned, isNotNull);
      expect(game.watcher.log, contains('game+'));
    });

    test('unmount fires while the world is still standing', () async {
      final game = await _boot();
      await run.stop();

      expect(game.watcher.log, ['game+', 'game-']);
    });
  });

  group('scene lifecycle is the scene answering for itself', () {
    test('a scene hears its own mount, and is told which instance', () async {
      final game = await _boot();

      expect(game.observer.heard, hasLength(1));
      expect(
        game.observer.heard.single<_Observer>(),
        same(game.observer),
        reason:
            'the handle, not the struct - one struct backs many loaded '
            'scenes, so only the handle identifies the instance',
      );
    });

    test('and never hears another scene', () async {
      final game = await _boot();

      // Both _Level and _Observer are loaded during boot.
      expect(
        game.observer.heard.map((s) => s<SceneStruct>()),
        everyElement(same(game.observer)),
        reason:
            'onSceneMounted is called on the struct being mounted and on no '
            'other, so a scene never compares handles to find out an event '
            'was not about it. That is the whole of what a virtual buys here',
      );
    });

    test('unload is announced while the entities are still readable', () async {
      final game = await _boot();
      final scene = await run.state.loadScene(game.nosyScene);
      expect(log, contains('scene.mounted'));

      run.state.unloadScene(scene);

      expect(log, contains('scene.unmounted'));
      expect(scene.isLoaded, isFalse);
    });

    test('one call per load, including later ones', () async {
      final game = await _boot();
      await run.state.loadScene(game.observer);

      expect(
        game.observer.heard,
        hasLength(2),
        reason:
            'two instances of one declaration are two mounts, and the '
            'struct is told about each - the handle is what tells them apart',
      );
      expect(game.observer.heard.first, isNot(game.observer.heard.last));
    });
  });

  group('entity lifecycle is the struct answering for itself', () {
    test(
      "the struct's own onEntityMounted fires, for its own entities only",
      () async {
        final game = await _boot();
        final scene = await run.state.loadScene(game.trackedScene);
        final entity = scene.addEntity(game.trackedScene.tracked);

        expect(game.trackedScene.tracked.mine, [entity]);
        expect(
          game.trackedScene.tracked.mine,
          isNot(contains(game.level.spawned)),
          reason:
              'and not another struct\'s entities, even though _Level '
              'spawned one during boot',
        );
      },
    );

    test('a system sees every entity and filters', () async {
      final game = await _boot();
      final scene = await run.state.loadScene(game.trackedScene);
      final tracked = scene.addEntity(game.trackedScene.tracked);
      final indexed = scene.addEntity(game.trackedScene.indexed);

      expect(
        game.census.mounted,
        containsAll(<Entity>[tracked, indexed]),
        reason:
            'EntitySpawnListener is the world-observation half: a system '
            'asked to see everything and gets everything, its own filter '
            'deciding what it keeps',
      );
    });

    test('the struct hook runs before the observation event', () async {
      final game = await _boot();
      final scene = await run.state.loadScene(game.trackedScene);
      log.clear();

      scene.addEntity(game.trackedScene.tracked);

      expect(
        log,
        ['tracked.mounted', 'observer.entitySpawned'],
        reason:
            'something watching the whole world sees an entity whose struct '
            'has already initialised it',
      );
    });

    test('a listener sees the declared defaults already stamped', () async {
      final game = await _boot();
      final scene = await run.state.loadScene(game.trackedScene);
      final indexed = scene.addEntity(game.trackedScene.indexed);

      expect(
        game.trackedScene.indexed.mark[indexed],
        7,
        reason: 'the notification is the last thing addEntity does',
      );
    });

    test(
      'unload tears entities down while their rows are still readable',
      () async {
        final game = await _boot();
        final scene = await run.state.loadScene(game.trackedScene);
        final tracked = scene.addEntity(game.trackedScene.tracked);
        final indexed = scene.addEntity(game.trackedScene.indexed);
        game.trackedScene.indexed.mark[indexed] = 42;
        game.census.marksAtUnmount.clear();

        run.state.unloadScene(scene);

        expect(game.trackedScene.tracked.gone, [
          tracked,
        ], reason: 'the struct is told its own entity is going');
        expect(game.census.unmounted, containsAll(<Entity>[tracked, indexed]));
        expect(
          game.census.marksAtUnmount,
          contains(42),
          reason:
              'read from inside the listener - the pages are released '
              'immediately afterwards, so this is the only moment it works',
        );
        expect(
          () => game.trackedScene.tracked.mark[tracked],
          throwsStateError,
          reason: 'and gone directly after',
        );
      },
    );

    test(
      'destroy() calls the struct\'s own unmount, not scene unload only',
      () async {
        // The stale claim this was written for: "there is no per-entity
        // destroy yet - rows are not recycled - so scene unload is the only
        // thing that fires this". Both halves were false, and the last change
        // that trusted it leaked a Box2D body per destroyed entity.
        final game = await _boot();
        final scene = await run.state.loadScene(game.trackedScene);
        final doomed = scene.addEntity(game.trackedScene.tracked);
        final kept = scene.addEntity(game.trackedScene.tracked);
        log.clear();

        doomed.destroy();

        expect(game.trackedScene.tracked.gone, [doomed]);
        expect(
          game.trackedScene.tracked.gone,
          isNot(contains(kept)),
          reason: 'and only the entity that was actually destroyed',
        );
        expect(
          log,
          ['observer.entityDespawned', 'tracked.unmounted'],
          reason:
              'observation first on the way out, mirroring the way the '
              'struct goes first on the way in',
        );
      },
    );
  });

  group('membership', () {
    test('a listener is only in the lists its type allows', () async {
      final game = await _boot();
      final state = run.state;

      expect(
        state.gameMountedEvent.listenerCount,
        1,
        reason:
            'only _Watcher. _Bystander listens to nothing, and the scene and '
            'entity structs are not GameListeners at all',
      );
      expect(
        state.entitySpawnedEvent.listenerCount,
        2,
        reason: '_Census and _Observing, both systems',
      );
      expect(
        state.sceneLoadedEvent.listenerCount,
        1,
        reason:
            'just _Observing - a SceneStruct hearing its own mount needs no '
            'entry here, because it is not being dispatched to',
      );
      expect(game.observer.heard, isNotEmpty);
    });

    test(
      'a disabled system declines an observation event like any other',
      () async {
        final game = await _boot();
        // _Level spawns one during boot, and the census hears every entity in
        // the game now - so the list has to start from a known point rather
        // than from whatever the bring-up put in it.
        game.census.mounted.clear();
        run.state.disableSystem<_Census>();
        final scene = await run.state.loadScene(game.trackedScene);
        scene.addEntity(game.trackedScene.indexed);

        expect(
          game.census.mounted,
          isEmpty,
          reason:
              'listensToEvents is checked per dispatch, and a lifecycle '
              'event is not special-cased out of it',
        );
      },
    );

    test('a disabled system does not stop the struct hearing itself', () async {
      final game = await _boot();
      run.state.disableSystem<_Census>();
      final scene = await run.state.loadScene(game.trackedScene);
      final entity = scene.addEntity(game.trackedScene.tracked);

      expect(
        game.trackedScene.tracked.mine,
        [entity],
        reason:
            'the struct hook is a method call and goes through no dispatcher, '
            'so nothing about the event system can switch it off',
      );
    });
  });

  group('bring-up and tear-down run in opposite orders', () {
    // The scene used to be told through a dispatcher its prefabs shared, read
    // forwards at mount and backwards at unmount. The virtual keeps the same
    // observable order against the world-observation event beside it, and
    // deleting either `reverse: true` or one of the two call orders in
    // `GameState` leaves the rest of this file passing.
    test('the scene is told first at mount and last at unmount', () async {
      final game = await _boot();
      log.clear();

      final scene = await run.state.loadScene(game.nosyScene);
      expect(
        log,
        ['scene.mounted', 'observer.sceneLoaded'],
        reason:
            'outside-in: the scene has spawned its starting entities by the '
            'time anything watching the world is told',
      );

      log.clear();
      run.state.unloadScene(scene);
      expect(
        log.take(2),
        ['observer.sceneUnloaded', 'scene.unmounted'],
        reason:
            'inside-out: the scene is told last, so it can still read a '
            'world the observers have already been warned about',
      );
    });
  });
}
