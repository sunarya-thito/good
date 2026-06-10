---
sidebar_position: 1
---

# Camera Follow

This page shows how to set up a camera that smoothly follows a moving player. The player moves with WASD in a world larger than the screen, and the camera catches up using `MathUtils.smoothDampVector2`.

## Live Demo

<iframe 
  src="/goo2d/play/#/camera" 
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

void main() => runApp(const CameraExample());
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

void main() => runApp(const CameraExample());

// Add this: ------
class CameraExample extends StatelessWidget {
  const CameraExample({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: FutureBuilder(
        future: GameAsset.loadAll(GameTextures.values).drain(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return const Game(child: CameraWorld());
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
class CameraWorld extends StatefulGameWidget {
  const CameraWorld({super.key});

  @override
  GameState<CameraWorld> createState() => CameraWorldState();
}

class CameraWorldState extends GameState<CameraWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
// --------
```

### 4. Player Scaffold

```dart
// Add this: ------
class Player extends StatefulGameWidget {
  const Player({super.key, super.tag});

  @override
  GameState<Player> createState() => PlayerState();
}

class PlayerState extends GameState<Player> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
// --------
```

### 5. Player Components

Attach the transform, input action, and sprite renderer to the player.

```dart
class PlayerState extends GameState<Player> {
  // Add this: ------
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
    addComponent(
      moveAction,
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

### 6. Player Movement

Mix in `Tickable` and apply the input direction each frame.

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
    getComponent<ObjectTransform>().position += dir * 5.0 * dt;
  }
  // --------

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```

### 7. Camera Object in the World

Add the player and a camera to `CameraWorldState`. Tag both objects so the follow behavior can find the player.

```dart
class CameraWorldState extends GameState<CameraWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {
    // Add this: ------
    yield const Player(tag: 'player');

    yield GameObjectWidget(
      tag: 'mainCamera',
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          Camera.new.withInitialValues(
            (c) => c
              ..orthographicSize = 5.0
              ..backgroundColor = const Color(0xFF111111),
          ),
        ),
      ],
    );
    // --------
  }
}
```

### 8. Empty Camera Follow Behavior

Define the `CameraFollow` behavior class. It will be attached to the camera object.

```dart
// Add this: ------
class CameraFollow extends Behavior with LateTickable {
  @override
  void onLateUpdate(double dt) {}
}
// --------
```

Camera follow belongs in `onLateUpdate`, not `onUpdate`. By the time `LateTickable` fires, all `Tickable` components — including the player — have already moved for this frame, so the camera always reads the final position, not an intermediate one.

### 9. Attach CameraFollow to the Camera Object

```dart
class CameraWorldState extends GameState<CameraWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield const Player(tag: 'player');

    yield GameObjectWidget(
      tag: 'mainCamera',
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          Camera.new.withInitialValues(
            (c) => c
              ..orthographicSize = 5.0
              ..backgroundColor = const Color(0xFF111111),
          ),
        ),
        // Add this: ------
        ComponentWidget(CameraFollow.new),
        // --------
      ],
    );
  }
}
```

### 10. Implement Smooth Follow

Add the smooth-damp state fields and implement `onLateUpdate` to track the player.

```dart
class CameraFollow extends Behavior with LateTickable {
  // Add this: ------
  Vector2 _velocity = Vector2.zero();
  // --------

  @override
  void onLateUpdate(double dt) {
    // Add this: ------
    final player = GameObject.findWithTag(gameObject, 'player');
    if (player == null) return;
    final target = player.tryGetComponent<ObjectTransform>()?.position;
    if (target == null) return;

    final camTransform = getComponent<ObjectTransform>();
    final result = MathUtils.smoothDampVector2(
      camTransform.position,
      target,
      _velocity,
      0.15,
      dt,
    );
    camTransform.position = result.value;
    _velocity = result.velocity;
    // --------
  }
}
```

`MathUtils.smoothDampVector2` applies a critically-damped spring that moves the camera toward the target. The `0.15` smoothing time controls how quickly it catches up — smaller values are snappier, larger values are lazier. `_velocity` must persist between frames so the spring has momentum across frames.

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

void main() => runApp(const CameraExample());

class CameraExample extends StatelessWidget {
  const CameraExample({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: FutureBuilder(
        future: GameAsset.loadAll(GameTextures.values).drain(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return const Game(child: CameraWorld());
        },
      ),
    );
  }
}

class CameraWorld extends StatefulGameWidget {
  const CameraWorld({super.key});

  @override
  GameState<CameraWorld> createState() => CameraWorldState();
}

class CameraWorldState extends GameState<CameraWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield const Player(tag: 'player');

    yield GameObjectWidget(
      tag: 'mainCamera',
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          Camera.new.withInitialValues(
            (c) => c
              ..orthographicSize = 5.0
              ..backgroundColor = const Color(0xFF111111),
          ),
        ),
        ComponentWidget(CameraFollow.new),
      ],
    );
  }
}

class Player extends StatefulGameWidget {
  const Player({super.key, super.tag});

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
    addComponent(
      moveAction,
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
    getComponent<ObjectTransform>().position += dir * 5.0 * dt;
  }

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}

class CameraFollow extends Behavior with LateTickable {
  Vector2 _velocity = Vector2.zero();

  @override
  void onLateUpdate(double dt) {
    final player = GameObject.findWithTag(gameObject, 'player');
    if (player == null) return;
    final target = player.tryGetComponent<ObjectTransform>()?.position;
    if (target == null) return;

    final camTransform = getComponent<ObjectTransform>();
    final result = MathUtils.smoothDampVector2(
      camTransform.position,
      target,
      _velocity,
      0.15,
      dt,
    );
    camTransform.position = result.value;
    _velocity = result.velocity;
  }
}
```
