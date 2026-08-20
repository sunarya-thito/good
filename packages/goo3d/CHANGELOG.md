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

Not here: **the renderer**. There are no meshes, materials, lights or draw
path, and nothing in this release stands in for them.
