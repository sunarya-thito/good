# goo2d_physics_box2d

ECS-facing Box2D physics for [`goo2d`](https://pub.dev/packages/goo2d): `RigidBody2D`/`Collider2D`
mixins and `Box2DPhysicsSystem`, built on
[`goo2d_ffi_box2d`](https://pub.dev/packages/goo2d_ffi_box2d)'s raw bindings. Steps the Box2D
world inside the game isolate, in lockstep with `good`'s fixed-tick
scheduler, and writes results back into `Transform2D`.

Status: **working.** Bodies, colliders, all nine joints, effectors, and
raycast and overlap queries, with the solver running across worker threads.
The [implementation status page](https://sunarya-thito.github.io/good/reference/roadmap/) lists what works today.
