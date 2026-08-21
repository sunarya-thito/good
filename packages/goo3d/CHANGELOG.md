## 0.1.0

Unreleased. The first landing of the 3D engine, on the same
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
