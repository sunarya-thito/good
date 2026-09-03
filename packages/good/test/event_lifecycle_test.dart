import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;

import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/event.dart';
import 'package:good/src/event/lifecycle.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/system.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

// Lifecycle at all three levels, and the scoping that decides who hears what.
//
// Only `GameState.onMounted()` is still a plain virtual. The scene and entity
// levels used to have one each; now the owner mixes in the same listener
// anything else would - `SceneLifecycleListener`, `EntityLifecycleListener` -
// and hears itself through its own dispatcher. What differs between the levels
// is where that dispatcher is declared, and that is not a detail - it *is* the
// audience:
//
//  * game lifecycle is declared on `GameState`, so it reaches everything -
//    correct, because `GameState` is the only object at that level;
//  * scene lifecycle is declared on the `SceneStruct`, so unloading scene A
//    cannot tell scene B;
//  * entity lifecycle is declared on the `EntityStruct`, so a listener never
//    has to ask whether the entity was one of its own.
//
// Widening any of them is explicit: override `collectListeners` and offer the
// listener in, which `_Indexed` below does for a system.

mixin _Marked on Component {
  final mark = Field.uint8(7);

  final markedType = Component.type<_Marked>();
}

class _Unit extends EntityStruct with _Marked {}

/// Game-level listener. A `GameSystem` is collected into `GameState`'s
/// dispatchers, so this is the level it can hear without being offered in.
class _Watcher extends GameSystem with GameLifecycleListener {
  final List<String> log = <String>[];

  @override
  void onGameMounted() => log.add('game+');

  @override
  void onGameUnmounted() => log.add('game-');
}

/// Listens to nothing - never collected anywhere.
class _Bystander extends GameSystem {}

/// A system mixing in both halves at once: the two *scoped* lifecycle mixins,
/// which no dispatcher a system reaches ever delivers, and the two
/// *observation* events, which `GameState` declares and does.
///
/// The pairing is the point. [scoped] staying empty is the claim under test,
/// and an empty list proves nothing on its own - [observed] filling up is what
/// says the system is wired, enabled and running, so the empty one means the
/// event never arrived rather than that the fixture is dead.
class _Deaf extends GameSystem
    with
        SceneLifecycleListener,
        EntityLifecycleListener,
        SceneLoadListener,
        EntitySpawnListener {
  final List<String> scoped = <String>[];
  final List<String> observed = <String>[];

  @override
  void onSceneMounted(Scene scene) => scoped.add('scene.mounted');

  @override
  void onSceneUnmounted(Scene scene) => scoped.add('scene.unmounted');

  @override
  void onEntityMounted(Entity entity) => scoped.add('entity.mounted');

  @override
  void onEntityUnmounted(Entity entity) => scoped.add('entity.unmounted');

  @override
  void onSceneLoaded(Scene scene) => observed.add('scene.loaded');

  @override
  void onSceneUnloaded(Scene scene) => observed.add('scene.unloaded');

  @override
  void onEntitySpawned(Entity entity) => observed.add('entity.spawned');

  @override
  void onEntityDespawned(Entity entity) => observed.add('entity.despawned');
}

class _Level extends SceneStruct {
  late final _Unit unit;
  Entity? spawned;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    unit = descriptor.has(_Unit.new);
  }

  @override
  void onSceneMounted(Scene scene) {
    spawned = scene.addEntity(unit);
    log.add('level.onMounted');
  }
}

/// Ordering probe shared by the fixtures below.
final List<String> log = <String>[];

/// A scene that listens for scene lifecycle. Because the dispatcher belongs to
/// the scene, this only ever hears about **itself** - which is the property
/// under test.
class _Observer extends SceneStruct with SceneLifecycleListener {
  final List<Scene> heard = <Scene>[];

  @override
  void onSceneMounted(Scene scene) {
    heard.add(scene);
    log.add('observer.onSceneMounted');
  }
}

/// A prefab that listens for *its scene's* lifecycle - reachable because a
/// scene's collect pass walks its prefabs.
class _SceneAware extends EntityStruct with SceneLifecycleListener {
  final List<Scene> heard = <Scene>[];

  @override
  void onSceneMounted(Scene scene) {
    heard.add(scene);
    log.add('prefab.mounted');
  }

  @override
  void onSceneUnmounted(Scene scene) => log.add('prefab.unmounted');
}

/// A prefab that hears the *game* coming up: the bottom of the composition
/// walk from `GameState` down.
class _Nosy extends EntityStruct with GameLifecycleListener {
  int mounts = 0;

