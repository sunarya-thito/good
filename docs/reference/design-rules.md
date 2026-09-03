# Engine design rules

<!-- snippet-scope
late Transform2D transform;
late Entity a;
late Entity b;
late Entity child;
late Entity parent;
-->

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

`DataPointer.readPending` is the one variant in the engine, and it is the
exception this rule is written around rather than a counter-example to it. A
structural mutation reads back the structure it is itself editing inside one
call: `Parent.addChild` needs the `parentLastChild` the previous `addChild`
wrote a moment ago, and no later phase exists to move that into. Three column
kinds implement it — `float64`, `optInt64`, `optEntity` — and every other
throws, so the second read path cannot spread past the callers that need it.
A system reading uncommitted state is still what the rule forbids.

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

<!-- snippet: skip shows the shapes the rule rejects -->
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
```

`Accessor<T> implements Entity`, so inside the extension `this` **is** the
entity: `component.healthHp[this]` indexes a column directly, and the accessor
can be passed anywhere an `Entity` is wanted. It costs nothing — `Accessor<T>`
erases to `Entity`, which erases to `int`.

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

## A property is for one entity, a column is for many

A property per `Field` on the accessor — `transform.offsetX = 10.0` on
`Accessor<Transform2D>` — is the shape someone arriving from Unity already has:
`entity.transform`, then fields on it. Easing that move is a goal here, so code
that touches one entity gets to write it that way.

Engine code does not, and neither does a system walking many entities. Both
resolve the component once per group and index the column:

```dart
// no - a property per entity, inside a loop over a group
for (final entity in group) {
  entity<Transform2D>().offsetX += 1;
}
```

```dart
// yes - resolve once per group, and the write is an index
for (final group in query.groups()) {
  final transform = group<Transform2D>();
  for (final entity in group) {
    transform.transformOffsetX[entity] += 1;
  }
}
```

Unity DOTS puts the line in the same place, between
`EntityManager.GetComponentData<T>` and `ComponentLookup` with chunk iteration,
and states which is meant for which. State it here too, or the property turns up
in a loop over 20,000 entities with nothing to point at.

**Hoisting the accessor does not hoist the lookup.** `Accessor<T>` carries only
the entity and erases to an `int`, so `component` resolves again on every
access: three property lines are three resolutions. Each one is a bounds-checked
list index behind `@pragma('vm:prefer-inline')` and an `is` check. For one
entity that is noise. Run it per entity in a loop and it is what *Resolve
components per group, not per entity* in
[Entities and components](../guide/entities-and-components.md) is about.

**A property performs one read.** `column[entity]` reads the published snapshot
and `column.readPending(entity)` reads the write slot, so a property can only be
the first of those. It never answers "what did I write earlier in this tick" —
`addChild` needs the pending `parentLastChild`, and a prefab's declared
children need the pending slot on the tick they mount. Those cases index the
column, and
[Same-tick reads](../guide/entities-and-components.md#same-tick-reads) covers
why the fix is usually to move the reader into a later phase instead.

**The names come out better.** A column carries its component's prefix,
`transformOffsetX`, because two mixins both declaring `x` on one prefab is a
silent two-column bug. `Accessor<Transform2D>` is its own type with nothing to
collide with, so the property is `offsetX`: shorter and safer at once.

An operation still beats a run of properties. `setEuler(yaw: 0.5)` is one
resolve and four writes, `offset = (10, 20, 30)` is one idea instead of three,
and `upZ` names something no column holds:

```dart
// yes
entity<Transform3D>().setEuler(yaw: 0.5);   // one lookup, four writes
entity<Transform3D>().distanceTo(target);
entity<Transform3D>().upZ;
```

!!! info "Nobody writes the properties by hand"
    `good_tool` writes them, into `lib/src/accessors.g.dart` inside each engine
    package, and the result is committed and shipped — so they arrive with
    `package:goo2d/goo2d.dart` and there is nothing for you to run.
    `Transform3D` alone is ten columns and so twenty members, and the tree holds
    128 `Field` declarations; a couple of hundred members held in step by memory
    is *One fact, one place* undone.

    It is a **parse** of the `Field.*` declarations, and that is the whole of
    what it needs: a property calls through the existing `DataPointer`, so it
    wants the column's name and its type, both of which are written in the
    source. It is emphatically *not* the pass that computes the row layout,
    which no scan can be — a byte offset is the running total of a
    `declareField` sequence that depends on values only available at run time.
    `Text2D.describeStruct` reads `textCapacity`, an overridable getter;
    `SpriteDescriptor.has` declares twenty-one columns per call and prefabs
    override `describeSprites`; `hasEnum` widens by `values.length`. Offsets are
    unobtainable and are not wanted here.

    What it cannot generate for, it leaves alone, and the omission is a compile
    error at the use site rather than a wrong read: an array column, a private
    one, a column whose type the generated file cannot name. The single
    exception is a column whose property name is already a member of `Accessor`,
    `Entity` or `int` — `sign`, `component`, `sceneSlot`. A Dart extension member
    loses to one the receiver already has, so that property would compile, never
    be reached, and quietly answer about the entity handle. The tool refuses and
    names the column.

!!! warning "Your own components do not get these"
    Only the engine's do. The generator runs over this repository and writes
    into packages that are published from it; a component in your game's `lib/`
    is in neither, and nothing in `good_cli` generates properties into your
    project. Index the column — `transform.transformOffsetX[entity]` — or write
    the accessor extension by hand, which is the shape `Accessor`'s own
    documentation describes:

    <!-- snippet: skip declares a component the surrounding page does not -->
    ```dart
    extension HealthAccessor on Accessor<Health> {
      int get hp => component.healthHp[this];
      set hp(int value) => component.healthHp[this] = value;
    }
    ```

    Doing it by hand is the thing *One fact, one place* warns about, which is
    why the engine's own are generated. Making it unnecessary for a game's
    components is a separate design and is not solved here.

## A unit belongs in the type, not in the name

A parameter that carries a quantity is named for what it **is**. The unit is
the type's job:

<!-- snippet: skip two signatures, not calls -->
```dart
void cast(double xTaskInSeconds) {}   // no
void cast(Seconds xTaskDuration) {}   // yes
```

`xTaskInSeconds: 10` reads at the call site as `cast(10)`, and the reader has
to open the signature to learn what `10` is. A bare number forces the unit into
the parameter name, where nothing checks it and a caller who never types the
name never sees it. `Seconds` puts it in front of the number itself —
`cast(Seconds(10))` — and the analyzer refuses a bare `10` in its place.

The type is an extension type over the storage, so this costs nothing: see
`Seconds` in `time.dart` and rule 1.

## A component's columns carry the component's name

`Transform2D` declares `transformOffsetX`, not `offsetX`. `Child` declares
`childParent`, not `parent`. Every component prefixes its columns with a stem
taken from its own type — a readable one, not the type name itself, and
without a dimension suffix, because `Transform2D` and `Transform3D` are never
on the same entity and `transform2dOffsetX` reads badly.

| component | stem | columns |
|---|---|---|
| `Transform2D` | `transform` | `transformOffsetX`, `transformRotation` |
| `WorldTransform2D` | `world` | `worldX`, `worldScaleY` |
| `Child` | `child` | `childParent`, `childNextSibling` |
| `Parent` | `parent` | `parentFirstChild`, `parentLastChild` |
| `Camera`, `Camera3D` | `camera` | `cameraZoom`, `cameraNear` |
| `RigidBody2D` | `body` | `bodyType`, `bodyLinearVelocityX` |

A component is a mixin, so every component on an entity puts its columns in
**one namespace**. Two of them declaring `speed` is not an error in Dart, it is
an override: the last mixin in the `with` clause wins, the row grows by both
columns, and writes aimed at the hidden one land on its neighbour. Since #57
made field initialisers eager there is nothing at run time to notice it — no
throw, no assert, and a debugger showing a plausible number in the wrong column.

The prefix is prevention. `good generate`'s shadow check (#100) is detection,
and it catches what predates the rule or arrives from a package that never
followed it; the two are not alternatives. The prefix is also the only half of
it that reaches a third-party component author, who will not run this
repository's checker over their own package.

This applies to a **component**. A prefab's own columns — `final speed =
Field.float64(220)` on a `Player` — are the leaf of the chain and nothing
mixes into them, so they stay unprefixed.

!!! note "The accessor is where the short name goes"
    `childParent` reads badly on purpose: it is storage, and storage is shared.
    An accessor is per-component and has its own namespace, so the readable
    spelling belongs there (#99) — `entity<Child>().parentOf` over a column
    called `childParent`. Renaming the column is what makes that possible; it
    is not an argument for leaving the column short.

## Never dispatch on `is` to work out what the receiver is

<!-- snippet: skip shows the shape the rule rejects -->
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
    `listener is EventBus`), and `entity.has<T>()`, which is that same test
    against the archetype prefab. The rule is about *dispatching on the
    receiver's own type*.

## Nothing is resolved by name

A key is a reference: a field, a tear-off, a type, a handle. Never a `String`,
and never a name that has to match something declared somewhere else.

Whatever a `describe*` pass produces comes back typed, and the caller keeps it in
a field. No `Map<String, ...>` the framework searches at use time, and no integer
index into a table you keep in step by hand. That covers buffers, state channels,
inputs, coroutines and colliders — every `describe*`.

A name used as a key is unanalyzable. `'chsae'` compiles, passes review, and
fails at run time with an error naming the string instead of the mistake. A
reference makes the compiler reject the typo. It makes rename work, it makes
go-to-definition work, and it turns a dead entry into something the analyzer
finds before a player does.

Here is the shape, from `Transitions` in #115 — real, unbuilt, and drafted with
string keys during the months this rule was not written down:

<!-- snippet: skip shows the shape the rule rejects, against an unbuilt API -->
```dart
// no
final transitions = Transitions.from({
  'patrol': ['chase', 'flee'],
});

