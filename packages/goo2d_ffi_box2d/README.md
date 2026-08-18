# goo2d_ffi_box2d

Vendored [Box2D](https://github.com/erincatto/box2d) **v3.1.1** behind a flat,
primitives-only C shim, plus the ffigen bindings to it.

Not meant to be used directly by game code — see
[`goo2d_physics_box2d`](https://pub.dev/packages/goo2d_physics_box2d) for the ECS-facing API
(`RigidBody2D`, `Box2DPhysicsSystem`).

## Why a shim instead of binding Box2D directly

Box2D's C API passes small structs by value (`b2Vec2`, `b2BodyId`,
`b2Transform`, `b2WorldDef`). ffigen maps each of those to a Dart `Struct`,
which is a heap object — so a direct binding would allocate on every call, on
the engine's hottest path. That is the cost this codebase already measured and
removed once (a `Pointer` held in a field: 14.63 ns/access vs 2.25 ns for a
plain `int`), and the no-allocation hot-path rule (https://sunarya-thito.github.io/good/reference/rules/) forbids reintroducing it.

`src/goo_box2d.h` therefore exposes only `int64_t`, `int32_t`, `uint64_t`,
`float`, and pointers to arrays of those. **The generated bindings contain no
`Struct` subclasses at all** — the property worth protecting if the header is
extended.

The shim also carries bulk entry points (`gooBodiesPushTransforms` /
`gooBodiesPullTransforms`), turning what would be 2N FFI calls per tick into
two, independent of body count.

Handles are packed by Box2D's *own* `b2StoreBodyId`/`b2LoadBodyId` helpers
(`id.h`) instead of by arithmetic written here, so the packing is stated in
exactly one place. Zero is the null handle, which is Box2D's convention too —
so a `hasInt64` component field defaulting to 0 already means "no body yet".

## Building

There are no prebuilt binaries in this repository. Each platform compiles the
vendored source itself:

| Platform | Route |
|---|---|
| Windows, Linux | `<platform>/CMakeLists.txt` → `src/CMakeLists.txt` |
| Android | `android/build.gradle` → NDK CMake → `src/CMakeLists.txt` |
| macOS, iOS | CocoaPods podspec (compiles sources directly, links statically) |

A Flutter app gets all of this automatically. Outside one — `flutter test`,
`dart run`, `tool/` scripts — nothing builds plugins, so build it once by hand:

```powershell
cd packages/goo2d_ffi_box2d
powershell -File tool/build_native.ps1
```

`lib/src/library.dart` finds that artifact by walking up from the working
directory, so tests in sibling packages pick it up without configuration.

## Regenerating the bindings

Requires libclang (LLVM), which is only needed to *regenerate* —
`lib/src/box2d.g.dart` is checked in.

```powershell
winget install --source winget LLVM.LLVM
cd packages/goo2d_ffi_box2d
dart run ffigen --config ffigen.yaml
```

## Two Box2D behaviours worth knowing before building on this

Both are measured, both are pinned by tests in `test/shim_test.dart`:

1. **`b2MakeRot` does not call libm.** It uses Bhaskara-style rational
   approximations (`b2ComputeCosSin`, `src/box2d/src/math_functions.c:107`), so
   an angle → `b2Rot` → angle round trip is lossy. Worst case measured across
   20 000 angles: **1.658e-3 rad**.
2. **That error is not zero-mean noise — it has attractors.** Feeding a pulled
   angle back in converges towards multiples of π/4: starting at 0.30 rad and
   round-tripping 10 000 times lands on 0.785 (π/4), a drift of about 27°.
   Consequently a pulled transform must **never** be pushed back. Authority is
   per body type — Dart owns static and kinematic bodies, Box2D owns dynamic
   ones.

## Threading

Box2D creates no threads of its own — it calls `enqueueTask`/`finishTask` and
expects a worker index back. `src/goo_threads.c` is the pool that backs those,
reached through `gooWorldCreateThreaded(gx, gy, workerCount)`.
`gooWorldCreate` is unchanged and creates no threads, so threading is entirely
opt-in.

Measured on a dense 5000-body stack (`goo2d_physics_box2d/tool/physics_bench.dart`,
AOT, 8 physical cores):

| workers | step | speedup |
|---|---|---|
| 1 | 5347.9 µs | 1.00× |
| 2 | 3943.3 µs | 1.45× |
| 4 | 2461.6 µs | 2.32× |
| 8 | 1969.4 µs | 2.90× |

**The contract that invalidates the obvious implementation.** `solver.c`
enqueues *all* `workerCount` solver tasks and only afterwards finishes them,
and those tasks synchronise at barriers inside the solver. So `enqueueTask`
must return **without running any work inline** — the usual parallel-for
shape, where the caller runs the last slice itself, blocks at a barrier
waiting for peers that have not been dispatched yet. That is a deadlock, not
a slowdown. Consequently the pool holds a thread *per* worker rather than
`workerCount - 1`, and hands work only to threads it has already claimed as
idle.

`workerIndex` is carried in Box2D's own `workerContext`, not taken from the
argument the pool passes, so the index only has to be in range.

Box2D's own guidance: only performance cores help, and "efficiency cores and
hyper-threading provide little benefit and may even harm performance". More
workers than physical cores usually costs time.

## Diagnostics

`gooWorldAwakeBodyCount` and `gooWorldCounters` exist because a step time on
its own cannot tell a heavy scene from an agitated one, and those have
completely different fixes. A sleeping body costs Box2D almost nothing, so
"4000 bodies, 40 awake" and "4000 bodies, 4000 awake" are different worlds
that report the same population.

`gooWorldCounters` flattens `b2Counters` into a caller's `int32` array instead
of returning it — `b2Counters` is a struct by value, which is the one thing this
shim exists to keep out of the generated bindings.

## Licence

Box2D is MIT, © Erin Catto — see `src/box2d/LICENSE`. The vendored tree is
upstream's `include/` and `src/` unmodified, at commit `8c66146` (tag
`v3.1.1`); `extern/` (glad, jsmn) is samples-only and is not vendored.
