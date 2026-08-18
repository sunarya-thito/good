# Transforms and hierarchy (3D)

!!! abstract "Layer: 3D (`goo3d`)"
    `Child`/`Parent` come from the kernel and are shared with 2D. `Transform3D`
    and `WorldTransform3D` are this package.

A `Transform3D` is where a thing sits, how it is turned, and how big it is —
relative to its parent. A `WorldTransform3D` is the same three facts after every
ancestor has been applied.

```dart
class Crate extends EntityStruct with Transform3D, WorldTransform3D {}
```

## The columns

Transforms are stored decomposed, exactly as `goo2d` stores them: position,
scale and rotation as separate columns, never as a matrix. Composing on demand
is cheaper than keeping sixteen floats per entity up to date, and a system that
only wants a position reads one column instead of a matrix row.

| | Columns |
|---|---|
| Position | `transformOffsetX`, `transformOffsetY`, `transformOffsetZ` |
| Scale | `transformScaleX`, `transformScaleY`, `transformScaleZ` |
| Rotation | `transformRotationX`, `transformRotationY`, `transformRotationZ`, `transformRotationW` |

`WorldTransform3D` mirrors it: `worldX`/`worldY`/`worldZ`,
`worldScaleX`/`worldScaleY`/`worldScaleZ`, and `worldRotationX` through
`worldRotationW`.

```dart
crate.transformOffsetY[entity] += 2.0;
```

## Rotation is a quaternion

Four columns, not three Euler angles and not a matrix.

A quaternion is four numbers that describe an orientation. You do not need to
understand how it works to use one, and you will rarely read the four columns
directly — you set rotations through the helpers below and read them back the
same way.

The reason it is stored this way: the obvious alternative is three angles, one
per axis, which is easy to type and breaks when you combine them. Turn something
90° about one axis and two of the remaining axes line up, so one of your three
controls stops doing anything. That is called gimbal lock, and combining
rotations is exactly what a parent-child hierarchy does on every tick. The other
alternative, a matrix, avoids that but costs nine numbers to store and real work
to get a scale back out of. Four numbers that combine cleanly is the cheapest
thing that is also correct.

The two conversions a game actually wants are helpers, not storage:

```dart
transform.setEuler(entity, yaw: 0.5, pitch: 0.0, roll: 0.0);
transform.lookAt(entity, targetX, targetY, targetZ);
```

Both write the four rotation columns. Neither allocates.

!!! warning "Y is up here, and down in `goo2d`"
    `goo3d` is right-handed with **+Y up** and **-Z forward**, which is what glTF
    uses and therefore what anything exported from Blender expects.

    `goo2d` puts **+Y down**, because it works in screen space where that is the
    convention. The two are deliberately different and neither is going to
    change. A `goo2d` game that moves a sprite "up" subtracts; a `goo3d` game
    adds.

## The hierarchy is the kernel's

`Child` and `Parent` are not 3D types. They are the same components a 2D game
uses, from `good`, and they work here unchanged:

```dart
scene.parent(wheel, of: car);
```

`WorldTransform3DSystem` walks parents before children and writes the world
columns during the fixed tick, in the same phase and under the same rules as its
2D counterpart. Anything that reads a world transform must run after it commits.
See [Architecture](../architecture.md#the-fixed-tick).

Change detection is per subtree: an entity whose local transform did not move,
and whose ancestors did not move, is not recomposed.

## What this costs

Ten columns of `float64` per entity for the local transform and ten for the
world one. That is more than 2D's five and five, and it is still a flat native
row with no object per entity and nothing allocated per tick.

If a game has thousands of static props, declare them without `WorldTransform3D`
and read their local transform directly — an entity with no parent has nothing
to compose.
