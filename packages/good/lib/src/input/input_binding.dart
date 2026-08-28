import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import 'package:good/src/input/input_axis.dart';
import 'package:good/src/input/input_key.dart';
import 'package:good/src/input/input_state.dart';

/// How the raw device state - held-or-not key bits, and the axis floats
/// beside them - becomes one action's value.
///
/// A binding is an **immutable value type**: `const`-constructible, `==` by
/// content, `copyWith`-able and serializable. That is what makes a keybinding
/// a piece of data a game can save, load, diff and hand to a rebinding screen
/// instead of behaviour compiled into a system. Nothing here holds a
/// reference to the action it is bound to, so one binding value can be shared
/// by any number of actions and swapped in and out freely
/// (`triggerSkill.binding = const TriggerBinding(.enter)`).
///
/// [CompositeBinding] is the one exception to `const`, and says why: it owns a
/// scratch value per source so that folding several sources together allocates
/// nothing per tick, and scratch cannot be built in a `const` constructor. It
/// is still immutable in every way that matters here - `==` by content,
/// serializable, and nothing in it changes once it is built.
///
/// # `copyWith` and `fromJson` are per concrete type
///
/// Neither is declared here. `copyWith`'s parameters differ per binding
/// (a trigger has one key, a vector has four), and `fromJson` is a static -
/// at a restore site you already statically know which binding you are
/// restoring, because you are the one who declared it:
///
/// ```dart
/// ping.binding = TriggerBinding.fromJson(json['ping'] as Map<String, Object?>);
/// json['ping'] = ping.binding!.toJson();
/// ```
///
/// So there is no binding registry and no framework-owned save format: a
/// registry could only turn a string back into a type you already named in
/// the line you are writing.
///
/// The cost, stated plainly: because `binding` is statically an
/// `InputBinding<T>?`, `movement.binding!.copyWith(right: .arrowRight)` does
/// not type-check - `copyWith` is not on this class. Tweak one axis by
/// starting from the concrete value instead, which is also where the rest of
/// the axes are legible:
///
/// ```dart
/// static const _walk = Vec2Binding(up: .w, down: .s, left: .a, right: .d);
/// movement.binding = _walk.copyWith(right: .arrowRight);
/// // or, from whatever is currently bound:
/// movement.binding = (movement.binding! as Vec2Binding).copyWith(right: .arrowRight);
/// ```
///
/// # Everything below runs per action per fixed tick
///
/// [resolve] and [isActuated] are the resolution pass (see `Input`), so they
/// must not allocate and must not close over anything (the no-allocation,
/// hot-event and no-closure rules). That is why [resolve] writes into storage
/// the action owns and hands it back, instead of returning a fresh value.
@immutable
abstract class InputBinding<T> {
  const InputBinding();

  /// Fresh scratch for an action to own and [resolve] to write into.
  ///
  /// Called **once**, at declare time (or the moment an action that was
  /// declared unbound is first bound) - never per tick. Its initial contents
  /// are unspecified and are never observed: `Input.value` returns the declared
  /// default until the first resolution overwrites this wholesale. For a value
  /// type like `bool` there is nothing to own, and this returns a placeholder
  /// [resolve] ignores.
  T createStorage();

  /// Computes this tick's value from [state], writing into [storage] and
  /// returning it.
  ///
  /// The return-what-you-were-given shape is what keeps `Input<Vector2>.value`
  /// a single object the action owns for its whole life, not a fresh `Vector2`
  /// sixty times a second.
  T resolve(InputState state, T storage);

  /// Whether this binding counts as *held* right now - the single bit
  /// `wasPressedThisFrame`, `wasReleasedThisFrame`, `pressed` and `released`
  /// are all derived from.
  ///
  /// Separate from [resolve] because "the value changed" and "the action was
  /// pressed" are different questions: a `Vec2Binding` whose value goes from
  /// (1, 0) to (0, 1) changed without ever being released, and a listener
  /// that only saw "value changed" would have to work the edge out itself.
  bool isActuated(InputState state);

  /// Merges two values of this binding's type into one, for
  /// [CompositeBinding] - "what the action reads when *both* of its sources
  /// are producing something".
  ///
  /// The rule is a property of `T`, not of the composite:
  ///
  /// | `T` | rule |
  /// |---|---|
  /// | `bool` | OR |
  /// | `Vector2` | componentwise sum, clamped to -1..1 |
  /// | `double` | whichever is further from rest |
  ///
  /// It lives here and not on [CompositeBinding] because a
  /// `CompositeBinding<T>` would have to switch on `T` to pick one, and it
  /// cannot know every value type a game will ever bind. Every source in a
  /// composite shares `T` by construction, so any one of them can supply the
  /// rule and the composite folds with the primary's.
  ///
  /// # It must not allocate
  ///
  /// Called per composite per tick, so for a reference `T` this **writes into
  /// [a] and returns it** rather than returning a fresh value - the same
  /// return-what-you-were-given shape [resolve] has, and for the same reason.
  /// [b] is read-only here.
  ///
  /// Not commutative in identity, then, only in value: `combine(a, b)` and
  /// `combine(b, a)` produce the same numbers in different objects.
  T combine(T a, T b);

