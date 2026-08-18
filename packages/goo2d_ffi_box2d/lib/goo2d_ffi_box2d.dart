/// Vendored Box2D v3.1.1 behind a flat, primitives-only C shim.
///
/// **Not meant to be used directly by game code** - see
/// `goo2d_physics_box2d` for the ECS-facing API (`RigidBody2D`,
/// `Box2DPhysicsSystem`) built on top of this.
///
/// Box2D **v3** specifically, not v2, because v3 exposes contacts and
/// sensors as flat event arrays polled once per step
/// (`b2World_GetContactEvents`/`GetSensorEvents`) rather than through
/// callbacks. Polling suits an FFI boundary; callbacks would mean a C
/// function pointer calling back into Dart on the hot path, which is both
/// slow and awkward to get right across isolates.
///
/// ## Why a shim rather than binding Box2D directly
///
/// Box2D's C API passes small structs by value - `b2Vec2`, `b2BodyId`,
/// `b2Transform`, `b2WorldDef`. ffigen maps each of those to a Dart
/// `Struct`, which is a heap object, so a direct binding would allocate on
/// every call on the engine's hottest path. This codebase has already
/// measured that class of cost once and removed it (a `Pointer` held in a
/// field cost 14.63 ns per access against 2.25 ns for a plain `int`), and
/// the no-allocation rule forbids reintroducing it.
///
/// So `src/goo_box2d.h` exposes only `int64_t`, `int32_t`, `uint64_t`,
/// `float`, and pointers to arrays of those. The generated bindings contain
/// **no** `Struct` subclasses at all, which is the property worth
/// protecting if this header is ever extended.
///
/// The shim also carries the bulk entry points
/// (`gooBodiesPushTransforms`/`gooBodiesPullTransforms`), which turn what
/// would be 2N FFI calls per tick into two, independent of body count.
///
/// ## Building
///
/// There are no prebuilt binaries in this repository. Windows, Linux and
/// Android compile `src/CMakeLists.txt` through their own thin wrapper;
/// macOS and iOS compile the same sources through CocoaPods. A Flutter app
/// gets all of this automatically.
///
/// Outside an app - `flutter test`, `dart run`, `tool/` scripts - nothing
/// builds plugins, so the library must be built once by hand:
///
/// ```
/// cd packages/goo2d_ffi_box2d && powershell -File tool/build_native.ps1
/// ```
library;

export 'src/box2d.g.dart' show Box2DBindings;
export 'src/library.dart' show box2d, nativeLibraryPathOverride;
