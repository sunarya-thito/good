# Developing a game

This chapter is the working reference for building with good. Each page says
which layer it belongs to, because most of it comes from the kernel and is
written the same way under `goo2d` and `goo3d`:

| Page | Layer |
|---|---|
| [Coming from Unity/Godot](mental-model.md) | Kernel (`good`) |
| [Thinking in ECS](thinking-in-ecs.md) | Kernel (`good`) |
| [Architecture](architecture.md) | Kernel |
| [Entities and components](entities-and-components.md) | Kernel |
| [Scenes and prefabs](scenes.md) | Kernel |
| [Systems and queries](systems-and-queries.md) | Kernel |
| [Events and listeners](events.md) | Kernel |
| [Transforms and hierarchy](transforms-and-hierarchy.md) | Hierarchy is kernel; `Transform2D` is 2D |
| [Rendering and cameras](rendering.md) | 2D (`goo2d`) |
| [Input](input.md) | Kernel |
| [Assets](assets.md) | Registry is kernel; texture/audio types are 2D |
| [Physics](physics.md) | Opt-in (`goo2d_physics_box2d`) |
| [Talking to Flutter](flutter-bridge.md) | Kernel |
| [Coroutines and animation](coroutines-and-animation.md) | Kernel |
| [Performance](performance.md) | Kernel |

!!! tip "Read this first if you have used Unity, Godot or Flame"
    good declares everything up front and **toggles it on and off** — there is no
    `AddComponent`, no `RemoveComponent`, and no component that appears at run
    time. [Coming from Unity, Godot or Flutter](mental-model.md) is the
    translation table: the call you would have written and what to write
    instead. [Thinking in ECS](thinking-in-ecs.md) is the layer under it — what
    happens to the habits you built, and worked answers to state machines,
    events and the rest.

## The one paragraph version

Your game is **declared** on a `Game` (main isolate) and **simulated** by a
`GameState` (its own isolate). A `SceneStruct` declares which prefabs can exist
and spawns the starting ones. An `EntityStruct` declares a row layout — its
fields are columns you index by `Entity`, not values on an object. A
`GameSystem` declares a `Query` once and walks the matching rows every fixed
step. Nothing between those declarations allocates.

## The vocabulary

| Term | What it is |
|---|---|
| `Game` | Main-isolate declarations: commands, cameras, published state, timing |
| `GameState` | Game-isolate simulation: declares the systems, owns the memory pool, the loaded scenes, the tick |
| `SceneStruct` | A *declaration* of a scene — which prefabs exist in it, what spawns on load |
| `Scene` | One **loaded instance** of a `SceneStruct`; an `extension type` over an int |
| `EntityStruct` | A *declaration* of one kind of entity — the row layout shared by all of them |
| `Entity` | One row. An `extension type` over an int packing archetype, page and offset |
| `Component` | A mixin on an `EntityStruct` contributing fields and a queryable type |
| `DataPointer<T>` | One column. `field[entity]` reads, `field[entity] = v` writes |
| `GameSystem` | Per-tick work, holding compiled queries |
| `Query` | A compiled archetype match, walked as groups |
| `describe*` | A declaration pass, run once, returning typed handles to keep in fields |

The `describe*`-returns-a-handle shape is universal and deliberate: there are no
string keys anywhere in the API, so a typo is a compile error, not a
runtime miss. See [Hot-path rules](../reference/rules.md).