  /// This binding as plain JSON-able maps, for the game's own save file. The
  /// inverse is a static `fromJson` on the concrete type - see the class doc.
  Map<String, Object?> toJson();
}

/// One key, one bool: the action is true exactly while [key] is held.
///
/// Binds a mouse button exactly as happily as a keyboard key
/// (`TriggerBinding(.leftMouseButton)`) - both are one bit.
final class TriggerBinding extends InputBinding<bool> {
  const TriggerBinding(this.key);

  final InputKey key;

  @override
  bool createStorage() => false;

  @override
  bool resolve(InputState state, bool storage) => state.isDown(key);

  @override
  bool isActuated(InputState state) => state.isDown(key);

  /// OR: the action is held while *either* source is, which is what "space or
  /// left click" means.
  @override
  bool combine(bool a, bool b) => a || b;

  TriggerBinding copyWith({InputKey? key}) => TriggerBinding(key ?? this.key);

  @override
  Map<String, Object?> toJson() => <String, Object?>{'key': key.toJson()};

  static TriggerBinding fromJson(Map<String, Object?> json) =>
      TriggerBinding(InputKey.fromJson(_map(json, 'key')));

  @override
  bool operator ==(Object other) =>
      other is TriggerBinding && identical(other.key, key);

  @override
  int get hashCode => Object.hash(TriggerBinding, key.id);

  @override
  String toString() => 'TriggerBinding(${key.name})';
}

/// Four keys composed into one vector: the classic WASD / arrow-keys pair of
/// axes.
///
/// ```dart
/// movement = input.has<Vector2>(const Vec2Binding(up: .w, down: .s, left: .a, right: .d));
/// ```
///
/// # What it produces
///
/// Each axis is the difference of its two keys, so opposing keys cancel to
/// exactly zero (holding `a` and `d` together stands still instead of picking
/// whichever was pressed last). The result is **not normalized**:
/// holding up and right gives (1, 1), whose length is √2, not 1. Normalizing
/// here would be a silent policy decision - a top-down walker wants it, a
/// twin-stick shooter feeding an acceleration does not - and it is one call
/// (`movement.value.normalized()`) away at the use site, where the game knows
/// which it wants. Note `normalized()` allocates; `..normalize()` on a copy
/// the system owns does not.
///
/// # Which way is up
///
/// [up] contributes **+1** to y and [down] -1, matching the world-space
/// convention both dimensions use: `goo2d` and `goo3d` put +y up, so adding
/// this vector straight to a `transformOffsetY` moves the thing the way the
/// key is named. That is the whole point of the sign - a binding whose `up`
/// moved a sprite down would be the sort of inversion that compiles.
///
/// A game working in a y-down space swaps the two keys in the binding - which
/// is a one-line data change, and exactly the kind of thing bindings exist to
/// make cheap.
final class Vec2Binding extends InputBinding<Vector2> {
  const Vec2Binding({
    required this.up,
    required this.down,
    required this.left,
    required this.right,
  });

  final InputKey up;
  final InputKey down;
  final InputKey left;
  final InputKey right;

  @override
  Vector2 createStorage() => Vector2.zero();

  @override
  Vector2 resolve(InputState state, Vector2 storage) {
    var x = 0.0;
    var y = 0.0;
    if (state.isDown(right)) x += 1;
    if (state.isDown(left)) x -= 1;
    if (state.isDown(up)) y += 1;
    if (state.isDown(down)) y -= 1;
    // In place, into the action's own vector: `Vector2(x, y)` here would be
    // one heap object per action per tick (the no-allocation rule).
    storage.setValues(x, y);
    return storage;
  }

  /// Held if *any* of the four keys is - so `pressed` fires when the player
  /// starts moving and `released` when they stop, not on every change of
  /// direction. Four bit tests, no allocation.
  @override
  bool isActuated(InputState state) =>
      state.isDown(up) ||
      state.isDown(down) ||
      state.isDown(left) ||
      state.isDown(right);

  /// Componentwise sum, clamped - see [_sumClamped]. Because [resolve] does
  /// not normalize, this is exactly the per-direction union: two of these
  /// combined behave like pressing all the keys on one keyboard.
  @override
  Vector2 combine(Vector2 a, Vector2 b) => _sumClamped(a, b);

