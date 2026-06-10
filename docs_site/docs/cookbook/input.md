---
sidebar_position: 3
---

# Input & Movement

This page shows how to read keyboard input and move a game object in response. A ship moves in four directions using WASD keys, and tilts slightly to show which direction it is heading.

## Live Demo

<iframe 
  src="/goo2d/play/#/input" 
  width="100%" 
  height="400px" 
  style={{ border: 'none', borderRadius: '8px', background: '#000' }}
/>

## Assets Used

This example uses assets from the [Kenney Pixel Shmup](https://kenney-assets.itch.io/pixel-shmup) pack.

| Preview | Asset | Action |
| :--- | :--- | :--- |
| ![](/img/cookbook/ship.png) | `ship.png` | [Download](/img/cookbook/ship.png) |

---

## Tutorial

### 0. Asset Setup

1. Create `assets/sprites/` in your project root.
2. Place `ship.png` in that directory.
3. Register it in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/sprites/
```

### 1. Imports, Asset Enum, and main()

```dart
// Add this: ------
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';

enum GameTextures with AssetEnum, TextureAssetEnum {
  ship;

  @override
  AssetSource get source => AssetSource.local('assets/sprites/$name.png');
}

void main() => runApp(const InputExample());
// --------
```

### 2. Root Widget

```dart
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';

enum GameTextures with AssetEnum, TextureAssetEnum {
  ship;
  @override
  AssetSource get source => AssetSource.local('assets/sprites/$name.png');
}

void main() => runApp(const InputExample());

// Add this: ------
class InputExample extends StatelessWidget {
  const InputExample({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: FutureBuilder(
        future: GameAsset.loadAll(GameTextures.values).drain(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return const Game(child: InputWorld());
        },
      ),
    );
  }
}
// --------
```

### 3. Game World Scaffold

```dart
// Add this: ------
class InputWorld extends StatefulGameWidget {
  const InputWorld({super.key});

  @override
  GameState<InputWorld> createState() => InputWorldState();
}

class InputWorldState extends GameState<InputWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
// --------
```

### 4. Camera

Yield a camera so the game scene is visible.

```dart
class InputWorldState extends GameState<InputWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {
    // Add this: ------
    yield GameObjectWidget(
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          Camera.new.withInitialValues((c) => c.orthographicSize = 5.0),
        ),
      ],
    );
    // --------
  }
}
```

`orthographicSize` is the half-height of the camera in world units. A value of `5.0` means 10 units are visible top-to-bottom.

### 5. Empty Player Widget

Define the `Player` widget that will hold the ship sprite and movement logic.

```dart
// Add this: ------
class Player extends StatefulGameWidget {
  const Player({super.key});

  @override
  GameState<Player> createState() => PlayerState();
}

class PlayerState extends GameState<Player> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
// --------
```

### 6. Add the Player to the World

```dart
class InputWorldState extends GameState<InputWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {
    // Add this: ------
    yield const Player();
    // --------

    yield GameObjectWidget(
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          Camera.new.withInitialValues((c) => c.orthographicSize = 5.0),
        ),
      ],
    );
  }
}
```

### 7. Player Components

In `PlayerState.initState`, attach the transform and sprite renderer.

```dart
class PlayerState extends GameState<Player> {
  // Add this: ------
  @override
  void initState() {
    super.initState();
    addComponent(
      ObjectTransform()..position = Vector2.zero(),
      SpriteRenderer()
        ..sprite = GameSprite(
          mesh: SimpleMesh(texture: GameTextures.ship),
          pixelsPerUnit: 64.0,
        ),
    );
  }
  // --------

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```

`SimpleMesh` wraps a loaded texture and passes it to `GameSprite`. `pixelsPerUnit` determines how large the sprite appears in world space — a 64×64 pixel image with `pixelsPerUnit: 64.0` renders as 1×1 world unit.

### 8. Declare the Move Action

Add an `InputAction` field and register it with WASD composite bindings.

```dart
class PlayerState extends GameState<Player> {
  // Add this: ------
  late InputAction moveAction;
  // --------

