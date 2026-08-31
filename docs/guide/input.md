# Input

<!-- snippet-scope
// The actions and the game's own helpers this page reads without introducing.
late InputDescriptor descriptor;
late InputBinding<double> binding;
late Input<bool> attack;
late Input<bool> fire;
late Input<bool> jump;
late Input<bool> p1Jump;
late Input<bool> p2Jump;
late Input<double> throttle;
late Input<Vector2> move;
late Input<Vector2> movement;
late Input<CursorPosition> pointer;
late Input<PointerContacts> contacts;
late List<InputKey> savedKeys;
late Game game;
late CameraView camera;
late PointerContact contact;
Vector2 _saved = Vector2.zero();

void startDrag(int id, Vector2 at) {}
void moveDrag(int id, Vector2 at) {}
void endDrag(int id) {}
void wakeUp() {}
void shoot() {}
void stopShooting() {}
void startWalkAnimation() {}
void startIdleAnimation() {}
-->

!!! abstract "Layer: kernel (`good`)"

Input in good is **declared as actions**, not polled as keys. You declare what
the player can *do*; a binding says what currently produces it. That indirection
is what makes rebinding a one-line assignment, not a rewrite.

```dart
class PlayerSystem extends GameSystem with FixedTickable {
  final movement = Input.of(
    const Vec2Binding(
      up: InputKey.w, down: InputKey.s,
      left: InputKey.a, right: InputKey.d,
    ),
  );
  final fire = Input.of(const TriggerBinding(InputKey.spacebar));

  @override
  void onFixedUpdate() {
    final direction = movement.value;   // a Vector2
    if (fire.value) shoot();            // a bool — held
    // ...
  }
}
```

`Input.of` declares the action on the field that holds it. `V` comes off the
binding, so `movement` is an `Input<Vector2>` and `fire` an `Input<bool>`
without either being written out. An action nothing binds yet has nothing to
infer from, so that one says so: `Input.of<bool>()`.

The initialiser is a plain `final`, and has to be. `late final fire =
Input.of(...)` compiles and runs on the first *read* — long after boot sealed
the registry — so the action would be refused outright. It throws at the
declaration instead, naming the shape.

Declare inputs on a **`GameSystem`** (keeping the action beside the loop that
reads it) or on the **`Game`** (for actions several systems share). All sources
share one descriptor, so a type-level default registered anywhere is visible
everywhere.

`Input.of` works on both, and for the same reason: `SystemDescriptor.has` and
`Game.start` each take a constructor, so the framework does the building and
the registry is open while the fields initialise.

The hook survives on both as well, and there is one thing that needs it:
`hasDefaultValue` hands nothing back, so it has no field to live on. Either
owner may use both forms at once — its fields declare first, its hook second:

```dart
class MyGame extends Game {
  final openMenu = Input.of(const TriggerBinding(InputKey.escape));

  late final Input<double> throttle;

  @override
  void describeInputs(InputDescriptor input) {
    super.describeInputs(input);
    input.hasDefaultValue<double>(0);
    throttle = input.has<double>();
  }
}
```

That game starts as `Game.start(MyGame.new)` — a constructor, not an instance.
Building it yourself leaves `Input.of` with no registry to declare into, and it
says so rather than declaring into nothing.

## Where values come from

Raw key, button and contact state is collected on the Flutter isolate by
whatever `GameView` is in the tree, and **resolved on the game isolate once per
fixed tick**. Your action's value is therefore stable for the whole step — every
system in a step sees the same input.

!!! info "No `GameView`, no input"
    A game with no `GameView` in the widget tree has nothing feeding it, so
    every action reads its default forever. That is correct instead of broken,
    and it is why defaults are mandatory.

## Reading an action

**`value` is the normal read.** It is typed as whatever you declared, so an
`Input<bool>` reads as a plain bool and an `Input<Vector2>` as a vector:

```dart
if (fire.value) shoot();                 // held
final direction = movement.value;        // (0, -1) while W is down
```

| Member | Meaning |
|---|---|
| `value` | The value as of the most recent resolution. **What you usually want** |
| `wasPressedThisFrame` | The rising *edge* — true on exactly the tick it became actuated |
| `wasReleasedThisFrame` | The falling edge. Never true on the same resolution as a press |
| `binding` | What currently produces the value, or null if unbound |
| `pressed` / `released` | Event streams |