  Vec2Binding copyWith({
    InputKey? up,
    InputKey? down,
    InputKey? left,
    InputKey? right,
  }) => Vec2Binding(
    up: up ?? this.up,
    down: down ?? this.down,
    left: left ?? this.left,
    right: right ?? this.right,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'up': up.toJson(),
    'down': down.toJson(),
    'left': left.toJson(),
    'right': right.toJson(),
  };

  static Vec2Binding fromJson(Map<String, Object?> json) => Vec2Binding(
    up: InputKey.fromJson(_map(json, 'up')),
    down: InputKey.fromJson(_map(json, 'down')),
    left: InputKey.fromJson(_map(json, 'left')),
    right: InputKey.fromJson(_map(json, 'right')),
  );

  @override
  bool operator ==(Object other) =>
      other is Vec2Binding &&
      identical(other.up, up) &&
      identical(other.down, down) &&
      identical(other.left, left) &&
      identical(other.right, right);

  @override
  int get hashCode =>
      Object.hash(Vec2Binding, up.id, down.id, left.id, right.id);

  @override
  String toString() =>
      'Vec2Binding(up: ${up.name}, down: ${down.name}, left: ${left.name}, '
      'right: ${right.name})';
}

/// One axis, one double: how far [axis] is displaced this tick.
///
/// ```dart
/// throttle = input.has<double>(const AxisBinding(.padRightTrigger), 0.0);
/// ```
///
/// The analog counterpart of [TriggerBinding], and the difference between them
/// is the whole point: a trigger bound as a bit is pulled or not, and a trigger
/// bound as an axis is pulled *this far*. Both readings of the same physical
/// control are available at once, because the collector writes both.
///
/// # What it produces
///
/// -1..1 with **0 at rest** for a stick axis, 0..1 for a trigger, and whatever
/// the device reported in between - no deadzone, no curve, no clamp. A resting
/// stick with a little drift therefore reads a little off zero, which is a
/// real fact about the hardware and not something to hide here: shaping is
/// the game's, and `GamepadCollector.stickDeadzone` still shapes the *bit*
/// reading it always did.
///
/// # There is no default for `double`
///
/// `Game.describeInputs` registers a type-level default for `bool` and
/// `Vector2` and not for `double`, so an action bound to this needs one of its
/// own - the `0.0` above - or a `hasDefaultValue<double>(0)` beside it.
/// Reading one that has neither throws. That is the engine refusing to guess,
/// not an omission: for a game, zero is a real value.
final class AxisBinding extends InputBinding<double> {
  const AxisBinding(this.axis);

  final InputAxis axis;

  @override
  double createStorage() => 0;

  @override
  double resolve(InputState state, double storage) => state.axis(axis);

  /// Held whenever the axis is off rest at all - so `pressed` fires when the
  /// player starts pulling and `released` when they let go.
  ///
  /// "At all" and not "past some threshold" because the threshold is the open
  /// question in #192 and this is not the place to answer it. It has a real
  /// consequence worth knowing: on a pad whose stick rests a hair off centre,
  /// an action bound to a stick axis reads as held forever. Bind the
  /// thresholded `*Stick*` key, or a button, when it is the edge you want.
  @override
  bool isActuated(InputState state) => state.axis(axis) != 0;

  /// Whichever is further from rest, which is the rule #192 settled for
  /// aggregating one control across gamepad slots: two hands on two devices
  /// pushing the same action does not push it twice as hard, and a pull of
  /// 0.8 is not diluted by a second source resting at 0.
  ///
  /// Ties go to [a], so a fold over sources in declaration order keeps the
  /// earlier one - which only matters when the two are equal in magnitude and
  /// opposite in sign, where there is no better answer than "the first".
  @override
  double combine(double a, double b) => b.abs() > a.abs() ? b : a;

  AxisBinding copyWith({InputAxis? axis}) => AxisBinding(axis ?? this.axis);

  @override
  Map<String, Object?> toJson() => <String, Object?>{'axis': axis.toJson()};

  static AxisBinding fromJson(Map<String, Object?> json) =>
      AxisBinding(InputAxis.fromJson(_map(json, 'axis')));

  @override
  bool operator ==(Object other) => other is AxisBinding && other.axis == axis;

  @override
  int get hashCode => Object.hash(AxisBinding, axis.id);

  @override
  String toString() => 'AxisBinding(${axis.name})';
}

