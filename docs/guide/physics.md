# Physics

!!! abstract "Layer: opt-in — `goo2d_physics_box2d`"
    Box2D v3, compiled from vendored source per platform, stepped inside the
    game isolate in lockstep with the fixed tick.

```yaml title="pubspec.yaml"
dependencies:
  goo2d_physics_box2d: ^0.0.1
```

## A body in three declarations

```dart
class Crate extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D, Collider2D, RigidBody2D {
  late final BoxBody box;
  late final Sprite sprite;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    box = descriptor.hasBoxCollider(
      halfWidth: 0.5, halfHeight: 0.5, friction: 0.4,
    );
  }

  @override
  void describeRigidBody(RigidBody2DDescriptor descriptor) {
    descriptor.has(type: BodyType2D.dynamicBody);
  }

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    sprite = descriptor.has(width: 1, height: 1, color: 0xFFCC8844);
  }
}
```

Declare the system on the state:

```dart
@override
void describeSystems(SystemDescriptor descriptor) {
  super.describeSystems(descriptor);
  descriptor.has(Box2DPhysicsSystem(gravityY: 10));
}
```

That is the whole opt-in. Bodies are created as entities spawn and destroyed as
they despawn — the system listens to spawn events rather than needing to be told.

!!! warning "Units are metres, kilograms and seconds"
    Box2D is tuned for objects roughly 0.1 m to 10 m. A game that treats one
    world unit as one pixel gives a 32-pixel crate the mass and inertia of a
    32-metre building — still simulated, visibly wrong, and usually diagnosed as
    "the physics feels floaty".

    Work in metres and apply the pixels-per-metre scale **once**, at the
    camera's zoom. Nothing in the simulation should know about pixels.

## Colliders

`Collider2D` lives in `goo2d`, not in the physics package — a collider describes
an entity's geometry whether or not it is ever simulated. Four shapes:

```dart
circle = descriptor.hasCircleCollider(radius: 0.5);
box    = descriptor.hasBoxCollider(halfWidth: 0.5, halfHeight: 0.5);
pill   = descriptor.hasCapsuleCollider(radius: 0.25, halfHeight: 0.5);
poly   = descriptor.hasPolygonCollider(maxPoints: 4);   // capacity, not points
```

A polygon declares its **capacity** at declare time and its actual points per
entity, because the outline is per-entity data like any other. Populate it at
mount:

```dart
class Wedge extends EntityStruct
    with Transform2D, Collider2D, EntityLifecycleListener {
  late final PolygonBody outline;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    outline = descriptor.hasPolygonCollider(maxPoints: 3);
  }

  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    outline.pointsX.set(entity, 0, -0.5);
    outline.pointsY.set(entity, 0,  0.5);
    outline.pointsX.set(entity, 1,  0.5);
    outline.pointsY.set(entity, 1,  0.5);
    outline.pointsX.set(entity, 2,  0.0);
    outline.pointsY.set(entity, 2, -0.5);
    outline.pointCount[entity] = 3;      // (1)!
  }
}
```

1. Defaults to `0`. A polygon of fewer than three points encloses no area and
   contains nothing — which is exactly what a prefab that forgot this line
   leaves behind.

`Collider2D` is a multi-component, so one entity can declare several shapes —
a body plus a separate trigger volume, for instance.

Every shape's properties are columns, so they are per-entity and writable:

| Column | Meaning |
|---|---|
| `enable` | Whether the solver sees this shape at all |
| `isTrigger` | Overlap events without a physical response |
| `density`, `friction`, `restitution` | Material |
| `offsetX`, `offsetY` | Position within the entity |
| `layer`, `excludeLayers` | Collision filtering |

```dart
crate.box.isTrigger[entity] = true;    // become a trigger at run time
crate.box.enable[entity] = false;      // stop colliding, keep the declaration
```

## Body types, and who owns the transform

This is the part that most often goes wrong, and it is worth being explicit.

| `BodyType2D` | Moves under | Transform authority |
|---|---|---|
| `staticBody` | Nothing | **You** — write `Transform2D` |
| `kinematicBody` | Velocity you set | **You** |
| `dynamicBody` | Forces, gravity, contacts | **Box2D** — it writes `Transform2D` |

**Writing a dynamic body's `Transform2D` every tick fights the solver.** To move
a dynamic body, apply forces or set its velocity:

```dart
final body = entity.get<RigidBody2D>();
body.applyForce(entity, 0, -50);
body.applyImpulse(entity, 5, 0);
body.applyTorque(entity, 2);
body.setVelocity(entity, 3, 0);
body.setAngularVelocity(entity, 1.5);
```

A body's type is itself a column, so a platform can become static and a
kinematic lift can become dynamic without anything being rebuilt:

```dart
body.bodyType[entity] = BodyType2D.staticBody;
```

And a body can be taken out of the simulation entirely without being destroyed —
the toggle pattern again, rather than a removal:

```dart
body.setSimulated(entity, false);
```

## Collisions and triggers

