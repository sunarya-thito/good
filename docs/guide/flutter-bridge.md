# Talking to Flutter

<!-- snippet-scope
// The reader's own game, seen from the Flutter side. Spelled out here so the
// fences that call into it are checked against the real command and state
// channel types.
class SpawnEnemy extends SinkCommand<int> {}

class SaveGame extends SinkCommand<String> {}

class WhoIsPlayer extends SupplierCommand<Entity> {}

class DocGame extends Game2D {
  late final StateChannel<int> score;
  late final SetPopulation setPopulation;
  late final SpawnEnemy spawnEnemy;
  late final Damage damage;
  late final SaveGame save;
  late final WhoIsPlayer whoIsPlayer;

  void pause() {}
}

late DocGame game;

class GameSurface extends StatefulWidget {
  const GameSurface({super.key});

  @override
  State<GameSurface> createState() => given<State<GameSurface>>();
}

Future<void> ensureGameReady() async {}

void _writeSaveFile(String path) {}
-->

!!! abstract "Layer: kernel (`good`)"

Your UI is ordinary Flutter — widgets, `setState`, whatever state management you
like — laid over a `GameView`. What is *not* ordinary is that the simulation is
on another isolate, so a button cannot simply call a method on your game.

Two lanes carry your traffic, and each exists because the other handles its
case badly.

| Lane | Direction | Shape | Use it for |
|---|---|---|---|
| [Commands](#commands) | both ways | bulk, per-tick | "Do this": spawn, damage, pause, save |
| [State channels](#state-channels) | game → main | one small value | HUD numbers: score, health, timings |

A third, `describeBuffers`, is renderer plumbing rather than game code: a ring
of records in shared memory, which is how `goo2d` gets a frame's draw list to
the painter. Nothing crosses outside these — component data in particular does
not, and [Reading the world](#reading-the-world) says why.

## Where your UI belongs

**Build your UI in Flutter.** That is the recommendation, and it is not a
fallback — it is the reason the engine renders into a widget instead of owning
the window.

Menus, HUDs, inventories, settings screens, dialogue boxes, pause overlays: all
ordinary widgets, laid over the `GameView`. You get Flutter's layout, text
rendering, accessibility, focus handling, animation, theming and hot reload for
free, and none of it costs the simulation anything — it is on the other isolate.

<!-- snippet: expr -->
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
  final count = Param.uint16();

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
    super.describeCommands(descriptor);
    setPopulation = descriptor.has(SetPopulation.new);
  }
}

class MyState extends GameState2D<MyGame> {
  int targetPopulation = 0;
  int score = 0;

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    descriptor.hasSink(game.setPopulation, _onSetPopulation);
  }

  void _onSetPopulation(int target) => targetPopulation = target;
}
```

Send it from anywhere on the Flutter side:

<!-- snippet: skip a widget argument, not a statement -->
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
  final amount = Param.uint16();
  final crit = Param.uint1();      // (1)!
  final dealt = Param.uint16();    // (2)!

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

<!-- snippet: plain -->
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

<!-- snippet: plain -->
<!-- snippet-setup
final descriptor = given<CommandDescriptor>();
-->
```dart
descriptor.hasHandler(game.damage, (Blow params) {
  return params.amount * (params.crit ? 2 : 1);
});
```

`hasHandler` is `R Function(P)` — parameters in, result out. `hasSink` is
`void Function(P)`, `hasSupplier` is `R Function()`, and `hasSignal` is
`void Function()`.

### The field schema

`Param` mirrors `Field`, with the same widths and the same packing — a
command parameter is declared on the field that holds it, exactly like a
component column:

<!-- snippet: in Damage -->
```dart
final x = Param.float32();
final y = Param.float32();
final kind = Param.uint4();          // 16 kinds in half a byte
final target = Param.entity();       // a handle, not a bare int64
final name = Param.string();         // any length, kept in the tail
final code = Param.fixedString(2);   // reserved inline, because 2 is real
```

A record has a fixed **head** — every numeric field, and the offset and length
of every variable-length one — and, if it declares any variable-length field, a
**tail** behind the head holding their bytes. Three things follow:

- **A string does not need a maximum.** `Param.string()` and `Param.bytes()`
  size themselves from what you write. `Param.fixedString(n)` and
  `Param.fixedBytes(n)` reserve `n` bytes in *every* record whether they are
  used or not, so reach for them when the bound is real — a two-letter country
  code, a 16-byte digest — and use the length-free kind for everything else.
- **The carrier is what bounds a record, not the declaration.** A batch grows to
  hold whatever is written into it, but it still has to fit in one ring-buffer
  record on the way across. A batch too big for that ring is refused at
  `send()`, naming the bound and `Game.commandBufferBytes`. It is never
  truncated.
- **Field widths are bandwidth.** `Param.uint1()` for a flag and
  `Param.uint4()` for a small enum are not micro-optimisation here — a batch of
  a few hundred commands per frame pays for every byte.

The schema is separate from `P`: `P` is what your *code* passes, and
the schema is what crosses the wire. `bufferFromParams` and `paramsFromBuffer`
are the two places that translate between them, and they are the only places
that mention a `ParamPointer` at all.

### Handling on the Flutter side

Some commands belong on main — writing a save file, opening a URL. Register the
handler in the `Game`'s own pass:

<!-- snippet: in Game2D -->
<!-- snippet-setup
late SaveGame save;
-->
```dart
@override
void describeCommands(CommandDescriptor descriptor) {
  super.describeCommands(descriptor);
  save = descriptor.has(SaveGame.new);
  descriptor.hasSink(save, _writeSaveFile);   // handled here, not on the game isolate
}
```

### Batching

Several commands in one round trip:

<!-- snippet: plain -->
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
    One would have to name a prefab by `archetypeId`, which is a game-isolate
    identifier the Flutter isolate has no way to see. Declare your own, in terms
    that mean something on both sides — an enum of spawnable kinds, say.

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
    super.describeState(descriptor);
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

<!-- snippet: expr -->
```dart
ValueListenableBuilder<int>(
  valueListenable: game.score,
  builder: (context, score, _) => Text('Score: $score'),
)
```

### Only the `Game` can declare one

Not arbitrary: a channel's storage is allocated on the main isolate *before the
spawn*, and its identity across the boundary is its index in that one
declaration pass. `describeState` is the only pass main runs that a game
overrides, so it is the only place an index can come from.

That rules out four hosts, each for its own reason:

- **`GameState`** is built on the game isolate, after the allocation it would
  have to be part of.
- **`GameSystem`** goes with the systems to the game isolate for the same
  reason.
- **`SceneStruct`** is loaded after boot, possibly several times, so it could
  never hold a stable index.
- **`Component`** comes and goes with the scene, for the same reason.

So a scene-derived value is declared on the `Game` and written from wherever
the per-tick work is — usually a `GameSystem`, through `game.score`, as
`ScoreSystem` above does.

!!! warning "Publish from `Tickable`, not `FixedTickable`"
    Phase totals are only complete once the fixed step has returned. A system
    publishing from inside `onFixedUpdate` reports a half-accumulated figure —
    numbers that are wrong in a way that looks plausible.

## Reading the world

You cannot, from Flutter. The main-isolate copy registers no archetypes and
holds no component pages, so `Entity.get` there throws and tells you to publish
the value through a channel instead. Every read of a column happens on the
game isolate.

That is not a gap waiting to be filled. Resolving handles on main costs a second
page list to keep in step with the game isolate's, and a handshake before any
page can be freed, since main might still be reading it — and use-after-free on
shared memory does not report, it returns plausible numbers.

An `Entity` still crosses perfectly well as a *value*, which is what
`Param.entity()` is for:

```dart
class WhoIsPlayer extends SupplierCommand<Entity> {
  final entity = Param.entity();