/// Two axes composed into one vector: a stick, read the way a stick actually
/// moves.
///
/// ```dart
/// move = input.has<Vector2>(
///   const StickBinding(x: .padLeftStickX, y: .padLeftStickY),
/// );
/// ```
///
/// The analog counterpart of [Vec2Binding], and what #192 exists to add. That
/// one composes four held-or-not keys, so a stick half-pushed reads exactly
/// like a stick slammed; this one reads the two floats the device actually
/// reported, so a stick half-pushed reads about half. Both remain available on
/// the same physical stick - the collector writes the thresholded bits and the
/// axes from one event - and a game picks its reading by picking its binding.
///
/// # What it produces
///
/// Each component is its axis, unshaped: -1..1 with **0 at rest**, +1 up and
/// +1 right, which is the convention [Vec2Binding] already follows and the one
/// the world uses, so `transformOffsetY += move.value.y * speed` moves the
/// thing the way the player pushed.
///
/// Not normalized, for the reason [Vec2Binding] is not: a corner-pushed stick
/// on hardware with a square gate is longer than 1, a top-down walker wants
/// that clamped and a twin-stick shooter feeding an acceleration does not, and
/// the game is the one that knows which.
///
/// # It does not care what moved it
///
/// An [InputAxis] is a float in the raw block, and a widget writing through
/// `InputDevice.setVirtualAxis` fills one in exactly as `GamepadCollector`
/// does for a pad. So the on-screen joystick of #191 and a real thumbstick
/// reach this the same way, and swapping one for the other is a change of
/// which axes the binding names.
final class StickBinding extends InputBinding<Vector2> {
  const StickBinding({required this.x, required this.y});

  final InputAxis x;
  final InputAxis y;

  @override
  Vector2 createStorage() => Vector2.zero();

  @override
  Vector2 resolve(InputState state, Vector2 storage) {
    // In place, into the action's own vector, for the reason Vec2Binding does
    // it: a fresh Vector2 here is one heap object per action per tick.
    storage.setValues(state.axis(x), state.axis(y));
    return storage;
  }

  /// Held whenever *either* axis is off rest - so `pressed` fires when the
  /// player starts pushing and `released` when the stick comes back to centre,
  /// not on every change of direction, which is the edge [Vec2Binding] gives
  /// for the same reason.
  ///
  /// The caveat on [AxisBinding.isActuated] applies here too: with no
  /// threshold, a stick that rests a hair off centre reads as held forever.
  @override
  bool isActuated(InputState state) => state.axis(x) != 0 || state.axis(y) != 0;

  /// The same componentwise sum [Vec2Binding.combine] uses, which is what
  /// makes a composite of a stick and a WASD binding coherent: both are
  /// `InputBinding<Vector2>`, and a stick at (0.5, 0) with `w` held reads
  /// (0.5, 1) rather than discarding one of the two devices.
  @override
  Vector2 combine(Vector2 a, Vector2 b) => _sumClamped(a, b);

  StickBinding copyWith({InputAxis? x, InputAxis? y}) =>
      StickBinding(x: x ?? this.x, y: y ?? this.y);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'x': x.toJson(),
    'y': y.toJson(),
  };

  static StickBinding fromJson(Map<String, Object?> json) => StickBinding(
    x: InputAxis.fromJson(_map(json, 'x')),
    y: InputAxis.fromJson(_map(json, 'y')),
  );

  @override
  bool operator ==(Object other) =>
      other is StickBinding && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(StickBinding, x.id, y.id);

  @override
  String toString() => 'StickBinding(x: ${x.name}, y: ${y.name})';
}

/// The `Vector2` merge rule, shared by [Vec2Binding.combine] and
/// [StickBinding.combine] so a composite mixing the two cannot end up with
/// two different answers depending on which source happens to be primary.
///
/// Componentwise sum clamped to -1..1, **in place into [a]**, which is what
/// keeps a composite's resolution free of per-tick allocation. Clamped rather
/// than left to run: two sources both pushing right is still "right", not
/// "twice as far right", and a game that wants the raw sum can read the
/// sources itself.
///
/// Written out rather than `num.clamp`, which returns `num` and so boxes on
/// the way back out.
Vector2 _sumClamped(Vector2 a, Vector2 b) {
  a.setValues(_clampUnit(a.x + b.x), _clampUnit(a.y + b.y));
  return a;
}

double _clampUnit(double v) => v < -1
    ? -1
    : v > 1
    ? 1
    : v;

/// Pulls a nested key or axis map out of a decoded JSON object with a
/// diagnostic that names the field, instead of letting a bare cast fail with
/// the type alone.
Map<String, Object?> _map(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException(
    'expected "$field" to hold a serialized InputKey or InputAxis object, '
    'found $value',
    json,
  );
}

