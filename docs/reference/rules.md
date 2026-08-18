# Hot-path rules

These are the constraints the engine is written against, and the reason its API
looks the way it does. They apply to **your** game code too — they are about the
per-frame path, where a small cost repeated sixty times a second across
thousands of entities is the whole budget.

!!! info "What counts as the hot path"
    **Every framework game event.** `onFixedUpdate`, `onTick`, `onEntityMounted`
    for a prefab that spawns often, collision handlers, input handlers, anything
    a system calls per entity.

    What is *not*: `describe*` passes, `seal()`, boot, and one-off scene setup.
    Closures and allocation there are fine, because they run once.

If you are working on the engine itself , not a game, the structural rules
live in [Engine design rules](design-rules.md).

---

## No heap allocation on the hot path

Including records, wrapper classes, and anything that quietly builds a list.
Extension types over a non-heap value are fine, which is why `Entity`, `Scene`,
`TimelineSample` and `Joint` are all `extension type ... (int)`.

```dart
// no — allocates a Vector2 per entity per tick
final delta = Vector2(dx, dy) * speed;

// yes — two doubles
final ndx = dx * speed;
final ndy = dy * speed;
```

## Every framework event is hot

If the engine calls it, treat it as per-frame until you have checked otherwise.

## No closures on the hot path

The rule above covers them, but they hide well:

```dart
// no — a closure and usually an Iterable, per call, per tick
if (entities.any((e) => hp[e] <= 0)) { }
enemies.forEach(update);

// yes
for (var i = 0; i < entities.length; i++) {
  if (hp[entities[i]] <= 0) { }
}
```

`any`, `where`, `map`, `forEach` and `fold` all allocate. Write the indexed
`for`. Closures in a `describe*` pass or at boot are fine.

## Do not break the draw batch

Avoid `Canvas.save`, `restore`, `rotate`, `translate` and `drawImage`. The
renderer batches everything into one `drawVertices` call per frame, and each of
those calls breaks the batch. Nothing in the replay path uses them.

## Avoid the `Zone` API

Zone lookups add indirection to every asynchronous hop, and a zone that captures
errors will swallow the ones the engine reports through `assert`. Nothing in the
engine forks a zone, and game code has no reason to either.

## Declarations hand back a typed handle

Whatever a `describe*` pass produces comes back as a handle you keep in a field.
**No string or int keys, no `Map<String, ...>` the framework searches at use
time.**

```dart
// yes
late final Sprite playerSprite;

void describeSprites(SpriteDescriptor d) {
  playerSprite = d.has(texture: playerTexture, width: 64, height: 64);
}

void use(Entity e) { playerSprite.color[e] = 0xFFFF0000; }

// no
void describeSprites(SpriteDescriptor d) { d.has('playerSprite'); }
void use() { sprites['playerSprite']; }
```

The analyzer catches a misspelled field; it cannot catch a misspelled string.
This applies to every `describe*` — buffers, state channels, inputs, coroutines,
colliders, cameras, commands.

## Everything is known at declaration time

No `addComponent`, no `removeComponent`, no archetype that changes shape. Declare
what an entity could need and **toggle** the parts that come and go. See
[Coming from Unity, Godot or Flutter](../guide/mental-model.md).

Which isolate a type lives on is also fixed, and the compiler enforces it — see
[Isolate affinity is a type](../guide/architecture.md#the-four-lanes-across-the-boundary).

---

## Applying these to your own game

Most of your code is not hot, and none of this is a style guide for menus and
save files. The set that matters day to day is short:

- [ ] Indexed `for` in `onFixedUpdate`, not `map`/`where`/`forEach`.
- [ ] Resolve components **per group**, not per entity.
- [ ] No `Vector2`, record, or list built per entity per tick.
- [ ] Do not keep `Input.value` for a `Vector2` past the tick — it is reused.
- [ ] Toggle flags instead of restructuring entities.
- [ ] Keep declaration passes pure and order-stable — both isolates run them.

See [Performance](../guide/performance.md) for measuring, and the traps that
make a benchmark lie.
