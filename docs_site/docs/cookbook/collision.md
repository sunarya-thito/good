---
sidebar_position: 4
---

# Collisions & Triggers

This page shows how physics collisions work in goo2d. A ball bounces between static walls using `Rigidbody` + `BoxCollider` for solid collision. A separate trigger zone changes the ball's color when it is entered, showing how `isTrigger = true` lets objects overlap without physics response.

## Live Demo

<iframe 
  src="/goo2d/play/#/collision" 
  width="100%" 
  height="400px" 
  style={{ border: 'none', borderRadius: '8px', background: '#000' }}
/>

## Assets Used

No external assets. All shapes are colored solid rectangles and circles.

---

## Tutorial

### 1. Imports and main()

```dart
// Add this: ------
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';

void main() => runApp(const CollisionExample());
// --------
```

### 2. Root Widget

```dart
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';

void main() => runApp(const CollisionExample());

// Add this: ------
class CollisionExample extends StatelessWidget {
  const CollisionExample({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Game(child: CollisionWorld())),
    );
  }
}
// --------
```

### 3. Game World and Camera Scaffold

```dart
// Add this: ------
class CollisionWorld extends StatefulGameWidget {
  const CollisionWorld({super.key});

  @override
  GameState<CollisionWorld> createState() => CollisionWorldState();
}

class CollisionWorldState extends GameState<CollisionWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield GameObjectWidget(
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          Camera.new.withInitialValues(
            (c) => c
              ..orthographicSize = 6.0
              ..backgroundColor = const Color(0xFF1a1a2e),
          ),
        ),
      ],
    );
  }
}
// --------
```

### 4. Static Walls

Add four static walls around the play area. `Rigidbody` with `bodyType = RigidbodyType.static` means the body participates in collision but never moves. `BoxCollider` defines the rectangular shape.

```dart
class CollisionWorldState extends GameState<CollisionWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {
    // Add this: ------
    for (final data in [
      (Vector2(0, 5.5), Vector2(12, 0.5)),   // top
      (Vector2(0, -5.5), Vector2(12, 0.5)),  // bottom
      (Vector2(-5.5, 0), Vector2(0.5, 11)),  // left
      (Vector2(5.5, 0), Vector2(0.5, 11)),   // right
    ]) {
      yield GameObjectWidget(
        children: [
          ComponentWidget(
            ObjectTransform.new.withInitialValues((t) => t.position = data.$1),
          ),
          ComponentWidget(
            Rigidbody.new.withInitialValues(
              (rb) => rb.bodyType = RigidbodyType.static,
            ),
          ),
          ComponentWidget(
            BoxCollider.new.withInitialValues((c) => c.size = data.$2),
          ),
          ComponentWidget(
            SpriteRenderer.new.withInitialValues(
              (r) => r.color = const Color(0xFF4a4e69),
            ),
          ),
        ],
      );
    }
    // --------

    yield GameObjectWidget(
      children: [ /* camera */ ],
    );
  }
}
```

Each wall is a separate game object. The `(position, size)` tuples make it easy to parameterize the loop. Physics bodies interact only with other objects that also have a `Rigidbody` + `Collider`.

### 5. Empty Ball Widget

Define the ball game object that will bounce around.

```dart
// Add this: ------
class Ball extends StatefulGameWidget {
  const Ball({super.key});

  @override
  GameState<Ball> createState() => BallState();
}

class BallState extends GameState<Ball> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
// --------
```

### 6. Add Ball to the World

```dart
class CollisionWorldState extends GameState<CollisionWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {
    // Add this: ------
    yield const Ball();
    // --------

    /* walls ... */
    /* camera ... */
  }
}
```

### 7. Ball Components

Attach a `Rigidbody` (dynamic) and `CircleCollider` to the ball. The `dynamic` body type means the physics engine controls its velocity via forces and collisions.

```dart
class BallState extends GameState<Ball> {
  // Add this: ------
  @override
  void initState() {
    super.initState();
    addComponent(
      ObjectTransform()..position = Vector2.zero(),
      Rigidbody()
        ..bodyType = RigidbodyType.dynamic
        ..gravityScale = 0
        ..linearDamping = 0
        ..angularDamping = 0,
      CircleCollider()
        ..radius = 0.4
        ..bounciness = 1.0
        ..friction = 0.0,
      SpriteRenderer()..color = Colors.white,
    );
  }
  // --------

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```

