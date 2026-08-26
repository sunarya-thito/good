## Unreleased

Documentation and build tooling. No code changes.

* `ffigen.yaml`'s function filter matched none of the shim's 60 symbols, so
  `dart run ffigen --config ffigen.yaml` emptied `lib/src/box2d.g.dart` instead
  of regenerating it. The checked-in bindings were always correct; regenerating
  from them was not.
* `gooJointCreateMouse` now documents the anchor-ordering trap and its
  measurement. That section was in the C header and had never reached the
  generated file, so it was absent from the published API docs.
* `gooShapeEnableContactEvents` and `gooShapeEnableSensorEvents` say what the
  flags do and how contacts and sensors differ, in place of a reference to a
  plan that no longer exists.
* No comment names `RULES.md`, which is not in the repository. The two rules
  cited were the no-allocation hot-path rule and one fact, one place, both on
  the docs site.

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
