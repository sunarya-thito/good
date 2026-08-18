# Systems and queries

!!! abstract "Layer: kernel (`good`)"

A `GameSystem` is where per-tick work lives. It declares its queries once and
walks the matching rows every step.

```dart
class MovementSystem extends GameSystem with FixedTickable {
  late final Query movers;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    movers = descriptor.query()
        .withAll(Transform2D, Velocity)
        .withNone(Child)          // roots only; parented movers follow theirs
        .build();
  }

  @override
  void onFixedUpdate() {
    final dt = game.fixedTimeStep.inMicroseconds / 1000000.0;
    for (final group in movers.groups()) {
      final transform = group.get<Transform2D>();
      final velocity = group.get<Velocity>();
      for (final entity in group) {
        transform
          ..transformOffsetX[entity] += velocity.x[entity] * dt
          ..transformOffsetY[entity] += velocity.y[entity] * dt;
      }
    }
  }
}
```

Declare it on the **state**, because a system exists only on the isolate that
ticks it:

```dart
class MyState extends GameState2D<MyGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(MovementSystem());
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

The difference is not cosmetic. Phase totals are only complete once the fixed
step has returned, so a system publishing timings from inside `onFixedUpdate`
reports a half-accumulated figure — numbers that are nonsense in a way that
looks plausible.

```dart
class HudPublisher extends GameSystem with Tickable {
  @override
  void onTick(Duration delta) {
    getGame<MyGame>().score.value = getState<MyState>().score;
  }
}
```

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
branches on `entity.tryGet<T>()`. `WorldTransformSystem` is the reference usage:
it matches every `Transform2D` entity, hierarchy-linked or not, and tests
`tryGet<Child>()` inside.

## Walking results

```dart
for (final group in query.groups()) {      // one group per matching archetype
  final transform = group.get<Transform2D>();   // resolved once for the group
  for (final entity in group) {
    transform.transformOffsetX[entity] += 1;
  }
}
```

The two-level shape is the point. `group.get<T>()` resolves that archetype's
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
| `getScene<S>()` | A loaded scene's declaration |

```dart
@override
void onTick(Duration delta) {
  // Read another system's finished results and publish them to the UI.
  final physics = getSystem<Box2DPhysicsSystem>();
  getGame<MyGame>().contactCount.value = physics.contactCount;
}
```

## Systems can declare too

A system is a full declaration host. It can declare its own queries, inputs,
state channels, commands and events:

```dart
class PlayerSystem extends GameSystem with FixedTickable {
  late final Input<Vector2> movement;
  late final Input<bool> fire;

  @override
  void describeInputs(InputDescriptor descriptor) {
    super.describeInputs(descriptor);
    movement = descriptor.has<Vector2>(
      const Vec2Binding(up: InputKey.w, down: InputKey.s,
                        left: InputKey.a, right: InputKey.d),
    );
    fire = descriptor.has<bool>(const TriggerBinding(InputKey.spacebar));
  }
}
```

Keeping the action beside the loop that reads it is usually better than
declaring every input on the `Game` — the declaration and its only consumer stay
in one file.

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
