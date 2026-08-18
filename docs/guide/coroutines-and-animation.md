# Coroutines and animation

!!! abstract "Layer: kernel (`good`)"

Two ways to make something happen over time, for two different shapes of
problem: **coroutines** for a one-shot sequence you write as a script, and
**timelines** for a curve you sample.

## Coroutines

A coroutine is a resumable piece of gameplay logic written as a `sync*`
generator:

```dart
class RoundSystem extends GameSystem with FixedTickable {
  /// A coroutine takes **no parameters**.
  Iterable startRound() sync* {
    showBanner();
    yield 2.0;                          // wait two simulated seconds
    hideBanner();
    yield null;                         // wait one fixed step
    yield WaitUntil(() => everyoneReady);
    beginPlay();
  }
}
```

`Coroutine` is `Iterable Function()` — a plain no-argument generator. That
signature is deliberate: it lets a coroutine be started **without allocating a
closure**, which matters because starting one is ordinary gameplay code.

Start it from anywhere that has a simulation — a `GameState`, a `GameSystem`, a
`SceneStruct`, or a prefab. Pass the **function itself**, not a call to it:

```dart
final running = startCoroutine(startRound);
```

!!! danger "Do not wrap it in a closure"
    ```dart
    startCoroutine(() => entrance(entity));   // allocates a closure per start
    ```
    That is what [no heap allocation on the hot path](../reference/rules.md#no-heap-allocation-on-the-hot-path)
    is about, and it is why the parameterised form below exists.

The body first advances on the **next** fixed step, never inline, so starting
one is safe from anywhere including outside the tick window.

### What a `yield` may be

| Yielded | Resumes |
|---|---|
| `null` | Next fixed step |
| a `num` | After that many **simulated** seconds |
| a `YieldInstruction` | When it says so, polled once per step |
| another `Iterable` | After running that one to completion |

Anything else throws instead of being silently treated as "next frame".

Seconds are **simulated**, accumulated from `fixedTimeStep`, so a coroutine
replays identically — `Future.delayed` would not.

Nesting is a plain stack, so a coroutine can be composed of coroutines without
either knowing about the other:

```dart
Iterable cutscene(Entity actor) sync* {
  yield walkToDoor(actor);       // an Iterable, run to completion first
  yield openDoor(actor);
  yield 1.0;                     // beat
  yield walkInside(actor);
}

Iterable walkToDoor(Entity self) sync* {
  while ((transform.transformOffsetX[self] - targetX[self]).abs() > 0.1) {
    transform.transformOffsetX[self] += speed[self] * fixedDelta;
    yield null;                  // one step at a time
  }
}
```

Nesting is a plain `yield` of another `Iterable`, so nothing is *started* here —
only the outermost coroutine goes through `startCoroutineWithParam`.

### Instructions

```dart
yield WaitUntil(() => player.isGrounded);
yield WaitWhile(() => menuIsOpen);
yield WaitForFuture(saveGame());
```

`WaitWhile` exists because `WaitUntil(() => !busy)` reads worse than
`WaitWhile(() => busy)`.

### Stopping

```dart
final running = startCoroutine(startRound);
stopCoroutine(running);        // idempotent
stopAllCoroutines();           // everything *this owner* started
```

`CoroutineFuture` implements `Future<void>`, so a coroutine can be awaited:

```dart
await startCoroutine(startRound);
await startCoroutineWithParam(entrance, param: entity);
```

### When the body needs an argument

A coroutine that has to know *which entity* it is running for takes exactly one
parameter, and is started through the parameterised call — never through a
closure:

```dart
/// One argument, and the type is CoroutineWithParam<Entity>.
Iterable entrance(Entity self) sync* {
  yield 0.5;                            // wait half a simulated second
  sprite.visible[self] = true;
  yield null;
  yield WaitUntil(() => landed[self]);  // an ordinary bool column
  sprite.color[self] = 0xFFFFFFFF;
}
```

```dart
startCoroutineWithParam(entrance, param: entity);
```

### More than one argument: use a record

`CoroutineWithParam<T>` takes a single `T`, and for several values that `T` is a
**Dart record**:

```dart
Iterable walkTo((Entity self, double x, double y) to) sync* {
  final (self, targetX, targetY) = to;         // destructure once, up front
  while ((transform.transformOffsetX[self] - targetX).abs() > 0.1) {
    transform.transformOffsetX[self] += speed[self] * fixedDelta;
    yield null;
  }
  transform.transformOffsetY[self] = targetY;
}
```

```dart
startCoroutineWithParam(walkTo, param: (entity, 120.0, -40.0));
```

A record keeps the arguments named and type-checked at the call site without a
wrapper class or a builder. It costs one small allocation per **start** — which
is fine for the occasional event a coroutine is for, and is not something to do
per entity per tick.

This is the engine's general answer to "one type parameter, several values":
[commands](flutter-bridge.md#more-than-one-parameter-use-a-record) and
[network messages](../packages/networking.md#declaring-messages) do exactly the
same thing.

### Why `sync*` and not `async*`

This matters enough to state plainly, because the obvious Dart spelling is the
wrong one here.

An `async*` generator resumes on a **microtask**. The engine requires every
component write to land between `beginTick` and `commitTick` — `beginTick`
copies the last published snapshot over the write slot, so anything written
outside that window is discarded.

A coroutine exists to write component data *after waiting*. Under `async*` every
one of those writes lands after `commitTick` and is therefore thrown away —
silently in release, on an assert in debug. Not intermittently: every time, for
every write after the first `yield`.

`sync*` resumes synchronously, so the scheduler drives it from inside the tick
window and the writes land where they must. It is also exactly what Unity's
`IEnumerator` coroutines are, for what is probably the same reason.

!!! danger "Never `await` inside gameplay that writes components"
    `await` puts you on a microtask, outside the tick window. If you need to
    wait on a real `Future`, wrap it: `yield WaitForFuture(f)`.

## Timelines

A coroutine is a script. A **timeline** is a curve — declared once, sampled by
an integer, with no per-entity animation object anywhere.

```dart
class EnemyTimeline extends TimelineStruct {
  late final Track<double> x;
  late final Track<double> y;
  late final Track<int> frame;

  late final TimelineAnimation entrance;
  late final TimelineAnimation blink;

  @override
  void describeTrack(TimelineDescriptor descriptor) {
    x = descriptor.has<double>(0);        // default outside any clip
    y = descriptor.has<double>(-1);
    frame = descriptor.has<int>(0);
  }

  @override
  void describeAnimation(TimelineAnimationDescriptor descriptor) {
    // 0 -> 100 over one second, hold two, back to 0 over one. Four seconds.
    entrance = descriptor.has()
      ..track(x).key(0.0).key(100.0, 1.0).hold(2.0).key(0.0, 1.0);

    blink = descriptor.has()
      ..track(y).key(0.0).key(10.0, 1.0)
      ..track(frame).key(0).key(3, 1.0);
  }
}
```

Declare it on a prefab:

```dart
class Enemy extends EntityStruct with Transform2D, Renderable2D {
  late final EnemyTimeline timeline;
  late final DataPointer<double> startedAt;

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    startedAt = data.hasFloat64();
  }

  @override
  void describeAnimation(AnimationTypeDescriptor descriptor) {
    timeline = descriptor.has(EnemyTimeline());
  }
}
```

Several clips can drive the **same** tracks. A track with no keys in the clip
being sampled reports its declared default, so a clip only has to mention the
tracks it actually moves.

### Sampling — the cheap path

What an entity stores is **one double**: when it started. Everything else is
derived:

```dart
@override
void onFixedUpdate() {
  for (final group in enemies.groups()) {
    final enemy = group.get<Enemy>();
    final transform = group.get<Transform2D>();
    for (final entity in group) {
      final sample = enemy.timeline.entrance.animate(
        offset: -enemy.startedAt[entity],
        wrapMode: WrapMode.loop,
      );
      transform
        ..transformOffsetX[entity] = enemy.timeline.x[sample]
        ..transformOffsetY[entity] = enemy.timeline.y[sample];
    }
  }
}
```

`TimelineSample` is an `extension type` over an `int` — 16 bits of clip id, 48
bits of microseconds — so producing one **allocates nothing**. That is the whole
reason sampling is shaped this way instead of as an animation object that owns
state and gets ticked: a system samples this per entity per frame.

| `WrapMode` | Past the clip's end |
|---|---|
| `clamp` | Hold the last keyframe. A one-shot entrance or death |
| `loop` | Start again from zero. An idle bob, a spinning coin |
| `pingPong` | Forwards, backwards, forwards. A breathing scale, a hovering platform |

`pingPong` is the one you would otherwise author twice and have to keep
symmetrical by hand.

### Playing — the push path

For a one-shot that must run to completion and then be awaited — an entrance, a
door opening, a cutscene beat — where you want `await` , not a flag to
check every tick:

```dart
await startAnimation(
  timeline.entrance,
  <TrackBinding>[
    timeline.x.bind(transform.transformOffsetX.bind(entity)),   // (1)!
    timeline.y.bind(transform.transformOffsetY.bind(entity)),
  ],
  wrapMode: WrapMode.clamp,
);
```

1. `DataPointer.bind(entity)` pins a column to one row, giving the
   `DataBinding<T>` the track writes through. No closure, and nothing to keep in
   step.

It runs on the coroutine scheduler, so its writes land inside the tick window.

!!! tip "Which one to reach for"
    `startAnimation` costs a coroutine and a binding per track, so it is for the
    occasional event. In a per-entity update loop, use `animate` and index the
    track — it costs nothing.

### Keys and curves

A clip is written as a chain of keyframes per track. Two calls do everything:

```dart
entrance = descriptor.has()
  ..track(x)
      .key(0.0)                          // (1)!
      .key(100.0, 1.0)                   // (2)!
      .hold(2.0)                         // (3)!
      .key(0.0, 1.0, Curves.easeInOut);  // (4)!
```

1. `key(value)` with no duration places the **first** keyframe at t = 0. The
   track reads `0.0` at the start of the clip.
2. `key(value, duration)` — reach `100.0` **one second after the previous
   keyframe**. Between them the value is interpolated.
3. `hold(seconds)` — stay at the previous value for two seconds. Sugar for
   repeating the last keyframe, and worth having: written by hand it means
   naming the same value twice, and the two copies then have to be kept in step
   by whoever edits the clip.
4. `key(value, duration, curve)` — return to `0.0` over one second, eased.

That clip is **four seconds long**: 0 + 1 + 2 + 1. Its length is derived from
its keys; you never state it.

<figure markdown="span">
<svg viewBox="0 0 600 235" role="img" width="600"
     aria-label="Value over time for the four-second clip: zero at t=0, rising to 100 at t=1, held at 100 until t=3, then eased back to zero at t=4."
     style="max-width:100%;height:auto;color:currentColor">
  <!-- axes -->
  <line x1="70" y1="40"  x2="70"  y2="192" stroke="currentColor" stroke-width="1" opacity=".45"/>
  <line x1="70" y1="192" x2="575" y2="192" stroke="currentColor" stroke-width="1" opacity=".45"/>
  <!-- gridlines at each second -->
  <g stroke="currentColor" stroke-width="1" opacity=".15">
    <line x1="190" y1="40" x2="190" y2="192"/>
    <line x1="310" y1="40" x2="310" y2="192"/>
    <line x1="430" y1="40" x2="430" y2="192"/>
    <line x1="550" y1="40" x2="550" y2="192"/>
  </g>
  <!-- the track: linear ramp, hold, eased return -->
  <path d="M 70 192 L 190 40 L 430 40 C 490 40 490 192 550 192"
        fill="none" stroke="currentColor" stroke-width="2.5"/>
  <!-- keyframes -->
  <g fill="currentColor">
    <circle cx="70"  cy="192" r="4"/>
    <circle cx="190" cy="40"  r="4"/>
    <circle cx="550" cy="192" r="4"/>
  </g>
  <!-- hold span -->
  <g stroke="currentColor" stroke-width="1.5" opacity=".7">
    <line x1="190" y1="26" x2="430" y2="26"/>
    <line x1="190" y1="21" x2="190" y2="31"/>
    <line x1="430" y1="21" x2="430" y2="31"/>
  </g>
  <g fill="currentColor" font-size="12" font-family="system-ui,sans-serif">
    <text x="310" y="18" text-anchor="middle" opacity=".8">hold(2.0)</text>
    <text x="62"  y="45"  text-anchor="end">100</text>
    <text x="62"  y="196" text-anchor="end">0</text>
    <text x="70"  y="212" text-anchor="middle" opacity=".7">0</text>
    <text x="190" y="212" text-anchor="middle" opacity=".7">1</text>
    <text x="310" y="212" text-anchor="middle" opacity=".7">2</text>
    <text x="430" y="212" text-anchor="middle" opacity=".7">3</text>
    <text x="550" y="212" text-anchor="middle" opacity=".7">4</text>
    <text x="575" y="212" text-anchor="start" opacity=".7">seconds</text>
    <text x="70"  y="230" text-anchor="middle">key</text>
    <text x="190" y="230" text-anchor="middle">key</text>
    <text x="550" y="230" text-anchor="middle">key</text>
  </g>
</svg>
<figcaption>The clip is four seconds long, and its length is derived from its
keys: 0 + 1 + 2 + 1.</figcaption>
</figure>

!!! important "Durations are **relative**, not absolute"
    Each call advances a write head, so `.key(0).key(100, 1.0).key(0, 1.0)` is a
    **two-second** clip — not a one-second one with keys at t = 1 and t = 1.

    Relative instead of absolute because absolute times would make inserting a
    keyframe mean renumbering every one after it.

| Call | Meaning |
|---|---|
| `key(v)` | Be `v` at the current position on the timeline. Used for the first key |
| `key(v, d)` | Reach `v` `d` seconds after the previous key, interpolating |
| `key(v, d, curve)` | The same, shaped by `curve` |
| `hold(d)` | Keep the previous value for `d` seconds |

A negative duration throws — a keyframe cannot arrive before the one it follows.
`hold()` before any `key()` throws too: there is nothing to hold.

#### The curve belongs to the key being moved *towards*

```dart
.key(100.0, 1.0, Curves.easeIn)
```

reads as "**ease into** 100", not "ease out of whatever came before". Any
Flutter `Curve` works, and `Curves.linear` is the default.

The curve shapes `t` between two keys *before* the blend, so an interpolator is
always a straight linear blend and never has to know what easing was asked for.

#### Tracks without arithmetic

A `Track<int>` for a sprite index, or a track of any type with no meaningful
midpoint, is **discrete**: it holds the previous value until the next key is
reached instead of inventing a value in between. That is correct for a frame
number and is the honest fallback for a type that cannot be interpolated.

```dart
..track(frame).key(0).key(3, 1.0)   // frames 0,1,2,3 — stepped, not blended
```

#### Multiple tracks in one clip

The `..` cascade is what lets one clip drive several tracks:

```dart
blink = descriptor.has()
  ..track(y).key(0.0).key(10.0, 1.0)
  ..track(frame).key(0).key(3, 1.0);
```

Each `track(...)` starts its own write head at zero, so the two chains are
independent timelines within the same clip.

---

## Next

[Performance rules →](performance.md)
