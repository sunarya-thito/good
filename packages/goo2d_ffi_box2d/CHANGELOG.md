## 0.1.1

Documentation only. No code changes.

README links now resolve on pub.dev.

## 0.1.0

First published release. Raw FFI bindings to Box2D:

* **Box2D v3.1.1 vendored** (MIT, © Erin Catto — see `src/box2d/LICENSE`)
  behind a flat C shim.
* Bindings generated over that shim, and a worker-thread pool so the solver can
  run across cores.
* Builds on Windows, Linux, Android, macOS and iOS.

This is the raw binding layer. Use
[`goo2d_physics_box2d`](https://pub.dev/packages/goo2d_physics_box2d) for the
ECS-facing API; depending on this package directly means managing worlds and
bodies by hand.

## 0.0.1

* Package scaffolded, no bindings generated. Never published.
