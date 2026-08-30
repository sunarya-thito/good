## Unreleased

### Breaking

* **`bodyType.defaultValue` is `bodyType.initialValue`.** The accessor is
  renamed in `good` 0.3.0-dev, because the value is stamped into a fresh row
  rather than consulted on a read (#210). `RigidBody2D`'s columns do not
  move.

* **`RigidBody2D` finishes the prefix its first two columns already had.**
  `bodyHandle` and `bodyType` were prefixed; the other twelve were not, and
  `linearVelocityX`, `gravityScale` and `fixedRotation` are all plausible
  names for a column on somebody else's component. The stem is `body` rather
  than `rigidBody`, which would have produced `rigidBodyLinearVelocityX`
  (#133).

  | before | after |
  |---|---|
  | `linearVelocityX` | `bodyLinearVelocityX` |
  | `linearVelocityY` | `bodyLinearVelocityY` |
  | `angularVelocity` | `bodyAngularVelocity` |
  | `gravityScale` | `bodyGravityScale` |
  | `linearDamping` | `bodyLinearDamping` |
  | `angularDamping` | `bodyAngularDamping` |
  | `fixedRotation` | `bodyFixedRotation` |
  | `isBullet` | `bodyIsBullet` |
  | `syncedX` | `bodySyncedX` |
  | `syncedY` | `bodySyncedY` |
  | `syncedAngle` | `bodySyncedAngle` |
  | `syncedType` | `bodySyncedType` |

  `bodyHandle` and `bodyType` do not move. The four `synced*` columns are
  `@internal` and are listed for completeness. Names only - column order,
  widths and `strideBytes` are unchanged, and the rule is in
  `docs/reference/design-rules.md`.

* **This needs `goo2d` 0.3.0.** Beyond the renames above nothing here moves,
  but `goo2d` and `good` carry source breaks under their own `## Unreleased` -
  `SystemDescriptor.has` takes a constructor now, and `Box2DPhysicsSystem` is
  declared through it - so a project cannot take this and leave the engine
  where it was. The dependency reads `^0.3.0-dev` until 0.3.0 is published
  (#236).

### Changed

* **`Box2DPhysicsSystem` declares its two queries on their fields.** Both were
  `late final` assigned from a `describeQuery` override that the system no
  longer has; they are plain `final` built by `Query.where()` and `Query.all`
  (#226). Which entities each one matches is unchanged, and neither field is
  public.

### Fixed

* **A declared buoyancy effector floats what is inside it.** The dispatch in
  `Box2DPhysicsSystem` handed `Effectors2D.buoyancyEffector` the region's
  bottom edge as the water line, and that function hangs its fluid *below* the
  line it is given - so the water sat one full region height under the region
  it was declared on. A body inside the region free-fell through it, and a
  body beneath the region was shoved upward by water that was not there. The
  comment above the call said `+y is down in goo2d`, which is the opposite of
  what this engine does (#197).

* **The `Box2DPhysicsSystem` doc example declares the system with a
  constructor.** The one snippet on the class still handed an instance to
  `descriptor.has`, so it taught a call that no longer compiles. The README
  had already been corrected; this had not.

## 0.2.0

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

### Performance

* **A static body no longer has its transform read back from the solver.**
  Since the drift fix below, a static body's pulled transform was discarded on
  arrival, but the read still happened — one per static body per tick, thrown
  away. The transform pull now runs off its own handle array with the static
  rows zeroed, and the shim skips those. Velocities still come back for every
  body, static included, because a body turned static has to report zero.

  The cost was about 11 ns per static body per tick, so it scaled with level
  geometry and was worst on exactly the scenes that notice it least — a
  mostly-static tilemap. Measured against the raw shim, AOT-compiled, on a
  scene of 500 dynamic bodies dropped onto a row of statics:

  | static bodies | transform pull, before | after | saved per tick |
  | --- | --- | --- | --- |
  | 1,000 | 14.2 µs | 4.7 µs | 9.5 µs |
  | 5,000 | 58.8 µs | 5.4 µs | 53.4 µs |
  | 20,000 | 243.2 µs | 8.9 µs | 234.3 µs |

  At 20,000 statics that is 1.4% of a whole 60 Hz frame, and roughly half the
  native part of a physics tick. `tool/static_pull_bench.dart` is the
  measurement, including the control case that shows what no difference looks
  like.

### Fixed

* **Static and kinematic bodies no longer drift toward multiples of π/4.** A
  non-dynamic body pushed its transform every tick and read Box2D's reading of
  it back, and that round trip has an error that converges there. A floor
  authored at 0.3 rad reached 0.785 in ten thousand ticks — 17 degrees to 41 in
  sixteen seconds. Static bodies no longer write back at all, and both kinds
  push only when gameplay wrote the value. The comparison has a threshold —
  `1e-4` units of position, `5e-3` radians of angle — so a static body scripted
  in smaller increments than that now moves in steps instead of continuously.
  It ends up where you told it. `docs/guide/physics.md` says which body type a
  moving platform wants and why; the short answer is kinematic, which is driven
  by velocity and never meets the threshold at all.
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