  @override
  void bufferFromResult(ParamBuffer call, Entity result) =>
      entity[call] = result;

  @override
  Entity resultFromBuffer(ParamBuffer call) => entity[call];
}
```

It is `Param.int64()` with the handle type on it — same eight bytes on the wire,
same cost — but a command declaring one cannot be handed a score by mistake,
and a mix-up that did cross would look like eight perfectly ordinary bytes on
the other side. What main can do with the handle it gets back is name that
entity in a later command. To *watch* one, publish its fields: see
[debugging without an inspector](thinking-in-ecs.md#debugging-without-an-inspector).

## Frames and ticks

<!-- snippet: plain -->
<!-- snippet-setup
void setState(void Function() fn) {}
final listener = given<void Function(int)>();
-->
<!-- snippet: skip GameRuntime.addTickListener is @internal and unreachable from a game -->
```dart
game.runtimeOrNull?.addTickListener((tick) => setState(() {}));
game.runtimeOrNull?.removeTickListener(listener);
```

The listeners hang off the `GameRuntime`, which exists only while the game is
running — hence the `?.`. `GameView` repaints from a `SchedulerBinding` frame
callback and not from these, so you rarely need them: reach for one when
something must react to the published snapshot moving rather than to the next
frame.

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

    <!-- snippet: in State<GameSurface> -->
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
