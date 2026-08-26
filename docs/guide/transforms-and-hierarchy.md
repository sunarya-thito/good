# Transforms and hierarchy

<!-- snippet-scope
import 'dart:math' as math;

late Transform2D transform;
late Parent parent;
late Turret turret;
late Eye eye;
late MyGame game;
late Entity a;
late Entity b;
late EntityStruct bodyPrefab;
late EntityStruct limbPrefab;
late EntityStruct playerPrefab;
late EntityStruct eyePrefab;
double targetX = 0, targetY = 0;
-->

!!! abstract "Layer: `Child`/`Parent` are kernel; `Transform2D`/`WorldTransform2D` are `goo2d`"

## `Transform2D`

Five columns — position, scale, rotation:

```dart
class Player extends EntityStruct with Transform2D {
  // transformOffsetX, transformOffsetY  (float64, default 0)
  // transformScaleX,  transformScaleY   (float64, default 1)
  // transformRotation                   (float64, radians, default 0)
}
```

```dart
transform
  ..transformOffsetX[entity] = 100
  ..transformOffsetY[entity] = -40
  ..transformRotation[entity] = math.pi / 4
  ..transformScaleX[entity] = 2
  ..transformScaleY[entity] = 2;
```

!!! note "Positive Y is **up**"
    A larger `transformOffsetY` draws *higher* on the screen, and a floor sits
    at a *smaller* y than the things falling onto it. Box2D's own examples and
    `goo3d` agree, so gravity is `(0, -10)` here as it is everywhere else.

    Flutter's canvas is y-down, but that is the camera's problem, not yours:
    `CameraProjection` is the one place the sign is turned round, and
    everything that maps between world and screen — drawing, pointer picking,
    world-space HUD markers — goes through it.

    Positive rotation is therefore **counter-clockwise**, the direction
    `atan2`, `sin` and `cos` already assume.

Scale defaults to `1` instead of to the field's own `0`, because a zero scale
collapses every point to the origin — an entity that simply never assigned a
scale would be invisible with nothing anywhere saying why.

### Helpers

`Transform2D` carries Unity-`Transform`-style helpers that operate on **local**
values:

```dart
final d = transform.distanceTo(a, b);   // local-space distance
transform.lookAt(entity, targetX, targetY);
```

Each resolves every `Entity` argument's own `Transform2D` fresh, instead of
reading through the receiver — a second entity may belong to a different
archetype with a different row layout entirely, and reading it through the wrong
one would silently address the wrong storage.

For world-space equivalents, use `WorldTransform2D`'s fields.

## The hierarchy

`Child` and `Parent` are kernel components. `Child` links an entity to its
parent; `Parent` marks an entity that can own children.

```dart
class Body() extends EntityStruct with Transform2D, WorldTransform2D, Child, Parent;
class Limb() extends EntityStruct with Transform2D, WorldTransform2D, Child;
```

Spawn into the hierarchy directly:

```dart
final body = scene.addEntity(bodyPrefab, parent: hubEntity);
for (var i = 0; i < 3; i++) {
  scene.addEntity(limbPrefab, parent: body);
}
```

Or link afterwards. Each operation is on the entity it is about:

```dart
parentEntity<Parent>().addChild(childEntity);   // childEntity must be unparented
parentEntity<Parent>().adopt(childEntity);      // move it here from wherever it is
parentEntity<Parent>().removeChild(childEntity);// destroys it and its subtree
childEntity<Child>().detach();                  // unlink, keep it alive as a root
```

`removeChild` destroys. Reach for `detach` when the entity has to outlive its
parent, and for `adopt` when it is moving — remove-then-add no longer means
reparent.

A link that would close a loop is refused where it is made: `addChild` and
`adopt` walk up from the prospective parent, and throw if they reach the child.

`Child` holds `parent`, `nextSibling` and `prevSibling`; `Parent` holds
`firstChild` and `lastChild`. They are readable columns like any other, so
walking a subtree by hand is an ordinary loop:

```dart
var next = parent.firstChild[entity];
while (next != null) {
  // ...
  next = next.get<Child>().nextSibling[next];
}
```

`entity.destroy()` destroys the **whole subtree**. One call on a body takes its
limbs with it.

## Children a prefab always has

A turret that is a base plus a barrel is a fact about the turret, not about
whoever spawns it. `EntityStruct.of` says so in the prefab:

