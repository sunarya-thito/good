---
sidebar_position: 2
---

# Sprites & Rendering

This page shows how to load a texture, slice it into a grid of frames, and cycle through those frames each tick to produce a sprite animation.

## Live Demo

<iframe 
  src="/goo2d/play/#/sprites" 
  width="100%" 
  height="400px" 
  style={{ border: 'none', borderRadius: '8px', background: '#000' }}
/>

## Assets Used

This example uses assets from the [ansimuz Explosion Pack](https://ansimuz.itch.io/explosion-animations-pack).

| Preview | Asset | Action |
| :--- | :--- | :--- |
| ![](/img/cookbook/explosion.png) | `explosion.png` | [Download](/img/cookbook/explosion.png) |

---

## Tutorial

### 0. Asset Setup

1. Create `assets/sprites/` in your project root.
2. Place `explosion.png` in that directory.
3. Register it in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/sprites/
```

### 1. Imports, Asset Enum, and main()

Set up the texture registry and entry point. The `AssetEnum` + `TextureAssetEnum` pattern gives you a strongly-typed reference to each asset. Call `GameAsset.loadAll` before the engine starts so textures are on the GPU before any `onMounted` runs.

```dart
// Add this: ------
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';

enum GameTextures with AssetEnum, TextureAssetEnum {
  explosion;

  @override
  AssetSource get source => AssetSource.local('assets/sprites/$name.png');
}

void main() => runApp(const SpriteExample());
// --------
```

### 2. Root Widget with Asset Loading

Wrap the `Game` widget in a `FutureBuilder` that waits for all textures to finish loading.

```dart
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';

enum GameTextures with AssetEnum, TextureAssetEnum {
  explosion;
  @override
  AssetSource get source => AssetSource.local('assets/sprites/$name.png');
}

void main() => runApp(const SpriteExample());

// Add this: ------
class SpriteExample extends StatelessWidget {
  const SpriteExample({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: FutureBuilder(
        future: GameAsset.loadAll(GameTextures.values).drain(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return const Game(child: SpriteWorld());
        },
      ),
    );
  }
}
// --------
```

`GameAsset.loadAll` streams progress events while decoding each asset. Calling `.drain()` converts that stream into a single `Future` that resolves when all assets are ready.

### 3. Empty Game World

Define the game object that will hold the explosion animation.

```dart
// Add this: ------
class SpriteWorld extends StatefulGameWidget {
  const SpriteWorld({super.key});

  @override
  GameState<SpriteWorld> createState() => SpriteWorldState();
}

class SpriteWorldState extends GameState<SpriteWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
// --------
```

`GameState.build` uses a `sync*` generator that yields child widgets. An empty generator is a valid starting point.

### 4. Declaring the Sheet and Frame State

Add the fields that will hold the sprite sheet and track the current animation frame.

```dart
class SpriteWorldState extends GameState<SpriteWorld> {
  // Add this: ------
  late SpriteSheet<TileCoord> sheet;
  int currentFrame = 0;
  double _timer = 0;
  // --------

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```

`late` fields are fine here because they will be assigned in `initState` before any component accesses them.

### 5. Slicing the Texture Grid

Override `initState` to slice the explosion texture into 13 columns and 1 row.

```dart
class SpriteWorldState extends GameState<SpriteWorld> {
  late SpriteSheet<TileCoord> sheet;
  int currentFrame = 0;
  double _timer = 0;

  // Add this: ------
  @override
  void initState() {
    super.initState();
    sheet = SpriteSheet.grid(
      texture: GameTextures.explosion,
      columns: 13,
      rows: 1,
      ppu: 64.0,
    );
  }
  // --------

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```

`ppu` (pixels per unit) controls how large each frame appears in world space. A 64×64 pixel frame with `ppu: 64.0` renders as 1×1 world unit.

### 6. Advancing the Frame Each Tick

Mix in `Tickable` and accumulate time each frame. When 100 ms has passed, advance to the next frame and rebuild.

```dart
// Add this: ------
class SpriteWorldState extends GameState<SpriteWorld> with Tickable {
// --------
  late SpriteSheet<TileCoord> sheet;
  int currentFrame = 0;
  double _timer = 0;

  @override
  void initState() {
    super.initState();
    sheet = SpriteSheet.grid(
      texture: GameTextures.explosion,
      columns: 13,
      rows: 1,
      ppu: 64.0,
    );
  }

  // Add this: ------
  @override
  void onUpdate(double dt) {
    if ((_timer += dt) >= 0.1) {
      _timer = 0;
      setState(() => currentFrame = (currentFrame + 1) % 13);
    }
  }
  // --------

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```

`dt` is the elapsed time in seconds since the last frame. Accumulating it into `_timer` and comparing against `0.1` gives you a 10 FPS animation regardless of the game's frame rate.

### 7. Rendering the Sprite

Yield two game objects: the animated sprite, and a camera to view the scene.

```dart
class SpriteWorldState extends GameState<SpriteWorld> with Tickable {
  late SpriteSheet<TileCoord> sheet;
  int currentFrame = 0;
  double _timer = 0;

  @override
  void initState() { /* ... */ }

  @override
  void onUpdate(double dt) { /* ... */ }

  @override
  Iterable<Widget> build(BuildContext context) sync* {
    // Add this: ------
    yield GameObjectWidget(
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          SpriteRenderer.new.withInitialValues(
            (r) => r.sprite = sheet[(0, currentFrame)],
          ),
        ),
      ],
    );

    yield GameObjectWidget(
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          Camera.new.withInitialValues((c) => c.orthographicSize = 2.0),
        ),
      ],
    );
    // --------
  }
}
```

`SpriteSheet` is indexed as `sheet[(row, column)]`. The first coordinate is the row — here always `0` since the sheet has one row. Each time `setState` updates `currentFrame`, `build` re-runs and passes the new frame index to `SpriteRenderer`.

---

## Final Code

```dart
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';

enum GameTextures with AssetEnum, TextureAssetEnum {
  explosion;

  @override
  AssetSource get source => AssetSource.local('assets/sprites/$name.png');
}

void main() => runApp(const SpriteExample());

class SpriteExample extends StatelessWidget {
  const SpriteExample({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: FutureBuilder(
        future: GameAsset.loadAll(GameTextures.values).drain(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return const Game(child: SpriteWorld());
        },
      ),
    );
  }
}

class SpriteWorld extends StatefulGameWidget {
  const SpriteWorld({super.key});

  @override
  GameState<SpriteWorld> createState() => SpriteWorldState();
}

class SpriteWorldState extends GameState<SpriteWorld> with Tickable {
  late SpriteSheet<TileCoord> sheet;
  int currentFrame = 0;
  double _timer = 0;

  @override
  void initState() {
    super.initState();
    sheet = SpriteSheet.grid(
      texture: GameTextures.explosion,
      columns: 13,
      rows: 1,
      ppu: 64.0,
    );
  }

  @override
  void onUpdate(double dt) {
    if ((_timer += dt) >= 0.1) {
      _timer = 0;
      setState(() => currentFrame = (currentFrame + 1) % 13);
    }
  }

  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield GameObjectWidget(
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          SpriteRenderer.new.withInitialValues(
            (r) => r.sprite = sheet[(0, currentFrame)],
          ),
        ),
      ],
    );

    yield GameObjectWidget(
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          Camera.new.withInitialValues((c) => c.orthographicSize = 2.0),
        ),
      ],
    );
  }
}
```
