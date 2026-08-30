# Performance

!!! abstract "Layer: kernel (`good`)"

[Hot-path rules](../reference/rules.md) is the list of what not to do per
frame. This page is what to do when you have followed it and the game is still
slow.

## Measure in profile mode

```bash
flutter run --profile
```

A debug build runs the JIT with assertions on and is not evidence of anything.

Use DevTools' timeline for the Flutter isolate, and remember that **most of
your game is not on it**: the simulation runs on its own isolate and shows up
separately. A frame that looks idle on the UI thread can still be late because
`advance` ran long on the other one.

## Put the numbers on screen first

For the first question — which is always "how many of what" — a debug overlay
beats a profiler. Publish counters from a system through
[state channels](flutter-bridge.md#state-channels) and read them in a
`ValueListenableBuilder`: entities alive, sprites emitted, bodies awake, and
how long your own systems took.

Time your own systems in parts rather than as one number. "Gameplay is slow" is
not something you can act on; "the spatial index rebuild is 4 ms of the 6" is.

!!! note "The engine's own timing fields are scaffolding"
    good instruments its phases while it is being tuned, and those fields come
    and go with it. Read them from a debug overlay if they are there; do not
    build gameplay or a shipped HUD on them.

## The usual causes

### Resolving components per entity

The single most common one:

```dart
// no — a registry lookup per entity
for (final entity in query.run()) {
  entity<Transform2D>().component.transformOffsetX[entity] += 1;
}

// yes — one lookup per archetype
for (final group in query.groups()) {
  final transform = group<Transform2D>();
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
like the renderer getting slower**. `GameRenderer2D.lastRecordsOverBudget` is
how many records the last frame asked for and could not fit: zero while you are
inside the budget, and the exact amount to raise it by when you are not. Put it
on your debug overlay next to the emitted sprite count — nothing on screen tells
"the scene is heavy" and "the scene is clipped" apart.

What a clipped frame loses is its furthest layers, so the symptom is a
background that comes and goes rather than a sprite vanishing at random. See
[Budgets](rendering.md#budgets).

It is not `lastWriteDropped`. That one means main had not collected the previous
frame yet, and no budget would have helped.

### Physics: density, not count

Box2D's cost follows the contact graph. A box too small for the pile it holds
means bodies overlapping, the solver pushing them apart every step without
converging, and no island ever quiet enough to sleep — far more expensive than
the same bodies with room to settle.

So if physics is slow, check the arena before the count. Then check for a
**leak**: a crowded arena explains a large cost, but only bodies that were
never destroyed explain 57,882 awake ones in a scene of 4,000. A body-count
readout is what tells those two apart.

### Field widths are bandwidth

`Field.boolean()` is one bit and `Field.uint4()` is half a byte. A row walked
thousands of times a tick is memory traffic, so declare the narrowest field the
value fits in. This is not micro-optimisation at that scale.

### Page size

<!-- snippet: in Game -->
```dart
@override
int get pageSize => 1 << 20;   // 1 MiB, not the 64 MiB default
```

A page costs **3×** its size resident, one slot per triple-buffer state. The
64 MiB default is ~192 MiB per page — right for a large game, wasteful for a
scene holding one camera.

---

## Next

[Exporting a game →](../exporting/index.md)
