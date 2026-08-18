# Rendering and cameras (3D)

!!! abstract "Layer: 3D (`goo3d`)"
    The renderer is a backend behind a contract, so a `goo3d` game does not name
    one directly.

Rendering is the step that turns "what exists" into "what you see". Your game
never calls a draw function: it declares that an entity is visible and what it
looks like, and the renderer walks those declarations once a frame.

That is the same arrangement `goo2d` uses, for the same reason — a game that
draws things itself has to be told *when*, and the answer changes depending on
what else is running.

## Making something visible

```dart
class Crate extends EntityStruct
    with Transform3D, WorldTransform3D, Renderable3D {
  late final MeshAsset mesh;
  late final MaterialAsset material;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    mesh = descriptor.has(Meshes.crate);
    material = descriptor.has(Materials.woodCrate);
  }

  @override
  void describeMesh(MeshDescriptor descriptor) {
    super.describeMesh(descriptor);
    descriptor.has(mesh: mesh, material: material);
  }
}
```

`Meshes` and `Materials` are generated enums, the same way `Textures` is in 2D:
`good generate` scans the assets your pubspec declares and writes one entry per
file, so a renamed asset is a compile error instead of a blank object at run
time.

## The camera

A camera is an entity, not a global. It has a transform like anything else, so
parenting it to something is how a follow camera works — there is no separate
"camera controller" concept to learn.

```dart
class Eye extends EntityStruct with Transform3D, WorldTransform3D, Camera3D {
  @override
  void describeCamera(Camera3DDescriptor descriptor) {
    super.describeCamera(descriptor);
    descriptor.has(fieldOfView: 60, near: 0.1, far: 1000);
  }
}
```

`fieldOfView` is in degrees, vertical. `near` and `far` bound what is drawn:
anything closer than `near` or further than `far` is skipped.

!!! warning "One camera per view"
    Same rule as 2D. More than one enabled camera on a view trips a debug
    assert; in release the first one found is used.

## What the renderer does each frame

1. Walk the entities that are visible and inside the camera's view.
2. Sort them — by material first, so the backend can draw everything sharing a
   material together, then by depth.
3. Write the result into a shared buffer the Flutter isolate reads.

Steps two and three are where 3D differs from 2D in kind rather than degree. In
2D everything is a textured rectangle, so the whole frame is one draw call. In
3D each distinct material is its own draw call, which is why grouping by
material comes before grouping by distance.

## Backends

`goo3d` defines the contract; a backend implements it. That is the same shape as
[`good_net`](../../packages/networking.md), where the transport is a contract and
a package like `good_net_p2p` implements it.

Two exist:

| Backend | Use it when |
|---|---|
| Flutter GPU | You want no native build step and are happy on the platforms Impeller supports |
| Native (FFI) | You need full control of the pipeline, and can accept a per-platform native build |

A game picks one by depending on it and declaring it, and nothing else in the
game changes:

```dart
descriptor.renderer(FlutterGpuRenderer());
```

!!! warning "No web target"
    Neither backend runs on the web, and neither does the kernel — it needs
    `dart:ffi` and isolates. See
    [the implementation status page](../../reference/roadmap.md).

## Lighting

Lights are entities too, declared the same way:

```dart
class Sun extends EntityStruct with Transform3D, WorldTransform3D, Light3D {
  @override
  void describeLight(LightDescriptor descriptor) {
    super.describeLight(descriptor);
    descriptor.directional(intensity: 3.0, colour: 0xFFFFF4E5);
  }
}
```

Directional, point and spot are the three kinds. A light has a transform, so a
torch is a light parented to the hand that carries it.
