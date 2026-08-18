# Performance

!!! abstract "Layer: kernel (`good`)"

good is built to make the fast thing the natural thing, but a game can still be
slow. This page is about finding out *why*, and about the traps that make a
measurement lie.

Read [Hot-path rules](../reference/rules.md) first — it is the list of what not
to do. This page is what to do when you have followed it and something is still
slow.

## Measure on the right machine, in the right mode

!!! danger "A JIT benchmark can be wrong by 100×"
    `flutter test` runs the JIT. Numbers from it have been wrong by roughly two
    orders of magnitude for write-path costs in this very engine. **AOT-compile
    any benchmark whose result would change code**, and prefer measuring on a
    real device over a desktop.

    ```bash
    dart compile exe bench/my_bench.dart -o build/my_bench
    ./build/my_bench
    ```

!!! danger "A benchmark must be able to fail"
    Two benches in this repository reported "flat" — no effect — because their
    setup made the effect unobservable in the first place. Before you trust a
    negative result, check that the same harness *could* have produced a
    positive one: turn the optimisation off and confirm the number moves.

## What to instrument

The engine measures its own phases during development and can publish them
through [state channels](flutter-bridge.md#state-channels). Putting them on
screen early is worth more than reaching for a profiler late — a debug overlay
that shows entity count, sprite count and per-phase time answers most "why is it
slow" questions immediately.

!!! note "Diagnostic counters are development instrumentation"
    The per-phase timing fields are debugging scaffolding, not a stable public
    API — they come and go as the engine is tuned. Read them from a debug
    overlay; do not build gameplay on them.

What is worth watching, whatever it is currently called:

| Reading | Why it matters |
|---|---|
| Time in fixed-tick systems | Your gameplay's own budget |
| One whole fixed step | Gameplay plus the engine around it |
| The presentation pass | Rendering, split into walk / sort / write |
| One `advance` end to end | What the frame actually cost |
| **Fixed steps in the last advance** | The denominator for everything above |
| Sprites actually emitted | Whether you are hitting the batch cap |
| Physics phases and body counts | Solver cost versus leaked bodies |

!!! warning "Divide by the step count before comparing anything"
    Whole-step totals are reset once per **advance** and accumulate across every
    fixed step in it, while a single system's timing is usually one step. The
    moment an advance costs more than one step's wall clock, those stop sharing
    a denominator.

    A recording in this engine once read as a catastrophic super-linear blowup
    and was entirely this.

### Split totals into phases

Three unrelated costs with three unrelated fixes cannot be directed by one
number. That is why the renderer reports walk, sort and write separately rather
than one presentation total, and why the physics system reports its phases
rather than one step time. Measure your own systems the same way when you
measure them at all — a single "gameplay is slow" figure tells you nothing you
can act on.

## The usual causes

### Resolving components per entity

The single most common one:

```dart
// no — a registry lookup per entity
for (final entity in query.run()) {
  entity.get<Transform2D>().transformOffsetX[entity] += 1;
}

// yes — one lookup per archetype
for (final group in query.groups()) {
  final transform = group.get<Transform2D>();
  for (final entity in group) {
    transform.transformOffsetX[entity] += 1;
  }
}
```

### Allocating in the loop

A `Vector2`, a record, a small list, a closure — each is cheap once and ruinous
sixty times a second across thousands of entities. Hoist the scratch object into
a field, or work in plain doubles.

### Hitting the sprite cap

`maxSpritesPerTick` truncates the batch when exceeded, which **looks exactly
like the renderer getting slower**. Put the emitted sprite count on your debug
overlay next to your entity count; if the two diverge, you are clipped, not
slow.

### Physics: density, not count

Box2D's cost follows the contact graph. A box too small for the pile it holds
means bodies overlapping, the solver pushing them apart every step without
converging, and no island ever quiet enough to sleep — far more expensive than
the same bodies with room to settle.

If physics is slow, check the arena before the count. And check for **leaks**:
an engine-level bug once left despawned bodies in the Box2D world forever, and
only a body-count readout told the two apart — a crowded arena explains a
*large* cost, but only a leak explains 57,882 awake bodies in a scene of 4,000.

### Page size

```dart
@override
int get pageSize => 1 << 20;   // 1 MiB, not the 64 MiB default
```

A page costs **3×** its size resident (one slot per triple-buffer state). The
64 MiB default is ~192 MiB per page — right for a large game, wasteful for a
scene holding one camera.

## Design choices that are already paid for

Worth knowing so you do not undo them:

**Row addresses are `int`, not `Pointer`.** A `dart:ffi` `Pointer` held in a
field measured 14.63 ns per access against 2.25 ns for a plain `int` — roughly
6.5×, because the `Pointer` is a heap object. Every column in the engine is an
integer address plus an offset for this reason.

**Bulk FFI entry points.** The physics shim pushes and pulls every transform in
two calls rather than 2N, independent of body count.

**One draw call.** The renderer batches into a single `drawVertices` per frame,
which is why `Canvas.save`/`restore`/`translate` are forbidden in the replay
path.

**Sub-byte fields.** `hasBool()` is one bit and `hasUint4()` is half a byte.
Across thousands of entities per tick, field widths are bandwidth.

## Profiling in Flutter

```bash
flutter run --profile
```

Use DevTools' timeline for the Flutter isolate. Remember that **most of your
game is not on it** — the simulation isolate shows up separately, and a frame
that looks empty on the UI thread can still be behind because `advance` is
running long on the other one. That is what the advance timing and step count on
your overlay are for.

---

## Next

[Exporting a game →](../exporting/index.md)
