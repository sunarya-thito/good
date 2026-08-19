# Engine design rules

These are for working on the engine itself. They are not about the per-frame
path — see [Hot-path rules](rules.md) for that — they are about keeping the
codebase from acquiring the kind of structure that rots. Each one is here
because it was violated first and cost something.

---

## Never `print` to report a framework problem

Including through `assert(() { print(...); return true; }())`. It is swallowed
in release and invisible in test output. Use `assert(false, 'message')`.

## Do not add a specialised variant to escape a constraint

If `operator[]` reads the published snapshot and you want the uncommitted one,
the answer is **not** a `readPending()` beside it. A second read path means
every later reader has to know which one is right here, and the first one stops
guaranteeing anything.

Fix the *placement* instead: a value that must be read after it is written
belongs in a later phase. Unity DOTS does this by running
`PresentationSystemGroup` after `SimulationSystemGroup` over the same
`LocalToWorld`. Same here — `WorldTransformSystem` writes during the fixed tick,
and consumers run after it commits.

## One fact, one place

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

The last one comes to mind first and is the weakest, because it makes the
coupling safe instead of removing it. Collapsing properly usually turns up dead
weight: `_EventDescriptor` held three lists in lockstep, and fusing them showed
two were the same decision and the third was never read.

!!! note "The one exception"
    Struct-of-arrays for cache locality, which the storage layer is built on.
    That needs a benchmark and a comment saying so, and it never applies to
    boot-time structures.

## A method that acts on one entity belongs on that component's accessor

A component mixin is **one instance for the whole archetype**. It describes the
layout; it is not any particular entity. So a method on it that does something
to an entity has to be handed the entity, and both spellings of that are wrong:

```dart
// no - the prefab is the receiver and the subject is an argument
transform.distanceTo(a, b);
parent.addChild(self, child);
body.applyImpulse(entity, ix, iy);

// also no - component-specific behaviour on bare Entity
extension Transform2DEntity on Entity {
  double distanceTo(Entity other) { ... }
}
```

**The tell:** the signature needs an `Entity` parameter to say *which entity
this is about*. If removing that parameter would leave the method unable to name
its subject, the subject should have been the receiver.

The fix is an extension on `Accessor<T>`, named `<Component>Accessor`:

```dart
// yes
extension Transform2DAccessor on Accessor<Transform2D> {
  double distanceTo(Entity other) {
    final t = component;
    ...
  }
}

a<Transform2D>().distanceTo(b);
parent<Parent>().addChild(child);
entity<RigidBody2D>().applyImpulse(ix, iy);
```

`Accessor<T> implements Entity`, so inside the extension `this` **is** the
entity: `component.hp[this]` indexes a column directly, and the accessor can be
passed anywhere an `Entity` is wanted. It costs nothing — `Accessor<T>` erases
to `Entity`, which erases to `int`.

Two things this buys that the first spelling cannot:

- **A helper can no longer be called through the wrong prefab.** A component
  instance is bound to one archetype's row layout. `crate.setPivot(orcEntity,
  …)` type-checks, and either reads the wrong storage or is silently repaired by
  a defensive re-resolve. With the entity as receiver there is nothing to
  mismatch.
- **Two components can want the same name.** `Accessor<Transform2D>` and
  `Accessor<Collider2D>` are different types, so both can declare `distanceTo` —
  centre to centre and surface to surface — and a file importing both compiles.
  The bare-`Entity` extension gives `ambiguous_extension_member_access` instead,
  and "don't import both" is no answer when they are in one package.

!!! info "What stays where it is"
    - **Declaration hooks.** `describeType`, `describeStruct`, `describeSprites`
      and `describeCollider` act on the *archetype*, take no entity, and belong
      on the mixin. That is the same test, answered the other way, and it is
      why `EntityStruct.of` returns a prefab rather than something per-entity.
    - **Listener callbacks.** `onEntityMounted`, `onEntitySpawned` and their
      unmount halves take an `Entity` as the event's *payload*, not as the
      receiver's subject. A broadcast listener is asking to be told about
      entities that are not its own.
    - **Additional entities.** Only the subject moves to the receiver.
      `distanceTo(Entity other)` and `lookAtEntity(Entity target)` keep their
      argument, and must resolve that one's component themselves — it may be a
      different archetype with a different layout.
    - **Private helpers inside a system.** `_composeRoot(entity, …)` is a
      system's own working code, not a component's API.

## Never dispatch on `is` to work out what the receiver is

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

The fix is to make the mixin state its requirement and let the hosts meet it. An
unimplemented mixin member becomes a requirement on the applying class, which is
exactly the constraint, checked by the compiler:

```dart
// yes
mixin Coroutines {
  @protected
  GameState get simulationState;          // hosts must supply it
  CoroutineScheduler get _scheduler => simulationState.coroutines;
}
```

`on` does **not** work here and neither does a marker interface: an `on` bound is
checked against the applying class's *superclass*, and none of the four hosts has
one that supplies a `GameState` — so every user would have had to write
`with Coroutines` by hand.

A pleasant side effect: applying a mixin with a private member twice is a compile
error, so a user who *also* writes `with Coroutines` is told, rather than
silently getting a second scheduler.

!!! info "Legitimate `is`"
    Narrowing a value whose type genuinely varies at run time (`yielded is num`,
    `listener is EventBus`), and `tryGet<T>`-style lookups that return null. The
    rule is about *dispatching on the receiver's own type*.