```dart
class Player extends EntityStruct
    with Transform2D, Collider2D, RigidBody2D, CollisionListener {
  @override
  void onCollisionEnter2D(Collision2DEvent event) { }
  @override
  void onCollisionStay2D(Collision2DEvent event) { }
  @override
  void onCollisionExit2D(Collision2DEvent event) { }

  // Triggers are the same three phases, dispatched separately.
  @override
  void onTriggerEnter2D(Collision2DEvent event) { }
  @override
  void onTriggerStay2D(Collision2DEvent event) { }
  @override
  void onTriggerExit2D(Collision2DEvent event) { }
}
```

Enter, stay and exit are separate phases, so "did we just land" does not have to
be reconstructed from a stream of contacts. Solid contacts and trigger overlaps
are dispatched to different handlers, so a shape with `isTrigger` set does not
have to be filtered out of collision logic.

## Queries

Raycasts and overlap queries go through the system:

```dart
final physics = state.getSystem<Box2DPhysicsSystem>();

if (physics.raycast(originX, originY, dirX, dirY, layerMask: -1)) {
  final entity = physics.hitEntity;
  final x = physics.hitX;
  final y = physics.hitY;
  final nx = physics.hitNormalX;
  final fraction = physics.hitFraction;
}
```

The hit is read back off the system rather than returned as an object, so a
raycast in a tick allocates nothing. `raycast` finds the **closest** hit.

```dart
final found = physics.overlapBox(minX, minY, maxX, maxY, maxResults: 256);
for (var i = 0; i < found; i++) {
  final entity = physics.overlapEntityAt(i);
  final collider = physics.overlapColliderAt(i);
}
```

!!! info "`overlapBox` is broad-phase"
    It is an **AABB test**, not an exact shape overlap, so a shape near a corner
    of the box can be reported without truly overlapping it. That is the useful
    primitive — "roughly what is in this region" — and a caller needing
    exactness re-tests the survivors, which is cheap once the set is small.

    Results are valid until the next query, and `maxResults` bounds the work
    rather than growing a buffer without limit.

## Joints

All nine of Unity's 2D joints, created on the system:

```dart
// A hinge at the top of `arm`, anchored to `post`, with a driven motor.
final hinge = physics.createRevoluteJoint(
  post, arm,
  anchorAX: 0, anchorAY: 0,
  anchorBX: 0, anchorBY: -0.5,
  enableLimit: true, lowerAngle: -1.2, upperAngle: 1.2,
  enableMotor: true, motorSpeed: 2, maxMotorTorque: 50,
);
```

`post` and `arm` are `Entity` handles that both carry `RigidBody2D`. Every joint
constructor takes the two entities positionally and everything else by name, and
returns `Joint.none` if either has no body yet.

| goo | Unity's name |
|---|---|
| `createDistanceJoint` | Distance / Spring |
| `createRevoluteJoint` | Hinge |
| `createPrismaticJoint` | Slider |
| `createWeldJoint` | Fixed |
| `createWheelJoint` | Wheel |
| `createMotorJoint` | Relative / Friction |
| `createMouseJoint` | Target |

A `Joint` is an `extension type` over an int handle — passing one costs nothing.

## Effectors

Unity's effectors are gameplay code that finds bodies in a region and applies a
force, so **Box2D has nothing to bind a component to**. They are extension
methods on the system instead:

```dart
class WindSystem extends GameSystem with FixedTickable {
  @override
  int compareTo(GameSystem other) => other is Box2DPhysicsSystem ? -1 : 0;

  @override
  void onFixedUpdate() {
    state.getSystem<Box2DPhysicsSystem>().areaEffector(
      -10, -5, 10, 5,          // the world-space box it acts in
      forceX: 20,
    );
  }
}
```

Area, Point, Buoyancy and Surface are provided. Platform (one-way) is not.

## Ordering around physics

A system that *sets up* physics state runs before the solver; one that *reacts*
to results runs after:

```dart
@override
int compareTo(GameSystem other) => other is Box2DPhysicsSystem ? -1 : 0;  // before

@override
int compareTo(GameSystem other) => other is Box2DPhysicsSystem ? 1 : 0;   // after
```

## Performance

```dart
Box2DPhysicsSystem(
  gravityY: 10,
  subStepCount: 4,     // solver accuracy per step
  workerCount: 4,      // parallel solver threads
)
```

Box2D's cost follows the **contact graph**, not the body count. A crowded arena
where bodies overlap and the solver pushes them apart every step without ever
converging costs far more than the same bodies with room to settle — and an
island that never goes quiet never sleeps. If physics is slow, look at density
before you look at counts.

The ECS layer around the solver — filling the scratch buffers, syncing
transforms back, dispatching contacts — is deliberately thin: bulk entry points
turn what would be 2N FFI calls per tick into two, independent of body count.

The system exposes per-phase timings and body counts for a debug overlay. They
are development instrumentation rather than a stable API, but they are how a
"physics is slow" report gets separated into "the arena is too small" and
"bodies are leaking" — two problems with nothing in common.

---

## Next

[Talking to Flutter →](flutter-bridge.md)
