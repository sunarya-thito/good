# good

Dimension-agnostic engine kernel for the `good` game engine family: the ECS
(`Entity`/`Component`/`GameSystem`/`Query`/`GameEvent`), the shared native
memory pool and ring buffers, `GameScene`, the fixed-tick loop, hierarchy
(`Child`/`Parent`), and the generic asset registry.

This package has no Flutter dependency, so it can run headless (e.g. a
dedicated multiplayer server) or under any renderer built on top of it. 2D
games depend on [`goo2d`](../goo2d) for 2D-specific pieces (`Transform2D`,
etc.); a future `goo3d` would depend on `good` the same way instead of
duplicating this kernel.

Status: API proposal, actively being implemented. See the project root plan
for the phased roadmap.
