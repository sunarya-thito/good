# Your first game

<!-- snippet-scope
class MyGameGame extends Game2D {
  @override
  MyGameState createState() => MyGameState();
}

class MyGameState extends GameState2D<MyGameGame> {}

class MainScene extends SceneStruct {}

late Input<Vector2> movement;
late Query players;
-->

Starting from the project [`good create`](create-a-project.md) scaffolded, this
page adds the four things every game needs: **a system**, **input**,
**an asset**, and **a camera**. Every snippet here compiles against the current
engine.

At the end you have a textured sprite you can drive with `W` `A` `S` `D`.

## 1. Run the scaffold

```bash
flutter run -d windows   # or linux, macos, android...
```

A blue 64×64 square in the middle of the window. That is `Player`, spawned by
`MainScene.onSceneMounted`, drawn by the renderer `Game2D` declared for you.

It is in the middle because **no camera exists yet**: with no active camera the
projection stays at the origin with a zoom of 1, and the whole world draws. A
game that has not placed a camera shows something, not a black screen.

## 2. Move it — a system

A `GameSystem` is where per-tick work lives. `FixedTickable` gets it
`onFixedUpdate`, called once per fixed step (60 Hz by default) with exactly
`fixedTimeStep` of simulated time — never a variable frame delta. That is the
mixin for anything that writes component data, which this system does;
`Tickable` is the other one, for systems that read what the simulation finished
and publish it. [Choosing between them](../guide/systems-and-queries.md#choosing-between-them)
covers the cases where it is less obvious.

Create `lib/game/systems/player_system.dart`:

```dart title="lib/game/systems/player_system.dart"
import 'package:goo2d/goo2d.dart';

import '../prefabs/player.dart';

class PlayerSystem extends GameSystem with FixedTickable {
  late final Query players;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    players = descriptor.query().withAll(Transform2D, Player).build();  // (1)!
  }

  @override
  void onFixedUpdate() {
    final dt = game.fixedTimeStep.inMicroseconds / 1000000.0;

    for (final group in players.groups()) {      // (2)!
      final transform = group.get<Transform2D>();
      for (final entity in group) {
        transform.transformOffsetX[entity] += 60 * dt;
      }
    }
  }
}
```

1. The query is compiled **once**, at declare time, into an archetype match.
   Nothing searches at tick time.
2. `groups()` yields one group per matching archetype; `group.get<T>()` resolves
   that archetype's component **once** for the whole group, and the inner loop
   indexes it by `Entity`. Resolving inside the inner loop would repeat that
   lookup per entity.

Declare it on the **state**, not the game — a system exists only on the isolate
that ticks it:

```dart title="lib/game/my_game_game.dart" hl_lines="4 5 6 7 8"
class MyGameState extends GameState2D<MyGameGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(PlayerSystem());
  }

  @override
  void onMounted() => loadScene(MainScene());
}
```

Run it: the square slides right forever.

!!! warning "No closures in `onFixedUpdate`"
    `players.groups()` is walked with indexed `for` loops.
    `.map`, `.where`, `.any` and `.forEach` each allocate a closure — and
    usually an `Iterable` — every call, and this method runs 60 times a second.
    See [Hot-path rules](../reference/rules.md).

## 3. Steer it — input

Input actions are **declared**, like everything else, and hand back a typed
handle. A system can declare its own:

```dart title="lib/game/systems/player_system.dart" hl_lines="2 6 7 8 9 10 11 12 13 14 15"
class PlayerSystem extends GameSystem with FixedTickable {
  late final Query players;
  late final Input<Vector2> movement;

  // ...

  @override
  void describeInputs(InputDescriptor descriptor) {
    super.describeInputs(descriptor);
    movement = descriptor.has<Vector2>(
      const Vec2Binding(
        up: InputKey.w,
        down: InputKey.s,
        left: InputKey.a,
        right: InputKey.d,
      ),
    );
  }
}
```

`Vec2Binding` composes four held/not-held keys into a `Vector2`. Keys are named
by **physical position**, so `InputKey.w` is the key where a QWERTY `W` sits
regardless of the player's layout — WASD stays under the same fingers on AZERTY.

Now use it:

<!-- snippet: in GameSystem with FixedTickable -->
```dart
@override
void onFixedUpdate() {
  final dt = game.fixedTimeStep.inMicroseconds / 1000000.0;
  final direction = movement.value;                      // (1)!
  if (direction.x == 0 && direction.y == 0) return;

  for (final group in players.groups()) {
    final transform = group.get<Transform2D>();
    final player = group.get<Player>();
    for (final entity in group) {
      final step = player.speed[entity] * dt;            // (2)!
      transform
        ..transformOffsetX[entity] += direction.x * step
        ..transformOffsetY[entity] += direction.y * step;
    }
  }
}
```

1. Read it, do not keep it. For a `Vector2` this returns the *one* instance the
   action owns and mutates in place each tick — storing it in a field stores
   something that changes under you.
2. `speed` is a component field added in the next step. Positive `y` is **down**
   — world space projects into Flutter's canvas.

### Per-entity data

`speed` is not a Dart field on `Player`; it is a column in the row layout, and
declaring it is one line:

```dart title="lib/game/prefabs/player.dart"
class Player extends EntityStruct with Transform2D, WorldTransform2D, Renderable2D {
  final speed = Field.float64(220);   // (1)!
}
```

1. `220` is the **default** every new row starts at, not a value stored on the
   prefab. Write per entity with `speed[entity] = 400`.

This is the single most important thing to internalise about the engine: a
`Field.float64()` is a *column*, and `[entity]` is the row index.
See [Entities and components](../guide/entities-and-components.md).

Run it: `WASD` drives the square.

## 4. Give it a texture — assets

Drop an image into the **source** directory, which holds the originals you
edit and commit:

```
my_game/
└── assets_src/
    └── sprites/player.png
```

Convert it to the canonical format:

```console
$ good assets compact
  sprites/player.png -> sprites/player.webp
1 written, 0 up to date, 0 failed.

These directories now hold assets but are not listed under `flutter: assets:` in pubspec.yaml,
so Flutter will not bundle them and `good generate` will not see them:
  - assets/sprites/
```

Do what it says — Flutter bundles only what the pubspec lists, and directory
entries do not recurse into subdirectories:

```yaml title="pubspec.yaml" hl_lines="5"
flutter:
  assets:
    - assets/
    - assets/packed/
    - assets/sprites/
```

Then generate the bindings:

```console
$ good generate
Wrote ./lib/good.generated/textures.dart
1 texture(s), 0 audio file(s).
```

<!-- snippet: skip generated output, elided -->
```dart title="lib/good.generated/textures.dart"
enum Textures with LocalEnumAssetKey<Texture> {
  spritesPlayer('assets/sprites/player.webp');
  // ...
}
```

The path became an identifier: `assets/sprites/player.webp` → `spritesPlayer`.
Rename a file and the enum value's name changes with it, so a stale reference
is a **compile error**, not a missing texture at runtime.

Declare the asset on the prefab and hand it to the sprite:

```dart title="lib/game/prefabs/player.dart" hl_lines="4 10 11 12 13 14 20"
import 'package:goo2d/goo2d.dart';

import '../../good.generated/textures.dart';

class Player extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  late final TextureAsset texture;
  late final Sprite sprite;
  final speed = Field.float64(220);

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    texture = descriptor.has(Textures.spritesPlayer);
  }

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    sprite = descriptor.has(width: 64, height: 64, texture: texture);
  }
}
```

!!! tip "Declare the asset wherever you use it"
    A prefab that reads a texture must declare it, even if its scene declares
    the same one. `has` is idempotent per identity and prefabs share their
    scene's descriptor, so both fields end up the identical handle — one
    address, one decode.

Run it: your image, moving with `WASD`.

## 5. Add a camera

A camera is an entity like any other — a transform plus the `Camera` component.
That is what makes "the camera follows the player" a parenting problem, not a
special case.

```dart title="lib/game/prefabs/player.dart"
class Eye() extends EntityStruct with Transform2D, WorldTransform2D, Camera;
```

Spawn it and point it at the view the game declared:

```dart title="lib/game/scenes/main_scene.dart" hl_lines="3 10 15 16"
class MainScene extends SceneStruct {
  late final Player player;
  late final Eye eye;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    player = descriptor.has(Player.new);
    eye = descriptor.has(Eye.new);
  }

  @override
  void onSceneMounted(Scene scene) {
    final camera = scene.addEntity(eye);
    eye.view[camera] = (game as Game2D).defaultCamera;   // (1)!
    scene.addEntity(player);
  }
}
```

1. `defaultCamera` is the view `Game2D` declares for you, and the one
   `GameView(camera: game.defaultCamera)` in `main.dart` shows. A game can
   declare more views and show several at once.

Nothing looks different yet — the camera sits at the origin, which is where the
projection already was. Move the `Eye`'s transform and the view moves; set
`eye.zoom[camera] = 2` and everything draws twice as large.

To make it follow, write its position from a system, or make it a `Child` of
the player and let `WorldTransformSystem` compose it. See
[Transforms and hierarchy](../guide/transforms-and-hierarchy.md).

## What you have

```
my_game/lib/game/
├── my_game_game.dart          Game + GameState, systems declared
├── prefabs/player.dart        Player (transform, sprite, speed) and Eye (camera)
├── scenes/main_scene.dart     what exists when the scene loads
└── systems/player_system.dart the movement loop and the input action
```

Four declarations and one loop. That shape holds as the game grows: prefabs
say what things *are*, scenes say what *exists*, systems say what *happens*,
and the `Game` says what crosses to Flutter.

Three names above are 2D: `Transform2D`, `Renderable2D`/`Sprite` and `Game2D`.
The rest — systems, queries, input, assets, scenes — came from the kernel, and
a `goo3d` game writes them unchanged.

## Where to go next

<div class="grid cards" markdown>

- **[Architecture](../guide/architecture.md)** — the two isolates, and why
  your `Game` exists twice.

- **[Systems and queries](../guide/systems-and-queries.md)** — ordering,
  enabling, `Tickable` versus `FixedTickable`.

- **[Physics](../guide/physics.md)** — add `RigidBody2D` and let Box2D drive
  the transforms.

- **[Exporting a game](../exporting/index.md)** — pack, encrypt and ship it.

</div>
