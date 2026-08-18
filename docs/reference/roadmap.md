# Implementation status

The rest of this documentation describes the engine as a whole. **This page is
the honest ledger of what is landed in the repository right now**, so that
nobody follows a guide for code that is not there yet.

Last verified: **2026-08-18**, against the `asset-api-redesign` branch.

## Packages

| Package | State | Notes |
|---|---|---|
| `goo` | **Working** | The kernel is real and tested — ECS, memory pool, ring buffers, scheduler, scenes, hierarchy, input, assets, coroutines, timelines, `GameView` |
| `goo2d` | **Working** | Transforms, world transforms, camera, colliders, sprite rendering, mouse picking, audio assets |
| `goo_cli` | **Working** | `create`, `generate`, `assets compact`, `assets pack`, `build windows/linux/android/ios`. Verified end to end |
| `goo2d_ffi_box2d` | **Working** | Box2D v3.1.1 vendored, shim written, bindings generated, builds on Windows/Linux/Android/macOS/iOS |
| `goo2d_physics_box2d` | **Working** | Bodies, colliders, the nine joints, effectors, raycast and overlap queries |
| `goo_net` | **Working** | Messages, targets, channels, sessions, roster events and `LoopbackNetTransport`, with a conformance suite every backend is run against |
| `goo_net_p2p` | **Working on a LAN** | A real UDP protocol — acks, retransmission, ordering, batching, fragmentation, keepalives — plus address-carrying join codes and LAN discovery. **Does not cross the internet yet**: that needs STUN and a rendezvous |
| `goo3d` and siblings | **Not started** | The kernel split exists so this lands without touching the shared half |

!!! warning "Package READMEs lag behind"
    Several package READMEs still say "placeholder" for code that is now
    written. Trust this page and the source over them.

## Verified end to end

These were run, not assumed:

- `goo create` → `flutter analyze` clean → `flutter run`
- `goo assets compact` on a real image, with ffmpeg auto-download
- `goo generate` producing a populated `Textures` enum
- `goo assets pack` writing an encrypted chunk and the mapping
- `goo build windows` producing a launchable application whose bundle contains
  the chunk and **not** the loose asset
- The `NetTransport` conformance suite against **both** backends — the
  in-process one and real UDP sockets
- Two `Game`s in one process, each with its own `P2PNetTransport`, playing a
  round over loopback UDP: a client request handled on the host, the host's
  answer handled on both
- The reliable channel delivering 30 messages in order across a link throwing
  away 30% of everything

## Not yet implemented

Deliberately deferred, and documented in place rather than left as silent gaps.

### Engine

- **Array-typed `DataDescriptor` fields** in the codegen path
- **Z-ordering and culling** beyond declaration order and the `zIndex` sort
- **Dependency-based system ordering** — `compareTo` is the mechanism today
- **Audio playback.** `AudioClip` decodes and the asset pipeline ships audio,
  but there is **no audio backend, no mixer and no voice management**. The asset
  half is done; the playback half is not.

### Tooling

- **Struct-layout codegen.** `goo generate` writes the asset bindings. Hoisting
  the runtime `DataDescriptor` layout algorithm to build time by scanning
  `Component`/`EntityStruct` with `package:analyzer` is a separate and much
  larger piece of work, and emitting a stub would make it look done.
- **`goo build macos`** — run the pipeline steps and `flutter build macos`.
- **`goo run`** — use `flutter run`.

### Networking

- **Crossing the internet.** `goo_net_p2p` join codes carry the host's address,
  which is enough on one machine or one LAN and not enough through a home
  router. STUN (learning a peer's public address) and a rendezvous (swapping
  those addresses so both sides punch at once) are the next landing.
- **A relay fallback.** Hole punching fails when *both* peers are behind
  symmetric NAT. "Free, no server" and "always connects" are not the same
  claim, and a TURN-style relay is a separate, clearly-scoped addition.
- **Request/reply messages.** Deliberately absent — see the networking guide.
- **The ECS replication layer** — a `Replicated` mixin, delta compression,
  prediction and reconciliation. `goo_net` moves declared records; replication
  is built on top of that, and the channel split is the primitive it needs.
- **Congestion control.** A link sends what the game asks it to and reports
  `packetLoss` so the game can decide to send less. Approximating a congestion
  controller would be worse than naming it as missing.

### Platforms

- **Web.** The kernel uses `dart:ffi` for storage and spawns an isolate for the
  simulation; neither exists there. `goo_net_p2p` additionally needs
  `dart:io` sockets.

!!! note "The Steam backend was dropped"
    `goo_net_steam` was removed rather than built. The transport contract is
    open, so a Steam backend remains possible as a separate package; nothing in
    `goo_net` assumes one. `goo_ffi_steamworks`, the empty bindings package it
    would have been built on, went with it.

## Publishing

The packages are `publish_to: none` and are not on pub.dev yet. pub.dev
currently serves `goo2d` **0.0.2**, an earlier iteration of this engine with an
entirely different API — a pubspec saying `goo2d: ^0.0.1` resolves to *that*,
and resolves successfully, so the mismatch surfaces as analyzer errors in
generated code rather than as a resolution failure.

Until the rewrite is published, depend on the engine by `path:` or `git:`.

## Known rough edges

Things that work but will catch you out:

- **`goo create` keeps Flutter's `main.dart`.** `flutter create` runs first and
  writes its counter app; the scaffolder never overwrites an existing file, so
  the goo `main.dart` is skipped and the log says `Kept existing lib/main.dart`.
  Delete it and re-run with `--no-flutter-create`.
- **Re-running `goo create` after editing the pubspec duplicates keys.** The
  idempotence check matches the literal line it wrote, so an edited dependency
  line slips past it and you get two `goo2d:` entries and two `assets:` blocks.
- **`test/widget_test.dart`** from `flutter create` references `MyApp`, which no
  longer exists once `main.dart` is the goo one.
- **`.goo_compact.json` ships** inside the built bundle. Harmless, but it names
  your source files.
- **The scaffolded `main.dart` leaks the game if the widget is disposed during
  startup.** It assigns a nullable `_game` *after* `await Game.start(...)` and
  calls `_game?.stop()` in `dispose`, so a dispose that lands mid-start stops
  nothing and the isolate outlives the widget. `stop()` is also a no-op on a run
  that has not finished booting, so both halves need fixing — see
  [Lifecycle in a widget](../guide/flutter-bridge.md#lifecycle-in-a-widget) for
  the shape the docs prescribe.

## Contributing to this page

When something in the "not yet implemented" list lands, move it up and delete
the entry — and when a page elsewhere in these docs starts being true, nothing
needs to change there, because it was already written as though it were.
