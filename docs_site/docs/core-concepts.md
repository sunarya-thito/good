---
sidebar_position: 2
---

# Core Concepts

## The Game Tree

Every game scene is a tree of Flutter widgets. The root is a `Game` widget. Everything inside it
is part of the engine — game objects, cameras, and physics all run within this subtree.

Game objects are created by subclassing `StatefulGameWidget` or `StatelessGameWidget`. Their `build`
method is a `sync*` generator that yields child widgets:

```dart
class BattleWorld extends StatefulGameWidget {
  @override
  GameState<BattleWorld> createState() => BattleWorldState();
}

class BattleWorldState extends GameState<BattleWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield const Background();
    yield const Player();
    yield const EnemyWave();
  }
}
```

For groups of components without custom logic, use `GameObjectWidget` with `ComponentWidget` children:

```dart
GameObjectWidget(
  name: 'Platform',
  children: [
    ComponentWidget(ObjectTransform.new.withInitialValues((t) => t.position = Vector2(0, -3))),
    ComponentWidget(SpriteRenderer.new.withInitialValues((r) => r.sprite = platformSprite)),
    ComponentWidget(Rigidbody.new.withInitialValues((rb) => rb.bodyType = RigidbodyType.static)),
    ComponentWidget(BoxCollider.new.withInitialValues((c) => c.size = Vector2(5, 0.3))),
  ],
)
```

## Components

A **Component** is a self-contained piece of data or logic attached to a game object. Game objects
are composed from multiple small components, each responsible for one thing:

- `ObjectTransform` — position, rotation, and scale
- `SpriteRenderer` — draws a sprite each frame
- `Rigidbody` + `BoxCollider` — physics body and shape
- `AudioSource` — plays a sound clip

### Component vs Behavior

`Component` is the base class. `Behavior extends Component` adds an `enabled` flag, which lets
you temporarily suspend a component's logic without removing it.

### Attaching Components

Call `addComponent(...)` in `GameState.initState()`. Components added there are available in
`onMounted()` callbacks of sibling components.

```dart
class PlayerState extends GameState<Player> {
  @override
  void initState() {
    super.initState();
    addComponent(
      ObjectTransform()..position = Vector2(0, 0),
      SpriteRenderer()..sprite = playerSprite,
      Rigidbody()..gravityScale = 1.0,
      BoxCollider()..size = Vector2(0.8, 1.8),
    );
  }
}
```

Do **not** add a `StatefulGameWidget`'s own components via `ComponentWidget` in `build()` — they
will not be available in `initState()` because `build()` runs after it. Use `build()` only for
declaring child game objects.

## Per-Frame Updates

Mix in update interfaces to receive engine callbacks:

| Mixin | Method | When |
|---|---|---|
| `Tickable` | `onUpdate(double dt)` | Every frame — use for game logic |
| `LateTickable` | `onLateUpdate(double dt)` | After all `Tickable` updates — use for camera follow |
| `FixedTickable` | `Future<void> onFixedUpdate(double dt)` | Fixed 50 Hz — use for physics queries |
| `Renderable` | `render(Canvas canvas)` | Canvas drawing pass |

`dt` is the elapsed time in seconds since the last frame. Always accumulate `dt` over time rather
than assuming a fixed step:

```dart
class MovementBehavior extends Behavior with Tickable {
  double speed = 5.0;

  @override
  void onUpdate(double dt) {
    getComponent<ObjectTransform>().position += Vector2(speed * dt, 0);
  }
}
```

## Lifecycle

Mix in `LifecycleListener` to receive mount and unmount notifications:

```dart
class MyBehavior extends Behavior with LifecycleListener {
  @override
  void onMounted() {
    // Called when the GameObject enters the tree.
    // All components added in initState() are already attached here.
  }

  @override
  void onUnmounted() {
    // Called when the GameObject leaves the tree.
  }
}
```

## Events

The event system lets components communicate without direct references.

A listener is a **mixin** that `implements EventListener`. An event dispatches to every component
on the target object that mixes in the listener:

```dart
// 1. Define the listener
mixin DamageListener implements EventListener {
  void onDamage(double amount);
}

// 2. Create the event
class DamageEvent extends Event<DamageListener> {
  final double amount;
  const DamageEvent(this.amount);

  @override
  void dispatch(DamageListener listener) => listener.onDamage(amount);
}

// 3. Opt in by mixing in the listener
class EnemyHealth extends Component with DamageListener {
  double hp = 100;

  @override
  void onDamage(double amount) => hp -= amount;
}

// 4. Dispatch
gameObject.sendEvent(const DamageEvent(10));      // this object only
gameObject.broadcastEvent(const DamageEvent(10)); // this object + all descendants
```

## Transform

`ObjectTransform` stores position, rotation, and scale. There are two sets of properties:
world-space and local-space (relative to the parent).

```dart
final t = getComponent<ObjectTransform>();

// World space
t.position = Vector2(3, 0);
t.angle += ObjectTransform.degrees(90) * dt;  // degrees() converts to radians
t.scale = Vector2(2, 2);

// Local space (relative to parent)
t.localPosition = Vector2(0, 1);
t.localAngle = ObjectTransform.degrees(45);
t.localScale = Vector2(1, 1);
```

The rotation property is named `angle` (world) and `localAngle` (local). There is no `rotation` property.

For UI elements that should remain fixed on screen regardless of camera movement, use `ScreenTransform`
instead of `ObjectTransform`.

## Component Navigation

```dart
// Same object
getComponent<T>()               // throws if not found
tryGetComponent<T>()            // returns null if not found
getComponents<T>()              // all instances (use with MultiComponent)

// Parents
getComponentInParent<T>()
tryGetComponentInParent<T>()

// Children (recursive — avoid in hot paths)
getComponentInChildren<T>()
tryGetComponentInChildren<T>()
```

## Assets

Assets use an enum that mixes in `AssetEnum` and either `TextureAssetEnum` or `AudioAssetEnum`:

```dart
enum Sprites with AssetEnum, TextureAssetEnum {
  ship, explosion;

  @override
  AssetSource get source => AssetSource.local('sprites/$name.png');
}
```

Load all assets before showing the game:

```dart
await GameAsset.loadAll(Sprites.values);
```

Then reference them directly:

```dart
final sprite = GameSprite(mesh: SimpleMesh(texture: Sprites.ship));
```

## Flutter Interoperability

`Game` is a normal Flutter widget and can be placed inside any Flutter widget tree — inside a
`Scaffold`, inside a `Stack`, inside a `Dialog`. The engine does not replace your app.

Normal Flutter widgets can also be yielded from `GameState.build()`. They appear in world space
and move with the camera unless they are inside a `ScreenTransform` object, which pins them to screen coordinates.

```dart
// FPS counter pinned to screen
class HudState extends GameState<Hud> with Tickable {
  double fps = 0;

  @override
  void onUpdate(double dt) {
    if (dt > 0) setState(() => fps = 1.0 / dt);
  }

  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield GameObjectWidget(
      children: [
        ComponentWidget(ScreenTransform.new),  // pins to screen space
      ],
      // children rendered as Flutter UI here
    );
  }
}
```
