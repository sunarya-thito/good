# Entities and components

<!-- snippet-scope
late DataPointer<double> velocityX;
late DataPointer<double> life;
late Entity enemy;
late Entity player;
late EntityStruct limb;
late Entity body;
-->

!!! abstract "Layer: kernel (`good`)"

This is the page to read slowly. good's storage model is the thing most unlike
an object-oriented engine, and everything else follows from it.

A column has to hold something, so the examples build 2D things. `Transform2D`,
`Renderable2D` and `Collider2D` come from `goo2d`; the storage model underneath
them is the kernel's and is the same either way. For the 3D components see
[Transforms and hierarchy (3D)](3d/transforms.md).

## An `EntityStruct` is a layout, not an object

```dart
class Bullet extends EntityStruct with Transform2D, Renderable2D {
  final velocityX = Field.float64();
  final velocityY = Field.float64();
  final life = Field.float64(3.0);   // default for every new row
}
```

There is **one `Bullet` instance** in your whole game, no matter how many
bullets exist. It is the *declaration*: it says that a bullet's row has three
doubles beyond what its mixins contribute, and it hands you a handle to each
column.

`velocityX` is a **column**. `Entity` is the **row index**:

```dart
velocityX[entity] = 12.0;          // write row `entity`, column velocityX
final v = velocityX[entity];       // read it back (published snapshot)
```

!!! danger "Never store per-entity state as a Dart field"
    ```dart
    class Bullet extends EntityStruct {
      double speed = 0;   // WRONG — one value shared by every bullet
    }
    ```
    The prefab is shared. A plain field is a global. Per-entity state is always
    a `DataPointer`.

    A plain field *is* fine for declare-time constants and for scratch state a
    system owns — the example demos use `int _spawned = 0` on a prefab as a
    spawn counter, which is per-prefab and intentional.

### What the layout buys you

Rows of the same archetype are contiguous in one native page, so a system
walking every bullet's `velocityX` walks memory in order — the cache behaviour
struct-of-arrays exists for. And because a column is an `int` address plus an
offset, not a `dart:ffi` `Pointer` object, indexing it allocates nothing.

## `Entity`

An `extension type` over `int`, packing three things:

<!-- snippet: skip a sketch of Entity, whose real declaration is the kernel's -->
```dart
extension type const Entity(int value) implements int {
  int get archetypeId;
  int get pageIndex;
  // + row offset
}
```

Passing one around costs an `int`. It is also self-describing — given only the
integer, the engine finds the archetype, the page, and the row.

```dart
final transform = entity.get<Transform2D>();      // throws if absent
final child = entity.tryGet<Child>();             // null if absent
entity.destroy();                                 // removes it and its subtree
```

`get<T>()` resolves the *prefab* that declared the archetype, which is why it
returns the component with all its columns bound to that archetype's layout.

!!! warning "Resolve components per group, not per entity"
    `entity.get<T>()` is a registry lookup. In a loop over thousands of
    entities, resolve once per group and index by entity inside:

    ```dart
    for (final group in query.groups()) {
      final transform = group.get<Transform2D>();   // once per archetype
      for (final entity in group) {
        transform.transformOffsetX[entity] += 1;    // just an indexed write
      }
    }
    ```

## Components

A `Component` is a mixin on an `EntityStruct`. It contributes two things: a
**queryable type** and some **columns**.

```dart
mixin Health on Component {
  final hp = Field.int32(100);
  final maxHp = Field.int32(100);

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Health>();          // (1)!
  }
}
```

1. This is what makes `withAll(Health)` match. A mixin that declares columns but
   not its type contributes storage without being queryable.

Mix it in, and the archetype gains those columns:

```dart
class Enemy() extends EntityStruct with Transform2D, Renderable2D, Health;
```

`describeType` must call `super` — each mixin in the chain contributes, and
skipping `super` silently drops everything below it. Columns declared as fields
need no such discipline: Dart runs every initialiser in the chain itself.

!!! warning "Field names collide across mixins"
    A component is a mixin, so two of them declaring a field called `speed` is
    not an error in Dart. It is an override: the later mixin in the `with`
    clause wins, the row grows by both columns, and the earlier one's column can
    no longer be reached under that name. Nothing reports it — not the analyzer,
    not the engine.

    Pick names that will not collide. `Transform2D` calls its position columns
    `transformOffsetX` and `transformOffsetY`, and a component you publish for
    other people to mix in wants the same kind of prefix.

