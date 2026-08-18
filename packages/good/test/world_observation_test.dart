// The world-observation events: entitySpawned/Despawned, sceneLoaded/Unloaded.
//
// These are deliberately NOT the lifecycle events at a wider scope - they are
// a different question with different names (see event/lifecycle.dart). The
// tests below pin both halves of that: an observer hears everything in the
// game, and the narrow lifecycle events keep their own scope untouched.

import 'package:flutter_test/flutter_test.dart';
import 'package:good/good.dart';

class _Rock extends EntityStruct {}

class _Tree extends EntityStruct {}

/// Can hold a parent and children, so a destroy can be tested on a subtree
/// rather than only on a lone entity.
class _Node extends EntityStruct with Child, Parent {}

/// Hears only its own entities, through the narrow lifecycle event.
class _Watched extends EntityStruct with EntityLifecycleListener {
  static int mounted = 0;

  @override
  void onEntityMounted(Entity entity) {
    mounted++;
    order.add('prefab.mounted');
  }
}

/// Every observation in the order it actually happened. Order is the thing
/// several of these tests assert, and inferring it from final list contents
/// cannot fail - both lists are non-empty at the end either way.
final List<String> order = <String>[];

class _Scene extends SceneStruct {
  late Scene handle;
  late final _Rock rock;
  late final _Tree tree;
  late final _Node node;
  late final _Watched watched;

  @override
  void onSceneMounted(Scene scene) => handle = scene;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    rock = descriptor.has(_Rock());
    tree = descriptor.has(_Tree());
    node = descriptor.has(_Node());
    watched = descriptor.has(_Watched());
  }
}

/// A system watching the whole world.
class _Observer extends GameSystem with EntitySpawnListener, SceneLoadListener {
  final List<Entity> spawned = <Entity>[];
  final List<Entity> despawned = <Entity>[];
  final List<Scene> loaded = <Scene>[];
  final List<Scene> unloaded = <Scene>[];

  /// Whether every despawned entity's row was still readable when told.
  bool rowsReadableOnDespawn = true;

  @override
  void onEntitySpawned(Entity entity) {
    spawned.add(entity);
    order.add('world.spawned');
  }

  @override
  void onEntityDespawned(Entity entity) {
    despawned.add(entity);
    order.add('world.despawned');
    // The contract says the row is still readable here.
    if (entity.tryGet<Component>() == null && entity.archetypeId < 0) {
      rowsReadableOnDespawn = false;
    }
  }

  @override
  void onSceneLoaded(Scene scene) => loaded.add(scene);

  @override
  void onSceneUnloaded(Scene scene) {
    unloaded.add(scene);
    order.add('world.sceneUnloaded');
  }
}

// ignore: library_private_types_in_public_api
late _Observer observer;

class _GameState extends GameState<_Game> {
  @override
  void onMounted() => loadScene(_Scene());

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    observer = descriptor.has(_Observer());
  }
}

class _Game extends Game {
  @override
  int get pageSize => 4096;

  @override
  GameState createState() => _GameState();
}

Future<(Game, _Scene)> _boot() async {
  final run = await Game.startInline(_Game());
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return (run, run.state.getScene<_Scene>());
}

