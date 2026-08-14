import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import 'package:goo/src/input/input_key.dart';
import 'package:goo/src/input/input_state.dart';

/// How raw held-or-not key bits become one action's value.
///
/// A binding is an **immutable value type**: `const`-constructible, `==` by
/// content, `copyWith`-able and serializable. That is what makes a keybinding
/// a piece of data a game can save, load, diff and hand to a rebinding screen,
/// rather than behaviour compiled into a system. Nothing here holds a
/// reference to the action it is bound to, so one binding value can be shared
/// by any number of actions and swapped in and out freely
/// (`triggerSkill.binding = const TriggerBinding(.enter)`).
///
/// # `copyWith` and `fromJson` are per concrete type, deliberately
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
/// must not allocate and must not close over anything (RULES.md rules 1, 2,
/// 5). That is why [resolve] writes into storage the action owns and hands it
/// back, instead of returning a fresh value.
@immutable
abstract class InputBinding<T> {
  const InputBinding();

  /// Fresh scratch for an action to own and [resolve] to write into.
  ///
  /// Called **once**, at declare time (or the moment an action that was
  /// declared unbound is first bound) - never per tick. Its initial contents
  /// are deliberately unspecified and are never observed: `Input.value`
  /// returns the declared default until the first resolution overwrites this
  /// wholesale. For a value type like `bool` there is nothing to own, and
  /// this returns a placeholder [resolve] ignores.
  T createStorage();

  /// Computes this tick's value from [state], writing into [storage] and
  /// returning it.
  ///
  /// The return-what-you-were-given shape is what keeps `Input<Vector2>.value`
  /// a single object the action owns for its whole life rather than a fresh
  /// `Vector2` sixty times a second.
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
/// exactly zero (holding `a` and `d` together stands still, rather than
/// picking whichever was pressed last). The result is **not normalized**:
/// holding up and right gives (1, -1), whose length is √2, not 1. Normalizing
/// here would be a silent policy decision - a top-down walker wants it, a
/// twin-stick shooter feeding an acceleration does not - and it is one call
/// (`movement.value.normalized()`) away at the use site, where the game knows
/// which it wants. Note `normalized()` allocates; `..normalize()` on a copy
/// the system owns does not.
///
/// # Which way is up
///
/// [up] contributes **-1** to y and [down] +1, matching the screen-space
/// convention the 2D renderer draws in (y grows downward, so `Transform2D`'s
/// `transformOffsetY` increasing moves a sprite *down* the screen). A game
/// working in a y-up space swaps the two keys in the binding - which is a
/// one-line data change, and exactly the kind of thing bindings exist to make
/// cheap.
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
    if (state.isDown(down)) y += 1;
    if (state.isDown(up)) y -= 1;
    // In place, into the action's own vector: `Vector2(x, y)` here would be
    // one heap object per action per tick (RULES.md rule 1).
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

// TODO: PressureBinding extends InputBinding<double>

/// Pulls a nested key map out of a decoded JSON object with a diagnostic that
/// names the field, rather than letting a bare cast fail with the type alone.
Map<String, Object?> _map(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException(
    'expected "$field" to hold a serialized InputKey object, found $value',
    json,
  );
}

/// Where the pointer is, in every space the engine can answer for.
///
/// One instance per declared action, mutated in place by [MouseBinding] each
/// tick - so `Input<MousePosition>.value` is the same object for the life of
/// the game and reading it allocates nothing (RULES.md rule 1). Treat it, and
/// the vectors it hands out, as read-only and do not hold either past the
/// current tick.
///
/// # Which spaces are here, and which is not
///
/// [screenSpace] and [viewSpace] are *captured*, on the Flutter isolate, at
/// the moment the pointer event arrives - the window position and the
/// position within the `GameView`'s own rect. Both cross the wire as plain
/// numbers.
///
/// **World space is deliberately absent**, and that is a layering fact rather
/// than an omission: projecting a pointer into the world needs the active
/// camera, `Camera` is a `goo2d` component, and this is `goo`. A kernel that
/// knew how to project would have to know what a camera is, which is exactly
/// the dependency the `goo`/`goo2d` split exists to avoid - the same reason
/// `GameView` paints nothing and lets a declared render system do it. `goo2d`
/// supplies the projection, against the camera it already resolves every
/// frame; see its `MousePositionCamera` extension.
final class MousePosition {
  @internal
  MousePosition();

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
  /// Per view rather than per game: with two views on screen of different
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
      'MousePosition(view: ${viewSpace.x}, ${viewSpace.y} of '
      '${viewSize.x}x${viewSize.y})';
}

/// Binds an action to the pointer's position.
///
/// ```dart
/// cursor = input.has<MousePosition>(const MouseBinding());
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
final class MouseBinding extends InputBinding<MousePosition> {
  const MouseBinding();

  @override
  MousePosition createStorage() => MousePosition();

  @override
  MousePosition resolve(InputState state, MousePosition storage) {
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
  /// rebinding screen can serialize every binding uniformly rather than
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
