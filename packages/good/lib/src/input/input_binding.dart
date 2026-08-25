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
