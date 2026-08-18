# goo2d — Roadmap from API Proposal to Working Engine

## Context

`goo2d` is currently a pure API sketch: one Flutter package (`packages/goo2d`) full of
abstract classes and `throw UnimplementedError()` bodies, describing (not yet
implementing) a data-oriented, allocation-averse 2D game engine:

- A custom ECS where component field storage (`DataDescriptor`/`DataPointer`) is
  meant to live in a raw FFI memory pool, not on the Dart heap (per `RULES.md`:
  no heap allocation on hot paths, all game events are hot path, no
  `Canvas.save/restore/rotate/translate/drawImage`, no `Zone`).
- A two-isolate split: a "game isolate" runs fixed-tick ECS systems (incl.
  physics later) against the shared memory pool; the main/UI isolate renders
  and hosts the Flutter widget tree (`bin/t.dart` is a working proof-of-concept
  of passing a raw pointer address across `Isolate.spawn`).
- Scenes as prefab factories (`GameScene.describeScene` → `EntityStruct`
  prefabs → `addToScene`), hierarchy (`Child`/`Parent`), transforms
  (`Transform2D`), a `GameRenderer` system that walks `Renderable` entities and
  emits `DrawData` for a `DrawCanvas`, and an `AssetManager`/`GameAsset`
  loading abstraction.