`gravityScale = 0` disables gravity so the ball slides freely. `bounciness = 1.0` (restitution) makes collisions fully elastic. `friction = 0.0` prevents the ball from slowing down along wall surfaces.

### 8. Apply Initial Velocity

Use `LifecycleListener.onMounted` to push the ball once the physics body is ready. Forces applied before mounting are ignored.

```dart
class BallState extends GameState<Ball> with LifecycleListener {
  @override
  void initState() { /* ... */ }

  // Add this: ------
  @override
  void onMounted() {
    getComponent<Rigidbody>().linearVelocity = Vector2(3.0, 2.5);
  }
  // --------

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```

`linearVelocity` sets the velocity directly in world units per second. Setting it in `onMounted` guarantees the physics body exists; setting it in `initState` would run before the body is registered.

### 9. Detect Collisions with CollisionListener

Mix in `CollisionListener` to receive callbacks when the ball hits a wall.

```dart
// Add this: ------
class BallState extends GameState<Ball>
    with LifecycleListener, CollisionListener {
// --------
  @override
  void initState() { /* ... */ }

  @override
  void onMounted() { /* ... */ }

  // Add this: ------
  @override
  Future<void> onCollisionEnter(Collision collision) async {
    getComponent<SpriteRenderer>().color = Color.fromARGB(
      255,
      100 + (collision.relativeVelocity.x.abs() * 20).toInt().clamp(0, 155),
      100,
      200,
    );
  }
  // --------

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}
```

`onCollisionEnter` fires once on the first frame of contact. `collision.otherCollider` identifies which wall was hit, and `collision.relativeVelocity` gives the impact speed. Here the color shifts based on the horizontal velocity component of the impact.

### 10. Add a Trigger Zone

A trigger zone overlaps objects physically but does not produce a collision response. It only fires `onTriggerEnter`/`onTriggerExit`. Requires `isTrigger = true` on the collider and `usedByEffector = true` is not needed — `isTrigger` alone is sufficient.

```dart
class CollisionWorldState extends GameState<CollisionWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield const Ball();

    // Add this: ------
    yield GameObjectWidget(
      children: [
        ComponentWidget(
          ObjectTransform.new.withInitialValues(
            (t) => t.position = Vector2(2.0, 1.0),
          ),
        ),
        ComponentWidget(
          Rigidbody.new.withInitialValues(
            (rb) => rb.bodyType = RigidbodyType.static,
          ),
        ),
        ComponentWidget(
          BoxCollider.new.withInitialValues(
            (c) => c
              ..size = Vector2(2.0, 2.0)
              ..isTrigger = true,
          ),
        ),
        ComponentWidget(TriggerZone.new),
        ComponentWidget(
          SpriteRenderer.new.withInitialValues(
            (r) => r.color = const Color(0x44ffff00),
          ),
        ),
      ],
    );
    // --------

    /* walls ... */
    /* camera ... */
  }
}
```

### 11. Trigger Zone Behavior

Define `TriggerZone` as a `Behavior` that uses `CollisionListener` to detect when the ball enters or exits.

```dart
// Add this: ------
class TriggerZone extends Behavior with CollisionListener {
  @override
  Future<void> onTriggerEnter(Collision collision) async {
    final renderer = collision.otherCollider.gameObject
        .tryGetComponent<SpriteRenderer>();
    renderer?.color = Colors.yellow;
  }

  @override
  Future<void> onTriggerExit(Collision collision) async {
    final renderer = collision.otherCollider.gameObject
        .tryGetComponent<SpriteRenderer>();
    renderer?.color = Colors.white;
  }
}
// --------
```

`onTriggerEnter` fires on the other object's first frame inside the zone. The `collision.otherCollider.gameObject` reference lets this behavior reach back to the ball and change its renderer color. `onTriggerExit` restores the color when the ball leaves.

---

## Final Code