### Multi-components

Some components are declared through their own descriptor instead of by
contributing fields directly — `Renderable2D` (sprites) and `Collider2D`
(shapes) are `on MultiComponent`, which lets one entity declare several sprites
or several collider shapes. You use them the same way; the difference is the
extra `describeSprites`/`describeCollider` pass.

## Field kinds

`Field` offers a wide set because packing matters — a flag that takes one bit
instead of eight is 7 bits per entity per frame of bandwidth saved.

| Call | Column type | Notes |
|---|---|---|
| `Field.boolean()` | `bool` | one bit |
| `Field.uint1/2/4()`, `Field.int1/2/4()` | `int` | sub-byte, for small counters and packed bits |
| `Field.uint8/16/32/64()`, `Field.int8/16/32/64()` | `int` | |
| `Field.entity()` | `Entity` | a handle to another entity, 64 bits — see [storing a handle](thinking-in-ecs.md#storing-a-handle-in-a-column) |
| `Field.optEntity([default])` | `Entity?` | the same handle, or `null` for no target — a presence bit ahead of the 64 |
| `Field.enumOf(values, [default])` | `E` | the member's index, in the narrowest column its `values` fit — two bits for four members |
| `Field.float32()`, `Field.float64()` | `double` | `Transform2D` uses float64 |
| `Field.packed<T>(table, [default])` | `T` | a value with an `int` representation |
| `Field.optPacked<T>(table, [default])` | `T?` | nullable packed — how `Sprite.texture` and `Camera.view` are stored |
| `Field.heapObject<T>()` / `Field.optHeapObject<T>()` | `T` / `T?` | an arbitrary Dart object, by registry address |
| `Field.*Array(length, [default])` | `DataArrayPointer<T>` | fixed-length inline array |

`Field.boolean` and not `Field.bool`, and `Field` and not `Column`: `bool` is a
type and `Column` is a Flutter widget, and neither name can be reused without
breaking the file that uses it.

Every one takes an optional **default**, which is what a freshly allocated row
starts at:

```dart
final scale = Field.float64(1);   // not 0 — a zero scale is a degenerate transform
```

!!! tip "Choose the default carefully"
    `Transform2D` defaults scale to `1` and offset/rotation to `0`, because `0`
    *is* the identity for the latter two and is a collapse-to-nothing for the
    first. A wrong default shows up as an entity that is invisible or at the
    origin with nothing anywhere saying why.

### Heap objects

`Field.heapObject<T>()` stores an arbitrary Dart object by address in a
registry. It is the unconstrained escape hatch, and it does not cross the
isolate boundary meaningfully — the address means something only in the isolate
that registered it. Prefer `Field.packed` for anything the other side has to
read.

## Helpers go on an accessor

`Health` gives you `hp` and `maxHp` and nothing that *does* anything with them.
Methods like `damage` and `isDead` do not go on the mixin. They go on an
extension of `Accessor<Health>`:

```dart
extension HealthAccessor on Accessor<Health> {
  void damage(int amount) {
    final health = component;
    health.hp[this] = health.hp[this] - amount;
  }

  bool get isDead => component.hp[this] <= 0;
}
```

You reach them through the entity:

```dart
enemy<Health>().damage(25);
if (enemy<Health>().isDead) enemy.destroy();
```

That is a call and not an index, because an operator cannot be generic:
`enemy[Health]` could only ever be typed `Null`.

The convention is the whole of it — name the extension `<Component>Accessor`
and hang it on `Accessor<YourComponent>`.

### Inside the extension, `this` is the entity

`Accessor<T>` implements `Entity`, so `this` is the row index and a column takes
it directly. `component` is the `Health` the receiver's archetype declared,
sugar for `get<Health>()` — an inlined list index and a type check, not a map,
so reaching for it twice is a style question and not a cost.

The rest of `Entity` is there too:

```dart
extension HealthAccessor on Accessor<Health> {
  void kill() {
    component.hp[this] = 0;
    destroy();
  }
}
```

and an accessor goes anywhere an entity is wanted:

<!-- snippet: skip calls drain, which the fence below declares -->
```dart
final target = enemy<Health>();
player<Health>().drain(target, 5);
```

A helper that takes a *second* entity resolves that one's component itself:

```dart
extension HealthAccessor on Accessor<Health> {
  void drain(Entity other, int amount) {
    final mine = component;
    final theirs = other.get<Health>();
    theirs.hp[other] -= amount;
    mine.hp[this] += amount;
  }
}
```

`other` may be a different prefab with a different row layout, and only the
receiver is guaranteed to be this one. `mine.hp[other]` compiles, and reads
*this* archetype's storage at the other entity's page and row — some unrelated
entity's health, or nothing at all.

### Two components can want the same method name

`Accessor<Health>` and `Accessor<Transform3D>` are different types, so both can
declare `distanceTo` and a file importing both still compiles. Two mixins
declaring it collide.

A method on the mixin also has to take the entity as an argument, because the
`Health` it would run on is the prefab, one for the whole archetype, and belongs
to no row in particular. Once two entities are in the signature, nothing in it
says which one the receiver is about.

None of this costs anything. `Accessor<T>` is an extension type over `Entity`,
which is an extension type over `int`, so reaching a helper allocates nothing and
`identical(enemy<Health>().entity, enemy)` is true.

## An archetype never changes

There is **no `addComponent` and no `removeComponent`**. A prefab's shape is
fixed when it is declared, and every entity of that prefab keeps that shape for
its whole life.

<!-- snippet: skip shows an API that does not exist -->
```dart
entity.addComponent(Shield());     // does not exist, and will not
```

Instead, declare everything the entity could ever need and **toggle** the parts
that come and go:

<!-- snippet-setup
final player = given<Player>();
-->
```dart
player.sprite.visible[entity] = false;    // stop drawing it
player.hitbox.enable[entity] = false;     // stop colliding
player.shielded[entity] = true;           // your own bool field
```

If you are arriving from Unity, Godot or Flame, read
[Coming from Unity, Godot or Flutter](mental-model.md) — it is the full
translation table and explains why the engine is strict about this.

## Archetypes

The set of components an `EntityStruct` mixes in *is* its archetype. Two prefabs
with the same components are still two archetypes — identity comes from the
declaration, not from the component set — and each gets its own contiguous
storage.

Archetype ids are process-global and assigned in first-registration order, which
is why [declaration order must be stable](architecture.md#how-both-copies-agree-without-negotiating)
and why scenes are declared once and loaded many times instead of registered
per load.

## Lifecycle hooks

Mix in `EntityLifecycleListener` to run code when a row is created:

```dart
class Bullet extends EntityStruct
    with Transform2D, Renderable2D, EntityLifecycleListener {
  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    life[entity] = 3.0;
    velocityX[entity] = 400;
  }
}
```

!!! warning "An entity must be *finished* when it is mounted"
    Not finished by the first system pass that happens to see it. If your update
    loop derives a transform from an angle, write that transform at mount too,
    with the same expression. Leaving it at the default for one frame is exactly
    how an entity appears to snap or flash at the origin on its second frame.

The mixin is what makes it work, and not as a formality. `onEntityMounted` is
an event: `EntityStruct` declares a dispatcher for it, and the boot pass
collects your prefab into that dispatcher because it is an
`EntityLifecycleListener`. Leave the mixin off and the override compiles, is
never collected, and never runs. Call `super` for the same reason you do in
`describeType` — another mixin on the same prefab may override the same hook.

Related mixins: `EntitySpawnListener` (a broad "something spawned" signal, which
is what the physics system listens to), `SceneLifecycleListener`,
`SceneLoadListener`, `GameLifecycleListener`, `GameSystemLifecycleListener`.
[Events and listeners](events.md) covers how all of them are delivered, and how
to declare one of your own.

## Same-tick reads

An ordinary read returns the **last published snapshot**, not what you wrote a
moment ago in the same tick. That is correct and deliberate — see
[the tick phases](architecture.md#phases-within-one-advance) — but it has one
sharp consequence worth knowing:

```dart
// Three children added in one tick.
for (var i = 0; i < 3; i++) {
  scene.addEntity(limb, parent: body);
}
```

`addChild` reads the tail of the child chain to append to it. Three
`addChild` calls in one tick would each read the same stale tail, orphaning all
but the last. The hierarchy code reads the pending slot for exactly this reason.
If you write a linked structure across component rows yourself, you will meet
the same problem — and the fix is placement (a later phase), not a second read
method.

---

## Next

[Scenes and prefabs →](scenes.md)
