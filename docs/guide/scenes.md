# Scenes and prefabs

!!! abstract "Layer: kernel (`good`)"

A `SceneStruct` answers two questions: **which prefabs can exist here**, and
**what exists when it loads**.

```dart
class Level1 extends SceneStruct {
  late final Player player;
  late final Enemy enemy;
  late final Eye eye;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    player = descriptor.has(Player());
    enemy = descriptor.has(Enemy());
    eye = descriptor.has(Eye());
  }

  @override
  void onSceneMounted(Scene scene) {
    final camera = scene.addEntity(eye);
    eye.view[camera] = (game as Game2D).defaultCamera;
    scene.addEntity(player);
    for (var i = 0; i < 10; i++) {
      scene.addEntity(enemy);
    }
  }
}
```

## Declaration versus instance

This distinction runs through the whole engine and is worth stating plainly.

| Declaration | Instance |
|---|---|
| `SceneStruct` — one object, describes a scene | `Scene` — an `extension type` over an int, one loaded copy |
| `EntityStruct` — one object, describes a row layout | `Entity` — an `extension type` over an int, one row |

A `SceneStruct` may back **several loaded scenes at once**. That is why it must
not hold mutable per-instance state:

```dart
class Level1 extends SceneStruct {
  late final Player player;    // fine — a declaration handle
  int enemiesKilled = 0;       // WRONG — shared by every loaded copy
}
```

Per-instance state belongs in components, or on a system that scopes it by
`Scene`.

Scene *content* is different from scene *handles*, and both are legitimate
fields — the example demos keep a `late Entity hubEntity` for the one entity the
scene creates itself, so spawns have something to parent to.

## Declaring scenes up front

Declaring a scene on the `Game` registers its archetypes and its assets **at
boot** — before the game isolate is spawned, and before any system's
`describeQuery` runs:

```dart
class MyGame extends Game2D {
  late final Level1 level1;
  late final HudScene hud;

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    level1 = descriptor.has(Level1());
    hud = descriptor.has(HudScene());
  }
}
```

`loadScene(game.level1)` then costs no registration at all — it allocates rows
and mounts.

That matters because registration is the half of loading that **cannot happen
freely at runtime**: archetype ids are process-global and never recycled, so a
scene registered afresh on every load would leak ids and leave every unloaded
scene's archetypes in the registry for queries to keep walking.

Passing an *undeclared* scene to `loadScene` still works and registers lazily,
so `describeScenes` is additive , not an obligation — the scaffold's
`loadScene(MainScene())` is fine for a game with one scene.

## Loading and unloading

```dart
class MyState extends GameState2D<MyGame> {
  @override
  void onMounted() {
    loadScene(game.level1);
  }

  Future<void> goToLevel2() async {
    for (final scene in loadedScenes) {
      unloadScene(scene);
    }
    await loadScene(game.level2);
  }
}
```

| Call | What it does |
|---|---|
| `loadScene(struct)` | Allocates rows, mounts, resolves assets. Returns a `Future<Scene>` |
| `unloadScene(scene)` | Unmounts one loaded instance and releases its pages |
| `unloadAllScene(struct)` | Unloads every instance of that declaration |
| `loadedScenes` | The live `Scene` handles |
| `getScene<S>()` | The declaration of type `S` |

`loadScene` is asynchronous because assets are decoded on the Flutter isolate:
the game isolate declares them but cannot decode them, so it asks and waits.
Assets already resident from another loaded scene are not decoded twice, and
unloading releases only what nothing else still declares.

Several scenes can be loaded at once, which is how a HUD scene, a world scene
and a pause overlay coexist. Each camera view draws the scene *its own camera*
is in, so two views can be looking at different scenes at the same instant.

## Spawning entities

```dart
final entity = scene.addEntity(prefab);
final child  = scene.addEntity(limb, parent: entity);
entity.destroy();          // removes it and its whole subtree
```

`addEntity` allocates a row in the prefab's archetype, applies every declared
default, fires `onEntityMounted`, and returns the handle.

!!! warning "Spawn from the game isolate"
    `scene.addEntity` writes component storage, so it belongs on the simulation
    side: a system, a state hook, or a command handler. Spawning "from the UI"
    means sending a [command](flutter-bridge.md#commands) that a game-side
    handler turns into an `addEntity`.

    The framework deliberately ships no built-in spawn command. One would have
    to name a prefab by `archetypeId`, which is a game-isolate identifier the
    Flutter isolate has no way to see. Declare your own, in terms that mean
    something on both sides.

### Rate-limiting spawns

Spawning is cheap but not free, and a burst that allocates thousands of rows in
one step shows up as a frame spike. The example demos cap per tick and converge
over several:

```dart
final shortfall = targetPopulation - alive;
if (shortfall > 0) {
  final batch = shortfall < _maxSpawnPerTick ? shortfall : _maxSpawnPerTick;
  for (var i = 0; i < batch; i++) {
    spawnOne();
  }
}
```

## Scene-level declarations

A `SceneStruct` carries the same `describe*` passes an entity does, and they
apply to everything in the scene:

```dart
class Level1 extends SceneStruct {
  late final TextureAsset tileset;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    tileset = descriptor.has(Textures.worldTileset);
  }
}
```

Prefabs and their scene **share one descriptor**, and `has` is idempotent per
identity — so a prefab declaring the same texture ends up with the identical
handle: one address, one decode. Declare an asset wherever you use it; declaring
it twice costs nothing and forgetting to costs a `LateInitializationError` on
mount.

Scenes can also mix in `SceneLifecycleListener`, `Tickable`, `FixedTickable`,
`Coroutines` and `Animations` — a scene is a `GameListener`, so it can hold
per-scene logic without a system.

## Composing scenes with mixins

A `SceneStruct` is an ordinary class, so shared scene behaviour composes as a
mixin:

```dart
mixin FieldScene on SceneStruct {
  late final TextureAsset grass;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    grass = descriptor.has(Textures.worldGrass);
  }
}

class Level1 extends SceneStruct with FieldScene { }
class Level2 extends SceneStruct with FieldScene { }
```

## Prefabs are declarations too

`descriptor.has(Player())` registers the archetype and runs the prefab's
`describe*` passes. The returned handle is what you spawn from, and it is the
same object every entity of that kind shares:

```dart
player = descriptor.has(Player());        // declare once
scene.addEntity(player);                  // spawn many
player.sprite.color[entity] = 0xFFFF0000; // per entity, through the handle
```

---

## Next

[Systems and queries →](systems-and-queries.md)