```dart
class Barrel extends EntityStruct with Transform2D, WorldTransform2D, Child;

class Turret extends EntityStruct with Transform2D, WorldTransform2D, Parent {
  final barrel = EntityStruct.of(Barrel.new);
}
```

Spawning a `Turret` spawns a `Barrel`, links it under the turret, and destroying
the turret takes it with it. Declarations nest, so a `Barrel` with children of
its own gets them too.

The field holds the child's **prefab**, which is one object for the whole
archetype — the same thing `descriptor.has(Turret.new)` hands a scene. Which
barrel belongs to which turret is per-entity state, so it lives in a column, and
the parent is what you ask:

```dart
final barrelEntity = turretEntity<Parent>()[turret.barrel];
```

`Barrel.new` and not `<Barrel>()`, for the same reason `descriptor.has` takes a
constructor: the child's own field initialisers declare columns, so a descriptor
has to be open before the object exists. A constructor with arguments goes in a
closure, `EntityStruct.of(() => Barrel(bore: 5))`.

The declarer must mix in `Parent` and the declared type must mix in `Child`.
Both are reported when the scene registers, along with a struct that declares
itself — which would spawn forever.

## `WorldTransform2D`

Mix it in and `WorldTransformSystem` composes a world-space transform for the
entity from its own local transform and its ancestors':

```dart
final world = entity.get<WorldTransform2D>();
final x = world.worldX[entity];    // composed, read-only
final y = world.worldY[entity];
```

The renderer and the camera read world transforms, so anything that draws or
sees needs this component.

!!! info "This is the whole point of the hierarchy"
    A limb's own `Transform2D` is a *constant* local offset, written once at
    spawn and never touched again. Everything you see it do — orbiting its
    body, travelling with it, swinging as the body turns — is
    `WorldTransformSystem` composing that constant against its ancestors. No
    system writes a limb after it is created.

    Rotating one hub entity moves an entire swarm, and the only line of code
    that runs is the one writing the hub's rotation.

## Phase ordering

`WorldTransformSystem` reads local transforms and writes world ones, so a system
that writes local transforms must run **before** it:

```dart
class MovementSystem extends GameSystem with FixedTickable {
  @override
  int compareTo(GameSystem other) => other is WorldTransformSystem ? -1 : 0;
}
```

Declaring it the other way round shows every entity one frame behind its own
parent. Consumers of world transforms — the renderer, picking — run after the
fixed tick has committed, which is the same discipline Unity's
`PresentationSystemGroup`-after-`SimulationSystemGroup` split enforces.

## Building a scene graph

```dart
class Hub() extends EntityStruct with Transform2D, WorldTransform2D, Parent;

class Critter() extends EntityStruct
    with Transform2D, WorldTransform2D, Child, Parent, Renderable2D;

class Limb() extends EntityStruct
    with Transform2D, WorldTransform2D, Child, Renderable2D;
```

`Child` because it hangs off something, `Parent` because it owns something,
`WorldTransform2D` because its children need a composed transform to compose
against. That full set is what a scene graph costs.

!!! danger "Several children in one tick"
    `addChild` reads the tail of the child chain to append to it. An ordinary
    read returns the last **published** snapshot, so three `addChild` calls in
    one tick would each read the same stale tail and orphan all but the last.

    The hierarchy handles this internally by reading the pending slot, and a
    prefab declaring three children with `EntityStruct.of` is that case every
    time. If you build a linked structure across component rows yourself,
    expect the same problem — and fix it by placement (a later phase), not by
    inventing a second read path.

## Camera following

A camera is an entity with `Transform2D`, `WorldTransform2D` and `Camera`, so
"the camera follows the player" is just parenting:

<!-- snippet: plain -->
```dart
final player = scene.addEntity(playerPrefab);
final camera = scene.addEntity(eyePrefab, parent: player);
eye.view[camera] = game.defaultCamera;
```

The camera's own local transform stays at the origin, and `WorldTransformSystem`
puts it wherever the player is. For a lagging or smoothed camera, write its
transform from a system that runs after movement instead.

The rotation does not carry over. A turning player swings a camera hung at an
offset around itself, because that is the *position* composing, but the
`worldRotation` the camera picks up is read by nothing and the view never
tilts — see the warning in [Rendering and cameras](rendering.md#cameras).

---

## Next

[Rendering and cameras →](rendering.md)
