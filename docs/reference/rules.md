# Hot-path rules

These are the constraints the engine is written against, and the reason its API
looks the way it does. They apply to **your** game code too — most of them are
about the per-frame path, where a small cost repeated sixty times a second over
thousands of entities is the whole budget.

!!! info "What counts as the hot path"
    **Every framework game event.** `onFixedUpdate`, `onTick`, `onEntityMounted`
    for a prefab that spawns often, collision handlers, input handlers, anything
    a system calls per entity.

    What is *not* the hot path: `describe*` passes, `seal()`, boot, and one-off
    scene setup. Closures and allocation there are fine — they run once.

---

## 1. No heap allocation on the hot path

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

## 2. Assume every framework game event is hot

If the engine calls it, treat it as per-frame until you have checked otherwise.

## 3. Avoid `Canvas.save`, `restore`, `rotate`, `translate`, `drawImage`

The renderer batches everything into one `drawVertices` call per frame. Those
calls each break the batch. Nothing in the replay path uses them.

## 4. Avoid the `Zone` API

## 5. No closures on the hot path

Rule 1 covers them, but they hide well:

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

## 6. A declaration hands back a typed handle

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

## 7. Never `print` to report a framework problem

Including through `assert(() { print(...); return true; }())`. It is swallowed
in release and invisible in test output. Use `assert(false, 'message')`.

## 8. Do not add a specialised variant to escape a constraint

If `operator[]` reads the published snapshot and you want the uncommitted one,
the answer is **not** a `readPending()` beside it. A second read path means
every later reader has to know which one is right here, and the first one stops
guaranteeing anything.

Fix the *placement* instead: a value that must be read after it is written
belongs in a later phase. Unity DOTS does this by running
`PresentationSystemGroup` after `SimulationSystemGroup` over the same
`LocalToWorld`. Same here — `WorldTransformSystem` writes during the fixed tick,
and consumers run after it commits.

## 9. Isolate affinity is a type

`GameListener` means "lives on the game isolate": `GameState`, `SceneStruct`,
`EntityStruct`, `GameSystem`. `Game` is not one, so

```dart
class MyGame extends Game with FixedTickable { }   // compile error
```

fails to compile instead of silently never ticking.

There is no second event lane for the main isolate — `Game.buildView` is its
whole surface, and traffic the other way goes through a `GameCommand` or a
`StateChannel`.

## 10. One fact, one place

If two structures have to agree and only your memory keeps them agreeing, they
will drift. The analyzer checks types, not "these stay in step".

**The tell:** you cannot change one place without hunting for the others. Adding
to a list means adding to a second list. Sorting one means permuting another.
Setting a flag means also updating a count, a cache, or a mirror. When the
correct edit is "and don't forget to…", fix the structure.

Remove the second copy, preferring in this order:

1. **Move the fact onto the object it describes** — a property of the things in
   a list belongs on those things, not in a second array beside them.
2. **Derive it** instead of storing it, when that is cheap enough.
3. **Fuse the structures**, when they only ever get used together.
4. Last resort: one collection of one small object with named fields.

The last one comes to mind first and is the weakest — it makes the coupling safe
instead of removing it. Collapsing properly usually turns up dead weight.

!!! note "The one exception"
    Struct-of-arrays for cache locality, which the storage layer is built on.
    That needs a benchmark and a comment saying so, and it never applies to
    boot-time structures.

## 11. Never dispatch on `is` to work out what the receiver is

```dart
// no — the type system reimplemented by hand, badly
final Object self = this;
if (self is GameState) return self.coroutines;
if (self is GameSystem) return self.state.coroutines;
throw StateError('...');
```

It compiles for a host it does not handle and fails at run time, it is invisible
to "find implementations", and every new host is an edit to a method in another
file. **The tell:** you are asking "what am I?" rather than "what can I do?".

The fix is to make the mixin state its requirement and let the hosts meet it —
an unimplemented mixin member becomes a requirement on the applying class, which
is exactly the constraint, checked by the compiler:

```dart
// yes
mixin Coroutines {
  @protected
  GameState get simulationState;          // hosts must supply it
  CoroutineScheduler get _scheduler => simulationState.coroutines;
}
```

`on` does **not** work here and neither does a marker interface: an `on` bound
is checked against the applying class's *superclass*, and none of the four hosts
has one that supplies a `GameState` — so every user would have had to write
`with Coroutines` by hand.

A pleasant side effect: applying a mixin with a private member twice is a
compile error, so a user who *also* writes `with Coroutines` is told, rather
than silently getting a second scheduler.

!!! info "Legitimate `is`"
    Narrowing a value whose type genuinely varies at run time (`yielded is num`,
    `listener is EventBus`), and `tryGet<T>`-style lookups that return null. The
    rule is about *dispatching on the receiver's own type*.

## 12. Everything is known at declaration time

No `addComponent`, no `removeComponent`, no archetype that changes shape. Declare
what an entity could need and **toggle** the parts that come and go. See
[Coming from Unity, Godot or Flutter](../guide/mental-model.md).

---

## Applying these to your own game

Most of your code is not hot, and the rules are not a style guide for menus and
save files. The set that matters day to day is short:

- [ ] Indexed `for` in `onFixedUpdate`, not `map`/`where`/`forEach`.
- [ ] Resolve components **per group**, not per entity.
- [ ] No `Vector2`, record, or list built per entity per tick.
- [ ] Do not keep `Input.value` for a `Vector2` past the tick — it is reused.
- [ ] Toggle flags instead of restructuring entities.
- [ ] Keep declaration passes pure and order-stable — both isolates run them.

See [Performance](../guide/performance.md) for measuring, and the traps that
make a benchmark lie.
