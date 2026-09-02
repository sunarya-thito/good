# good

GOOD — **G**ame **O**verdrive **O**n **D**art — is an ECS game engine for
Flutter.

Your game is data in columns and systems that walk them. The simulation runs on
its own isolate at a fixed timestep, keeps every component in shared native
memory, and allocates nothing on the per-frame path, so neither a Flutter
rebuild nor the garbage collector can stall it.

`good` is the kernel. The ecosystem around it includes `goo2d` for 2D games and
`goo3d` for 3D games, both built on it.

<div class="grid cards" markdown>

- :material-cube-outline: **`good`** — the kernel

    ECS, scenes, the fixed-tick loop, the memory pool, input, assets, coroutines
    and the cross-isolate plumbing. The base both engines are built on.

- :material-shape-square-plus: **`goo2d`** — the 2D engine

    Transforms, cameras, colliders, sprite rendering. Re-exports the kernel, so
    a 2D game has one dependency and one import.

- :material-cube: **`goo3d`** — the 3D engine

    Transforms, cameras, meshes, materials and lighting. Re-exports the kernel,
    so a 3D game has one dependency and one import.

</div>

```dart
class Player extends EntityStruct with Transform2D, WorldTransform2D, Renderable2D {
  final sprite = Sprite.of(width: 64, height: 64, color: 0xFF4FC3F7);
}
```

---

## Start here

<div class="grid cards" markdown>

- **[Installation](getting-started/installation.md)**

    Flutter SDK, per-platform toolchains, and the `good` command-line tool.

- **[Create a project](getting-started/create-a-project.md)**

    `good create`, and what a good project is made of.

- **[Your first game](getting-started/your-first-game.md)**

    A sprite you can drive with the keyboard, built from an empty project.

- **[Exporting a game](exporting/index.md)**

    Compaction, packing, encryption, and `good build <platform>`.

</div>

---

## The packages

A 2D game needs **one dependency**. Everything else is opt-in, because each
carries weight not every game wants.

| Package | What it is |
|---|---|
| [`goo2d`](packages/index.md#goo2d) | The 2D engine. Re-exports the kernel — one dependency, one import |
| [`good`](packages/index.md#good) | The kernel. You do not normally depend on it directly |
| [`good_cli`](reference/cli.md) | The `good` build tool: scaffolding, codegen, asset pipeline, packaging |
| [`goo2d_physics_box2d`](guide/physics.md) | Box2D v3 physics: `RigidBody2D`, colliders, joints, effectors |
| [`goo2d_ffi_box2d`](packages/index.md#goo2d_ffi_box2d) | Vendored Box2D plus a primitives-only C shim. Not used directly |
| [`good_net`](packages/networking.md) | Declared network messages, sessions, and the transport contract |
| [`good_net_p2p`](packages/networking.md#p2p) | Serverless P2P backend — nothing to host |

[The packages →](packages/index.md) explain how they divide up, and
[Implementation status](reference/roadmap.md) tracks what is landed in the
repository right now.

---

## What the split buys

The kernel holds the ECS, the scheduler, scenes, hierarchy, input, the asset
registry, the isolate bootstrap, networking, and the CLI. That is what lets
`goo3d` sit beside `goo2d` without duplicating any of it — and what lets a
headless dedicated server depend on the kernel and physics without pulling in a
renderer at all.

The practical consequence for you: **most of what you learn is not
2D-specific.** Every guide page is marked with which layer it belongs to.

---

## The shape of a good game

Three ideas carry most of the engine, and they are worth meeting before the
tutorial.

**Two isolates, two copies of your `Game`.** Declarations live on the Flutter
isolate; the simulation runs on its own. The same `Game` object is deep-copied
across the boundary, so both sides agree on every id without negotiating.
See [Architecture](guide/architecture.md).

**Everything is declared once, and hands back a typed handle.** There are no
string keys anywhere in the API. A declaration returns the object you keep in
the field that declares it, and the analyzer catches a misspelling that a map
lookup would not.

<!-- snippet: in EntityStruct with Renderable2D -->
```dart
final sprite = Sprite.of(width: 64, height: 64);  // keep the handle

void hit(Entity entity) => sprite.color[entity] = 0xFFFF0000;
```

**Components are storage, not objects.** An `EntityStruct` subclass is a
*description* of a row layout, shared by every entity of that kind. A field is
a `DataPointer` you index by `Entity`, not a value on an instance. See
[Entities and components](guide/entities-and-components.md).

---

## The rules that shaped it

good is written against an explicit set of hot-path constraints — no heap
allocation per frame, no closures in a tick, no `Canvas.save`/`restore`. They
are worth reading before writing systems, because the engine's API shapes are
consequences of them: [Hot-path rules](reference/rules.md).
