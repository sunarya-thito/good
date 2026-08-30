## Unreleased

### Breaking

* **Components are reached by calling the receiver, not by `get`/`tryGet`.**
  `Entity.get`/`tryGet`, `QueryGroup.get`/`tryGet` and `Scene.get`/`tryGet` are
  removed in `good` 0.3.0-dev, and the type argument now says whether the
  component may be absent (#220). `entity.get<Transform3D>()` becomes
  `entity<Transform3D>().component`, `entity.tryGet<Transform3D>()` becomes
  `entity<Transform3D?>().component`, and `group.get<Transform3D>()` becomes
  `group<Transform3D>()`. `Transform3D`, `WorldTransform3D` and `Camera3D` are
  unchanged, and `entity<Transform3D>().setEuler(...)` reads as it did.

* **`cameraFar.defaultValue` is `cameraFar.initialValue`.** `DefaultPointer`
  is `InitialPointer` in `good` 0.3.0-dev and its accessor is renamed with it
  (#210). `Camera3D`'s columns do not move - names, order and widths are
  unchanged - but a prefab written as `cameraFieldOfView.defaultValue = 90`
  has one word to change.

* **`Camera3D` columns carry the component's name.** `near`, `far`,
  `fieldOfView` and `view` sat in the namespace every component on the entity
  shares, and `view` was the same name `goo2d`'s `Camera` declared (#133).

  | before | after |
  |---|---|
  | `Camera3D.fieldOfView` | `Camera3D.cameraFieldOfView` |
  | `Camera3D.near` | `Camera3D.cameraNear` |
  | `Camera3D.far` | `Camera3D.cameraFar` |
  | `Camera3D.view` | `Camera3D.cameraView` |

  `Transform3D` and `WorldTransform3D` already prefixed and do not move. Names
  only - column order, widths and `strideBytes` are unchanged. The rule is in
  `docs/reference/design-rules.md`.

### Fixed

* **A tick that destroys thousands of parented entities is linear in how many
  again.** `WorldTransform3DSystem` holds every entity spawned since the last
  fixed step, so it can compose those from what their spawner wrote rather
  than from a stale row, and it took a destroyed entity back out of that
  collection with a linear scan. So spawning and destroying N entities
  carrying `WorldTransform3D` inside one tick - an explosion clearing a
  squad, a level unloading - cost O(N^2). Measured over a 4x step in
  entities, from 16.0x to 4.1x. Nothing to do, and nothing about the composed
  transforms changes: the collection is a `Set` now, which iterates in the
  same spawn order it did as a `List`, and a scene with no `WorldTransform3D`
  in it never paid this and still does not (#181).

## 0.2.0

First published release, and it starts at 0.2.0 rather than 0.1.0 so the
engine packages carry one version between them - `good create --3d` writes a
single constraint for both dimensions, and a `goo3d` a minor behind it would
not resolve.

The first landing of the 3D engine, on the same
[`good`](https://pub.dev/packages/good) kernel `goo2d` uses:

* **`Transform3D`** — position, scale and a quaternion rotation, as ten
  decomposed columns. `setEuler`, `lookAt`, `yaw`/`pitch`/`roll` and the
  forward/right/up basis getters hang off `entity<Transform3D>()`, and none of
  them allocate.
* **`WorldTransform3D`** and **`WorldTransform3DSystem`** — parent composed
  into child once per fixed tick, top-down, with per-subtree change detection.
  Opt-in, so an entity that is never parented pays nothing for it.
* **`Camera3D`** — `fieldOfView`, `near`, `far` and `view`, stored as row
  defaults a prefab can move in its own `describeStruct`.
* **Audio assets load.** A 3D project could not load anything at all: `goo3d`
  named no payload type, so `good create --3d` typed every generated key
  `Object?`. `AudioClip` moved into the kernel, which this package re-exports,
  so a sound declared in a 3D game loads and its generated key is typed. It is
  bytes and a container name — nothing plays them yet.

Not here: **the renderer**. There are no meshes, materials, lights or draw
path, and nothing in this release stands in for them — which is also why
textures are the one asset kind a 3D project still cannot load. A texture is an
image behind a handle, and there is nothing here that could draw one.
