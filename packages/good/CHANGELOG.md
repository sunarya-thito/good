## 0.1.1

Documentation only. No code changes.

The README now opens with the column-and-row model and a code example, and
says plainly that a 2D game should depend on `goo2d` instead.

## 0.1.0

First published release. The dimension-agnostic kernel is real and tested:

* **ECS** — `Entity`, `Component`, `GameSystem`, `Query`, `GameEvent`.
* **Storage** — the native memory pool and ring buffers behind `dart:ffi`,
  with `DataDescriptor` computing struct layouts at runtime.
* **Simulation** — the fixed-tick loop, the scheduler, and `GameScene`, run on
  their own isolate.
* **Hierarchy** — `Child`/`Parent` and composed world transforms.
* **Input, assets, coroutines and timelines**, plus `GameView` for the Flutter
  side.
* **Commands** — `SinkCommand`/`SignalCommand` over the shared record layer
  (`ParamDescriptor`, `ParamPointer`, `ParamBatch`, `ParamBuffer`), which
  `good_net` reuses instead of reimplements.

Not here yet: array-typed `DataDescriptor` fields in the codegen path,
dependency-based system ordering (`compareTo` is the mechanism today), and
audio playback — `AudioClip` decodes, but there is no backend or mixer. Web is
unsupported: the kernel needs `dart:ffi` and isolates.

## 0.0.1

* Initial split from `goo2d`: dimension-agnostic ECS kernel, memory pool,
  ring buffer, scenes, fixed-tick loop, hierarchy, and generic asset
  registry. Never published.
