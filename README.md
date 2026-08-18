# goo

A data-oriented, allocation-averse game engine family for Flutter/Dart: the
dimension-agnostic `goo` kernel, and the renderers built on it.

**[Read the documentation →](https://sunarya-thito.github.io/goo/)**

The docs are the reference for the whole engine — installation, creating a
project, developing a game, and exporting one — and they are the spec the
implementation is measured against. Build them locally with:

```bash
pip install -r docs/requirements.txt
mkdocs serve
```

`docs/reference/roadmap.md` is the honest ledger of what is landed right now;
the rest of the documentation is written as the finished engine.

## Packages

| Package | What it is |
|---|---|
| [`packages/goo2d`](packages/goo2d) | The 2D engine. Re-exports the kernel — one dependency, one import |
| [`packages/goo`](packages/goo) | The dimension-agnostic kernel: ECS, memory pool, ring buffers, scenes, the tick loop, input, assets, coroutines, `GameView` |
| [`packages/goo_cli`](packages/goo_cli) | The `goo` build tool: scaffolding, codegen, the asset pipeline, packaging |
| [`packages/goo2d_physics_box2d`](packages/goo2d_physics_box2d) | Box2D v3 physics (opt-in) |
| [`packages/goo2d_ffi_box2d`](packages/goo2d_ffi_box2d) | Vendored Box2D plus a primitives-only C shim |
| [`packages/goo_net`](packages/goo_net) | Declared network messages, sessions, and the transport contract (opt-in) |
| [`packages/goo_net_p2p`](packages/goo_net_p2p) | Serverless P2P backend for `goo_net` |

A 2D game depends on `goo2d` alone; everything else is added explicitly, and
each opt-in package also needs its system declared. See
[The goo family](docs/packages/index.md).

## Status

[docs/reference/roadmap.md](docs/reference/roadmap.md) is the current ledger of
what is implemented, what is deferred, and the known rough edges. Package
READMEs lag behind it — trust that page and the source.

## Repository layout

- `packages/` — the engine
- `game/` — a real game built against it
- `docs/` — the documentation site (MkDocs Material), published by
  `.github/workflows/docs.yml`
