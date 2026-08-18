# good

Game Overdrive On Dart: a game engine for Flutter that keeps your simulation
off the UI thread and out of the garbage collector.

`goo` is the family name and the last letter says what it targets. `good` runs
on Dart and knows nothing about dimensions. `goo2d` does 2D. `goo3d` will do 3D
when it exists.

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
| [`good`](packages/good) | The kernel: ECS, memory pool, ring buffers, scenes, the tick loop, input, assets, coroutines, `GameView` |
| [`good_cli`](packages/good_cli) | The `good` command: scaffolding, codegen, the asset pipeline, packaging |
| [`goo2d_physics_box2d`](packages/goo2d_physics_box2d) | Box2D v3 physics. Opt-in |
| [`goo2d_ffi_box2d`](packages/goo2d_ffi_box2d) | Vendored Box2D and the C shim under it |
| [`good_net`](packages/good_net) | Network messages, sessions, and the transport contract. Opt-in |
| [`good_net_p2p`](packages/good_net_p2p) | A peer-to-peer backend for `good_net`, with no server to run |

[The good family](docs/packages/index.md) explains why the split falls where it
does.

## What actually works

The documentation describes the finished engine, so not all of it is built yet.
[docs/reference/roadmap.md](docs/reference/roadmap.md) tracks what is real
today, what is deferred and which rough edges will catch you out. It gets
updated first, so believe it over a package README that disagrees.

## Working on the engine

```bash
pip install -r docs/requirements.txt
mkdocs serve
```

`packages/` is the engine. `game/` is a real game built against it, which is
how the awkward parts get found. `docs/` is the site, published by
`.github/workflows/docs.yml` on every push to the default branch.
