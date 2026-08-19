# Talking to Flutter

!!! abstract "Layer: kernel (`good`)"

Your UI is ordinary Flutter — widgets, `setState`, whatever state management you
like — laid over a `GameView`. What is *not* ordinary is that the simulation is
on another isolate, so a button cannot simply call a method on your game.

Three lanes cross the boundary, and each exists because the others handle its
case badly.

| Lane | Direction | Shape | Use it for |
|---|---|---|---|
| [Commands](#commands) | both ways | bulk, per-tick | "Do this": spawn, damage, pause, save |
| [State channels](#state-channels) | game → main | one small value | HUD numbers: score, health, timings |
| [Entity reads](#reading-the-world-directly) | game → main | per-entity | Reading the world itself |

## Where your UI belongs

**Build your UI in Flutter.** That is the recommendation, and it is not a
fallback — it is the reason the engine renders into a widget instead of owning
the window.

Menus, HUDs, inventories, settings screens, dialogue boxes, pause overlays: all
ordinary widgets, laid over the `GameView`. You get Flutter's layout, text
rendering, accessibility, focus handling, animation, theming and hot reload for
free, and none of it costs the simulation anything — it is on the other isolate.

```dart
Stack(
  children: <Widget>[
    GameView(camera: game.defaultCamera),
    Positioned(
      top: 16, left: 16,
      child: ValueListenableBuilder<int>(
        valueListenable: game.score,
        builder: (context, score, _) => Text('Score: $score'),
      ),
    ),
    Align(
      alignment: Alignment.bottomCenter,
      child: ElevatedButton(
        onPressed: () => game.pause(),
        child: const Text('Pause'),
      ),
    ),
  ],
)
```

The UI reads through [state channels](#state-channels) and acts through
[commands](#commands). That is the whole interface.

### When to put UI *in* the game instead

One case, and it is a real one: **when the element is as interactive as the game
itself** — when it lives in world space, moves with the world, or has to be hit
tested against the same things the game is.

| In the game (an entity) | In Flutter (a widget) |
|---|---|
| A health bar pinned above an enemy | The player's health bar in the corner |
| A world-space button on a machine the player walks up to | The pause menu |
| Drag-and-drop that lands on game objects | An inventory grid |
| A damage number that flies off a hit | A settings screen |
| A speech bubble tracking a character | A dialogue box at the bottom of the screen |
| A minimap marker in a second camera view | The minimap frame around it |

The test: **does it need the camera?** If it has to move when the world moves,
be occluded by the world, or be picked in world coordinates, make it an entity —
a `Renderable2D` with `MouseReceiver`, and `NineSliceBorder` for panels and
bars. If it sits in screen space and never has to know where the camera is, it
is a widget, and making it an entity buys nothing but work.

!!! tip "You can mix them freely"
    A world-space marker as an entity and the panel it opens as a Flutter
    dialog is a perfectly ordinary combination. They are not competing systems
    — one is drawn by the camera and one is drawn over it.

## Commands

A command is a declared message with typed parameters, carried on a shared ring
buffer — not a `SendPort` message per call.

```dart
class SetPopulation extends SinkCommand<int> {
  late final ParamPointer<int> count;

  @override
  void describeParams(ParamDescriptor descriptor) {
    count = descriptor.hasUint16();
  }

  @override
  void bufferFromParams(ParamBuffer call, int params) => count[call] = params;

  @override
  int paramsFromBuffer(ParamBuffer call) => count[call];
}
```

Declare it on the `Game`, and handle it on the `GameState`:

```dart
class MyGame extends Game2D {
  late final SetPopulation setPopulation;

  @override
  void describeCommands(CommandDescriptor descriptor) {
    setPopulation = descriptor.has(SetPopulation());
  }
}

class MyState extends GameState2D<MyGame> {
  @override
  void describeCommands(CommandDescriptor descriptor) {
    descriptor.hasSink(game.setPopulation, _onSetPopulation);
  }

  void _onSetPopulation(int target) => targetPopulation = target;
}
```

Send it from anywhere on the Flutter side:

```dart
onPressed: () => game.setPopulation(400),
```

!!! info "Every command is declared on the `Game`, whichever side handles it"
    `describeCommands` runs on **both** copies in the same order, which is what
    makes a command's index mean the same thing on both sides. `GameState`'s
    pass may only *handle* what the `Game`'s pass declared — a command declared
    there would have an index on the game isolate and none on the Flutter one,
    which is the same as having none.

### The four shapes

| Class | Signature | For |
|---|---|---|
| `SignalCommand` | `()` | "Pause". No data either way |
| `SinkCommand<P>` | `(P)` | "Spawn 5 enemies". Data in, nothing back |
| `SupplierCommand<R>` | `() → R` | "How many are alive?" Nothing in, data back |
| `GameCommand<P, R>` | `(P) → R` | Both |

All four are awaitable — `await game.saveGame()` completes when the far side has
handled it.

### More than one parameter: use a record

`P` is a **single** type, so a command that carries several values carries a
**Dart record** — the same answer coroutines give:

```dart
typedef Blow = ({int amount, bool crit});

class Damage extends GameCommand<Blow, int> {
  late final ParamPointer<int> amount;
  late final ParamPointer<int> crit;
  late final ParamPointer<int> dealt;

  @override
  void describeParams(ParamDescriptor descriptor) {
    amount = descriptor.hasUint16();
    crit = descriptor.hasUint1();      // (1)!
    dealt = descriptor.hasUint16();    // (2)!
  }

  @override
  void bufferFromParams(ParamBuffer call, Blow params) {
    amount[call] = params.amount;
    crit[call] = params.crit ? 1 : 0;  // (3)!
  }

  @override
  Blow paramsFromBuffer(ParamBuffer call) =>
      (amount: amount[call], crit: crit[call] == 1);

  @override
  void bufferFromResult(ParamBuffer call, int result) => dealt[call] = result;

  @override
  int resultFromBuffer(ParamBuffer call) => dealt[call];
}
```

1. One bit, not a byte. Field widths are wire bandwidth.
2. The **result** shares the same record as the parameters — one layout, one
   reservation, both directions.
3. `ParamPointer` is integer-typed, so a `bool` is marshalled explicitly, not by
   an implicit conversion you cannot see.

Call it with a record literal, and the field names are checked at the call site:

```dart
final dealt = await game.damage((amount: 25, crit: true));
```

The `typedef` is worth writing. The record type appears in four signatures, and
naming it once means a new field is one edit instead of four.

!!! tip "Why a record, not a parameter list"
    A command has to be **one value** to be reserved, marshalled, queued in a
    batch and handed to a handler. A record gives that one value named,
    type-checked fields with no wrapper class to declare and no positional
    argument order to get wrong — and it exists only at the call site, never in
    the record that crosses the wire.

The four marshalling methods are the whole contract, and `call`/`execute` are
provided in terms of them instead of being things you override.

### Handlers take the record

```dart
descriptor.hasHandler(game.damage, (Blow params) {
  return params.amount * (params.crit ? 2 : 1);
});
```

`hasHandler` is `R Function(P)` — parameters in, result out. `hasSink` is
`void Function(P)`, `hasSupplier` is `R Function()`, and `hasSignal` is
`void Function()`.

### The field schema

`ParamDescriptor` mirrors `DataDescriptor`, with the same widths and the same
packing:

```dart
@override
void describeParams(ParamDescriptor descriptor) {
  x = descriptor.hasFloat32();
  y = descriptor.hasFloat32();
  kind = descriptor.hasUint4();          // 16 kinds in half a byte
  target = descriptor.hasEntity();       // a handle, not a bare int64
  name = descriptor.hasString(32);       // bounded, so the record has a size
}
```

Two things follow from the record being fixed-width:

- **Strings need a maximum byte length.** A command's whole wire image has to
  fit in one ring-buffer record, so an unbounded string has no place to live.
- **Field widths are bandwidth.** `hasUint1()` for a flag and `hasUint4()` for a
  small enum are not micro-optimisation here — a batch of a few hundred commands
  per frame pays for every byte.

The schema is separate from `P`: `P` is what your *code* passes, and
the schema is what crosses the wire. `bufferFromParams` and `paramsFromBuffer`
are the two places that translate between them, and they are the only places
that mention a `ParamPointer` at all.

### Handling on the Flutter side

Some commands belong on main — writing a save file, opening a URL. Register the
handler in the `Game`'s own pass:

```dart
@override
void describeCommands(CommandDescriptor descriptor) {
  save = descriptor.has(SaveGame());
  descriptor.hasSink(save, _writeSaveFile);   // handled here, not on the game isolate
}
```

### Batching

Several commands in one round trip:

```dart
final batch = game.createCommandBatch();
game.spawnEnemy.execute(1, batch);
game.spawnEnemy.execute(2, batch);
game.setPopulation.execute(400, batch);
await batch.send();
```

A UI frame that issues a few hundred orders at once must not overflow between
two drains 16 ms apart, which is what `commandBufferBytes` (64 KiB by default)
sizes.

!!! note "There is no built-in spawn command"
    `SpawnEntityCommand` was deleted instead of shipped: it named a prefab by
    `archetypeId`, which is a game-isolate identifier the Flutter isolate has no
    way to see. Declare your own, in terms that mean something on both sides —
    an enum of spawnable kinds, say.

## State channels

For "one number the UI shows", a command per read would be absurd. A state
channel is a small fixed-width value the game isolate writes and the Flutter
isolate reads **straight out of shared memory**, coherent per tick.

```dart
class MyGame extends Game2D {
  late final StateChannel<int> score;
  late final StateChannel<double> health;
  late final StateChannel<bool> paused;

  @override
  void describeState(StateDescriptor descriptor) {
    score = descriptor.hasInt32();
    health = descriptor.hasFloat32(100);
    paused = descriptor.hasBool();
  }
}
```

Write from the game isolate:

```dart
class ScoreSystem extends GameSystem with Tickable {
  @override
  void onTick(Duration delta) {
    getGame<MyGame>().score.value = getState<MyState>().score;
  }
}
```

Read from Flutter — a `StateChannel` **is** a `ValueListenable`, so it drops
straight into a `ValueListenableBuilder`:

```dart
ValueListenableBuilder<int>(
  valueListenable: game.score,
  builder: (context, score, _) => Text('Score: $score'),
)
```

### Who can declare one

Exactly two hosts: **`Game`** and **`GameSystem`**. That is not arbitrary — a
channel's storage is allocated on the main isolate *before the spawn*, and its
identity across the boundary is its index in that one declaration pass. So only
something main declares can own an index.

That rules out three things, each for its own reason:

- **`GameState`** is built on the game isolate, after the allocation it would
  have to be part of. Publish from the `Game` and write through
  `state.game.score`.
- **`SceneStruct`** is loaded after boot, possibly several times, so it could
  never hold a stable index.
- **`Component`** comes and goes with the scene, for the same reason.

Publish scene-derived values from a `GameSystem`, which outlives the scene and
is where the per-tick work already is.

!!! warning "Publish from `Tickable`, not `FixedTickable`"
    Phase totals are only complete once the fixed step has returned. A system
    publishing from inside `onFixedUpdate` reports a half-accumulated figure —
    numbers that are wrong in a way that looks plausible.

## Reading the world directly

The Flutter-side copy of your `Game` runs the same declarations, so it has the
identical archetype layout and adopts every page the game isolate allocates. An
`Entity` therefore resolves and reads with **no message and no copy**.

Getting the handle across is the only part that needs a command — an `Entity` is
an `int`, so it fits in one parameter, and `hasEntity` is the field that says
so:

```dart
class WhoIsPlayer extends SupplierCommand<Entity> {
  late final ParamPointer<Entity> entity;

  @override
  void describeParams(ParamDescriptor descriptor) {
    entity = descriptor.hasEntity();
  }

  @override
  void bufferFromResult(ParamBuffer call, Entity result) =>
      entity[call] = result;

  @override
  Entity resultFromBuffer(ParamBuffer call) => entity[call];
}
```

```dart
final playerEntity = await game.whoIsPlayer();
final transform = playerEntity.get<Transform2D>();
final x = transform.transformOffsetX[playerEntity];
```

This is a read of the published snapshot, coherent per tick, and **read-only** —
the game isolate is the only writer anywhere in the process.

`hasEntity` is `hasInt64` with the handle type on it — same eight bytes on the
wire, same cost — but a command declaring one cannot be handed a score by
mistake, and a mix-up that did cross the boundary would look like eight
perfectly ordinary bytes on the other side.

## Frames and ticks

```dart
game.addTickListener((tick) => setState(() {}));
game.removeTickListener(listener);
```

`GameView` is already push-driven off these notifications instead of polling
vsync, so you rarely need this directly — reach for it when a HUD must repaint
exactly in step with the simulation.

## The widget surface

`Game.buildView` is the game's *whole* Flutter surface. There is no second event
lane into the main isolate, by design: every event in the engine happens on the
game isolate, and traffic the other way is a command or a channel.

```dart
class MyGame extends Game2D {
  @override
  Widget? buildView(BuildContext context, CameraView? camera) {
    // optional: a custom surface. `Game2D` supplies the default painter.
    return null;
  }

  @override
  void onViewAttached() { }
  @override
  void onViewDetached() { }
}
```

## Lifecycle in a widget

```dart
class _GameSurfaceState extends State<GameSurface> {
  /// Constructed **synchronously**, so there is always something to stop.
  final MyGame _game = MyGame();

  /// The in-flight start. `dispose` waits on it before stopping.
  late final Future<void> _starting;

  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _starting = _start();
  }

  Future<void> _start() async {
    await ensureGameReady();          // check assets before anything decodes
    await Game.start(_game);
    if (!mounted) return;             // disposed mid-start; dispose stops it
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    // `dispose` cannot await, so the teardown is hung off the start future.
    // Already-complete: stops now. Still in flight: stops the moment it boots.
    _starting.whenComplete(_game.stop);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return GameView(camera: _game.defaultCamera);
  }
}
```

!!! danger "Do not stop through a nullable field assigned after the await"
    This is the shape to avoid, and it leaks silently:

    ```dart
    MyGame? _game;

    Future<void> _start() async {
      final game = MyGame();
      await Game.start(game);         // (1) widget can be disposed during this
      if (mounted) setState(() => _game = game);
    }

    @override
    void dispose() {
      _game?.stop();                  // (2) still null — does nothing
      super.dispose();
    }
    ```

    If the widget is disposed while `Game.start` is in flight, `_game` is still
    null at (2), so `?.` swallows the call. The start then completes, `mounted`
    is false so the field is never assigned, and **the game keeps running** —
    its isolate alive and its native memory held — attached to a widget that no
    longer exists. Nothing reports it.

    Constructing the game synchronously fixes half of it. The other half is that
    `stop()` returns immediately when the run has not finished booting, so
    stopping *during* start is also a no-op — which is why `dispose` hands the
    teardown to the start future instead of calling `stop()` directly.

`stop()` is not optional. The game owns native memory and an isolate, and
neither is reclaimed by the widget going away.

!!! danger "One `Game` instance backs one run"
    A `Game` that has been started cannot be started again — its declarations
    are sealed. Build a fresh instance for a fresh run.

---

## Next

[Coroutines and animation →](coroutines-and-animation.md)
