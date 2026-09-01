# Systems and queries

<!-- snippet-scope
// The component the movement example walks, and the systems the enable /
// disable example names.
mixin Velocity on Component {
  final velocityX = Field.float64();
  final velocityY = Field.float64();

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Velocity>();
  }
}

class AiSystem extends GameSystem {}

class SpawnSystem extends GameSystem {}
-->

!!! abstract "Layer: kernel (`good`)"

A `GameSystem` is where per-tick work lives. It declares its queries once and
walks the matching rows every step.

```dart
class MovementSystem extends GameSystem with FixedTickable {
  final movers = Query.where()
      .withAll(Transform2D, Velocity)
      .withNone(Child)            // roots only; parented movers follow theirs
      .build();

  @override
  void onFixedUpdate() {
    final dt = game.fixedTimeStep.inMicroseconds / 1000000.0;
    for (final group in movers.groups()) {
      final transform = group<Transform2D>();
      final velocity = group<Velocity>();
      for (final entity in group) {
        transform
          ..transformOffsetX[entity] += velocity.velocityX[entity] * dt
          ..transformOffsetY[entity] += velocity.velocityY[entity] * dt;
      }
    }
  }
}
```

Declare it on the **state**, because a system exists only on the isolate that
ticks it:

```dart
class MyState extends GameState2D<MyGame> {
  int score = 0;

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(MovementSystem.new);
  }
}
```

Calling `super` matters — `GameState2D` declares the renderer and the world
transform system there.

## Two tick mixins

| Mixin | Called | Use for |
|---|---|---|
| `FixedTickable` | `onFixedUpdate()`, once per fixed step | Gameplay, physics, anything that writes component data |
| `Tickable` | `onTick(Duration delta)`, once per presentation pass | Reading finished results — publishing to the UI, rendering |

### Choosing between them

One question settles almost every case: **does this system write component
data?** If it does, it is `FixedTickable`, and there is no judgement call to
make. `onFixedUpdate` runs inside the tick window, between `beginTick` and
`commitTick`, and that window is the only place a component write survives —
the next `beginTick` copies the published snapshot over the write slot, so
anything written outside it is gone before anyone reads it.

If instead the system takes what the simulation finished and sends it somewhere
else — a score into a state channel, a transform into the renderer, a position
into an audio backend — it is `Tickable`. `onTick` runs after `commitTick`, so
it reads the snapshot the step just published, including everything derived
during that step.

Three details decide the rest.

**They do not run the same number of times.** One `advance` spends whatever
wall-clock time has accumulated in whole fixed steps, up to
`maxFixedStepsPerAdvance`, then presents once. So a stuttering frame can run
three `onFixedUpdate` calls and exactly one `onTick`, and a frame that afforded
no step at all still gets its `onTick` — which is what lets a camera keep easing
toward its target on a frame where nothing simulated.

**Only one of them gets a delta.** `onFixedUpdate` takes no argument because
the answer is always `game.fixedTimeStep`; anything integrating over time wants
that fixed number, since a variable one makes the same input produce different
results on different machines. `onTick` is handed the wall-clock `Duration`
since the previous presentation pass, which is the right input for something
smoothing on screen and the wrong input for anything the simulation has to
reproduce.

**Presentation is not stale.** Moving a system out of the fixed step costs no
freshness. During step N a `FixedTickable` reads state as of the end of N-1; a
`Tickable` running after N commits reads values derived during N from that same
end-of-N-1 state. One frame of latency either way, so a renderer belongs in
presentation and stops recomputing what the simulation already worked out.

The one that catches people out is publishing timings. Phase totals are only
complete once the fixed step has returned, so a system reporting them from
inside `onFixedUpdate` publishes a half-accumulated figure — a number that is
wrong and looks plausible.

```dart
class HudPublisher extends GameSystem with Tickable {
  @override
  void onTick(Duration delta) {
    getGame<MyGame>().score.value = getState<MyState>().score;
  }
}
```

Nothing stops one system mixing in both, and a few want to: read input and move
things in `onFixedUpdate`, publish what happened in `onTick`. Splitting it into
two systems is usually clearer, and costs nothing either way.