/// Where the pointer is, in every space the engine can answer for.
///
/// One instance per declared action, mutated in place by [MouseBinding] each
/// tick - so `Input<CursorPosition>.value` is the same object for the life of
/// the game and reading it allocates nothing (the no-allocation rule). Treat
/// it, and the vectors it hands out, as read-only and do not hold either past
/// the current tick.
///
/// # Which spaces are here, and which is not
///
/// [screenSpace] and [viewSpace] are *captured*, on the Flutter isolate, at
/// the moment the pointer event arrives - the window position and the
/// position within the `GameView`'s own rect. Both cross the wire as plain
/// numbers.
///
/// **World space is absent**, and that is a layering fact and not an
/// omission: projecting a pointer into the world needs the active
/// camera, `Camera` is a `goo2d` component, and this is `good`. A kernel that
/// knew how to project would have to know what a camera is, which is exactly
/// the dependency the `good`/`goo2d` split exists to avoid - the same reason
/// `GameView` paints nothing and lets a declared render system do it. `goo2d`
/// supplies the projection, against the camera it already resolves every
/// frame: `MousePickingSystem` keeps the cursor's world position in
/// `worldSpace` and its `CameraProjection` in `projection`, and its
/// `MousePickingAccess` extension puts a `mousePicking` shortcut on every
/// component so nothing has to spell out `getSystem<MousePickingSystem>()`.
final class CursorPosition {
  @internal
  CursorPosition();

  /// The pointer in window coordinates, origin at the window's top-left.
  final Vector2 screenSpace = Vector2.zero();

  /// The pointer within the `GameView`'s rect, origin at its top-left.
  /// Independent of where the view sits in the window, which is what makes
  /// this the space to hit-test a HUD in.
  final Vector2 viewSpace = Vector2.zero();

  /// The size in logical pixels of the `GameView` the pointer is **currently
  /// over**, or zero before anything has laid out (or on a game with no widget
  /// at all - see `InputDevice`).
  ///
  /// Per view, not per game: with two views on screen of different
  /// sizes, "the view size" is only answerable relative to a pointer, and the
  /// widget that received the event is what supplies it.
  ///
  /// Carried alongside the position because every use of [viewSpace] that is
  /// not a raw hit test wants it: centring, edge detection and the
  /// view-to-world projection all need to know how big the view is, and
  /// asking the widget tree for it from the game isolate is not possible.
  final Vector2 viewSize = Vector2.zero();

  @override
  String toString() =>
      'CursorPosition(view: ${viewSpace.x}, ${viewSpace.y} of '
      '${viewSize.x}x${viewSize.y})';
}

/// Binds an action to the pointer's position.
///
/// ```dart
/// cursor = input.has<CursorPosition>(const MouseBinding());
/// ```
///
/// Nothing to configure and nothing to name: there is one pointer, so unlike
/// [TriggerBinding] this takes no [InputKey]. Mouse *buttons* are ordinary
/// triggers (`TriggerBinding(InputKey.leftMouseButton)`) - only the position
/// needs its own binding, because it is the one input that is not a bit.
///
/// [isActuated] is always false: a position has no pressed/released edge, so
/// `wasPressedThisFrame` and the `pressed`/`released` streams never fire for
/// an action bound to one. Bind a button if you want the click.
final class MouseBinding extends InputBinding<CursorPosition> {
  const MouseBinding();

  @override
  CursorPosition createStorage() => CursorPosition();

  @override
  CursorPosition resolve(InputState state, CursorPosition storage) {
    storage.screenSpace.setValues(state.pointerScreenX, state.pointerScreenY);
    storage.viewSpace.setValues(state.pointerViewX, state.pointerViewY);
    storage.viewSize.setValues(state.viewWidth, state.viewHeight);
    return storage;
  }

  @override
  bool isActuated(InputState state) => false;

  /// Throws. A device has **one** cursor, so there is no answer to "the
  /// pointer is at both of these places": summing two positions gives a point
  /// neither pointer is at, and picking one silently ignores a source the
  /// caller asked for.
  ///
  /// That is why [MouseBinding] does not go in a [CompositeBinding], which
  /// asserts against it at declare time and has no wire tag for it. This is
  /// the release-mode backstop for the same mistake - and the honest answer
  /// for anyone calling [combine] directly.
  @override
  CursorPosition combine(CursorPosition a, CursorPosition b) {
    throw UnsupportedError(
      'CursorPosition values cannot be merged, so a MouseBinding cannot be a '
      'source in a CompositeBinding: a device has one cursor, and "the '
      'pointer is at either of two places" is not a position. Bind the '
      'pointer on its own action; compose the mouse *buttons*, which are '
      'ordinary TriggerBindings, if that is what was wanted.',
    );
  }

  MouseBinding copyWith() => const MouseBinding();

  @override
  Map<String, Object?> toJson() => const <String, Object?>{};

