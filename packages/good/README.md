# good

**G**ame **O**verdrive **O**n **D**art. The dimension-agnostic engine kernel
for the `good` game engine family: the ECS
(`Entity`/`Component`/`GameSystem`/`Query`/`GameEvent`), the shared native
memory pool and ring buffers, `GameScene`, the fixed-tick loop, hierarchy
(`Child`/`Parent`), and the generic asset registry.

This package is dimension-agnostic, not Flutter-agnostic: it depends on
Flutter, because `GameView` is a widget and `StateChannel` is a
`ValueListenable`. What it holds no opinion about is dimensionality. 2D
games depend on [`goo2d`](https://pub.dev/packages/goo2d) for 2D-specific pieces (`Transform2D`,
etc.); a future `goo3d` would depend on `good` the same way instead of
duplicating this kernel.

Status: **working.** The kernel is real and tested - ECS, memory pool, ring
buffers, scheduler, scenes, hierarchy, input, assets, coroutines, timelines
and `GameView`. Audio playback, array-typed `DataDescriptor` fields and
dependency-based system ordering are not implemented yet, and the web is
unsupported because the kernel needs `dart:ffi` and isolates. The
[implementation status page](https://sunarya-thito.github.io/good/reference/roadmap/) lists what works today.
