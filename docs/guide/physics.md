# Physics

<!-- snippet-scope
late ColliderDescriptor descriptor;
late CircleBody circle;
late BoxBody box;
late CapsuleBody pill;
late PolygonBody poly;
late Wedge wedge;
late Crate crate;
late RigidBody2D body;
late AreaEffector wind;
late Box2DPhysicsSystem physics;
late Entity post;
late Entity arm;
double originX = 0, originY = 0, dirX = 1, dirY = 0;
double minX = 0, minY = 0, maxX = 1, maxY = 1;
-->

!!! abstract "Layer: opt-in — `goo2d_physics_box2d`"
    Box2D v3, compiled from vendored source per platform, stepped inside the
    game isolate in lockstep with the fixed tick.

```yaml title="pubspec.yaml"
dependencies:
  goo2d_physics_box2d: ^0.1.0
```

## A body in one mixin

```dart
class Crate extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D, Collider2D, RigidBody2D {
  late final BoxBody box;
  final sprite = Sprite.of(width: 1, height: 1, color: 0xFFCC8844);

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    box = descriptor.hasBoxCollider(
      halfWidth: 0.5, halfHeight: 0.5, friction: 0.4,
    );
  }
}
```

`RigidBody2D` has no declaration pass of its own. Every one of its columns
already starts at what a plain dynamic body wants, so a crate that wants a
plain dynamic body says nothing. A prefab that wants something else moves the
column's default:

```dart
class Wall extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    bodyType.initialValue = BodyType2D.staticBody;
  }
}
```

That is a default for every wall's row, not a write to one — the same column
[you set per entity](#body-types-and-who-owns-the-transform) once the game is
running.

Declare the system on the state:

<!-- snippet: in GameState -->
```dart
@override
void describeSystems(SystemDescriptor descriptor) {
  super.describeSystems(descriptor);
  descriptor.has(() => Box2DPhysicsSystem(gravityY: -10));
}
```

That is the whole opt-in. Bodies are created as entities spawn and destroyed as
they despawn — the system listens to spawn events instead of needing to be told.

!!! note "Gravity is negative"
    World +Y is up, so down is `-Y` and gravity is `(0, -10)` — the same sign
    Box2D's own samples use, and the same one `goo3d` uses. A floor sits at a
    *smaller* y than the bodies landing on it.

    `-10` is also the default, so `Box2DPhysicsSystem()` on its own already
    falls the right way. The magnitude is 10 rather than 9.81 because Box2D
    uses 10; it is a game engine, not a geodesy package.

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
poly   = descriptor.hasPolygonCollider(points: [(-0.5, 0.5), (0.5, 0.5), (0, -0.5)]);
```

A polygon states its outline where it declares the field, and every entity of
the prefab starts with those vertices:

```dart
class Wedge extends EntityStruct with Transform2D, Collider2D {
  late final PolygonBody outline;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    outline = descriptor.hasPolygonCollider(
      points: const [(-0.5, 0.5), (0.5, 0.5), (0.0, -0.5)],
      maxPoints: 4,      // (1)!
    );
  }
}
```

1. The storage capacity, fixed per archetype. It defaults to `points.length`,
   and 8 is the ceiling — Box2D's own `b2_maxPolygonVertices`. Reserve more
   than the outline fills when an entity should be able to *grow* its polygon
   at run time.

The outline is per-entity data like anything else, so an entity can still
rewrite it — `pointCount` is what the solver and `containsLocalPoint` read,
never the array's capacity:

```dart
wedge.outline.pointsX.set(entity, 3, 0.5);
wedge.outline.pointsY.set(entity, 3, -0.25);
wedge.outline.pointCount[entity] = 4;   // (1)!
```

1. A polygon of fewer than three points encloses no area and contains nothing.
   Declaring one is an error; shrinking to one at run time simply picks up
   nothing.

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
final body = entity<RigidBody2D>().component;
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

### Move a platform or rotating body with a kinematic body

Give a moving platform or scripted rotating body `kinematicBody` and drive it
with `setVelocity` or `setAngularVelocity`. It carries whatever rests on it,
contacts never push it off course, and its motion reaches the solver smoothly on
every tick.

A static body you script by writing `Transform2D` behaves differently, and the
difference is easy to read as a bug. Each tick the system compares what you
wrote against what it last sent to Box2D, and sends nothing when the change is
smaller than `1e-4` units of position (`positionEpsilon`) or `5e-3` radians of
angle (`angleEpsilon`, roughly 0.29°). Turn a static body by 0.001 rad per tick
and it holds still for around five ticks, then turns by the whole accumulated
amount at once. It ends up within one threshold of everything you wrote; it gets
there in steps.

The threshold earns its place. Sending a static body's transform every tick
round-trips its angle through `b2MakeRot`, and that is an approximation — a
floor authored at 0.3 rad drifts to 0.718 over a thousand ticks and to π/4 over
ten thousand. Comparing first is what stops an unmoved body being re-sent and
re-approximated forever.

Static suits geometry that stays put, and geometry you reposition in jumps
nobody tracks frame by frame: a door that opens, a bridge that drops. Anything
meant to glide, spin, or rotate smoothly is kinematic.

And a body can be taken out of the simulation entirely without being destroyed —
the toggle pattern again, not a removal:

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

Raycasts and overlap queries go through the system, and each one names the
scene to search:

```dart
final physics = state.getSystem<Box2DPhysicsSystem>();

