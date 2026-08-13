/// Raw ffigen bindings to Box2D v3's C API. Not meant to be used directly
/// by game code - see `goo2d_physics_box2d` for the ECS-facing API
/// (RigidBody2D/Collider2D/Box2DPhysicsSystem) built on top of these
/// bindings.
///
/// Box2D v3 specifically (not v2) because it exposes contacts/sensors as
/// flat event arrays you poll each step (b2World_GetContactEvents /
/// GetSensorEvents) instead of callback-based collision handling - a much
/// better fit for the FFI-in-isolate, no-heap-allocation-on-hot-path model
/// than v2's callback interface.
///
/// Placeholder - generated bindings and prebuilt per-platform binaries land
/// in Phase 2 of the project root plan. This will likely become a Flutter
/// FFI plugin package (native platform folders for binary bundling), not a
/// pure Dart package, once that lands.
library;