None of this runs yet — `QueryBuilder.&`/`|`, hierarchy sibling pointers,
`MemoryPool` paging, `AssetManager`, `DrawData`, `Game`, and `GameView` are all
stubs, and the double-buffered memory pool has a known, unresolved tearing
race (flagged in `pool.dart`). You've confirmed the current `abstract
class`/`UnimplementedError` shapes are throwaway placeholders (kept abstract
only to keep the analyzer quiet) — nothing about their current shape, or their
member names, needs to survive into the real implementation.

You want to pick this back up and take it from proposal to a real engine, adding
four large capabilities on top: Box2D physics, Steam networking, a
"plug-and-play, no server to run" P2P networking option for non-web platforms,
and a CLI to compile/package a game (asset packing + encryption, codegen,
platform builds) — all as neatly separated packages, built for high
performance with the ticking and rendering bottlenecks specifically addressed.

You've also flagged that **2D is the current focus, but 3D (`goo3d`) is a
real future direction** once Flutter's 3D support matures, and you want the
package/naming split to absorb that without an API break later. That reshapes
the split below: a dimension-agnostic `goo` kernel that both `goo2d` and a
future `goo3d` depend on, plus a naming rule that any inherently-2D class
carries a `2D` suffix now so `goo3d` can introduce its `3D` counterpart later
without colliding.

This plan lays out the full roadmap (not just one fix), phased so each phase
is buildable and testable before the next depends on it. Decisions already
made with you: **desktop+mobile native-first** (web stays a conditional
fallback seam, not a day-one requirement), **Box2D via FFI to native Box2D
v3** (not a pure-Dart port), a **full CLI build tool** (codegen + asset
pipeline + packaging), a **shared dimension-agnostic `goo` kernel** package,
and the **naming conventions** below. The one open design area — the
non-Steam P2P transport — you clarified as "no server to set up, free, plug
and play"; §Phase 3 proposes a concrete design for that and calls out its one
real trade-off (NAT traversal isn't 100% without a paid relay) for you to sign
off on explicitly.

---

## Naming conventions (apply from Phase 1 onward)

- **No engine-brand prefixes.** Classes are named for what they are, not
  branded with the package name: `Game`, `PhysicsSystem`, `Transform2D` — never
  `Goo2dGame`, `Goo2dPhysicsEngine`, etc.
- **Backend-identifying subclass names are fine and encouraged** — they name
  *which backend*, not the engine brand: `Box2DPhysicsSystem`,
  `P2PNetTransport`, `LoopbackNetTransport`.
- **Anything inherently 2D-specific is suffixed `2D`**, matching the existing
  `Transform2D` precedent, so a future `goo3d` package can add a `Transform3D`
  (etc.) side by side without breaking `goo2d`'s API. This applies
  retroactively to the current render-layer stubs too — e.g. `Renderable` →
  `Renderable2D`, `DrawCanvas` → `DrawCanvas2D`, `GameRenderer` →
  `GameRenderer2D`, `DrawData`/`DrawRegistry` → `DrawData2D`/`DrawRegistry2D`.
  `Collider2D`/`RigidBody2D` (Phase 2) already follow this.
- **Dimension-agnostic classes keep plain, unsuffixed names** — ECS kernel
  (`Entity`, `Component`, `System`, `Query`, `GameEvent`), memory pool,
  networking, CLI. These are shared as-is by a future `goo3d`, no dimension
  suffix needed since there's nothing dimension-specific about them.
- **Member names (methods/fields) inherited from the current stubs are not
  fixed** — rename anything (`hasFloat64`, `describeStruct`, `runQuery`,
  whatever) wherever the real implementation makes a clearer name obvious.

---

## Target package layout (monorepo)

Split the current do-everything `packages/goo2d` into a **shared
dimension-agnostic kernel** plus **2D-specific specialization** packages, so a
future `goo3d` can plug into the same kernel/net/cli without duplicating them,
and so e.g. a headless dedicated-server binary can depend on `goo` +
`goo2d_physics_box2d` + `goo_net` without pulling in Flutter at all:

```
packages/
  goo/                     # shared, dimension-agnostic kernel: Entity/Component/
                           # System/Query/Event, memory pool, scenes, fixed-tick
                           # loop, hierarchy (Child/Parent), generic asset
                           # registry, Game/isolate bootstrap — no Flutter dep
  goo_net/                  # transport-agnostic NetPeer/NetConnection/Lobby —
                           # not dimension-specific, a goo3d game needs the
                           # same lobby/P2P plumbing
  goo_net_p2p/               # serverless UDP backend — no server to host
  goo_cli/                   # `goo` command: asset pack/encrypt, codegen,
                           # build orchestration — dimension-agnostic; goo2d
                           # (and later goo3d) register their own asset types
                           # as plugins into the same pipeline

  goo2d/                    # 2D specialization: Transform2D and anything else
                           # inherently 2D — depends on `goo`
  goo2d_render/              # DrawCanvas2D/Renderable2D/GameRenderer2D, sprite
                           # assets, GameView widget — the only package
                           # depending on Flutter/Skia
  goo2d_ffi_box2d/           # raw ffigen bindings to Box2D v3's C API
  goo2d_physics_box2d/       # RigidBody2D/Collider2D, Box2DPhysicsSystem —
                           # depends on `goo` + `goo2d` + `goo2d_ffi_box2d`

  # future, not built now — the split above exists specifically so this
  # slots in later without touching goo / goo_net / goo_cli:
  # goo3d/, goo3d_render/, goo3d_physics_<backend>/
