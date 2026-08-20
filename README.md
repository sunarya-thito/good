# good

GOOD — **G**ame **O**verdrive **O**n **D**art — is an ECS game engine for
Flutter.

Your game is data in columns and systems that walk them. The simulation runs on
its own isolate at a fixed timestep, keeps every component in shared native
memory, and allocates nothing on the per-frame path, so neither a Flutter
rebuild nor the garbage collector can stall it.

The good ecosystem includes `goo2d` for 2D games and `goo3d` for 3D games, both
built on the `good` kernel.

```bash
flutter pub add goo2d
```

That is the only dependency a 2D game needs, because `goo2d` re-exports the
kernel. Physics and networking are separate packages you add when you want
them, and each one needs its system declared before it does anything.

**[Read the documentation](https://sunarya-thito.github.io/good/)** for
installing, starting a project, building a game and shipping it.

## Packages

| Package | What it is |
|---|---|
| [`goo2d`](packages/goo2d) | The 2D engine, and the only thing a 2D game depends on |
| [`goo3d`](packages/goo3d) | The 3D engine: transforms, hierarchy and the camera |
| [`good`](packages/good) | The kernel: ECS, memory pool, ring buffers, scenes, the tick loop, input, assets, coroutines, `GameView` |
| [`good_cli`](packages/good_cli) | The `good` command: scaffolding, codegen, the asset pipeline, packaging |
| [`goo2d_physics_box2d`](packages/goo2d_physics_box2d) | Box2D v3 physics. Opt-in |
| [`goo2d_ffi_box2d`](packages/goo2d_ffi_box2d) | Vendored Box2D and the C shim under it |
| [`good_net`](packages/good_net) | Network messages, sessions, and the transport contract. Opt-in |
| [`good_net_p2p`](packages/good_net_p2p) | A peer-to-peer backend for `good_net`, with no server to run |

[The packages](docs/packages/index.md) explains why the split falls where it
does.

## Status

The documentation describes the finished engine, and parts of it are still
being written. [docs/reference/roadmap.md](docs/reference/roadmap.md) lists
what is implemented, what is deferred, and the rough edges. It is updated
before anything else, so where a package README disagrees with it, it is the
package README that is behind.

## Working on the engine

```bash
pip install -r docs/requirements.txt
mkdocs serve
```

`packages/` is the engine. `docs/` is the site, published by
`.github/workflows/docs.yml` on every push to the default branch.
