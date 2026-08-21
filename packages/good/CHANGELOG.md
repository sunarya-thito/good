## Unreleased

Two gaps 0.1.0 admitted are closed: a column can be declared by the field that
holds it, and system order is worked out from the constraints instead of by
sorting. Several checks that used to let a mistake through now stop it.

### Breaking

* **The profiler is out of the engine.** `GameState` no longer publishes
  `lastSimulationMicros`, `lastSystemMicros`, `lastPresentationMicros` or their
  best-of rings. A game framework is not a profiler, and anything that wanted
  those numbers can time the part it cares about. The clocks that run the
  engine stay, including the two `FrameMeter`s behind `fps` and `jank`.
* **`Accessor` is bound to `Component`.** `entity<String>()` no longer
  compiles. `Accessor` also gained a `component` getter, which is what an
  extension on it reaches for on nearly every line.
* **`SingleQuery.component` is abstract.** It was a
  `throw UnimplementedError()` on the public class while the only
  implementation always supplied it.
* **`describeType`, `describeAssets`, `describeStruct`, `describeEvents` and
  `describeCommand` are `@mustCallSuper`.** An override that drops the base
  pass contributed nothing and said nothing; `EntityStruct`, `GameState` and
  `SceneStruct` all did it with `describeEvents`. For a component mixin,
  `good generate` now fails on it outright.
* **Indexing a column with an entity of another archetype throws.** The access
  path resolved a row from the page index and the row offset alone, so a column
  subscripted with the wrong entity read or overwrote whichever live row sat at
  that offset in its own storage. The message names the entity's archetype, the
  column's, and the column. Debug builds only, like the other guards below.
* **A hierarchy edge cannot cross a scene.** A scene's pages are freed
  wholesale, so an edge spanning two of them left the surviving side naming a
  freed row. `unloadScene` now unlinks the edges leaving the scene, after the
  unmount events, so a listener still reads the hierarchy as it stood.
* **Eleven per-access and per-spawn guards are asserts.** A release build no
  longer throws on them, because each was answering a question settled by the
  shape of the code and not by the running game. The two that cost most were
  the array bounds check on every element get and set, and the acyclicity walk
  on every `addChild`, `adopt` and declared-child spawn.

### Added

* **`Game.describeAssetLoaders` registers a payload type's decoder.** It joins
  `describeState`, `describeScenes`, `describeCommands`, `describeBuffers` and
  `describeCameras`, chains through `super` the same way, and is the one of
  that family that runs on the decoding isolate only - `AssetLoaders` is a
  per-isolate static, and the game isolate holds payload-free declarations and
  never decodes. Registering a type the layer below already covers replaces it,
  so a game can substitute its own decoder for an engine one. `AssetLoaders`
  also gained `isRegistered<T>()`, which answers what `of<T>()` could only
  answer by throwing.

* **A column can be declared by the field that holds it.**
  `final speed = Field.float64(220)` replaces a `late final DataPointer<double>`
  paired with a `describeStruct` body a few lines down. Both forms work: a
  column whose default comes from `describeAssets` cannot be a field
  initialiser, since Dart will not let one field read another. Row layouts moved
  as a result, which costs only a test that named an offset.
* **A prefab can declare the children it always spawns.**
  `final barrel = EntityStruct.of(Barrel.new)` on a `Parent` spawns the barrel
  with the turret, links it underneath, and destroys it with the turret.
  Declarations nest, and a struct that declares itself is a registration error
  naming the ring.
* **A prefab can move an inherited column's default.** `DefaultPointer` carries
  `defaultValue`, writable until `seal()`, so two prefabs sharing a component no
  longer need a descriptor class and a hook that exists only to feed `has*`
  calls.
* **`hasEntity`** for a column holding an entity handle, **`hasEnum`** for an
  enum-valued column, and **`hasEntity`/`optEntity`** on `ParamDescriptor`.
* **`hasFloat32ArrayOf` and `hasFloat64ArrayOf`**, taking one default per
  element. Array defaults were a single scalar broadcast across every slot.

### Fixed

* **An entity's heap-object slots are freed when its row goes.** A slot in the
  process-global table was the one thing a row owned that neither freeing the
  row nor dropping its page reclaimed, so a game using `hasHeapObject` and
  destroying entities grew that table for the life of the process. Both
  `destroy()` and scene unload release them now.
* **System order honours every constraint.** `compareTo` states a partial
  order, which `List.sort` is not defined for; given one it permuted the list
  and dropped an unrelated constraint elsewhere. A composer could sort ahead of
  the spawner, so an entity created during a tick was composed on the next one
  and published `(0, 0)` in between.
* **Gamepads are detached before the input buffer is freed.**

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