  @override
  void onGameMounted() => mounts++;
}

class _NosyScene extends SceneStruct {
  late final _Nosy nosy;
  late final _SceneAware aware;

  @override
  void onSceneMounted(Scene scene) => log.add('scene.mounted');

  @override
  void onSceneUnmounted(Scene scene) => log.add('scene.unmounted');

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    nosy = descriptor.has(_Nosy.new);
    aware = descriptor.has(_SceneAware.new);
  }
}

/// A struct hearing its **own** entities.
///
/// There is no separate virtual hook for this: a prefab's default
/// `collectListeners` offers itself, so mixing in [EntityLifecycleListener] is
/// what a struct does to initialise its own rows. One mechanism, and the same
/// one anything else would use.
class _Tracked extends EntityStruct with _Marked, EntityLifecycleListener {
  final List<Entity> mine = <Entity>[];
  final List<Entity> gone = <Entity>[];

  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    mine.add(entity);
  }

  @override
  void onEntityUnmounted(Entity entity) {
    super.onEntityUnmounted(entity);
    gone.add(entity);
  }
}

/// Widening the audience, explicitly: this struct offers a *system* into its
/// own dispatcher, so `_Census` hears `_Indexed` entities and no others.
class _Indexed extends EntityStruct with _Marked {
  @override
  void collectListeners(ListenerCollector collector) {
    super.collectListeners(collector);
    collector.offer(getSystem<_Census>());
  }
}

/// Offered in by [_Indexed]. It is a system, so nothing collects it into an
/// entity dispatcher by default - being told is something a struct opts it
/// into.
class _Census extends GameSystem with EntityLifecycleListener {
  final List<Entity> mounted = <Entity>[];
  final List<Entity> unmounted = <Entity>[];

  /// Read during unmount, to prove the row is still live at that point.
  final List<int> marksAtUnmount = <int>[];

  @override
  void onEntityMounted(Entity entity) => mounted.add(entity);

  @override
  void onEntityUnmounted(Entity entity) {
    unmounted.add(entity);
    marksAtUnmount.add(entity<_Marked>().component.mark[entity]);
  }
}

class _TrackedScene extends SceneStruct {
  late final _Tracked tracked;
  late final _Indexed indexed;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    tracked = descriptor.has(_Tracked.new);
    indexed = descriptor.has(_Indexed.new);
  }
}

class _LifecycleState extends GameState<_LifecycleGame> {
  @override
  void onMounted() {
    loadScene(game.level);
    loadScene(game.observer);
  }

  final watcher = GameSystem.of(_Watcher.new);
  final census = GameSystem.of(_Census.new);
  final bystander = GameSystem.of(_Bystander.new);
  final deaf = GameSystem.of(_Deaf.new);
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
  /// `late final` fields on this class, assigned during `describeSystems` -
  /// which is a `GameState` pass now, so a field here would be written on a
  /// copy that no longer runs it.
  _Watcher get watcher => run.state.getSystem<_Watcher>();
  _Census get census => run.state.getSystem<_Census>();
  _Deaf get deaf => run.state.getSystem<_Deaf>();

  @override
  GameState createState() => _LifecycleState();

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    level = descriptor.has(_Level.new);
    observer = descriptor.has(_Observer.new);
    nosyScene = descriptor.has(_NosyScene.new);
    trackedScene = descriptor.has(_TrackedScene.new);
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

    test('reaches prefabs too, not just systems', () async {
      final game = await _boot();

      expect(
        game.nosyScene.nosy.mounts,
        1,
        reason:
            'GameState -> scenes -> prefabs: the whole composition, '
            'collected once at boot',
      );
    });

