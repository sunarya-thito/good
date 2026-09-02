# Implementation status

The rest of this documentation describes the engine as a whole. **This page says which parts of it
are built**, so that nobody follows a guide for code that is not there yet.

Last verified: **2026-09-02**, on `master`.

## Packages

| Package | State | Notes |
|---|---|---|
| `good` | **Working** | The kernel is real and tested — ECS, memory pool, ring buffers, scheduler, scenes, hierarchy, input, assets, coroutines, timelines, `GameView`, on-screen sticks |
| `goo2d` | **Working** | Transforms, world transforms, screen space, camera, colliders, sprite rendering, grid-font text, debug draw, mouse picking |
| `good_audio_soloud` | **Plays clips on five buses** | The `AudioBackend` implementation, over SoLoud. Play, set a volume, stop. Bus levels and the voice budget are counted in `good`. No looping, loop points, fades or web |
| `good_cli` | **Working** | `create`, `generate`, `assets compact`, `assets pack`, `build windows/linux/android/ios`. Verified end to end |
| `goo2d_ffi_box2d` | **Working** | Box2D v3.1.1 vendored, shim written, bindings generated, builds on Windows/Linux/Android/macOS/iOS |
| `goo2d_physics_box2d` | **Working** | Bodies, colliders, the nine joints, effectors, raycast and overlap queries |
| `good_net` | **Working** | Messages, targets, channels, sessions, roster events and `LoopbackNetTransport`, with a conformance suite every backend is run against |
| `good_net_p2p` | **Working on a LAN** | A real UDP protocol — acks, retransmission, ordering, batching, fragmentation, keepalives — plus address-carrying join codes and LAN discovery. **Does not cross the internet yet**: that needs STUN and a rendezvous |
| `goo3d` | **Transforms only** | `Transform3D`, composed `WorldTransform3D` and `Camera3D` are real and tested. **Nothing draws**: there is no renderer, no mesh, no material and no light. Not on pub.dev, and `good create --3d` is still refused |
| `goo3d`'s siblings | **Not started** | `goo3d_physics_box3d` and the rest. The kernel split exists so they land without touching the shared half |

## Verified end to end

These were actually run:

- `good create` → `flutter analyze` clean → `flutter run`
- `good assets compact` on a real image, with ffmpeg auto-download
- `good generate` producing a populated `Textures` enum, each value carrying
  the pixel size read from the image header, and a `TextureSize` class of the
  same numbers as `static const int`
- `good assets pack` writing an encrypted chunk and the mapping
- `good build windows` producing a launchable application whose bundle contains
  the chunk — and, with `strip-originals` unset, the loose copy beside it
- The `NetTransport` conformance suite against **both** backends — the
  in-process one and real UDP sockets
- Two `Game`s in one process, each with its own `P2PNetTransport`, playing a
  round over loopback UDP: a client request handled on the host, the host's
  answer handled on both
- The reliable channel delivering 30 messages in order across a link throwing
  away 30% of everything

## Not yet implemented

Deferred, and documented in place instead of left as silent gaps.

### Engine

- **Array-typed `DataDescriptor` fields** in the codegen path
- **Screen space beyond anchoring and view-fraction sizing.**
  `ScreenTransform2D` anchors an entity to a point on the view, sizes each axis
  in view units or as a fraction of the view, and draws it in a layer behind or
  in front of the world. Not there: parallax (a scroll factor against the
  camera), texture tiling with a UV origin, and the aspect-driven fit modes —
  `auto`, `cover` and `contain` — which need a decoded texture's dimensions on
  the game isolate
- **Z-ordering** beyond declaration order and the `zIndex` sort
- **Skipping work for a subtree nothing moved.** A sprite outside the camera's
  viewport is now dropped before it is queued, but a static subtree is still
  re-composed and re-tested every tick
- **Dependency-based system ordering** — `compareTo` is the mechanism today
- **On-screen controls beyond a stick.** `JoystickArea`, `JoystickControl` and
  `Joystick` draw an analog stick and write the four `VirtualAxis` floats. Not
  there: a button, a d-pad, a trigger, and a layout that arranges a set of them
  for a phone. A button is a `Listener` around the game's own art calling
  `InputDevice.press` and `release`, so the missing half is the art and the
  arrangement, not a mechanism
- **Text beyond a grid font.** `Text2D` draws one line from a fixed-cell
  bitmap atlas you supply, laid out by arithmetic on the game isolate. Not
  there: proportional metrics, kerning, line wrapping, shaping, `dart:ui`
  rasterisation, runtime font loading, and a font shipped with the engine.
  Screen-space text is not coming either — a HUD is widgets, and a `Text2D`
  on a `ScreenTransform2D` entity is refused at declare time
- **Runtime inspection beyond debug draw.** `debugDraw` draws lines, circles
  and labels over the world from a system, in world space, on its own buffer
  and its own budget, and a `const bool` takes all of it out of a release
  build. Not there: the panel half — archetypes and their entity counts, one
  entity's column values, the system list with per-system tick cost.
  `WorldCensus` answers the counting half on the game isolate already; nothing
  renders it, no component or field carries a name at runtime, and there is no
  per-system timing to report