void main() {
  setUp(() {
    _Watched.mounted = 0;
    order.clear();
  });

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test('a system hears every entity spawn, whatever its archetype', () async {
    final (_, scene) = await _boot();

    final rock = scene.handle.addEntity(scene.rock);
    final tree = scene.handle.addEntity(scene.tree);

    expect(
      observer.spawned,
      containsAll(<Entity>[rock, tree]),
      reason: 'an EntitySpawnListener on a GameSystem should hear entities of '
          'archetypes it has no relationship with - that is the whole point '
          'of the broad scope',
    );
  });

  test('spawn observation does not disturb the narrow lifecycle event',
      () async {
    final (_, scene) = await _boot();

    scene.handle.addEntity(scene.rock);
    scene.handle.addEntity(scene.watched);
    scene.handle.addEntity(scene.watched);

    expect(
      _Watched.mounted,
      2,
      reason: "the struct's own onEntityMounted must still fire only for its "
          'own entities, not for the rock',
    );
    expect(observer.spawned.length, 3, reason: 'the observer saw all three');
  });

  test('the prefab is told before the world observer', () async {
    // Something watching the whole world should see an entity whose own
    // struct has already initialised it.
    final (_, scene) = await _boot();

    order.clear();
    scene.handle.addEntity(scene.watched);

    expect(order, <String>['prefab.mounted', 'world.spawned']);
  });

  test('a scene load is observed', () async {
    final (_, scene) = await _boot();
    expect(
      observer.loaded,
      contains(scene.handle),
      reason: 'the scene loaded during onMounted should have been observed',
    );
  });

  test('unloading a scene reports its scene and its entities', () async {
    final (run, scene) = await _boot();

    final rock = scene.handle.addEntity(scene.rock);
    final handle = scene.handle;

    run.state.unloadScene(handle);

    expect(observer.unloaded, contains(handle));
    expect(
      observer.despawned,
      contains(rock),
      reason: 'every entity in an unloaded scene should be reported',
    );
    expect(
      observer.rowsReadableOnDespawn,
      isTrue,
      reason: 'the contract says a despawned entity is still readable',
    );
  });

  test('the scene is reported before its entities', () async {
    // Mirrors unloadScene's own ordering guarantee: the scene says its piece
    // while its entities are all still there.
    final (run, scene) = await _boot();
    scene.handle.addEntity(scene.rock);
    scene.handle.addEntity(scene.rock);

    order.clear();
    run.state.unloadScene(scene.handle);

    expect(
      order,
      <String>['world.sceneUnloaded', 'world.despawned', 'world.despawned'],
      reason: 'the scene must be reported once, before any of its entities',
    );
  });

  test('destroying one entity reports it, like unloading its scene', () async {
    // **The gap that leaked.** `Entity.destroy` fired only the prefab's narrow
    // `unmountedEvent`; the broad `entityDespawnedEvent` went in on the scene
    // unload path alone. So an observer that allocates a resource per entity -
    // a Box2D body, a native handle, a slot in a side table - heard every
    // spawn and only some of the releases, and leaked one per destroyed
    // entity with nothing in Dart to show for it.
    //
    // It was found in the physics demo, where Box2D reported 57 882 awake
    // bodies for a scene holding 4000 entities.
    final (_, scene) = await _boot();

    final rock = scene.handle.addEntity(scene.rock);
    final keep = scene.handle.addEntity(scene.tree);

    order.clear();
    observer.despawned.clear();
    rock.destroy();

    expect(
      observer.despawned,
      <Entity>[rock],
      reason: 'destroy() must tell world observers, exactly as unload does',
    );
    expect(
      observer.despawned,
      isNot(contains(keep)),
      reason: 'and only about the entity that was actually destroyed',
    );
    expect(
      order,
      <String>['world.despawned'],
      reason: 'broad before narrow, matching the scene-unload path (_Rock has '
          'no narrow listener of its own, so only the broad one appears)',
    );
  });

  test('destroying a subtree reports every entity in it', () async {
    // Children are destroyed recursively, and each one is a resource an
    // observer may be holding. Reporting only the root would leak the rest.
    final (_, scene) = await _boot();

    final parent = scene.handle.addEntity(scene.node);
    final child = scene.handle.addEntity(scene.node, parent: parent);

    observer.despawned.clear();
    parent.destroy();

    expect(observer.despawned, containsAll(<Entity>[parent, child]));
    expect(observer.despawned.length, 2);
  });

  test('stopping the game reports every loaded scene', () async {
    final (run, scene) = await _boot();
    final handle = scene.handle;
    scene.handle.addEntity(scene.rock);

    await run.stop();

    expect(
      observer.unloaded,
      contains(handle),
      reason: 'teardown should report the unload too, not only unloadScene',
    );
  });
}
