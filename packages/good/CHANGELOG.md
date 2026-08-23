## Unreleased

### Breaking

* **`ParamDescriptor`'s integer and float declarations no longer take a
  default value.** `descriptor.hasInt32(100)` used to compile and then do
  nothing: `ParamLayout` never read the argument, and there was nowhere for it
  to go. A param record carries a written-mask, and reading a field nobody
  wrote throws instead of handing back a default — zero is a real value for
  every width here, so the engine reports the omission rather than inventing
  one. Drop the argument at the call site; nothing else changes. The
  same-named methods on `DataDescriptor` and `StateDescriptor` keep their
  defaults, which are read and do apply.

* **`Query` and `SingleQuery` gained members.** They are exported, so a class
  outside the engine that `implements Query` no longer satisfies it: `run`,
  `groups` and `runQuery` each take a trailing optional `Scene`, and `inScene`
  is new. Widen the three signatures and add `inScene`. Nothing that only
  *calls* a query is affected.

### Added

* **A query can be scoped to one loaded scene.** `Query.run`, `Query.groups`
  and `Query.runQuery` take an optional `Scene`; `Query.inScene(scene)` binds
  one once, for a system that always works in the same scene; and
  `QueryGroup.inScene(scene)` narrows a single archetype's group. The scope
  skips at the *page* level - a `MemoryPage` records the scene it was
  allocated for - so another scene's rows are rejected without being
  touched, where the per-row `entity.sceneSlot` test this replaces pays for
  every row it throws away. Nothing changes for a call with no scene.

  A scope naming a scene that is no longer loaded **throws**, and it throws
  twice over: when the scope is applied, and again when a walk starts, since a
  `QueryGroup` and a lazy `run()` both outlive the call that made them. The
  alternative - iterating empty - reads as a system that has quietly stopped
  working, a long way from the stale handle that caused it. A `Scene` carries
  a generation counter, so a handle whose slot has since been reused by a
  different scene is refused rather than answered for.

### Fixed

* **A false claim in the 0.2.0 notes is corrected.** They said the four
  commands the engine now declares broke `good_net` peer compatibility. They
  did not: the handshake hash reads network messages, declared in
  `describeNetwork` on the `GameState`, and never the commands
  `describeCommands` declares on the `Game`. No behaviour changed, here or
  there. `good_net` 0.2.1 carries the same correction for the users it
  actually reached.

## 0.2.0

Two gaps 0.1.0 admitted are closed: a column can be declared by the field that
holds it, and system order is worked out from the constraints instead of by
sorting. Several checks that used to let a mistake through now stop it.

### Breaking

* **`getScene<S>()` is now `singleScene<S>()`**, on `GameState` and on
  `GameSystem`. Rename the call; nothing else changes. It always threw once a
  second scene was resident, and several scenes at once is ordinary here — a
  level plus a HUD, a pause menu over a game — so the old name described a call
  that worked right through development and then threw on the first tick after
  something loaded a HUD. The name is the only place that precondition is
  visible at the call site. A game with more than one scene loaded reaches them
  through `loadedScenes` or the handle `loadScene` returned, and asks an entity
  which scene it belongs to with `entity.sceneSlot`. `Component.getScene`,
  which resolves the scene *that entity* was registered with, is unaffected and
  keeps its name.
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

