# Physics (3D)

!!! abstract "Layer: opt-in — a `goo3d` physics backend"
    Physics is not part of `goo3d`. Add a backend package when you want it.

Physics is what makes things fall, collide and get pushed around without you
writing any of that yourself. You declare that an entity has a body and a shape;
the physics system moves it, and writes the result back into its transform.

If you have never used a physics engine: the two ideas are a **body**, which is
the thing that moves and has mass, and a **collider**, which is the shape used
to work out what it hits. They are separate because they are often different —
a character is one body with a simple capsule collider, not a body shaped like a
person.

## A falling crate

```dart
class Crate extends EntityStruct
    with Transform3D, WorldTransform3D, Renderable3D, Collider3D, RigidBody3D {
  late final BoxBody3D box;

  @override
  void describeCollider(Collider3DDescriptor descriptor) {
    super.describeCollider(descriptor);
    box = descriptor.hasBoxCollider(
      halfWidth: 0.5, halfHeight: 0.5, halfDepth: 0.5, friction: 0.4,
    );
  }

  @override
  void describeRigidBody(RigidBody3DDescriptor descriptor) {
    descriptor.has(type: BodyType3D.dynamicBody);
  }
}
```

Then declare the system once, and that is the whole opt-in:

```dart
@override
void describeSystems(SystemDescriptor descriptor) {
  super.describeSystems(descriptor);
  descriptor.has(Physics3DSystem(gravityY: -9.81));
}
```

Bodies appear as entities spawn and go away as they despawn. The system listens
for that rather than needing to be told.

!!! warning "Gravity is negative"
    The world is Y-up, so gravity pulls along **negative** Y. `-9.81` is earth
    gravity in metres per second squared; a positive value makes things fall
    upwards, which is a fun bug to find at the wrong moment.

## Body types

| Type | Moves | Affected by forces | Use for |
|---|---|---|---|
| `staticBody` | no | no | Ground, walls, anything fixed |
| `kinematicBody` | yes, by you | no | Lifts, moving platforms, doors |
| `dynamicBody` | yes, by the solver | yes | Crates, debris, ragdolls |

The type is a column, so a platform can become dynamic when it breaks without
anything being rebuilt:

```dart
body.bodyType[entity] = BodyType3D.dynamicBody.index;
```

## Pushing things

```dart
final body = entity.get<RigidBody3D>();
body.applyImpulse(entity, 0, 5, 0);
body.setVelocity(entity, 3, 0, 0);
```

## Shapes

Box, sphere, capsule and convex hull cover nearly everything that moves.
**Triangle meshes** are for terrain and level geometry and can only be static —
a mesh cannot be a dynamic body, in any engine, because there is no cheap way to
work out how a concave shape should tumble.

```dart
ground = descriptor.hasMeshCollider(Meshes.terrain);
```

## Queries

Asking "what is in front of the player" is a raycast: a line through the world
that reports the first thing it meets.

```dart
final RaycastResult result = RaycastResult();   // kept in a field, reused

physics.raycast(result, originX, originY, originZ, dirX, dirY, dirZ, distance);
if (result.hit) {
  // result.entity, result.x/y/z, result.normalX/Y/Z, result.distance
}
```

The result object is yours and you reuse it. That keeps the per-frame path free
of allocation, and it means two systems can each hold their own result without
interfering.

!!! warning "Work in metres, kilograms and seconds"
    Physics engines are tuned for objects roughly 0.1 m to 10 m. Treating one
    world unit as one centimetre gives a crate the mass and inertia of a
    building — still simulated, visibly wrong, and usually reported as "the
    physics feels floaty". Apply any scale once, at the rendering edge.

## Backends

Like the renderer, physics is a contract with backends behind it, so the code
above does not name an engine. See
[2D and 3D](../../packages/2d-and-3d.md) for which ones exist and what each is
good at.