The full order of what happens inside one `advance` is in
[Architecture](architecture.md#phases-within-one-advance).

## Building queries

`descriptor.query()` returns a builder. Every clause is repeatable and the
result is compiled **once** into an archetype match — nothing searches at tick
time.

| Clause | Meaning |
|---|---|
| `.withAll(A, B, ...)` | Every listed component must be present |
| `.withNone(A, B, ...)` | Every listed component must be absent |
| `.withAny(A, B, ...)` | At least one of the listed must be present |
| `.withOptional(A, ...)` | Documentation only — does not narrow the match |
| `.build()` | Compiles it. Call once |

Each clause takes up to ten types.

!!! info "`withAny` groups per call"
    `.withAny(A, B).withAny(C, D)` means **(A or B) and (C or D)** — each call
    is its own group and every group must be satisfied. It is not one flat
    "any of these four".

`withOptional` narrows nothing; it signals to the reader that the loop body
branches on whether an entity has the component. `WorldTransformSystem` is the
reference usage: it matches every `Transform2D` entity, hierarchy-linked or
not, and asks `entity.has<Child>()` inside.

## Walking results

```dart
for (final group in query.groups()) {      // one group per matching archetype
  final transform = group<Transform2D>();   // resolved once for the group
  for (final entity in group) {
    transform.transformOffsetX[entity] += 1;
  }
}
```

The two-level shape is the point. `group<T>()` resolves that archetype's
component **once**; the inner loop is then pure indexed access. Resolving inside
the inner loop repeats a registry lookup per entity, which is the single most
common performance mistake in a good system.

`query.run()` yields entities directly when you do not need per-group resolution
— fine for a handful of entities like cameras, wasteful for thousands.

!!! danger "No closures in a system tick"
    `.map`, `.where`, `.any`, `.fold` and `.forEach` allocate a closure per
    call, and usually an `Iterable` too. Write the indexed `for`. See
    [Hot-path rules](../reference/rules.md).

## Ordering systems

By default systems run in declaration order. When a system genuinely depends on
another, say so with `compareTo`:

```dart
class MovementSystem extends GameSystem with FixedTickable {
  /// Writes the *local* transforms `WorldTransformSystem` then composes, so it
  /// has to run first. The other way round shows every entity one frame behind.
  @override
  int compareTo(GameSystem other) => other is WorldTransformSystem ? -1 : 0;
}
```

Return `-1` for "before", `1` for "after", `0` for no opinion — which is the
default, and the right answer for most systems. A system that must run *after*
physics does the mirror:

<!-- snippet: in GameSystem -->
```dart
@override
int compareTo(GameSystem other) => other is Box2DPhysicsSystem ? 1 : 0;
```

## Enabling and disabling

```dart
state.disableSystem<AiSystem>();
state.enableSystem<AiSystem>();
state.setSystemEnabled(AiSystem, false);
state.disableSystems(<Type>[AiSystem, SpawnSystem]);
```

A disabled system stops receiving every event, not just its tick — it is
excluded from event dispatch, so it costs nothing while off. This is also
reachable from the Flutter isolate through a control message, which is how a
pause menu switches simulation systems off without unloading the scene.

## Reaching the rest of the game

| Member | What it gives |
|---|---|
| `state` | The `GameState` this system belongs to |
| `game` | The `Game` — declarations, timing, state channels |
| `getState<S>()` | The state, narrowed to your subclass |
| `getGame<G>()` | The game, narrowed to your subclass |
| `getSystem<S>()` | Another system, for reading its results |
| `singleScene<S>()` | The one loaded scene's declaration. Throws when a second is resident |

<!-- snippet: in GameSystem with Tickable -->
```dart
@override
void onTick(Duration delta) {
  // Read another system's finished results and publish them to the UI.
  final physics = getSystem<Box2DPhysicsSystem>();
  getGame<MyGame>().contactCount.value = physics.touchingPairCount;
}
```

## Systems can declare too

A system is a full declaration host. It can declare its own queries, inputs,
state channels, commands and events:

```dart
class PlayerSystem extends GameSystem with FixedTickable {
  final movement = Input.of(
    const Vec2Binding(up: InputKey.w, down: InputKey.s,
                      left: InputKey.a, right: InputKey.d),
  );
  final fire = Input.of(const TriggerBinding(InputKey.spacebar));
}
```

Keeping the action beside the loop that reads it is usually better than
declaring every input on the `Game` — the declaration and its only consumer stay
in one file. See [input](input.md) for when the `describeInputs` hook is still
the answer.

## Lifecycle

```dart
class SpawnSystem extends GameSystem
    with FixedTickable, GameSystemLifecycleListener {
  @override
  void onMounted() {
    super.onMounted();
    // subscribe to input events, seed state
  }

  @override
  void onUnmounted() {
    super.onUnmounted();
  }
}
```

Subscribe to input events from `onMounted`, not from a tick — `pressed +=` in a
tick adds a subscriber sixty times a second.

---

## Next

[Transforms and hierarchy →](transforms-and-hierarchy.md)
