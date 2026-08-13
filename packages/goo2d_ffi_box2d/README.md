# goo2d_ffi_box2d

Raw `ffigen` bindings to Box2D v3's C API, plus prebuilt per-platform
binaries (Windows/macOS/Linux/Android/iOS). Kept separate from
[`goo2d_physics_box2d`](../goo2d_physics_box2d)'s ECS-facing API so the
generated bindings can be regenerated independently.

Targets Box2D **v3**: it exposes contacts/sensors as flat event arrays you
poll each step, instead of v2's callback-based collision handling - a much
better fit for this engine's FFI-in-isolate, no-heap-allocation-on-hot-path
model.

Status: **placeholder.** This is Phase 2 of the project root plan; nothing
here is implemented yet.