  /// Round-trips, trivially - there is no state to restore. Present so a
  /// rebinding screen can serialize every binding uniformly without
  /// special-casing this one.
  static MouseBinding fromJson(Map<String, Object?> json) =>
      const MouseBinding();

  @override
  bool operator ==(Object other) => other is MouseBinding;

  @override
  int get hashCode => (MouseBinding).hashCode;

  @override
  String toString() => 'MouseBinding()';
}

/// One action, several sources: `attack` on the spacebar **or** the left mouse
/// button, `move` on the left stick **or** WASD.
///
/// ```dart
/// move = input.has<Vector2>(
///   CompositeBinding(
///     const StickBinding(x: .padLeftStickX, y: .padLeftStickY),
///     const Vec2Binding(up: .w, down: .s, left: .a, right: .d),
///   ),
/// );
///
/// attack = input.has<bool>(
///   CompositeBinding(
///     const TriggerBinding(.spacebar),
///     const TriggerBinding(.leftMouseButton),
///   ),
/// );
/// ```
///
/// Every source is an `InputBinding<T>` for the same `T`, so the composite is
/// itself one binding of that type and nothing about [Input] or
/// `InputDescriptor.has` changes. A composite is a legal source of another
/// composite, and nests to any depth.
///
/// # The edges come out right, with no state of its own
///
/// [isActuated] is "any source is actuated", and the action derives
/// `wasPressedThisFrame`/`wasReleasedThisFrame` from that one bit. So pressing
/// the second source while the first is still held does **not** re-fire
/// `pressed`, and the release fires once, when the last source goes up. That
/// is the whole reason to compose here instead of declaring two actions and
/// `||`-ing their edges at the use site: two actions have two edges, and a
/// player holding space and then clicking swings twice.
///
/// # Values merge, they do not take precedence
///
/// [resolve] folds every source through [InputBinding.combine] - OR for
/// `bool`, componentwise sum clamped to -1..1 for `Vector2`, furthest-from-rest
/// for `double`.
///
/// Precedence - "walk the sources and take the first actuated one" - reads
/// straight off the argument names and is wrong. Hold `w`, then press
/// `arrowRight`: the WASD source is still actuated, so it still supplies
/// (0, 1) and the arrow key does nothing. A player using both halves of the
/// keyboard could not move diagonally. Summing gives (1, 1), and because
/// [Vec2Binding] does not normalize, summing two of them **is** the
/// per-direction union - `w` + `arrowUp` is (0, 1), not (0, 2), and
/// `a` + `arrowRight` cancels to (0, 0) exactly as pressing both on one
/// keyboard does.
///
/// # It allocates at declare time and never again
///
/// Every source but the first needs somewhere to resolve into that is not the
/// action's own storage, and [createStorage] is what makes those: one per
/// extra source, built in this constructor. So constructing a composite is
/// **not `const`** - that is the price of the scratch, and it is paid once, in
/// the `describeInputs` pass. The sources themselves stay `const` values,
/// which is where the `const` mattered.
///
/// One consequence worth knowing: the scratch belongs to the composite, not to
/// the action, so one composite instance shared by two actions shares it. That
/// is safe because a scratch is filled and consumed inside a single [resolve]
/// call and never read across ticks - but it is why this is the one binding
/// whose instances are not entirely interchangeable with equal ones.
///
/// # [MouseBinding] is not a source
///
/// A device has one cursor, so "the pointer is at either of two places" is not
/// a position. The constructor asserts against it, this format has no tag for
/// it, and [MouseBinding.combine] throws if the first two are somehow got
/// past. Mouse *buttons* are ordinary [TriggerBinding]s and compose freely.
///
/// # Serialization carries a kind tag, and only here
///
/// A composite's children are heterogeneous by design, so unlike every other
/// binding it cannot be told statically what it is restoring. [toJson] wraps
/// each child in a `{'kind': ..., 'binding': ...}` envelope and [fromJson]
/// dispatches on that - the same shape [InputKey.fromJson] already uses.
///
/// The tags are this class's own format and nothing else's: every other
/// binding's `toJson` output is exactly what it always was, and the
/// [InputBinding] doc's "no binding registry and no framework-owned save
/// format" still holds for all five of them.
final class CompositeBinding<T> extends InputBinding<T> {
  /// Two to ten sources, known where they are written.
  ///
  /// Ten positional parameters for the reason `_QueryBuilder._mask` gives:
  /// Dart has no varargs, and `withAll`/`withOptional` already stop at ten.
  /// Sugar over [CompositeBinding.fromList] - see that constructor for why
  /// there is one storage shape and not two.
  CompositeBinding(
    InputBinding<T> primary,
    InputBinding<T> secondary, [
    InputBinding<T>? c,
    InputBinding<T>? d,
    InputBinding<T>? e,
    InputBinding<T>? f,
    InputBinding<T>? g,
    InputBinding<T>? h,
    InputBinding<T>? i,
    InputBinding<T>? j,
  ]) : this.fromList(<InputBinding<T>>[
         primary,
         secondary,
         ?c,
         ?d,
         ?e,
         ?f,
         ?g,
         ?h,
         ?i,
         ?j,
       ]);