  @override
  void initState() {
    super.initState();
    // Add this: ------
    moveAction = InputAction()
      ..name = 'move'
      ..type = InputActionType.value
      ..bindings = [
        InputBinding.composite(
          up: Keyboard.keyW,
          down: Keyboard.keyS,
          left: Keyboard.keyA,
          right: Keyboard.keyD,
        ),
      ];
    addComponent(moveAction);
    // --------

    addComponent(
      ObjectTransform()..position = Vector2.zero(),
      SpriteRenderer()
        ..sprite = GameSprite(
          mesh: SimpleMesh(texture: GameTextures.ship),
          pixelsPerUnit: 64.0,
        ),
    );
  }

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```

`InputActionType.value` means the action produces a continuous `Vector2` rather than a one-shot button event. `InputBinding.composite` maps four keys to the four cardinal directions of that vector — pressing W and D simultaneously gives `Vector2(1, 1)` before normalization.

### 9. Apply Movement Each Frame

Mix in `Tickable` and read the action's direction vector each frame.

```dart
// Add this: ------
class PlayerState extends GameState<Player> with Tickable {
// --------
  late InputAction moveAction;

  @override
  void initState() { /* ... */ }

  // Add this: ------
  @override
  void onUpdate(double dt) {
    final dir = moveAction.readValue<Vector2>();
    if (dir.length > 0) dir.normalize();
    getComponent<ObjectTransform>().position += dir * 4.0 * dt;
  }
  // --------

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```

`readValue<Vector2>()` returns the composite direction from the four bound keys. Normalizing it before multiplying prevents diagonal movement from being faster than axis-aligned movement. Multiplying by `dt` makes speed frame-rate independent.

### 10. Add Visual Banking

Tilt the ship left or right based on the horizontal input component.

```dart
class PlayerState extends GameState<Player> with Tickable {
  late InputAction moveAction;

  @override
  void initState() { /* ... */ }

  @override
  void onUpdate(double dt) {
    final dir = moveAction.readValue<Vector2>();
    if (dir.length > 0) dir.normalize();
    final transform = getComponent<ObjectTransform>();
    transform.position += dir * 4.0 * dt;

    // Add this: ------
    final targetAngle = -dir.x * 0.4;
    transform.angle += (targetAngle - transform.angle) * 10.0 * dt;
    // --------
  }

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```

`transform.angle` is in radians. The target bank angle is ±0.4 radians (about ±23°) based on horizontal input. Lerping toward it at `10 * dt` gives a smooth banking effect instead of snapping.

---

## Final Code

```dart
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';

enum GameTextures with AssetEnum, TextureAssetEnum {
  ship;

  @override
  AssetSource get source => AssetSource.local('assets/sprites/$name.png');
}

void main() => runApp(const InputExample());

class InputExample extends StatelessWidget {
  const InputExample({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: FutureBuilder(
        future: GameAsset.loadAll(GameTextures.values).drain(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return const Game(child: InputWorld());
        },
      ),
    );
  }
}

class InputWorld extends StatefulGameWidget {
  const InputWorld({super.key});

  @override
  GameState<InputWorld> createState() => InputWorldState();
}

class InputWorldState extends GameState<InputWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield const Player();

    yield GameObjectWidget(
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          Camera.new.withInitialValues((c) => c.orthographicSize = 5.0),
        ),
      ],
    );
  }
}

class Player extends StatefulGameWidget {
  const Player({super.key});

  @override
  GameState<Player> createState() => PlayerState();
}

class PlayerState extends GameState<Player> with Tickable {
  late InputAction moveAction;

  @override
  void initState() {
    super.initState();
    moveAction = InputAction()
      ..name = 'move'
      ..type = InputActionType.value
      ..bindings = [
        InputBinding.composite(
          up: Keyboard.keyW,
          down: Keyboard.keyS,
          left: Keyboard.keyA,
          right: Keyboard.keyD,
        ),
      ];
    addComponent(moveAction);

    addComponent(
      ObjectTransform()..position = Vector2.zero(),
      SpriteRenderer()
        ..sprite = GameSprite(
          mesh: SimpleMesh(texture: GameTextures.ship),
          pixelsPerUnit: 64.0,
        ),
    );
  }

  @override
  void onUpdate(double dt) {
    final dir = moveAction.readValue<Vector2>();
    if (dir.length > 0) dir.normalize();
    final transform = getComponent<ObjectTransform>();
    transform.position += dir * 4.0 * dt;
    final targetAngle = -dir.x * 0.4;
    transform.angle += (targetAngle - transform.angle) * 10.0 * dt;
  }

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```