```dart
import 'package:flutter/material.dart';
import 'package:goo2d/goo2d.dart';

void main() => runApp(const CollisionExample());

class CollisionExample extends StatelessWidget {
  const CollisionExample({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Game(child: CollisionWorld())),
    );
  }
}

class CollisionWorld extends StatefulGameWidget {
  const CollisionWorld({super.key});

  @override
  GameState<CollisionWorld> createState() => CollisionWorldState();
}

class CollisionWorldState extends GameState<CollisionWorld> {
  @override
  Iterable<Widget> build(BuildContext context) sync* {
    yield const Ball();

    yield GameObjectWidget(
      children: [
        ComponentWidget(
          ObjectTransform.new.withInitialValues(
            (t) => t.position = Vector2(2.0, 1.0),
          ),
        ),
        ComponentWidget(
          Rigidbody.new.withInitialValues(
            (rb) => rb.bodyType = RigidbodyType.static,
          ),
        ),
        ComponentWidget(
          BoxCollider.new.withInitialValues(
            (c) => c
              ..size = Vector2(2.0, 2.0)
              ..isTrigger = true,
          ),
        ),
        ComponentWidget(TriggerZone.new),
        ComponentWidget(
          SpriteRenderer.new.withInitialValues(
            (r) => r.color = const Color(0x44ffff00),
          ),
        ),
      ],
    );

    for (final data in [
      (Vector2(0, 5.5), Vector2(12, 0.5)),
      (Vector2(0, -5.5), Vector2(12, 0.5)),
      (Vector2(-5.5, 0), Vector2(0.5, 11)),
      (Vector2(5.5, 0), Vector2(0.5, 11)),
    ]) {
      yield GameObjectWidget(
        children: [
          ComponentWidget(
            ObjectTransform.new.withInitialValues((t) => t.position = data.$1),
          ),
          ComponentWidget(
            Rigidbody.new.withInitialValues(
              (rb) => rb.bodyType = RigidbodyType.static,
            ),
          ),
          ComponentWidget(
            BoxCollider.new.withInitialValues((c) => c.size = data.$2),
          ),
          ComponentWidget(
            SpriteRenderer.new.withInitialValues(
              (r) => r.color = const Color(0xFF4a4e69),
            ),
          ),
        ],
      );
    }

    yield GameObjectWidget(
      children: [
        ComponentWidget(ObjectTransform.new),
        ComponentWidget(
          Camera.new.withInitialValues(
            (c) => c
              ..orthographicSize = 6.0
              ..backgroundColor = const Color(0xFF1a1a2e),
          ),
        ),
      ],
    );
  }
}

class Ball extends StatefulGameWidget {
  const Ball({super.key});

  @override
  GameState<Ball> createState() => BallState();
}

class BallState extends GameState<Ball>
    with LifecycleListener, CollisionListener {
  @override
  void initState() {
    super.initState();
    addComponent(
      ObjectTransform()..position = Vector2.zero(),
      Rigidbody()
        ..bodyType = RigidbodyType.dynamic
        ..gravityScale = 0
        ..linearDamping = 0
        ..angularDamping = 0,
      CircleCollider()
        ..radius = 0.4
        ..bounciness = 1.0
        ..friction = 0.0,
      SpriteRenderer()..color = Colors.white,
    );
  }

  @override
  void onMounted() {
    getComponent<Rigidbody>().linearVelocity = Vector2(3.0, 2.5);
  }

  @override
  Future<void> onCollisionEnter(Collision collision) async {
    getComponent<SpriteRenderer>().color = Color.fromARGB(
      255,
      100 + (collision.relativeVelocity.x.abs() * 20).toInt().clamp(0, 155),
      100,
      200,
    );
  }

  @override
  Iterable<Widget> build(BuildContext context) sync* {}
}

class TriggerZone extends Behavior with CollisionListener {
  @override
  Future<void> onTriggerEnter(Collision collision) async {
    collision.otherCollider.gameObject
        .tryGetComponent<SpriteRenderer>()
        ?.color = Colors.yellow;
  }

  @override
  Future<void> onTriggerExit(Collision collision) async {
    collision.otherCollider.gameObject
        .tryGetComponent<SpriteRenderer>()
        ?.color = Colors.white;
  }
}
```
