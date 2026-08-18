# Coming from Unity, Godot or Flutter

!!! abstract "Layer: kernel (`good`)"

good will feel familiar in its vocabulary — entities, components, systems,
scenes, prefabs, coroutines — and then surprise you in one specific way:

> **Everything is known at declaration time. Nothing is added or removed at
> run time.**

There is no `AddComponent`, no `RemoveComponent`, no `GetComponent<T>()` that
might return null because someone attached one this frame. A prefab's shape is
fixed the moment it is declared, and every entity of that prefab has exactly
that shape for its whole life.

**Instead of adding and removing, you declare everything up front and toggle it
on and off.**

This page is the translation table: the call you would have written, and the
one to write instead. For the layer underneath it — what happens to the habits
an entity-component developer has built, and worked answers to state machines,
cross-entity references and the rest — read
[Thinking in ECS](thinking-in-ecs.md).

## The translation table

| What you would do elsewhere | What you do in good |
|---|---|
| `gameObject.AddComponent<Shield>()` | Declare the shield's fields on the prefab; toggle `player.shielded[entity] = true` |
| `Destroy(GetComponent<Collider>())` | `collider.enable[entity] = false` |
| `renderer.enabled = false` | `sprite.visible[entity] = false` |
| `gameObject.SetActive(false)` | Turn off its parts, or `entity.destroy()` if it is really gone |
| `rigidbody.isKinematic = true` | `body.bodyType[entity] = BodyType2D.kinematicBody.index` |
| Attach a script at run time | Declare the system once; `state.disableSystem<S>()` when it should not run |
| `FindObjectsOfType<Enemy>()` | A `Query` declared once in `describeQuery` |
| A tag component added to mark state | A `bool`/`uint1` field on the entity, tested in the loop |
| `Instantiate(prefab)` | `scene.addEntity(prefab)` |
| `Destroy(gameObject)` | `entity.destroy()` — takes its whole subtree with it |
| `Dictionary<string, Thing>` lookups | A `late final` handle returned by a `describe*` pass |

## Why an entity cannot change shape

Three reasons, and they compound.

**Archetypes are storage.** An entity's components determine which native page
its row lives in and at what offset every field sits. Adding a component at run
time means moving the row to a different archetype — copying it, invalidating
every `Entity` handle that pointed at it, and forcing every compiled query to be
re-evaluated. Engines that offer it pay for it, usually as a structural-change
sync point. good does not offer it, so it does not pay.

**Both isolates must agree.** Archetype ids are assigned in first-registration
order and the [two copies of your `Game`](architecture.md#two-copies-of-one-object)
each run the same declarations to arrive at the same ids. A component added at
run time on one side would exist on one side only, and every `Entity` handle
crossing the boundary would resolve to a different layout.

**Toggling is free; restructuring is not.** `visible[entity] = false` is a
one-bit write in a row you were walking anyway. It costs nothing, it cannot
fail, and it cannot invalidate a handle.

## What toggles look like in practice

Every part of the engine that could plausibly be "attached and detached"
exposes an enable flag on the row instead:

```dart
// Rendering — the sprite still exists, it is just not drawn.
player.sprite.visible[entity] = false;

// Collision — the shape stays declared; the solver ignores it.
player.hitbox.enable[entity] = false;

// Trigger versus solid, per entity, at run time.
player.hitbox.isTrigger[entity] = true;

// Physics authority — a body can become static without being rebuilt.
player.bodyType[entity] = BodyType2D.staticBody.index;

// Whole systems, for a pause menu.
state.disableSystem<AiSystem>();
```

Invisible sprites are dropped before they ever become a draw record, and
disabled colliders never reach the solver — so an off toggle really is off, not
"processed and then skipped at the end".

### Your own optional behaviour

Do the same thing for gameplay. Declare the field, branch on it:

```dart
class Player extends EntityStruct with Transform2D, Renderable2D {
  late final DataPointer<bool> shielded;
  late final DataPointer<double> shieldEnergy;

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    shielded = data.hasBool(false);      // one bit
    shieldEnergy = data.hasFloat64(0);
  }
}
```

```dart
const double drainPerSecond = 12;

for (final entity in group) {
  if (!player.shielded[entity]) continue;
  final left = player.shieldEnergy[entity] - drainPerSecond * dt;
  player.shieldEnergy[entity] = left;
  if (left <= 0) player.shielded[entity] = false;   // toggle off, not remove
}
```

!!! question "Isn't that wasteful — every player carrying shield fields?"
    Usually not, and measurably so. `shielded` is one bit; `shieldEnergy` is
    eight bytes in a row you are already walking. The alternative — a separate
    archetype, or a side table keyed by entity — costs a lookup per access and a
    second structure to keep in step. When a variant is genuinely large and
    genuinely rare, that is what a **separate prefab** is for.

### When the difference is big: separate prefabs

`Bullet` and `HomingBullet` do not have to be one prefab with a flag. Two
prefabs are two archetypes, each with exactly the fields it needs, and a query
can match either or both:

```dart
homing = descriptor.query().withAll(Transform2D, HomingBullet).build();
allBullets = descriptor.query().withAny(Bullet, HomingBullet).build();
```

The rule of thumb: **a flag for a state an entity moves in and out of; a prefab
for a kind of thing it simply is.**

## Other expectations worth resetting

### Components are not objects with methods on instances

A `late final DataPointer<double> speed` is a **column**, and `speed[entity]` is
the row. There is one `Player` object in your game, not one per player. A plain
Dart field on a prefab is shared by every entity of that kind — see
[Entities and components](entities-and-components.md).

### There is no `Update()` per entity

Behaviour lives in systems that walk many entities at once, not in a method on
each entity. A prefab can carry lifecycle hooks for setup — `onEntityMounted`,
which it hears by mixing in `EntityLifecycleListener` — but the per-frame loop
belongs in a `GameSystem`. Those hooks are events, not virtual methods the
engine calls on your class; see [Events and listeners](events.md).

### `Start()`/`Awake()` ordering is explicit

Systems run in declaration order, adjusted by `compareTo`. There is no implicit
script execution order to discover.

### Gameplay does not run on the Flutter isolate

A button press does not call into your simulation. It sends a
[command](flutter-bridge.md#commands), which the game isolate handles on its own
tick. Numbers come back through [state channels](flutter-bridge.md#state-channels),
not through shared mutable objects.

### Coroutines are `sync*`, not `async`

`yield` returns control to the fixed step. `await` would resume on a microtask,
outside the tick window, and every component write after it would be silently
discarded. See [Coroutines](coroutines-and-animation.md).

### The engine avoids allocation, and asks you to as well

`.map`, `.where` and `.forEach` allocate a closure per call. In a method that
runs sixty times a second over thousands of entities, that is the whole budget.
Write the indexed `for` — see [Hot-path rules](../reference/rules.md).

## What you keep

Plenty carries over unchanged:

- **Prefabs and scenes** mean what you expect them to mean.
- **The hierarchy** is real: parent an entity and its world transform is
  composed, not copied.
- **Coroutines** read like Unity's `IEnumerator` — because they are the same
  idea, for the same reason.
- **Fixed timestep** is `FixedUpdate`, and physics runs in it.
- **Flutter is your UI layer**, in full, and that is the recommended way to
  build one: your HUD, menus and overlays are ordinary widgets over the game
  surface. Put UI *in* the game only when it is as interactive as the game —
  see [Where your UI belongs](flutter-bridge.md#where-your-ui-belongs).

---

## Next

[Architecture →](architecture.md)
