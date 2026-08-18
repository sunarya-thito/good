# goo2d_physics_box2d

ECS-facing Box2D physics for [`goo2d`](../goo2d): `RigidBody2D`/`Collider2D`
mixins and `Box2DPhysicsSystem`, built on
[`goo2d_ffi_box2d`](../goo2d_ffi_box2d)'s raw bindings. Steps the Box2D
world inside the game isolate, in lockstep with `good`'s fixed-tick
scheduler, and writes results back into `Transform2D`.

Status: **placeholder.** This is Phase 2 of the project root plan; nothing
here is implemented yet.
