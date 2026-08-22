## Unreleased

### Breaking

* **One Box2D world per loaded scene, and the queries name the scene.**
  `raycast` and `overlapBox` take a `Scene` as their first argument, as do the
  four `Effectors2D` functions (`areaEffector`, `pointEffector`,
  `buoyancyEffector`, `surfaceEffector`). Pass the handle `loadScene` returned;
  a game with one scene passes the one it has. There is deliberately no default
  and no fallback to "the one loaded scene" - that shape works for months and
  then queries the wrong world the day a HUD scene loads, which is why
  `getScene` became `singleScene` in the kernel.

  Before this, every loaded scene shared one world: a dynamic body in one scene
  came to rest on static geometry in another, one `overlapBox` returned shapes
  from two scenes interleaved, and `layerMask` was the only way to tell them
  apart - a budget that exists for something else. A scene is this engine's
  isolation boundary everywhere else, so physics was the subsystem catching up.

  Two more consequences. A joint between bodies in different scenes is refused
  with an `ArgumentError` naming both slots, because they have no solver in
  common and Box2D has no defined behaviour for it. And unloading a scene
  destroys its world outright, taking every body and joint in it, so nothing
  survives an unload that used to.

  `Box2DPhysicsSystem.world` is gone; `worldOf(scene)` replaces it.
  `awakeBodyCount` and `counters` sum across loaded scenes, which reads the
  same as before for a game with one.

* **`+y` is up, following `goo2d`.** Gravity defaults to `-10`, the wheel
  joint's axis to `(0, -1)`, and buoyancy searches below the waterline. A world
  that set any of these itself needs the sign checked.
* **A polygon collider takes its points**, and the eight-vertex cap now lives
  here — Box2D's solver is what the limit was ever about.

### Fixed

* **Static and kinematic bodies no longer drift toward multiples of π/4.** A
  non-dynamic body pushed its transform every tick and read Box2D's reading of
  it back, and that round trip has an error that converges there. A floor
  authored at 0.3 rad reached 0.785 in ten thousand ticks — 17 degrees to 41 in
  sixteen seconds. Static bodies no longer write back at all, and both kinds
  push only when gameplay wrote the value.
* **Changing `bodyType` on a live body is applied.** It was documented as
  working and moved only the column, so the solver went on treating the body as
  whatever it was created as.

## 0.1.1

Documentation only. No code changes.

The README now shows a declared collider and effector. The library docs
described the superseded effector API, where you wrote your own system and a
`compareTo` to order it before the solver; declaring `Effector2D` is the
current shape and the physics system handles the ordering.

## 0.1.0

First published release. The ECS-facing 2D physics layer:

* **Bodies and colliders**, declared as components.
* **All nine joints** — distance, motor, mouse, prismatic, revolute, weld,
  wheel and the rest of Unity's 2D set — with `Joint` as a real type, not a
  raw handle.
* **Effectors**, declared alongside the colliders they act on.
* **Raycast and overlap queries.**
* The solver runs across worker threads; the thread count is set on the `Game`.

## 0.0.1

* Package scaffolded. Never published.