### Held versus the edge

For an `Input<bool>` the two are genuinely different questions, and reaching for
the wrong one is the classic input bug:

```dart
if (fire.value) shoot();                 // fires every tick it is held — full auto
if (fire.wasPressedThisFrame) shoot();   // fires once per press — semi-auto
```

`value` is what the binding *resolves to*; the edge flags are computed from
whether it is **actuated**, compared against the previous resolution. For a
`TriggerBinding` those coincide, so `wasPressedThisFrame` is simply
`value && !valueLastTick`.

Use `value` for anything continuous — movement, holding a shield up, a
throttle. Use the edge for anything that should happen **once per press**:
jumping, toggling a menu, a semi-automatic weapon, confirming a dialogue.

!!! tip "The edge works on non-bool actions too"
    This is the reason the flags exist instead of being left to `bool`
    actions. `Vec2Binding` is actuated when *any* of its four keys is down, so
    an `Input<Vector2>` can answer "did the player start moving this tick" —
    a question `value` cannot answer, because a vector has no previous-frame
    comparison built into it.

    ```dart
    if (movement.wasPressedThisFrame) startWalkAnimation();
    if (movement.wasReleasedThisFrame) startIdleAnimation();
    ```

`wasPressedThisFrame` and `wasReleasedThisFrame` are mutually exclusive by
construction — `down && !was` and `!down && was` cannot both hold — so a press
and a release can never land on the same resolution.

!!! danger "Do not keep `value` past the tick"
    For a `Vector2` this returns the **one instance** the action owns and
    mutates in place on every resolution — not a fresh copy per read, which
    would be a heap allocation per read per tick. Storing it in a field stores
    something that silently changes under you next tick.

    ```dart
    final v = movement.value;            // fine — used this tick
    _saved = movement.value;             // WRONG — aliases the live instance
    _saved = Vector2.copy(movement.value);  // if you really need to keep one
    ```

## Bindings

### `TriggerBinding` — one key, held or not

<!-- snippet-setup
late Input<bool> shoot;
-->
```dart
jump = descriptor.has<bool>(const TriggerBinding(InputKey.spacebar));
shoot = descriptor.has<bool>(const TriggerBinding(InputKey.leftMouseButton));
```

A mouse button binds exactly like a keyboard key — from an action's point of
view there is no difference, both are one bit.

### `Vec2Binding` — four keys composed into a vector

```dart
movement = descriptor.has<Vector2>(
  const Vec2Binding(
    up: InputKey.padLeftStickUp,
    down: InputKey.padLeftStickDown,
    left: InputKey.padLeftStickLeft,
    right: InputKey.padLeftStickRight,
  ),
);
```

!!! note "`up` is `+y`"
    `up` contributes **+1** to y and `down` −1, matching world space in both
    dimensions, so `transformOffsetY += movement.value.y * speed` moves the
    player the way the key is named. A game working in a y-down space swaps the
    two keys in the binding.

!!! note "Analog sticks are thresholded here"
    The `*Stick*` directions are not buttons on any real pad — they are analog
    axes thresholded into held/not-held bits by the gamepad collector, which is
    what lets a `Vec2Binding` compose them at all. A stick half-pushed reads
    like a stick slammed. Bind the stick's *axes* instead when you want the
    displacement — `StickBinding`, below.

### `StickBinding` — two axes composed into a vector

```dart
movement = descriptor.has<Vector2>(
  const StickBinding(x: InputAxis.padLeftStickX, y: InputAxis.padLeftStickY),
);
```

The proportional reading of the same stick: a stick half-pushed gives a vector
half as long, where `Vec2Binding` over the `*Stick*` keys gives a full one.
Components run −1..1 with **0 at rest**, `+1` up and `+1` right, the same
convention `Vec2Binding` follows.

Both readings of one physical stick are live at once — the collector writes the
axes and the thresholded bits from a single event — so which one a game gets is
which binding it declares. Nothing is normalized and no deadzone is applied:
`GamepadCollector.stickDeadzone` shapes the bits and leaves the axes alone,
because how an analog value should be shaped is the game's question.

### `AxisBinding` — one axis as a `double`

