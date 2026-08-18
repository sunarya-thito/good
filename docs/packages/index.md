# The goo family

goo is a monorepo of packages that divide along one line: **is this about how
many dimensions you have, or not?**

Everything that is not — the ECS, the scheduler, scenes, hierarchy, input, the
asset registry, the isolate bootstrap, networking, the CLI — lives in the
dimension-agnostic half and is shared. Only rendering, transforms and the
physics binding are per-dimension.

```
packages/
├── goo                     the kernel — no dimension anywhere in it
├── goo_cli                 the `goo` command
├── goo_net                 declared messages + the transport contract
│   └── goo_net_p2p         serverless P2P backend
│
├── goo2d                   the 2D engine
├── goo2d_physics_box2d     ├── Box2D physics for it
└── goo2d_ffi_box2d         └── vendored Box2D + C shim + bindings
```

A future `goo3d` and its siblings slot in beside `goo2d` — the split exists
specifically so that costs nothing above it. See
[Dimensions](dimensions.md).

!!! tip "What a game depends on"
    **One package.** `goo2d` re-exports the kernel, so a 2D game has one
    dependency and one import. Physics and networking are added explicitly,
    because each carries weight not every game wants.

---

## goo

The kernel. Dimension-agnostic, and the largest package in the repository.

- **ECS** — bit-packed component storage, archetype registration, `Entity`
  handles, and a `QueryBuilder` whose `withAll`/`withNone`/`withAny` compile to
  real sum-of-products archetype matching.
- **`MemoryPool`** — native pages, each a lock-free round-robin triple buffer,
  so the Flutter isolate reads a coherent snapshot while the game isolate writes
  the next one.
- **`RingBuffer`** — the shared-memory SPSC primitive behind cross-isolate
  command dispatch and the draw-command buffer. No `SendPort` per command.
- **`Game`/`GameState`** — the fixed-timestep scheduler, the declarative
  system/command/buffer/state registration, and the two-isolate bootstrap.
- **Scenes and hierarchy** — `SceneStruct`, `Scene`, `Child`/`Parent`.
- **Input** — declared actions, bindings, keyboard/mouse/gamepad collection.
- **Assets** — the generic registry, `AssetKey`/`AssetSource`/`AssetLoader`,
  and `AssetPack` for encrypted chunks.
- **Coroutines and timelines** — `sync*` gameplay scripts and sampled animation.
- **`GameView`** — the widget every renderer plugs into.

It depends on Flutter — `StateChannel` is a `ValueListenable` and `GameView` is
a widget — but on nothing dimension-specific.

You do not normally depend on this directly; `goo2d` re-exports it.

## goo2d

The 2D engine, and the one dependency a 2D game needs.

- `Transform2D`, `WorldTransform2D` and `WorldTransformSystem`
- `Camera`, `CameraView`, `CameraProjection`
- `Collider2D` and its four shapes — geometry belongs to the engine whether or
  not it is ever simulated
- `Renderable2D`, `Sprite`, `SpriteFrame`, `NineSliceBorder`, `Texture`
- `GameRenderer2D` on the game isolate, batching into one `drawVertices` per
  frame on the Flutter one
- `MouseReceiver` and `MousePickingSystem`
- `AudioClip` and its loader
- `Game2D`/`GameState2D` — the pair whose narrowing *is* the 2D opt-in

Re-exports `goo`, so `import 'package:goo2d/goo2d.dart';` is the whole engine.

## goo2d_physics_box2d

ECS-facing Box2D v3: `RigidBody2D`, `Box2DPhysicsSystem`, the nine joints, and
the effectors. Steps the Box2D world inside the game isolate, in lockstep with
the fixed-tick scheduler, and writes results back into `Transform2D`.

Opt-in, and it needs its system declared. See [Physics](../guide/physics.md).

## goo2d_ffi_box2d

Vendored **Box2D v3.1.1** behind a flat, primitives-only C shim, plus the ffigen
bindings to it. Built from source per platform rather than shipped as prebuilt
binaries. **Not meant to be used directly by game code.**