- **`goo2d`'s transform helpers are still on the mixin.** `Transform2D.lookAt`,
  `distanceTo` and the rest take the entity as an argument
  (`transform.lookAt(entity, x, y)`). The accessor form the guide teaches,
  `entity<Transform2D>().lookAt(x, y)`, is `goo3d` only so far.
- **Audio beyond levels and a budget.** A clip plays and stops through
  `state.audio`, and a playing voice holds a claim on its asset so a track
  survives the scene that started it unloading. Five buses - master, music,
  effects, dialogue, interface - each carry a level, `setLevel` reaches the
  voices already sounding, and `Game.maxVoicesPerBus` caps each bus separately
  and stops that bus's oldest voice to seat a new one. The budget is counted
  in the engine because no backend supplies one: flutter_soloud 4.1.7's
  `setMaxActiveVoiceCount` caps how many voices are *mixed* per buffer and not
  how many may be alive, so a cap of 4 reads back as 4 and then permits 59
  concurrent voices. What is **not** there: looping and authored loop points
  (an asset-pipeline change before it is a mixer change - there is nowhere to
  author a loop point today), fades, a settings surface that persists the
  levels, positional audio, and web.
- **The 3D renderer.** `goo3d` composes transforms and carries a camera; the
  half that draws is a native backend behind our own C shim and is not written.
  `Renderable3D`, `MeshAsset`, `MaterialAsset` and `Light3D` do not exist yet,
  so the 3D rendering guide describes them ahead of the code.

### Tooling

- **Struct-layout codegen.** `good generate` writes the asset bindings. Hoisting
  the runtime `DataDescriptor` layout algorithm to build time by scanning
  `Component`/`EntityStruct` with `package:analyzer` is a separate and much
  larger piece of work, and emitting a stub would make it look done.
- **`good build macos`** — run the pipeline steps and `flutter build macos`.
- **`good run`** — use `flutter run`.
- **A texture size the generator could not read.** `good generate` parses PNG,
  WebP, GIF, BMP and JPEG headers. Anything else with a texture extension
  generates `0` for its width and height, named in the run's output. An SVG or
  an AVIF is the case that reaches this.

### Networking

- **Crossing the internet.** `good_net_p2p` join codes carry the host's address,
  which is enough on one machine or one LAN and not enough through a home
  router. STUN (learning a peer's public address) and a rendezvous (swapping
  those addresses so both sides punch at once) are the next landing.
- **A relay fallback.** Hole punching fails when *both* peers are behind
  symmetric NAT. "Free, no server" and "always connects" are not the same
  claim, and a TURN-style relay is a separate, clearly-scoped addition.
- **Request/reply messages.** Not provided — see the networking guide.
- **The ECS replication layer** — a `Replicated` mixin, delta compression,
  prediction and reconciliation. `good_net` moves declared records; replication
  is built on top of that, and the channel split is the primitive it needs.
- **Congestion control.** A link sends what the game asks it to and reports
  `packetLoss` so the game can decide to send less. Approximating a congestion
  controller would be worse than naming it as missing.

### Platforms

- **Web.** The kernel uses `dart:ffi` for storage and spawns an isolate for the
  simulation; neither exists there. `good_net_p2p` additionally needs
  `dart:io` sockets.

!!! note "The Steam backend was dropped"
    `good_net_steam` was removed instead of built. The transport contract is
    open, so a Steam backend remains possible as a separate package; nothing in
    `good_net` assumes one. `good_ffi_steamworks`, the empty bindings package it
    would have been built on, went with it.

## Publishing

All seven packages are on pub.dev at **0.1.0**, under BSD 3-Clause. Pin
`^0.1.0`; the long-dead `goo2d` 0.0.2 still resolves for `^0.0.1`.

## Known rough edges

Things that work but will catch you out:

- **`good create` keeps Flutter's `main.dart`.** `flutter create` runs first and
  writes its counter app; the scaffolder never overwrites an existing file, so
  the good `main.dart` is skipped and the log says `Kept existing lib/main.dart`.
  Delete it and re-run with `--no-flutter-create`.
- **Re-running `good create` after editing the pubspec duplicates keys.** The
  idempotence check matches the literal line it wrote, so an edited dependency
  line slips past it and you get two `goo2d:` entries and two `assets:` blocks.
- **`test/widget_test.dart`** from `flutter create` references `MyApp`, which no
  longer exists once `main.dart` is the good one.
- **A component declares its type, its assets and its events in fields, and
  the rest still declare in a hook.** `Component.type<T>()` replaced
  `describeType`, `Asset.of` replaced a prefab's `describeAssets`, and
  `Event.of` replaced `describeEvents`; `describeStruct`, `describeSprites`
  and `describeCollider` are still hooks that have to chain `super`. The two
  spellings sit side by side until the remaining hooks follow.
- **A scene declares its own events from its constructor body and its assets
  in `describeAssets`.** A scene is constructed by the caller, so its field
  initialisers run before it has an `Assets` to declare into. `EventBus.events`
  reads the owner rather than the declaration stack, so events have a route a
  constructor body can take; assets do not, and the hook is where a scene
  declares them until scene construction moves under the framework. The
  mount/unmount pair every scene, prefab and system inherits is a field
  initialiser either way.

## Contributing to this page

When something in the "not yet implemented" list lands, move it up and delete
the entry — and when a page elsewhere in these docs starts being true, nothing
needs to change there, because it was already written as though it were.