```dart
throttle = descriptor.has<double>(const AxisBinding(InputAxis.padRightTrigger), 0.0);
```

A trigger bound as a `TriggerBinding` is pulled or not; bound as an axis it is
pulled *this far*, 0..1. The default is spelled out because there is no
type-level default for `double` — see [Defaults](#defaults).

!!! warning "There is no threshold in either analog binding"
    Both are *actuated*, and so fire `pressed`/`released`, whenever the value
    is off rest at all. On a pad whose stick rests a hair off centre that is
    always. Bind the thresholded `*Stick*` key, or a button, when the edge is
    what you want.

### `MouseBinding` — pointer position

```dart
pointer = descriptor.has<CursorPosition>(const MouseBinding());
```

`CursorPosition` carries `screenSpace` (window coordinates), `viewSpace` (within
the `GameView`'s rect, which is the space to hit-test a HUD in) and the size of
the view the pointer is currently over — carried alongside the position because
with two views of different sizes on screen, "the view size" is only answerable
relative to a pointer.

### `ContactBinding` — fingers on the screen

```dart
contacts = descriptor.has<PointerContacts>(const ContactBinding());
```

A **contact** is one thing pressing on the screen: a finger, a stylus, or a
mouse with a button held. `PointerContacts` is all of them for the current tick,
indexed:

```dart
final pressing = contacts.value;
for (var i = 0; i < pressing.count; i++) {
  final contact = pressing[i];
  switch (contact.phase) {
    case PointerPhase.began:
      startDrag(contact.id, contact.viewSpace);
    case PointerPhase.held:
      moveDrag(contact.id, contact.viewSpace);
    case PointerPhase.ended:
    case PointerPhase.cancelled:
      endDrag(contact.id);
  }
}
```

Indexed and not `for (final c in pressing)`: a for-in builds an iterator per
tick, which is exactly the allocation this shape avoids. There is no `Iterable`
here to make that mistake with.

| Member | Meaning |
|---|---|
| `id` | Identifies the contact for its whole life, and is not reused |
| `phase` | `began`, `held`, `ended` or `cancelled` |
| `kind` | `touch`, `stylus`, `mouse` or `other` |
| `screenSpace` | Window coordinates |
| `viewSpace` | Coordinates inside the `GameView` — the space to hit-test in |
| `isOver` | `ended` or `cancelled`, the last tick this contact is reported |

The list is ordered by `id`, which is the order the contacts started, so
`contacts.value[0]` is the oldest one still pressing — "the finger", for a game
that only wants one. The **index is not stable**: a contact ending moves the
ones after it up a place. Follow a contact by its `id`.

Both the list and the `PointerContact` objects in it are scratch the action owns
and refills each tick. Read what you need during the tick; a contact kept until
the next one describes something else by then.

!!! warning "`cancelled` is not optional"
    A notification, an incoming call, the app losing focus, or a widget taking
    the gesture all end a contact with **no lift behind it**. A game that only
    ends a drag on `ended` leaves the player steering into a wall after a phone
    call, and nothing about testing by hand on a desk produces that. Handle
    `cancelled` wherever you handle `ended`; the position on a cancelled contact
    is where it was abandoned and says nothing about intent.

A mouse button held is a contact too, so a game written for fingers is playable
with a mouse and testable without a phone. A game that has its own mouse
controls skips `ContactKind.mouse` while reading — `MouseBinding` and the
mouse-button keys already report that press.

Bound to an action, contacts press when the first contact lands and release when
the last one leaves:

```dart
if (contacts.wasPressedThisFrame) wakeUp();
```

#### How many at once

`Game.maxPointerContacts` sizes the table — ten by default, which is every
finger on two hands. A press arriving while every slot is live is dropped whole,
so raise it if a game genuinely reads more:

```dart
class Tabletop extends Game {
  @override
  int get maxPointerContacts => 16;
}
```

It is read once, while the game is being constructed, because the raw block is
sized from it and both isolate copies index the contact table by offsets
computed from it.

#### What one fixed tick can see

The raw block is a latest-value snapshot sampled once per tick, so a contact
that presses and lifts entirely between two ticks is reported once, with
`ended` — its `began` tick never existed to be read. Fire a tap on the end for
that reason, which is also when a real tap gesture fires.

#### Screen to world

A contact reports in window and view coordinates. Turning that into world
coordinates needs the active camera, which is a `goo2d` component, so the
projection lives there — `PointerPickingSystem.projection` is the same
`CameraProjection` picking already inverts every tick:

<!-- snippet: skip CameraProjection is goo2d, and this page is the kernel guide -->
```dart
final projection = getSystem<PointerPickingSystem>().projection;
final worldX = projection.viewToWorldX(contact.viewSpace.x);
final worldY = projection.viewToWorldY(contact.viewSpace.y);
```

That projection is resolved against the view the **cursor** is in, which is the
right answer whenever one view is on screen. With several, ask
`game.viewOfContact(contact)` which view the contact landed in and resolve a
`CameraProjection` against that one — a contact is per finger, and two fingers
can be in two views at once, which one cursor never is.

#### Raw contacts, not gestures

Two fingers into one Flutter `GestureDetector`'s pan callbacks arrive as a
single drag, because `DragGestureRecognizer` is mono-drag by construction — so a
twin-stick scheme cannot be built on the gesture layer at all. Contacts come off
a raw `Listener` instead, which also means they reach a game with no widget: a
replay, a bot or a test writes them through `game.inputDevice`.

`GameView` does not claim the gesture arena. A `GameView` inside a `ListView`
therefore reads a drag the list is also scrolling on. Claiming the arena would
silence every Flutter gesture widget below the view, and in this engine a HUD is
a descendant — so put interactive widgets in a `Stack` **above** the `GameView`,
not inside it.

Two `GameView`s stacked over each other share one hit test, and the front one
takes the pointer. `GameView`'s `Listener` is translucent, so a finger over a
HUD view drawn above a world view is handed to both; only the front-most view
writes it. One finger is one contact however many views it passes through, and
`game.viewOfContact` and `game.pointerView` both name the view it visibly
landed in. A pointer outside the front view's box never reaches that view at
all, so the one behind takes it as usual.

#### On-screen sticks and buttons are widgets

An on-screen joystick is a Flutter widget in that `Stack`, feeding
`game.inputDevice?.setVirtualAxis(...)`. A game reading a `StickBinding` cannot
tell a thumb from a thumbstick, which is the point. `JoystickArea` and
`JoystickControl` are that widget, written once — see
[On-screen sticks](#on-screen-sticks). Buttons are still the game's to draw.

Wrap those widgets in `SafeArea` so they stay clear of a home indicator. **Do
not wrap `GameView` in one**: it takes its viewport from its constraints and
feeds `camera.setViewport`, so wrapping it letterboxes the art. Full-bleed art
with inset controls is the shape.

### `CompositeBinding` — one action, several sources

<!-- snippet-setup
late Input<bool> attack;
late Input<Vector2> move;
late List<InputKey> savedKeys;
-->
```dart
attack = descriptor.has<bool>(
  CompositeBinding(
    const TriggerBinding(InputKey.spacebar),
    const TriggerBinding(InputKey.leftMouseButton),
  ),
);

move = descriptor.has<Vector2>(
  CompositeBinding(
    const StickBinding(x: InputAxis.padLeftStickX, y: InputAxis.padLeftStickY),
    const Vec2Binding(
      up: InputKey.w, down: InputKey.s,
      left: InputKey.a, right: InputKey.d,
    ),
  ),
);
```

Space **or** left click; the stick **or** WASD. Every source is an
`InputBinding<T>` over the same `T`, so the composite is itself one binding of
that type and the action is declared exactly as it would be with one source.
Two to ten sources positionally, and `CompositeBinding.fromList` when the count
is only known at run time — which is what a rebinding screen has:

```dart
attack.binding = CompositeBinding<bool>.fromList(<InputBinding<bool>>[
  for (final key in savedKeys) TriggerBinding(key),
]);
```

**One action, one pair of edges.** The composite is *actuated* while any source
is, and the edges come off that one bit — so pressing the second source while
the first is held does not re-fire `wasPressedThisFrame`, and the release fires
once, when the last source goes up. Declaring two actions and `||`-ing their
edges instead is the shape to avoid: hold space, then click while still
holding, and both fire on their own tick, so one intended attack swings twice.

!!! note "Values merge, they do not take precedence"
    `resolve` folds the sources through `InputBinding.combine`, whose rule
    belongs to the value type: OR for `bool`, componentwise sum clamped to
    −1..1 for `Vector2`, furthest-from-rest for `double`.

    | held | reads |
    |---|---|
    | `w` + `arrowRight` | `(1, 1)` — the diagonal |
    | `w` + `arrowUp` | `(0, 1)` — the clamp, not `(0, 2)` |
    | `a` + `arrowRight` | `(0, 0)` — cancelling, as on one keyboard |
    | stick at `(0.5, 0)` + `w` | `(0.5, 1)` — both devices, not one |

    "First actuated source wins" would read straight off the `primary` /
    `secondary` naming and lose the first row: `w` keeps the WASD source
    actuated, so the arrow key would do nothing and a player using both halves
    of the keyboard could not move diagonally.

!!! warning "`MouseBinding` is not a source"
    A device has one cursor, so "the pointer is at either of two places" is not
    a position. A composite asserts against it at declare time. Mouse *buttons*
    are ordinary `TriggerBinding`s and compose like any other key.

This is the one binding that is **not `const`**: every source past the first
needs somewhere to resolve into that is not the action's own storage, and the
constructor makes those once, at declare time. Resolution itself allocates
nothing. The sources stay `const` values, which is where it mattered.

## On-screen sticks

Three widgets turn a finger into the virtual axes above. They are ordinary
Flutter widgets on the main isolate, they draw no engine art, and the only
engine thing they touch is the `Game` they are handed.

| widget | what it reads | what it draws |
|---|---|---|
| `JoystickArea` | a finger anywhere in its box, centring the stick where the finger lands | nothing, until it is given a `track` or a `thumb` |
| `JoystickControl` | a finger on a stick fixed to its own box | the stick, always |
| `Joystick` | nothing | a stick at an offset the caller holds |

A `JoystickArea` covering the left half of the screen turns that half into a
touchpad and leaves the right half to the game:

<!-- snippet: expr -->
```dart
Stack(
  children: [
    GameView(camera: camera),
    Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: 160,
      child: JoystickArea(game: game),
    ),
    Positioned(
      right: 40,
      bottom: 40,
      width: 120,
      height: 120,
      child: JoystickControl(
        game: game,
        x: InputAxis.virtualRightStickX,
        y: InputAxis.virtualRightStickY,
      ),
    ),
  ],
)
```

The game reads that through a `StickBinding` naming the same two axes, and
cannot tell the thumb from a thumbstick:

<!-- snippet: in GameSystem -->
```dart
@override
void describeInputs(InputDescriptor input) {
  super.describeInputs(input);
  move = input.has<Vector2>(
    const StickBinding(x: .virtualLeftStickX, y: .virtualLeftStickY),
  );
}
```

### The axis pair is the address

There is no stick number and no slot. A widget names the two `VirtualAxis`
values it writes and a binding names the two it reads, so a typo is a compile
error and two sticks are two axis pairs. `virtualLeftStickX`/`Y` is the
default, which leaves `virtualRightStickX`/`Y` for the second one.

Two widgets naming one pair fight over it: the last event wins, and the reading
flips between them.

### The value is -1..1, and it is proportional

Half the travel reads a half, the same range `StickBinding` delivers and
`Joystick.thumbOffset` takes, with **+1 up** to match the world's y. Past full
travel the value clamps to the circle, so a diagonal at the edge has a
magnitude of 1 and not 1.41.

`JoystickArea.radius` is the travel to full deflection in logical pixels, 64 by
default, and also half the width of the stick it draws. `JoystickControl` takes
its travel from its own box: half the shorter side, so the thumb reaches the
track's edge as the axis reaches 1. Both need a bounded box and assert without
one.

No deadzone and no response curve. The value is what the finger did; shaping is
the game's, the same call `AxisBinding` and `StickBinding` make for hardware.

### A finger can stop without lifting

A notification, an incoming call, or an ancestor winning the gesture arena ends
a pointer with no up event behind it. All three widgets return the stick to
rest on a cancel, on a lift, and on going away with a finger still down. A
stick that waited for a lift would hold its direction until the app was
restarted, which is the same hole `PointerPhase.cancelled` covers for contacts.

The first finger down owns the stick until it ends. A second one inside the
same widget is ignored, so two thumbs cannot fight over one pair.

### Drawing

`JoystickArea` and `JoystickControl` both take a `track` and a `thumb` widget,
and paint a default disc and ring for whichever is left null. The thumb's
position drives a repaint through a `Listenable`, so a drag rebuilds no
widgets — a builder taking the offset would rebuild once per pointer event, and
a drag produces them continuously.

Hit testing is opaque. A finger landing on a stick belongs to the stick and
does not also reach the `GameView` underneath as a contact.

Wrap a stick in `SafeArea` when its edges have to stay reachable: a control at
`bottom: 40` sits under the home indicator on most phones. **Do not wrap
`GameView`** in one — it takes its viewport from its constraints, so that
letterboxes the art.

On-screen **buttons** are not here. A `Listener` around whatever art the game
wants, calling `game.inputDevice?.press` and `release`, is the whole of one.

## Keys

`InputKey` carries every key as a `const`:

- letters `InputKey.a` … `InputKey.z`, digits, function keys
- modifiers, arrows, navigation, numpad
- mouse: `leftMouseButton`, `rightMouseButton`, `middleMouseButton`,
  `backMouseButton`, `forwardMouseButton`
- gamepad: `padA`, `padB`, `padLeftShoulder`, `padStart`, the stick directions —
  and per-slot variants by calling one: `InputKey.padA(1)`

!!! info "Keys are physical positions, not characters"
    `InputKey.w` is the key where a US-layout `W` sits, matched by USB HID
    usage. That choice is load-bearing twice over: a *logical* key changes when
    a modifier is held (`shift`+`1` gives `!`), so a logical binding held across
    a shift press would see a release it never got and stick down — and a
    logical key changes with layout, so WASD would land on ZQSD for a French
    player.

    The cost: `InputKey.q.name` describes the US-layout label,
    so a rebinding screen showing it to an AZERTY user names the key their
    keyboard prints "a" on.

## Axes

`InputAxis` is the second vocabulary, over the same block: a key is a bit and an
axis is a `float32`, so nothing that indexes bits could carry a half-pushed
stick. It carries every axis as a `const`, and slots work exactly as they do for
keys:

- gamepad: `padLeftStickX`, `padLeftStickY`, `padRightStickX`, `padRightStickY`,
  `padLeftTrigger`, `padRightTrigger` — and per-slot by calling one,
  `InputAxis.padLeftStickX(2)`. Slot 0 is "any connected pad", and for an axis
  that means whichever seat is pushed furthest from rest.
- on-screen: `virtualLeftStickX`, `virtualLeftStickY`, `virtualRightStickX`,
  `virtualRightStickY`, which no engine *system* writes. The three widgets in
  [On-screen sticks](#on-screen-sticks) do, and so does anything else calling
  `InputDevice.setVirtualAxis`.

A widget drives the virtual ones through `InputDevice.setVirtualAxis`, and a
binding cannot tell which kind of source filled a float in. So an on-screen
joystick and a real thumbstick reach a `StickBinding` the same way, and swapping
one for the other is a change of which axes it names.

## Defaults

Every action needs a default, because there is a real window — before the first
resolution, or with no `GameView` — where it has no value:

<!-- snippet: in Game2D -->
```dart
@override
void describeInputs(InputDescriptor input) {
  super.describeInputs(input);        // registers bool -> false, Vector2 -> zero
  input.hasDefaultValue<double>(0);   // a type-level default for your own T
  throttle = input.has<double>(binding, 0.5);   // this action's own default
}
```

`super.describeInputs` is `@mustCallSuper` because dropping the shipped defaults
is a *silent* failure: nothing breaks at declaration time, and the game runs
until the first read of an unbound action, which then throws.

The engine does **not** infer a default from `T`. Zero and false
are real, meaningful values to a game, and inventing one turns a forgotten
declaration into a number that is quietly wrong instead of an error that says
so. Declaring the same type twice in one boot is an error, not a silent
overwrite.

## Events

<!-- snippet: in GameSystem with GameSystemLifecycleListener -->
```dart
@override
void onMounted() {
  super.onMounted();
  fire.pressed += (event) => shoot();
  fire.released += (event) => stopShooting();
}
```

`+=` is the subscription — the stream appends and returns itself, which the
setter accepts back. Subscribe from `onMounted`, **not from a tick**: `+=` in
`onFixedUpdate` adds a subscriber sixty times a second.

`GameSystemLifecycleListener` is what supplies `onMounted`; `GameState.mount`
fires every system's `mountEvent` once the game's own `onMounted` has returned.

`-=` removes one. It compares by `==`, so a **method tear-off** can be removed
by writing it again:

<!-- snippet: in GameSystem with GameSystemLifecycleListener -->
```dart
@override
void onMounted() {
  super.onMounted();
  fire.pressed += onFire;      // an ordinary instance method
}

void onFire(InputEvent<bool> event) => shoot();

void stopListening() => fire.pressed -= onFire;   // a different tear-off, equal
```

A closure cannot: two closures written the same way are never equal, so
unsubscribing one means keeping the reference the `+=` used.

### The subscription cannot move onto the declaration

An action is declared on a field and subscribed in `onMounted`, and those two
halves cannot be folded into one line. Dart will not let a field initialiser
name an instance member, by any spelling:

<!-- snippet: skip shows the shapes the compiler rejects -->
```dart
final fire = Input.of(binding) + onFire;                    // implicit_this_reference_in_initializer
final fire = Input.of(binding) + ((e) => onFire(e));        // the same error - the restriction reaches into the closure
final fire = Input.of(binding) + ((e) => this.onFire(e));   // invalid_reference_to_this
```

What compiles there is a `static` method, a top-level function, or a closure
that captures nothing — three spellings of one answer, and it is the wrong one:
the handler cannot reach the object that declared the action, which is the state
an input handler exists to change. `late final` compiles and is the trap
`Input.of` already names, because the initialiser runs on the first read, after
boot has sealed the registry.

This is a compiler fact, not the no-closure rule. A listener *body* is hot, but
one built at mount is boot-time work and explicitly fine.

## Rebinding

An action's binding is a plain settable property, which is the whole point of
the indirection:

```dart
jump.binding = const TriggerBinding(InputKey.enter);
jump.binding = null;                    // unbound: reads its default, fires nothing
```

Takes effect on the next resolution, so a rebind never changes what a tick
already in progress sees. An **unbound action is a legitimate declared state**,
not an error — it is exactly what an action the player has not assigned a key to
should do.

Rebinding while the old binding is held produces a `released` on the next
resolution, so every `pressed` stays paired. *Unbinding* entirely does not — an
unbound action fires nothing by definition, so a press outstanding at that moment
goes unanswered. If that matters, unbind from the `released` handler.

### Saving bindings

Bindings serialise, which is what a rebinding screen needs:

```dart
final json = jump.binding!.toJson();
jump.binding = TriggerBinding.fromJson(json);

// A composite is restored the same way, with its value type written out.
final saved = attack.binding!.toJson();
attack.binding = CompositeBinding.fromJson<bool>(saved);
```

Keys serialise by **name**, not by index, so a saved binding survives a
reordering of the key table.

`fromJson` is a static on the concrete binding rather than a lookup, because a
restore site already knows which action it is restoring — it is the one that
declared it. A composite is the exception that proves it: its children are
heterogeneous by design, so it writes a `kind` tag around each one and
dispatches on that when it reads them back. The tags are the composite's own
format; every other binding's JSON is unchanged.

## Gamepads

Gamepads are collected per slot and normalised onto a standard Xbox-style
layout. `game.gamepads` exposes the collector.

A bare `InputKey.padA` is **slot 0, meaning "any connected pad"** — which is what
a single-player game wants. Calling it selects a seat: `InputKey.padA(1)` is the
A button on the first real controller, and there are three seats plus the
aggregate.

```dart
p1Jump = descriptor.has<bool>(TriggerBinding(InputKey.padA(1)));
p2Jump = descriptor.has<bool>(TriggerBinding(InputKey.padA(2)));
```

A slotted key is built at run time instead of being a `const`, so two calls
produce two instances — they compare equal by id, which is what a rebinding
screen comparing a saved key against a declared one needs.

---

## Next

[Assets →](assets.md)