```

The existing `packages/goo2d` files map over roughly like this: `struct.dart`,
`system.dart`, `scene.dart`, `event*.dart`, `pool.dart`, `data.dart`, and the
hierarchy parts of `data/hierarchy.dart` become `goo`; `data/transform.dart`
becomes `goo2d`; `draw*.dart`, `asset.dart` (generic parts move to `goo`,
sprite-specific parts stay), and `widget/game.dart` become `goo2d_render`.
Mechanical split, done first so every later phase lands in the right package
from the start instead of getting migrated later.

---

## Cross-isolate architecture: UI commands, live reads, and the render pipeline

This is the piece `example.dart`'s own TODO ("how do we handle a UI element
that wants to add entity to the scene?") and `draw.dart`'s own TODO ("game
isolate creates draw calls, main isolate draws them, or skip draw calls
entirely?") leave open. Resolving both together, because they're the same
underlying question — how data crosses the game-isolate/main-isolate
boundary — with three distinct lanes, each reusing the *same* mechanism
everywhere it applies rather than inventing a new one per use case:

**1. Bulk reads — any isolate, zero-copy, lock-free (the shared memory pool).**
Because the pool is raw native memory (not Dart heap), *any* isolate holding
its base pointer can resolve `DataPointer<T>[Entity]` for **reading**,
directly, with no message passing — this is what `bin/t.dart` already proves
works. Phase 1's triple-buffer fix (§Phase 1) is what makes this safe: a
reader always sees a complete, non-torn snapshot without blocking the
writer. This lane covers two cases with one mechanism:
   - The render pipeline reading component data (below).
   - A UI widget reading live game state directly — e.g. a HUD showing
     "enemies remaining" can run a **read-only query** against the pool from
     the main isolate itself, no round-trip needed. This works because the
     archetype/component-type bookkeeping (bitsets, offsets — Dart-level
     objects, not pool data) is cheap enough to duplicate per isolate: any
     isolate that calls the same `describeType`/`describeStruct` sequence at
     startup gets an identical schema, since it's a pure function of the
     component class definitions. The entity *bytes* still live exactly once,
     in the pool — Phase 4's codegen later turns this schema into a shared
     generated constant table so the two isolates' bookkeeping can't drift
     out of sync from registration-order differences.
   Only the game isolate is ever allowed to **write** entity data — a second
   writer would race the triple buffer's single-writer assumption.

**2. Commands — any isolate → game isolate, applied at a fixed point per tick,
via a ring buffer in the shared pool, *not* raw `SendPort` traffic.** This
started out as "just `SendPort.send()` one message per command" in an earlier
draft — worth being precise about why that doesn't hold up once you consider
bursty command volume (bulk unit orders, replicated network deltas, a big
particle spawn — thousands of commands landing inside one tick):

   - `SendPort.send()` is **reliable** (FIFO per port, no drops) but it is
     not free: every call deep-copies the message's object graph into a new
     clone on the receiving side, goes through a lock-protected per-isolate
     mailbox, and is dispatched as its own separate event-loop turn on the
     receiver. One call for an occasional UI click is a non-issue; thousands
     of calls inside a single tick is thousands of allocations and thousands
     of dispatch turns — exactly the hot-path cost `RULES.md` rules 1–2 exist
     to prevent, just relocated to the command path instead of the tick loop.
   - So: commands don't get their own bespoke transport. They reuse the exact
     producer/consumer shape as the draw-command buffer in lane 3 below — a
     flat, fixed-header/variable-payload **ring buffer living in the shared
     `MemoryPool`** (SPSC: the main/UI isolate is the only writer for now;
     see the Phase 3 note below on whether networking needs a second
     producer later). `Game.dispatchCommand(...)` encodes the command
     directly into the ring buffer via raw pointer writes — no heap
     allocation, no serialization, no per-command isolate message — and
     advances an atomic write cursor. Submitting 1 command or 5,000 costs the
     same *per command* regardless of burst size.
   - The game isolate's `CommandProcessor` runs **first** in each tick's
     system order and drains whatever is currently in the ring buffer (0 to
     however many accumulated since the last tick), applying each one through
     the existing scene mutation API (`GameScene.addToScene`, etc.) — so all
     game-state writes still happen from one place, at one deterministic
     point in the tick, never interleaved mid-tick with gameplay systems.
   - Because lane 2 and lane 3 are structurally the same primitive (a
     ring/flat buffer in the pool, one producer, one consumer, drained once
     per tick), this plan treats them as **one generic `RingBuffer`
     abstraction in `goo`**, not two bespoke mechanisms — used in opposite
     directions.
   - `SendPort` is kept, but demoted to what it's actually good at: rare,
     low-frequency, small-payload traffic — the one-time isolate handshake
     (passing the pool's base address), lifecycle signals (pause/resume/
     shutdown, scene-load requests — inherently rare "stop the world"
     operations), and acks/notifications back to the UI (e.g. handing back
     the `Entity` for a just-spawned prefab, or a "score changed" event) —
     never bulk per-tick command submission.
   - Overflow policy is an explicit design decision for Phase 1, not
     hand-waved: size the ring generously (configurable, default sized for a
     few thousand entries per tick) and treat exceeding it as a real,
     surfaced error (assert/log), not silent data loss or corruption.

**3. Control signals — game isolate → main isolate, small pings only, never
bulk data.** This is the answer to "draw calls are made from the game
isolate, rendering happens on the main isolate": resolving `draw.dart`'s
"TO BE CONSIDERED" in favor of **game isolate produces draw calls, main
isolate only replays them** — not "main isolate draws game objects
directly" — because `draw.dart` already commits to transforms arriving
pre-finalized with no `Canvas.save/restore` (no matrix stack), which means
hierarchy flattening (parent×child world-transform composition) has to
happen exactly once, and the game isolate is where the hierarchy data is
already being walked every tick:
   - `GameRenderer2D` runs **last** in each tick's system order (after
     physics/transform/hierarchy are finalized for that tick). It walks the
     `Renderable2D` query, composes final world transforms, applies z-order
     and basic culling, and writes a flat `DrawData2D` command buffer — into
     its own page of the *same* `MemoryPool`, through the same generic
     `RingBuffer` abstraction lane 2 uses (reused, not a second
     synchronization primitive).
   - After committing that buffer, the game isolate sends **one** cheap
     "frame ready" ping over `SendPort` (no payload beyond that signal).
   - The main isolate's `GameView`/`CustomPainter` is **push-driven**: it
     does not free-run on vsync polling game state — it only repaints in
     response to that ping, and `paint()` just replays the already-finalized
     buffer (`DrawCanvas2D`) with zero query/hierarchy/allocation work of its
     own. This is also why lane 3 is a plain `SendPort`, unlike lane 1: it's
     a control signal, never the data itself.
   - **Render/tick coupling for the MVP: 1:1 with the fixed tick** — simplest
     correct option, no interpolation math, no risk of blending mismatched
     entity sets across a spawn/despawn boundary. Decoupling render framerate
     from a lower simulation tick rate (extrapolating between two tick
     snapshots for smoother high-refresh visuals) is real but is explicitly
     deferred to §Phase 5 as a named enhancement, not built speculatively now.

---

## Phase 1 — Finish the `goo` kernel + `goo2d` specialization (hard prerequisite for everything else)

Physics needs a working fixed-tick loop and `Transform2D` writes; networking
replication needs working `DataPointer` reads; the CLI's codegen needs a
finalized struct-layout contract. Nothing else in this plan can start for real
until these gaps close (all in `goo` unless noted otherwise):

- **Generic `RingBuffer` primitive**: a fixed-header/variable-payload,
  single-producer/single-consumer ring buffer living in the shared
  `MemoryPool` — the shared mechanism behind both the UI→game command queue
  and the game→main draw-command buffer (see §Cross-isolate architecture
  below). One implementation, two directions, instead of a bespoke transport
  per use case.
- **Memory pool tearing fix** (`pool.dart`): replace the 2-state
  `_state.value = 1 - _state.value` toggle with a proper lock-free triple
  buffer — 3 buffers per page, an atomic "latest complete" index, the writer
  always writes into whichever buffer isn't the current latest-complete or
  in-flight-read, the reader atomically snapshots the latest-complete index
  without blocking the writer. This removes the tearing case currently
  flagged as an unsolved `TODO`.
- **`DataDescriptor` layout algorithm**: each `Component`/`EntityStruct` type
  gets its field layout computed once (sequential offsets with alignment,
  memoized per type) the first time it's described; an entity's row is stored
  contiguously per-archetype (AoS-per-struct-type, not a fully columnar
  archetype-SoA — simpler to implement generically over mixins, still
  cache-friendly for the common "iterate one archetype" access pattern).
  `DataPointer<T>.operator[]` resolves `Entity → page + row offset + field
  offset` directly into the raw buffer. This layout is exactly what Phase 4's
  CLI codegen will later hoist to compile time.
- **`QueryBuilder` (`With`/`Without`/`OptWith`, `&`/`|`)**: give every
  `ComponentType` a bit in a per-archetype signature bitset (assigned at
  describe-time); compile a `QueryBuilder` tree into `(includeMask,
  excludeMask, optionalMask)`; `Query.run()`/`runQuery()` iterate matching
  pages.
- **Hierarchy** (`data/hierarchy.dart`, dimension-agnostic → `goo`): implement
  `nextSibling`/`prevSibling` as real linked-list `DataPointer`s and
  `addChild`/`removeChild` to maintain them alongside
  `Parent.firstChild/lastChild`.
- **Fixed-timestep scheduler**: `event/fixed_loop.dart` currently only defines
  the *event type* (`FixedTickEvent`) — there's no accumulator/loop driving
  it yet. Add the actual fixed-timestep accumulator (with a max-substep clamp
  to avoid spiral-of-death) that lives on `Game` and drives
  `FixedTickable.onFixedUpdate` each step; also add explicit system execution
  ordering (a small dependency list per system) so e.g. physics always runs
  before anything reading `Transform2D` for render extraction.
- **`Game`/`GameView`/isolate bootstrap**: implement the isolate spawn
  orchestration sketched in `bin/t.dart`, generalized — main isolate owns the
  Flutter tree + allocates the memory pool (`calloc`) + spawns the game
  isolate with the pool's base address; game isolate runs the fixed-tick loop,
  the `CommandProcessor`, and (last) `GameRenderer2D`, per the three lanes in
  §Cross-isolate architecture above. Start with exactly **two** isolates
  (game: logic+physics+draw-command generation; main: `Canvas` drawing +
  input); leave the seam open to split draw-command generation into a third
  isolate later *if* profiling shows it's warranted — don't add it
  speculatively. `GameView` (`goo2d_render`) is the Flutter-facing,
  ping-driven `CustomPainter` side of this bootstrap.
- **`AssetManager`** (currently a marker interface only): the generic
  register/load/unload API and integer-indexed loaded-asset table live in
  `goo` (assets like textures/audio aren't inherently 2D or 3D); the
  address-resolution path `DataPointer<T extends GlobalObject>` already
  documented in `data.dart` plugs into this. Sprite-specific `GameAsset`
  subtypes live in `goo2d_render`.
- **`DrawData2D`/`DrawRegistry2D`** (`goo2d_render`): concrete
  `DrawSpriteData`/`DrawTextData` as flat, non-heap, isolate-transferable
  command buffer entries (same memory-pool mechanism as game state, not
  individual Dart objects per `RULES.md`), plus a `DrawCanvas2D` backend that
  batches via `Canvas.drawAtlas`/`drawVertices` with transforms pre-baked into
  vertex data — never the canvas matrix stack, per the existing ban on
  `save/restore/rotate/translate`.

**Verification for this phase:** a runnable example app (replaces the current
placeholder `lib/src/example.dart`, which isn't valid Dart) that spawns a
scene with a few hundred moving `Transform2D` entities, ticks them, and
renders them — plus unit tests for query matching, layout offsets, and pool
buffer swapping under concurrent read/write (stress test, not just
happy-path).

---

## Phase 2 — Box2D physics (`goo2d_ffi_box2d` + `goo2d_physics_box2d`)

- Bind Box2D v3's C API via `ffigen`. v3 is the right target specifically
  because it exposes contacts/sensors as **flat event arrays you poll each
  step** (`b2World_GetContactEvents`/`GetSensorEvents`) instead of
  callback-based collision handling — that fits the FFI-in-isolate,
  no-heap-allocation model far better than v2's callback interface would.
- Prebuilt platform binaries (Windows `.dll`, macOS `.dylib`, Linux `.so`,
  Android `.so`, iOS static xcframework); build/CI scripting for these is
  real but mechanical work, called out here, not deep-planned in this pass.
- `RigidBody2D` mixin (same shape as `Transform2D`): stores the Box2D body id
  as a `DataPointer<int>`, plus cached velocity/angular-velocity
  `DataPointer<double>`s. `Collider2D` mixin: shape (box/circle/polygon) +
  material (density/friction/restitution) + collision filter bits.
- `Box2DPhysicsSystem extends GameSystem with FixedTickable` (backend-named
  per the naming convention above): owns the `b2World`, steps it in
  `onFixedUpdate` against a query over `RigidBody2D` entities, writes results
  back into `Transform2D` `DataPointer`s, and turns polled contact/sensor
  events into dispatches through the existing `GameEvent`/`GameListener`
  machinery — using a single reusable/pooled event instance per dispatch (not
  one allocation per contact) to hold to the hot-path rule.
- Runs **inside the game isolate**, in lockstep with the Phase-1 fixed-tick
  scheduler (physics stepping has to share the same fixed timestep as
  gameplay logic).

**Verification:** an example scene with falling/colliding bodies, checked
against Box2D's own reference behavior; a stress test (thousands of bodies)
to get a first ticking-performance baseline.

---

## Phase 3 — Networking (`goo_net`, `goo_net_p2p`) — **landed, except the internet**

Dimension-agnostic (a future `goo3d` game needs the same lobby/P2P plumbing),
so these live alongside `goo`, not under `goo2d`.

**What this phase actually shipped, and how it differs from the plan above.**
Three decisions were taken during the work and are worth recording, because
each one replaced something this document originally said:

1. **A network message is a `GameCommand` over a socket, not a new paradigm.**
   The plan described `goo_net` as byte-level transport plumbing with the ECS
   layer deferred. What landed instead is a *declared message* API spelled
   exactly like the command API — `NetMessage`/`NetSignal` beside
   `SinkCommand`/`SignalCommand`, a `describeNetwork` pass beside
   `describeCommands`, the same `ParamDescriptor` vocabulary — because a game
   should not learn two ways to describe the same record. The record layer in
   `goo` (`ParamBatch`/`ParamBuffer`/`ParamLayout`) was promoted out of the
   command layer and is now shared by both, rather than being written twice.
   The byte-level `NetTransport`/`NetConnection`/`NetSession` contract still
   exists underneath, as the thing a backend implements.

2. **The Steam backend was dropped**, not deferred: `goo_net_steam` is
   deleted. The transport contract is open, so it remains possible as a
   separate package, and nothing in `goo_net` assumes one. `goo_ffi_steamworks`,
   the empty bindings package it would have been built on, went with it.

3. **The command ring buffer stays SPSC.** The plan flagged that a network
   isolate would make the UI→game ring a second producer. It does not arise:
   the socket lives on the *game* isolate, beside the simulation, because
   `Game`'s loop is a `Timer` and that isolate already has an ordinary event
   loop. A separate network isolate would need its own copy of the message
   registry and a second producer on the ring, to save a socket read costing
   microseconds.

- **`goo_net`** — messages (`NetMessage`, `NetSignal`), their two declared
  axes (`NetTarget`: who handles it; `NetChannel`: reliable-ordered or
  unreliable-unordered), `MultiplayerState`/`NetworkSystem`, `NetSession` and
  the roster, `NetPeerListener`/`NetSessionListener`, and
  `LoopbackNetTransport` — in-process, real, and what tests and split-screen
  run on. `NetTransport.schemaHash` refuses a peer running a different build,
  which is the failure mode index-on-the-wire creates across *machines* and
  cannot create across isolates.
- **`goo_net_p2p`** — a real UDP protocol: sequenced packets with
  ack/ackBits, per-message retransmission, in-order reliable delivery,
  per-tick batching into one datagram, fragmentation and reassembly,
  keepalives and timeouts. Join codes **carry the host's address** (ten
  characters, base-31), so there is no broker at all — the plan's
  "goo-hosted free rendezvous relay" is not needed for the cases that work
  today and is what the remaining work is about. LAN discovery is host
  beacons plus a listening client, so nothing has to own a well-known port.

**Verification:** one conformance suite (`package:goo_net/testing.dart`) run
against both backends — in-process, and over real UDP sockets; the reliable
channel delivering 30 messages in order across a link throwing away 30% of
everything (`simulatedLoss`, a knob on the shipped class); and two `Game`s in
one process, each with its own `P2PNetTransport`, playing a round over
loopback UDP.

**Still to do, in order:**

- **Phase 3a — crossing the internet.** STUN against free public servers to
  learn each peer's public endpoint, and a rendezvous to swap those endpoints
  so both sides punch at once. This is where the plan's hosted relay comes
  back, and it is the only thing between "works on a LAN" and "works from
  anywhere". The known limit stands and is not to be conflated with it: pure
  hole punching fails when **both** peers are behind symmetric NAT, and a
  TURN-style relay fallback is a separate, explicitly-scoped addition.
- **Phase 3b — ECS replication.** A `Replicated` mixin, delta compression,
  client-side prediction and reconciliation. Its own phase, as this document
  always said, and now with the primitive it needs already in place.

---

## Phase 4 — CLI build tool (`goo_cli`)

Dimension-agnostic (asset packing/codegen/build orchestration isn't 2D- or
3D-specific), so this lives alongside `goo`, not under `goo2d`. `goo2d_render`
and (later) `goo3d_render` register their own asset types into the same
pipeline rather than each having their own CLI.

- **Asset pipeline**: content-addressed packer producing one archive per
  platform build; per-asset encryption (AES-256-GCM, build-time-embedded key,
  per-asset nonce) — documented honestly as deterring casual asset
  extraction/modding, **not** DRM against a determined reverse engineer, since
  the key ships inside the binary. A manifest maps logical asset name → pak
  offset/length/nonce, consumed by Phase 1's `AssetManager`/`GameAssetSource`
  at load time.
- **Compile-time codegen**: using `package:analyzer` (the same approach
  `build_runner`/`source_gen` use), scan the game's `Component`/`EntityStruct`
  subclasses and generate the concrete struct layout (fixed offsets/strides)
  instead of computing it at runtime — removes layout bookkeeping from the hot
  path and turns struct-definition mistakes into build-time errors with real
  source locations instead of runtime `UnimplementedError`s. This directly
  hoists Phase 1's runtime layout algorithm to build time once the runtime
  contract is proven.
- **Packaging orchestration**: wraps `dart compile exe`/`flutter build` per
  target platform and bundles the encrypted asset pak alongside the binary —
  scoped as orchestration/glue over Flutter's existing build system, not a
  reimplementation of it.
- **Command shape**: `goo codegen`, `goo assets pack`, `goo build <target>`,
  `goo run` (dev loop against unencrypted loose assets for fast iteration).

**Verification:** run the CLI against the Phase 1 example app end-to-end —
codegen the structs, pack+encrypt its assets, build a real platform binary,
and confirm it runs and loads assets correctly.

---

## Phase 5 — Performance hardening pass (cross-cutting, dedicated pass at the end)

Concrete mechanisms for the two bottlenecks you called out, most of which are
seeded by earlier phases and get a focused pass here:

- **Ticking**: the Phase-1 fixed-timestep accumulator + system ordering
  handles correctness; this pass adds instrumentation (per-system timing) and
  only reaches for additional isolate-based parallelism across independent
  queries if profiling actually shows the single game isolate CPU-bound — not
  before.
- **Rendering**: sprite batching via `drawAtlas`/`drawVertices` (Phase 1),
  viewport/frustum culling before the draw-command buffer is built, a
  dirty-flag skip for static subtrees, and the triple-buffered draw-command
  handoff from Phase 1's pool fix.
- **Benchmark harness first**: build the N-thousand-entity stress scene once
  (early, reused from Phase 1's verification), so every phase after it has a
  real before/after number instead of guesswork.

---

## Suggested phase order

**Phase 1 → Phase 2 (physics) → Phase 4 (CLI) → Phase 3 (networking) → Phase
5 (perf pass, though instrumentation starts as early as Phase 1).** Physics
before CLI/networking because it's the more self-contained domain and proves
out the FFI-in-game-isolate pattern that Steam/P2P bindings will reuse. CLI
before networking because asset+codegen ergonomics make every later phase
(including finishing networking's example apps) faster to iterate on.
Networking last because it's the largest, most open-ended phase. Adjustable —
flag if you'd rather reorder (e.g. networking earlier if that's the part
you're most excited to prototype).
