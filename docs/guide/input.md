# Input

<!-- snippet-scope
// The actions and the game's own helpers this page reads without introducing.
late InputDescriptor descriptor;
late InputBinding<double> binding;
late Input<bool> fire;
late Input<bool> jump;
late Input<bool> p1Jump;
late Input<bool> p2Jump;
late Input<double> throttle;
late Input<Vector2> movement;
late Input<CursorPosition> pointer;
Vector2 _saved = Vector2.zero();

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
  late final Input<Vector2> movement;
  late final Input<bool> fire;

  @override
  void describeInputs(InputDescriptor descriptor) {
    super.describeInputs(descriptor);
    movement = descriptor.has<Vector2>(
      const Vec2Binding(
        up: InputKey.w, down: InputKey.s,
        left: InputKey.a, right: InputKey.d,
      ),
    );
    fire = descriptor.has<bool>(const TriggerBinding(InputKey.spacebar));
  }

  @override
  void onFixedUpdate() {
    final direction = movement.value;   // a Vector2
    if (fire.value) shoot();            // a bool — held
    // ...
  }
}
```

Declare inputs on a **`GameSystem`** (keeping the action beside the loop that
reads it) or on the **`Game`** (for actions several systems share). All sources
share one descriptor, so a type-level default registered anywhere is visible
everywhere.

## Where values come from

Raw key and button state is collected on the Flutter isolate by whatever
`GameView` is in the tree, and **resolved on the game isolate once per fixed
tick**. Your action's value is therefore stable for the whole step — every
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
  `virtualRightStickY`, which nothing in the engine writes.

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
```

Keys serialise by **name**, not by index, so a saved binding survives a
reordering of the key table.

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