    test('unmount fires while the world is still standing', () async {
      final game = await _boot();
      await run.stop();

      expect(game.watcher.log, ['game+', 'game-']);
    });
  });

  group('scene lifecycle, declared on the SceneStruct', () {
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
            'the dispatcher belongs to _Observer, so its list was '
            'filled from _Observer\'s composition. Declared on GameState '
            'this would be one list holding every scene, and loading _Level '
            'would call onSceneMounted(_Level) on _Observer, which would '
            'then have to compare handles to find out it was not about it',
      );
    });

    test('a prefab hears its own scene mount', () async {
      final game = await _boot();
      final scene = await run.state.loadScene(game.nosyScene);

      expect(
        game.nosyScene.aware.heard,
        [scene],
        reason:
            'a scene collects its prefabs, so this is in range - and it '
            'heard only its own scene, not _Level or _Observer',
      );
    });

    test('unload is announced while the entities are still readable', () async {
      final game = await _boot();
      final scene = await run.state.loadScene(game.nosyScene);
      expect(game.nosyScene.aware.heard, hasLength(1));

      run.state.unloadScene(scene);

      expect(scene.isLoaded, isFalse);
    });

    test('one dispatch per load, including later ones', () async {
      final game = await _boot();
      await run.state.loadScene(game.observer);

      expect(
        game.observer.heard,
        hasLength(2),
        reason:
            'two instances of one declaration are two mounts, and the '
            'struct is told about each - the handle is what tells them '
            'apart, which is the one case a struct legitimately hears about '
            'a sibling instance',
      );
      expect(game.observer.heard.first, isNot(game.observer.heard.last));
    });
  });

  group('entity lifecycle, declared on the EntityStruct', () {
    test(
      "the struct's own onMounted fires, for its own entities only",
      () async {
        final game = await _boot();
        final scene = await run.state.loadScene(game.trackedScene);
        final entity = scene.addEntity(game.trackedScene.tracked);

        expect(
          game.trackedScene.tracked.mine,
          [entity],
          reason:
              'the narrow half, unchanged apart from its name - it was '
              'onCreated, which made the entity level read as a different '
              'kind of thing from the two levels above it',
        );
        expect(
          game.trackedScene.tracked.mine,
          isNot(contains(game.level.spawned)),
          reason:
              'and not another struct\'s entities, even though _Level '
              'spawned one during boot',
        );
      },
    );

    test(
      'a system offered in by a struct hears that struct\'s entities',
      () async {
        final game = await _boot();
        final scene = await run.state.loadScene(game.trackedScene);
        final indexed = scene.addEntity(game.trackedScene.indexed);

        expect(
          game.census.mounted,
          [indexed],
          reason:
              '_Indexed offers _Census into its own dispatcher, which is '
              'how a system is let into a scope it is not part of',
        );
      },
    );

    test('and hears nothing from a struct that did not offer it', () async {
      final game = await _boot();
      final scene = await run.state.loadScene(game.trackedScene);
      scene.addEntity(game.trackedScene.tracked);

      expect(
        game.census.mounted,
        isEmpty,
        reason:
            '_Tracked never offered _Census in, so its entities are '
            'invisible to it - no filtering by archetype required, because '
            'the event never arrives',
      );
      expect(game.census.mounted, isNot(contains(game.level.spawned)));
    });

    test(
      'the event fires after the struct hook, on a finished entity',
      () async {
        final game = await _boot();
        final scene = await run.state.loadScene(game.trackedScene);
        final indexed = scene.addEntity(game.trackedScene.indexed);

        expect(
          game.trackedScene.indexed.mark[indexed],
          7,
          reason:
              'a listener sees declared defaults already stamped, because '
              'the dispatch is the last thing addEntity does',
        );
      },
    );

    test(
      'unload tears entities down while their rows are still readable',
      () async {
        final game = await _boot();
        final scene = await run.state.loadScene(game.trackedScene);
        final tracked = scene.addEntity(game.trackedScene.tracked);
        final indexed = scene.addEntity(game.trackedScene.indexed);
        game.trackedScene.indexed.mark[indexed] = 42;

        run.state.unloadScene(scene);

        expect(game.trackedScene.tracked.gone, [
          tracked,
        ], reason: 'the struct is told its own entity is going');
        expect(
          game.census.unmounted,
          [indexed],
          reason:
              'and so is the system _Indexed offered in - and only for '
              '_Indexed entities',
        );
        expect(
          game.census.marksAtUnmount,
          [42],
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
  });

  group('membership', () {
    test('a listener is only in the lists its type and scope allow', () async {
      final game = await _boot();
      final state = run.state;

      expect(
        state.gameMountedEvent.listenerCount,
        2,
        reason:
            '_Watcher (a system) and _Nosy (a prefab). _Bystander '
            'listens to nothing, and the scene/entity listeners are not '
            'game-level',
      );
      expect(
        game.observer.mountedEvent.listenerCount,
        1,
        reason: 'the observer scene collects only itself - it has no prefabs',
      );
      expect(
        game.nosyScene.aware.mountedEvent.listenerCount,
        0,
        reason:
            'a prefab composes nothing, and _SceneAware is not an '
            'EntityLifecycleListener, so its own entity dispatcher is empty',
      );
      expect(
        game.trackedScene.indexed.mountedEvent.listenerCount,
        1,
        reason:
            'just the _Census it offered in - _Indexed is not itself an '
            'EntityLifecycleListener',
      );
    });

    test(
      'a disabled system declines a lifecycle event like any other',
      () async {
        final game = await _boot();
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
  });

  group('the scoped lifecycle events never reach a system', () {
    // `event/lifecycle.dart` used to say a `GameSystem` mixing in
    // `SceneLifecycleListener` heard "a scene mounted" as a broadcast, and
    // that `EntityLifecycleListener` had a broadcast half wherever `GameState`
    // collects. Neither dispatcher exists: `GameState` declares
    // `SceneLoadListener` and `EntitySpawnListener` for that question, and the
    // scoped pair is declared on the `SceneStruct` and the `EntityStruct`,
    // which collect their own composition. A system following the old comment
    // got a hook that compiled and never ran, which is the one kind of failure
    // no other test can see - it looks exactly like a hook nobody wrote.

    test('a system hears no scene lifecycle, and every scene load', () async {
      final game = await _boot();
      final deaf = game.deaf;
      deaf.scoped.clear();
      deaf.observed.clear();

      final scene = await run.state.loadScene(game.nosyScene);
      run.state.unloadScene(scene);

      expect(
        deaf.scoped,
        isEmpty,
        reason:
            'SceneLifecycleListener is delivered only by a SceneStruct\'s own '
            'mountedEvent/unmountedEvent, and those collect that struct and '
            'its prefabs - a system is offered to neither',
      );
      expect(
        deaf.observed,
        ['scene.loaded', 'scene.unloaded'],
        reason:
            'the same system heard both through SceneLoadListener, which is '
            'what GameState declares for this question',
      );
    });

    test('a system hears no entity lifecycle, and every spawn', () async {
      final game = await _boot();
      final scene = await run.state.loadScene(game.trackedScene);
      final deaf = game.deaf;
      deaf.scoped.clear();
      deaf.observed.clear();

      final entity = scene.addEntity(game.trackedScene.tracked);
      entity.destroy();

      expect(
        deaf.scoped,
        isEmpty,
        reason:
            'EntityLifecycleListener is delivered only by an EntityStruct\'s '
            'own dispatchers, which collect that struct. _Tracked never '
            'offered this system in, the way _Indexed offers _Census',
      );
      expect(
        deaf.observed,
        ['entity.spawned', 'entity.despawned'],
        reason:
            'and EntitySpawnListener on the same system saw both ends, which '
            'is what a spatial index or a physics backend mixes in',
      );
    });

    test(
      'destroy() fires the struct\'s own unmount, not scene unload only',
      () async {
        // The other stale claim: "there is no per-entity destroy yet - rows are
        // not recycled - so scene unload is the only thing that fires this".
        // Both halves were false, and the last change that trusted it leaked a
        // Box2D body per destroyed entity.
        final game = await _boot();
        final scene = await run.state.loadScene(game.trackedScene);
        final doomed = scene.addEntity(game.trackedScene.tracked);
        final kept = scene.addEntity(game.trackedScene.tracked);

        doomed.destroy();

        expect(game.trackedScene.tracked.gone, [doomed]);
        expect(
          game.trackedScene.tracked.gone,
          isNot(contains(kept)),
          reason: 'and only the entity that was actually destroyed',
        );
      },
    );
  });

  group('bring-up and tear-down run in opposite orders', () {
    // This is the guarantee that used to be carried by a pair of virtuals
    // (`SceneStruct.onMounted`/`onUnmounted`) bracketing the dispatch. Those
    // are gone; what replaced them is one collect pass read forwards at mount
    // and backwards at unmount (`reverse: true` on `unmountedEvent`).
    //
    // Nothing covered it before, and it is not self-evident: deleting the
    // `reverse` flag leaves every other test in this file and in
    // multi_scene_test passing.
    test('the scene is told first at mount and last at unmount', () async {
      final game = await _boot();
      log.clear();

      final scene = await run.state.loadScene(game.nosyScene);
      expect(
        log,
        ['scene.mounted', 'prefab.mounted'],
        reason:
            'outside-in: the scene has spawned its starting entities by '
            'the time anything it composes is told, which is exactly what '
            "SceneLifecycleListener.onSceneMounted's doc promises",
      );

      log.clear();
      run.state.unloadScene(scene);
      expect(
        log,
        ['prefab.unmounted', 'scene.unmounted'],
        reason:
            'inside-out: the scene is told last, so it can still read a '
            'world its prefabs have already been warned about. Reversed '
            'from the mount order, off the same collected list',
      );
    });
  });
}