// yes — the nodes are already fields
final transitions = Transitions.from({
  patrol: [chase, flee],
});
```

The distinction that keeps this usable is between *resolving* and *displaying*.
Resolving by name is what the rule forbids: any map keyed by a name that has to
match a declaration elsewhere. Carrying a name for display is fine — an
inspector label, a debug-draw caption, a log line. So a state node may hold a
label. Nothing may look a node up by that label. When you are unsure which side
you are on, ask whether some Dart declaration has to be spelled the same way for
the code to work.

!!! note "A label cannot be inferred"
    Nothing on the declaration path sees a Dart field name. The runtime watches
    an anonymous object register itself against the open descriptor, and the
    identifier `patrol` never reaches it — which is why a label has to be passed
    if it is wanted at all. That is the same fact that moved #58's shadowed-field
    check out of the runtime and into the analyzer, so a check that a label
    matches the field holding it belongs beside it, in
    `packages/good_cli/lib/src/generate/struct_scan.dart`.

## AOT-compile any benchmark that would change code

`flutter test` runs the JIT. Two write-path costs measured that way came out
wrong by roughly 100x, and what was tuned against them was tuned for a compiler
nobody ships.

```bash
dart compile exe bench/my_bench.dart -o build/my_bench
./build/my_bench
```

Prefer a real device over a desktop for anything the frame budget depends on.

## A benchmark must be able to fail

Two benches here reported "flat" — no effect — because their setup had made the
effect unobservable. A negative result is worth something only if the same
harness could have produced a positive one, so turn the optimisation off and
watch the number move before you believe it did not.

The same trap wearing a different hat: whole-step totals reset once per
`advance` and accumulate over every fixed step inside it, while one system's
timing is a single step. The moment an advance costs more than one step, those
two stop sharing a denominator. A recording here read as a catastrophic
super-linear blowup and was entirely this.

## A change to what a command or an API does updates `Unreleased` with it

In the same commit, under `## Unreleased` in the `CHANGELOG.md` of the package
it affects, and saying what someone upgrading has to do about it.