  /// Sources whose count is not known until run time - a rebinding screen
  /// rebuilding an action from what the player chose, or [fromJson] rebuilding
  /// one from a save.
  ///
  /// ```dart
  /// attack.binding = CompositeBinding<bool>.fromList(<InputBinding<bool>>[
  ///   for (final key in savedKeys) TriggerBinding(key),
  /// ]);
  /// ```
  ///
  /// [sources] is copied, so a later mutation of the list passed in does not
  /// reach the binding.
  ///
  /// # Why the positional form is sugar over this, and not a second shape
  ///
  /// Ten nullable fields would keep the common case off a `List`, which is the
  /// trade `_QueryBuilder._mask` makes. It buys nothing here. The scratch is a
  /// list in a field that [resolve] walks whatever the constructor looked
  /// like, so the hot path already has one; the list a positional call
  /// allocates is allocated once, at declare time, beside that scratch; and
  /// `const` - the other thing a fields-based shape would have bought - is off
  /// the table anyway, because the scratch cannot be built in a `const`
  /// constructor. What two shapes would actually buy is two of everything: two
  /// [resolve]s, two [toJson]s, two `==`s.
  ///
  /// Throws an [ArgumentError] on an empty list. An action the player has
  /// bound nothing to is `binding = null`, which is a declared, meaningful
  /// state; a composite of nothing is not.
  CompositeBinding.fromList(List<InputBinding<T>> sources)
    : sources = _checked(sources),
      _scratch = _scratchFor(sources);

  /// What this composite reads, in the order it folds them. Unmodifiable, and
  /// public because a rebinding screen listing "what is bound to attack" needs
  /// exactly this.
  final List<InputBinding<T>> sources;

  /// Somewhere for every source but the first to [resolve] into, since the
  /// first resolves into the action's own storage. `_scratch[i - 1]` belongs
  /// to `sources[i]`.
  ///
  /// Built once, here, from each source's own [createStorage] - never per
  /// tick. For a value type like `bool` these are the same placeholders
  /// [createStorage] hands back everywhere else, and [resolve] ignores them.
  final List<T> _scratch;

  static List<InputBinding<T>> _checked<T>(List<InputBinding<T>> sources) {
    if (sources.isEmpty) {
      throw ArgumentError.value(
        sources,
        'sources',
        'a CompositeBinding needs at least one source - it is what the action '
            'reads, and there is nothing to read from none of them. An action '
            'with nothing bound to it is action.binding = null, which resolves '
            'to its default and fires nothing.',
      );
    }
    assert(
      !sources.any((source) => source is MouseBinding),
      'a MouseBinding cannot be a source in a CompositeBinding: a device has '
      'one cursor, so "the pointer is at either of two places" is not a '
      'position - summing two gives a point neither pointer is at, and '
      'picking one silently drops a source the caller asked for. Bind the '
      'pointer on its own action. Mouse buttons are ordinary TriggerBindings '
      'and compose like any other key.',
    );
    return List<InputBinding<T>>.unmodifiable(sources);
  }

  static List<T> _scratchFor<T>(List<InputBinding<T>> sources) =>
      List<T>.generate(
        sources.length - 1,
        (index) => sources[index + 1].createStorage(),
        growable: false,
      );

  /// The primary's storage: the action's value is whatever the fold ends up
  /// holding, and the fold starts by resolving `sources[0]` straight into it.
  @override
  T createStorage() => sources[0].createStorage();

  /// Resolves every source and folds them with [InputBinding.combine].
  ///
  /// Allocation-free: `sources[0]` writes into the action's own [storage] and
  /// each later source writes into the scratch the constructor already made
  /// for it, so a `Vector2` composite mutates two vectors that have existed
  /// since declare time and creates none.
  @override
  T resolve(InputState state, T storage) {
    // The fold's rule comes off sources[0] rather than off `this`, because a
    // composite cannot switch on T - see InputBinding.combine.
    final merge = sources[0];
    var value = merge.resolve(state, storage);
    for (var i = 1; i < sources.length; i++) {
      value = merge.combine(value, sources[i].resolve(state, _scratch[i - 1]));
    }
    return value;
  }

  /// Held while *any* source is - which is what gives the composite correct
  /// edges without any state of its own. See the class doc.
  @override
  bool isActuated(InputState state) {
    for (var i = 0; i < sources.length; i++) {
      if (sources[i].isActuated(state)) return true;
    }
    return false;
  }