!!! question "Why a shim instead of binding Box2D directly?"
    Box2D's C API passes small structs by value (`b2Vec2`, `b2BodyId`,
    `b2Transform`). ffigen maps each to a Dart `Struct`, which is a **heap
    object** — so a direct binding would allocate on the engine's hottest path.
    That cost was measured and removed once already in this codebase: a
    `Pointer` held in a field cost 14.63 ns per access against 2.25 ns for a
    plain `int`.

    `goo_box2d.h` therefore exposes only `int64_t`, `int32_t`, `uint64_t`,
    `float`, and pointers to arrays of those. **The generated bindings contain
    no `Struct` subclasses at all** — the property worth protecting if the
    header is ever extended.

The shim also carries bulk entry points, turning what would be 2N FFI calls per
tick into two, independent of body count. Handles are packed by Box2D's own
`b2StoreBodyId`/`b2LoadBodyId` helpers rather than by arithmetic written here,
so the packing is stated in exactly one place — and zero is the null handle,
which is Box2D's own convention, so a component field defaulting to 0 already
means "no body yet".

### Building it

| Platform | Route |
|---|---|
| Windows, Linux | `<platform>/CMakeLists.txt` → `src/CMakeLists.txt` |
| Android | `android/build.gradle` → NDK CMake → `src/CMakeLists.txt` |
| macOS, iOS | CocoaPods podspec, compiled directly and linked statically |

A Flutter app gets all of this automatically. Outside one, build it by hand
once:

```powershell
cd packages/goo2d_ffi_box2d
powershell -File tool/build_native.ps1
```

### Regenerating the bindings

`lib/src/box2d.g.dart` is checked in; regenerating needs libclang.

```powershell
winget install --source winget LLVM.LLVM
cd packages/goo2d_ffi_box2d
dart run ffigen --config ffigen.yaml
```

## goo_cli

The `goo` command: project scaffolding, codegen, the asset pipeline, and build
orchestration. **Dimension-agnostic** — it lives beside the kernel rather than
under `goo2d`, so each renderer registers its own asset types into the same
pipeline instead of needing its own CLI.

See the [CLI reference](../reference/cli.md).

## goo_net

Networking, shared across dimensions because a 3D game needs the same session
and messaging plumbing a 2D one does.

**It is the command API over a socket.** A game declares network messages the
way it declares everything else — a `describe*` pass handing back typed handles
— and `NetMessage`/`NetSignal` are spelled exactly like `SinkCommand`/
`SignalCommand`, over the kernel's own record layer rather than a second one.

- `NetDescriptor`, `NetMessage`, `NetSignal`, `NetTarget`, `NetChannel`
- `MultiplayerState` and `NetworkSystem` — the mixin and the system that carry
  the traffic
- `NetTransport`, `NetSession`, `NetConnection`, `NetPeerId`
- **`LoopbackNetTransport`** — in-process and real, not a mock. What tests and
  split-screen run on
- `package:goo_net/testing.dart` — the conformance suite every backend passes

## goo_net_p2p

The serverless backend: UDP hole punching against public STUN servers, a free
rendezvous relay for signalling, and a lightweight reliable/unreliable UDP data
channel. Nothing for you to host.

See [Networking](networking.md).

---

## Package dependency graph

```
                    ┌─────────┐
                    │   goo   │  kernel
                    └────┬────┘
          ┌──────────────┼───────────────┐
          │              │               │
     ┌────▼────┐   ┌─────▼─────┐   ┌─────▼──────┐
     │  goo2d  │   │  goo_cli  │   │  goo_net   │
     └────┬────┘   └───────────┘   └─────┬──────┘
          │                              │
  ┌───────▼──────────────┐        ┌──────▼───────┐
  │ goo2d_physics_box2d  │        │ goo_net_p2p  │
  └───────┬──────────────┘        └──────────────┘
          │
  ┌───────▼──────────┐
  │ goo2d_ffi_box2d  │
  └──────────────────┘
```

Nothing in the left column is reachable from the right, which is the property
that lets a headless dedicated server depend on `goo` + `goo_net` without a
renderer, and lets `goo3d` arrive without touching any of the shared half.