Doing it at release time means reading every commit since the last tag and
working out user-visible effect from a diff that also touches tests and docs.
That is how a breaking change gets missed: not because anyone decided to leave
it out, but because it did not look like one in the diff. Six changes to what
`good_cli`'s commands do went unrecorded between `0.1.1` and the pass that
reconstructed them, and every one of the six turns a build that worked into a
build that fails.

Three weeks later nobody remembers which commits were user-visible. The commit
making the change is the only place that knowledge exists while it is still
reliable.

## Every commit names its issue

The subject ends with a trailing `(#N)`.

```
Give each loaded scene its own Box2D world (#106)
Refuse to strip an asset compaction cannot rebuild (#136)
```

Of the sixty commits before this rule, twelve referenced an issue somewhere in
the body and not one did in a subject. So `git log --oneline` — the view anyone
actually reads — could not tell you what a single one of them was for. It gives
you the what and never the why, and the why sits in a tracker the log offers no
route to.

Use a bare `(#N)`. No `Closes`, no `Fixes`: those cross-link *and* close, and
closing is not the commit's to do. An issue here is closed deliberately, with a
comment carrying the evidence and the test counts, and GitHub's auto-close fires
on push — which on this repo is rare and batched. A keyword would shut a stack of
issues at once, silently, on the schedule of whoever happened to push, and throw
that record away.

If a change has no issue, file one before you commit. The exception is pure
mechanics with no design content — a formatting sweep, a revert — which should
say so plainly instead of inventing an issue to point at.

