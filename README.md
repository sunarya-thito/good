# goo2d

A data-oriented, allocation-averse 2D game engine for Flutter/Dart.
Currently in active development, moving from an API proposal to a working
engine. See [RULES.md](RULES.md) for the hot-path constraints that shape
the whole codebase.

## Packages

**A 2D game needs exactly one dependency: `goo2d`.** It re-exports the
kernel, so one `import 'package:goo2d/goo2d.dart';` is the whole engine -
there is no second package to add and keep version-matched by hand.

```yaml
dependencies:
  goo2d:
    path: ../packages/goo2d
```

- [`packages/goo2d`](packages/goo2d) - **the 2D engine.** Transforms,
  world transforms, camera, colliders, and Flutter-facing 2D rendering
  (`GameRenderer2D` on the game isolate, `RenderSystem2D` on the Flutter
  one). Re-exports `goo`.
- [`packages/goo`](packages/goo) - the dimension-agnostic kernel `goo2d`
  is built on: ECS (Entity/Component/System/Query/Event), the shared native
  memory pool and ring buffers, scenes, `Game`/`GameState`, the fixed-tick
  loop, hierarchy, cross-isolate state channels, and the renderer-agnostic
  `GameView` widget. Depends on Flutter, but on nothing dimension-specific -
  a future `goo3d` is a sibling of `goo2d`, not a layer on top of it, and
  supplies its own render system (a native surface rather than a
  `CustomPaint`) without `GameView` changing at all. You do not normally
  depend on this directly.

Opt-in, added explicitly only if you want them (each also needs its system
declared in your `Game.describeSystems`):

- [`packages/goo2d_physics_box2d`](packages/goo2d_physics_box2d) /
  [`packages/goo2d_ffi_box2d`](packages/goo2d_ffi_box2d) - Box2D v3 physics.
- [`packages/goo_net`](packages/goo_net) - transport-agnostic networking
  interfaces (`NetTransport`/`NetPeer`/`NetConnection`/`Lobby`).
- [`packages/goo_net_steam`](packages/goo_net_steam) /
  [`packages/goo_ffi_steamworks`](packages/goo_ffi_steamworks) - Steam
  backend for `goo_net`.
- [`packages/goo_net_p2p`](packages/goo_net_p2p) - serverless P2P backend
  for `goo_net` (no server to host, free).
- [`packages/goo_cli`](packages/goo_cli) - the `goo` build tool: asset
  packing/encryption, ECS struct-layout codegen, platform packaging.

## Status

**Phase 1 (core engine) is done and tested.** `goo`/`goo2d`/`goo2d_render`
are real, working implementations, not stubs:

- ECS: bit-packed component storage (`goo/lib/src/data_layout.dart`),
  archetype registration, `Entity` handles, `QueryBuilder`
  (`With`/`Without`/`OptWith`, `&`/`|` as real sum-of-products matching).
- `MemoryPool`: a lock-free round-robin triple buffer per page (the
  original 2-state toggle's tearing race is fixed and stress-tested across
  real isolates).
- `RingBuffer`: the shared-memory SPSC primitive behind both cross-isolate
  command dispatch and the draw-command buffer - no `SendPort`-per-command.
- `Game`: fixed-timestep scheduler, declarative system/command/buffer
  registration, and a real two-isolate bootstrap (`Isolate.spawn`, page and
  buffer address handoff, command ring buffer, tick-complete notification).
- Hierarchy (`Child`/`Parent`, `addChild`/`removeChild`/`addToParent`),
  `AssetManager`/`GlobalObjectRegistry` for `hasObject`/`optObject` fields.
- 2D rendering: `GameRenderer2D` composes world-space transforms through a
  hierarchy on the game isolate and batches solid-color quads into one
  `Canvas.drawVertices` call per frame on the main isolate - no
  `save`/`restore`/`rotate`/`translate`/`drawImage` anywhere in the replay
  path, per `RULES.md`. `GameView` is push-driven off tick notifications,
  not vsync-polling.
- A working example app (`packages/goo2d_render/example`) exercising all of
  the above: a spinning player with an orbiting (hierarchy-parented)
  wingman, UI-dispatched enemy spawning via the command ring buffer. Builds
  clean (`flutter build bundle`).

`goo`: 131 tests. `goo2d`: 5 tests. `goo2d_render`: 39 tests. All packages
`dart analyze`/`flutter analyze` clean.

Deliberately deferred within Phase 1 (documented in place, not silent
gaps): array-typed `DataDescriptor` fields, textured/atlas sprite
rendering (no image-decoding asset type exists yet), z-ordering/culling
beyond declaration order, dependency-based system ordering, `loadScene`
(scene transitions).

Phase 2-5 (Box2D physics, Steam/P2P networking, the CLI build tool, and the
cross-cutting performance-hardening pass) haven't started - `goo_net*`,
`goo_cli`, `goo2d_ffi_box2d`, `goo2d_physics_box2d` are still
scaffolding-only placeholders. See the project plan for the full roadmap.