if (physics.raycast(scene, originX, originY, dirX, dirY, layerMask: -1)) {
  final entity = physics.hitEntity;
  final x = physics.hitX;
  final y = physics.hitY;
  final nx = physics.hitNormalX;
  final fraction = physics.hitFraction;
}
```

The hit is read back off the system instead of returned as an object, so a
raycast in a tick allocates nothing. `raycast` finds the **closest** hit.

Each loaded scene simulates in its own Box2D world, so a query has to say which
one it means. There is no default: a query that fell back to "the one loaded
scene" would work for months and then search the wrong world the day you load a
HUD. Pass the handle `loadScene` gave you.

```dart
final found = physics.overlapBox(scene, minX, minY, maxX, maxY, maxResults: 256);
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
    instead of growing a buffer without limit.

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

| good | Unity's name |
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

An effector is a region that pushes on whatever is inside it: wind, a current,
an updraft, water. Declare one on an entity beside the collider that gives it
its shape.

```dart
class WindZone extends EntityStruct with Transform2D, Collider2D, Effector2D {
  late final BoxBody region;
  late final AreaEffector wind;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    region = descriptor.hasBoxCollider(
      halfWidth: 50, halfHeight: 50, isTrigger: true,
    );
  }

  @override
  void describeEffector(EffectorDescriptor descriptor) {
    super.describeEffector(descriptor);
    wind = descriptor.hasAreaEffector(region, forceY: 400);
  }
}
```

It has no `RigidBody2D`, because a force field is not a thing that falls, and
its collider is a trigger, so it pushes bodies without blocking them. Positive
y is up, so a wind that lifts blows toward `+y`.

**You do not write a system for this, and you do not write a `compareTo`.** The
physics system walks the declared effectors before its own step, so the
ordering is not your problem.

Four kinds are provided:

| Declare | Does |
|---|---|
| `hasAreaEffector(region, forceX:, forceY:, torque:)` | A uniform push, and optionally a spin |
| `hasPointEffector(region, force:, minDistance:)` | Pulls toward or pushes from the centre. `minDistance` stops the force exploding at zero |
| `hasBuoyancyEffector(region, density:, linearDrag:, angularDrag:)` | Water: floats what is less dense, drags what moves. The water line is the region's **top** edge |
| `hasSurfaceEffector(region, speed:, speedY:, force:)` | A conveyor, dragging contents toward a target speed |

Platform (one-way) is not provided.

Every parameter is a column, so a zone can change while the game runs, and
`layerMask` picks what it acts on:

```dart
wind.forceY[entity] = 800;
wind.enable[entity] = false;
```

!!! note "The functions underneath"
    `Effectors2D` on the system still exposes the same four as one-shot calls
    for a region you compute per tick. Declaring is the better default: it
    keeps the region with the entity and gets the ordering right for you.

## Ordering around physics

A system that *sets up* physics state runs before the solver; one that *reacts*
to results runs after:

<!-- snippet: skip two alternatives, one per system, not one class -->
```dart
@override
int compareTo(GameSystem other) => other is Box2DPhysicsSystem ? -1 : 0;  // before

@override
int compareTo(GameSystem other) => other is Box2DPhysicsSystem ? 1 : 0;   // after
```

## Performance

<!-- snippet: expr -->
```dart
Box2DPhysicsSystem(
  gravityY: -10,
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
transforms back, dispatching contacts — is thin: bulk entry points
turn what would be 2N FFI calls per tick into two, independent of body count.

The system exposes per-phase timings and body counts for a debug overlay. They
are development instrumentation, not a stable API, but they are how a
"physics is slow" report gets separated into "the arena is too small" and
"bodies are leaking" — two problems with nothing in common.

---

## Next

[Talking to Flutter →](flutter-bridge.md)
