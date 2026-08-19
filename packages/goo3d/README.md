# goo3d

Game Overdrive On 3D. The 3D half of the [good](https://pub.dev/packages/good)
engine: transforms, hierarchy and the camera, on the same kernel `goo2d` runs
on.

**There is no renderer yet, and this package does not pretend otherwise.**
Meshes, materials, lights and the draw path are not written. What is here is
everything underneath them, which is maths and columns and needs no GPU.

## What a prefab looks like

An entity kind is a struct of columns, and `[entity]` indexes a row in one:

```dart
import 'package:goo3d/goo3d.dart';

class Crate extends EntityStruct with Transform3D, WorldTransform3D, Child {}
```

```dart
crate.transformOffsetY[entity] += 2.0;             // +Y is up

entity<Transform3D>().setEuler(yaw: 0.5);          // radians, about +Y
entity<Transform3D>().lookAt(0, 0, 0);             // points its -Z at a point
final aim = entity<Transform3D>().forwardX;
```

Columns are read and written through the prefab; everything you *do* with them
hangs off `entity<Transform3D>()`, a view of the entity that costs nothing -
it erases to the entity handle, which erases to an `int`.

Position, scale and rotation are separate columns - never a matrix. Rotation is
a quaternion in four of them, so combining a parent's turn with a child's does
not gimbal-lock, and nothing asks you to type one: `setEuler` and `lookAt`
write the four columns, and `yaw`/`pitch`/`roll` and the
`forward`/`right`/`up` getters read them back.

## The hierarchy

`Child` and `Parent` come from the kernel and are shared with 2D:

```dart
scene.parent(wheel, of: car);
```

`WorldTransform3DSystem` walks parents before children once per fixed tick and
writes `worldX`/`worldY`/`worldZ`, the world quaternion and the world scale.
Anything reading those must be ordered after it, or it reads last tick's
answer.

`WorldTransform3D` is opt-in. An entity that is never parented has world equal
to local by construction, and declaring it without the world columns means the
composition pass never touches it.

## Which way is up

Right-handed, **+Y up**, **-Z forward** - what glTF uses, so a mesh exported
from Blender arrives oriented correctly. `goo2d` puts +Y up too, so a system
that moves something upward moves it upward in either dimension.

## Status

Not on pub.dev yet. The renderer is tracked as its own issue, and this package
lands there before it is published.