* **Seeded random streams.** The kernel had no randomness, so a game would
  reach for `dart:math`'s `Random()` — seeded from the clock, invisible to the
  engine, different on every machine, and impossible to retrofit once shipped
  games depend on it (#125).

  ```dart
  late final RandomStream loot;

  @override
  void describeRandom(RandomDescriptor descriptor) {
    super.describeRandom(descriptor);
    loot = descriptor.has();
  }
  ```

  Declared like every other handle and kept in a field — there are no stream
  names and nothing to look up. Streams are independent, which matters more
  than it sounds: with one shared stream a system that draws a different number
  of times shifts every draw after it, and the engine now disables a system by
  itself when one throws, so that happens without anyone editing the drawing
  code.

  `RandomStream.intFor(entity, max)` is the per-entity form, and it is a
  **hash** of the seed, the stream, the tick and the entity rather than a draw.
  So it does not depend on how many entities exist or who was asked first, and
  a scene loading or unloading cannot shift it.

  The seed is `Game.randomSeed`, an overridable member like `pageSize`. Back it
  with a final field to supply a recorded one. It is part of a save: recording
  inputs without it reproduces nothing.

  **The algorithm is written out in the engine** rather than taken from
  `dart:math`. `Random` gives no guarantee that a seed produces the same
  sequence on a different Dart SDK, so a replay could stop matching after an
  upgrade with nothing in the game having changed. SplitMix64's constants are
  now part of the engine's contract, and changing one is a breaking change to
  every recorded replay.

  Only the simulating copy may draw. A draw on the handle the main isolate
  holds throws, naming the copy.

  **This is not deterministic replay, and does not deliver it.** A replay also
  needs the player's input recorded per tick, the tick each command landed on,
  and an answer for asset loads finishing at a different moment — and control
  commands are explicitly unordered against tick-delivered ones, so their
  arrival is not reproducible either. See #63.

* **`pause`, `resume`, `setTimeScale` and `stepOnce` travel as commands.** They
  were four hand-rolled string tags on the control port; they are now ordinary
  receipt-delivered commands (#142). Nothing changes at the call site, and the
  behaviour is the same — the tests for #117 and #124 pass unmodified — but
  there is one less bespoke channel between the isolates, and the four tags are
  gone.

  Receipt-delivered because each one can stop the fixed tick. A tick-delivered
  command is pumped from `runFixedStep`, so the message that started the tick
  again would be waiting on the tick it stopped.

  **The engine now declares four commands of its own**, before anything a game
  declares, so a game's commands sit after them in the declaration order. That
  order is internal wire identity and both isolate copies agree on it, so a
  game sees no difference.

  0.2.0 shipped this paragraph claiming the shift also broke `good_net` peer
  compatibility. **It does not**, and that sentence has been corrected rather
  than removed. `good_net` hashes the messages `describeNetwork` declares on
  the `GameState`, not the commands `describeCommands` declares on the `Game`,
  so the two passes are independent - see `good_net` 0.2.1.

* **A command can be delivered when the message arrives instead of on the next
  tick.** Register the handler with `hasControlSink` or `hasControlSignal`
  instead of `hasSink`/`hasSignal` (#142).

  ```dart
  // in GameState.describeCommands
  descriptor.hasControlSink(setTimeScale, (s) => state.timeScale = s);
  ```

  A normal command is pumped from `GameState.runFixedStep`, so it arrives only
  if the tick runs. That is right for gameplay — a command-spawned entity is
  visible to every system on the tick its command lands — and useless for
  anything that *stops* the tick, because the message that starts it again
  would be waiting on the tick it stopped. A control command is carried over
  the control port and run from the port callback, with no tick involved.

  Four things are true of it that are not true of `hasSink`, all following from
  there being no tick:

  * **Its future completes on send, not on execution.** `await` means "handed
    to the port", not "done". There is no reply leg, because a reply would be
    pumped inside the tick window this exists to work without.
  * **Its handler must not write component data.** There is no open write slot
    outside a tick, so a write would be erased by the next `beginTick` with
    nothing said. A debug assert catches it.
  * **That assert has one hole**: it stays silent while a page has never
    published, which is scene bootstrap and nothing else. A running game is
    covered.
  * **No ordering against ordinary commands.** Two calls sent in order can run
    in either, since they travel by different carriers.

  `hasControlHandler` and `hasControlSupplier` exist and **always throw**. A
  receipt-delivered command cannot answer, so the names that promise a reply
  fail where they are written rather than hanging where they are called.

  `CommandDescriptor` gained these four methods. Nothing outside the engine
  implements it, so this affects no game.

* **Pause, time scale and single-step.** There was no way to pause a game, run
  it in slow motion, or advance it one tick (#124).

  ```dart
  game.setTimeScale(0.25);   // quarter speed
  game.pause();              // and stopped
  game.stepOnce();           // exactly one fixed tick
  game.resume();             // back at quarter speed
  ```

  Callable from the main isolate, because that is where a pause button lives;
  `GameState.timeScale`, `.paused` and `.stepOnce()` are the same controls on
  the simulating side. Pause and scale are separate state, so a game paused at
  half speed comes back at half speed.

  **The scale changes how often a fixed tick happens, never how big one is.**
  Every `onFixedUpdate` still represents exactly `Game.fixedTimeStep` at every
  scale — a fixed timestep means a constant step, and that guarantee is why
  anything integrating over it is stable. So there is no `dt` parameter to
  scale and none was added.

  For the same reason a `timeScale` of `0` runs **no fixed ticks at all**,
  rather than ticks with a zero-size step: nothing divides by zero and no
  system sees a step it was not written for.

  There is no `unscaledDt` to look for either, because both clocks already
  exist under other names. The fixed loop is scaled simulation time; a
  `Tickable`'s `onTick(Duration)` is real wall clock and keeps running while
  the simulation is stopped. Anything that must ignore pause and scale — a UI
  animation, a network heartbeat, an autosave timer — is a `Tickable`, which
  is where it already belonged. Presentation running while paused is also what
  lets a pause menu draw itself.

  Two edges worth knowing. A negative scale is rejected with an assert, since
  nothing here is reversible and a negative delta would corrupt the step
  arithmetic rather than rewind anything. And a *large* scale meets the
  existing `maxFixedStepsPerAdvance` guard: a frame affords at most 5 steps
  however much scaled time it earned, so scales past about 5 run the game
  slower than asked instead of faster. Raise that cap if a game genuinely
  needs fast-forward; it is deliberately unchanged here, because it is what
  stops a slow machine spiralling.

  Independent of `pauseWhenHidden`: a game paused here stays paused across
  being hidden and shown again.

* **The game reacts to the app being hidden.** Nothing in the engine knew the
  app had been backgrounded, so a game went on simulating at its fixed tick
  while nobody was looking at it — battery spent on a world off screen (#117).
  The fixed tick now stops when the app is hidden and starts again when it
  comes back. Override `Game.pauseWhenHidden` to `false` for a game that has to
  keep running unattended: a live server-authoritative session, a download, a
  timer the player expects to have advanced.

  A system hears it by mixing in `AppVisibilityListener`, which gets
  `onAppHidden()` and `onAppShown(Duration gap)`.

  **Visibility, never focus.** Flutter's five `AppLifecycleState`s collapse to
  two, and `inactive` counts as visible: a window losing focus, a phone call,
  the notification shade, the app switcher. Pausing on those is why some games
  stop when you alt-tab.

  **There is no "about to be killed" hook**, deliberately. `onAppHidden` is the
  last reliable moment and it is a real one — iOS and Android both synthesise
  `hidden` before `paused` — so a save goes there. `detached` gets no callback:
  it is also the state an app is in before it starts, a killed process never
  sends it, and no platform promises time to act on it.

  On the accumulator, one correction worth stating because it is easy to assume
  otherwise: a long absence never queued a long catch-up. `advance` already
  capped a single frame at `maxFixedStepsPerAdvance` and dropped the rest, and
  it leaves under one step behind it, so the burst a resume could produce was
  never proportional to the time away. Stopping the tick is what saves the
  battery; discarding the leftover on the way back is worth **one** step, not
  five, and that is the step this no longer spends.

* **`AudioClip` is a kernel type, and the kernel registers its decoder.** It
  was in `goo2d`, which put sound behind a 2D renderer for no reason it could
  defend: a clip is bytes and a container name, with no canvas, device or
  dimension in it. A `goo3d` project could load nothing at all as a result
  (#93). Every engine package re-exports the kernel, so `AudioClip`,
  `AudioLoader`, `AudioKey` and `AudioAsset` are named exactly where they were
  for a `goo2d` game and are now reachable from a 3D one. `Game` registers the
  decoder itself, so no game declares anything to get it. Still no playback.

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

* **A system that throws no longer kills the game.** It used to, silently and
  permanently (#126). One uncaught error anywhere on the game isolate stopped
  the tick for good, while `Game.isRunning` went on answering `true` and
  `stop()` waited forever for a message from an isolate that no longer
  existed — a hung shutdown and a leaked pool, with no Dart error anywhere.
  The only trace was an engine log nothing in the app could see.

  Each listener is now guarded individually, so one bad system does not stop
  the others in the same tick, and the offending listener is disabled.

  **Debug and release differ here, and the difference is surprising enough to
  spell out.** In debug an `assert` fires and stops the game isolate — the
  loud answer, and no longer a silent one, because `Game.start` now installs
  an error port: the death reaches the main isolate, `isRunning` goes false, a
  pending `stop()` completes with the error instead of hanging, and the
  failure is reported where Flutter and the test runner already look. In
  release there is no assert: the system stays disabled and the game keeps
  running. So **the disable is release behaviour**, and
  `Game.enableSystem<MySystem>()` brings it back if the throw was transient.

  Two things that were already true and are now written down. The tick is
  **atomic** as far as any reader is concerned: the fixed-tick dispatch runs
  before the tick is committed, so a tick that throws publishes nothing, and
  the next tick copies the last published state back over the partial write. A
  failed step is **not retried**, because the accumulator is debited before the
  step runs — otherwise a deterministically throwing system would be handed the
  same step forever.

  Coroutines were already handled and are unchanged: `CoroutineScheduler`
  removes a throwing coroutine and completes its handle with the error.

  `GameListener` gains `disableAfterUncaught()`, which is how a listener says
  whether it can be switched off. `GameSystem` disables itself; the other three
  hosts do nothing, since switching off a `GameState`, `SceneStruct` or
  `EntityStruct` is not a smaller failure than the throw was.

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