  /// Delegates to the primary, so a composite nested inside another composite
  /// merges by the same rule its own sources do.
  @override
  T combine(T a, T b) => sources[0].combine(a, b);

  static const String _kindTrigger = 'trigger';
  static const String _kindVec2 = 'vec2';
  static const String _kindAxis = 'axis';
  static const String _kindStick = 'stick';
  static const String _kindComposite = 'composite';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'sources': <Object?>[
      for (final source in sources)
        <String, Object?>{'kind': _kindOf(source), 'binding': source.toJson()},
    ],
  };

  /// The wire tag for one child. A `switch` over the concrete bindings, and
  /// not the registry the [InputBinding] doc rules out: it resolves nothing a
  /// caller could have named instead, and it is the only place in the engine
  /// that needs one, because a composite's children are the only bindings
  /// whose type is not statically known at the restore site.
  static String _kindOf(InputBinding<Object?> source) => switch (source) {
    TriggerBinding() => _kindTrigger,
    Vec2Binding() => _kindVec2,
    AxisBinding() => _kindAxis,
    StickBinding() => _kindStick,
    CompositeBinding<Object?>() => _kindComposite,
    _ => throw UnsupportedError(
      'a $source cannot be a source in a serialized CompositeBinding: this '
      'format tags the five bindings good ships, and a MouseBinding is '
      'deliberately not one of them (a device has one cursor). A binding of '
      'your own has no tag here at all - serialize the composite yourself, '
      'from its sources, where you know what they are.',
    ),
  };

  /// Rebuilds a composite from [toJson]'s output. `T` is written at the call
  /// site, because a restore site always knows which action it is restoring:
  ///
  /// ```dart
  /// attack.binding = CompositeBinding.fromJson<bool>(saved);
  /// ```
  ///
  /// Throws a [FormatException] naming the offender if a tag is unknown, or if
  /// a child decodes to a binding of the wrong type for `T` - a save file
  /// claiming an `axis` source for a `CompositeBinding<bool>`, say.
  static CompositeBinding<T> fromJson<T>(Map<String, Object?> json) {
    final raw = json['sources'];
    if (raw is! List) {
      throw FormatException(
        'expected "sources" to hold the list of tagged bindings '
        'CompositeBinding.toJson writes, found $raw',
        json,
      );
    }
    if (raw.isEmpty) {
      throw FormatException(
        'a serialized CompositeBinding has no sources, and a composite of '
        'nothing has nothing to resolve. An action bound to nothing is saved '
        'by not saving a binding for it at all',
        json,
      );
    }
    final sources = <InputBinding<T>>[];
    for (final entry in raw) {
      sources.add(_sourceFromJson<T>(entry, json));
    }
    return CompositeBinding<T>.fromList(sources);
  }

  static InputBinding<T> _sourceFromJson<T>(
    Object? entry,
    Map<String, Object?> json,
  ) {
    if (entry is! Map) {
      throw FormatException(
        'expected each entry of "sources" to be a {"kind": ..., "binding": '
        '...} object, found $entry',
        json,
      );
    }
    final tagged = entry.cast<String, Object?>();
    final kind = tagged['kind'];
    final body = tagged['binding'];
    if (body is! Map) {
      throw FormatException(
        'expected the "$kind" source to carry its binding under "binding", '
        'found $body',
        json,
      );
    }
    final decoded = body.cast<String, Object?>();
    final InputBinding<Object?> source = switch (kind) {
      _kindTrigger => TriggerBinding.fromJson(decoded),
      _kindVec2 => Vec2Binding.fromJson(decoded),
      _kindAxis => AxisBinding.fromJson(decoded),
      _kindStick => StickBinding.fromJson(decoded),
      _kindComposite => CompositeBinding.fromJson<T>(decoded),
      _ => throw FormatException(
        'unknown CompositeBinding source kind "$kind" - expected '
        '"$_kindTrigger", "$_kindVec2", "$_kindAxis", "$_kindStick" or '
        '"$_kindComposite"',
        json,
      ),
    };
    if (source is InputBinding<T>) return source;
    throw FormatException(
      'a "$kind" source cannot go in a CompositeBinding<$T> - it decoded to a '
      '$source, whose value type is not $T. Every source of a composite has '
      'the composite\'s own value type, so a save file mixing them was not '
      'written by this class',
      json,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    if (other is! CompositeBinding<T>) return false;
    if (other.sources.length != sources.length) return false;
    for (var i = 0; i < sources.length; i++) {
      if (other.sources[i] != sources[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(CompositeBinding, Object.hashAll(sources));

  @override
  String toString() => 'CompositeBinding(${sources.join(', ')})';
}
