import 'package:goo/src/event.dart';

/// Opts a [GameListener] into the fixed-tick loop.
///
/// The bound is `on GameListener`, not `implements GameListener`, and that is
/// load-bearing: a fixed tick only happens on the game isolate, so this mixin
/// must be impossible to apply to something that lives on the main one. `Game`
/// is a `WidgetListener` and not a `GameListener`, so `class MyGame extends
/// Game with FixedTickable` no longer compiles - which is the entire point of
/// the split (see [GameEvent]'s doc). Put the tick on the `GameState`, the
/// `SceneStruct`, or a `GameSystem`.
mixin FixedTickable on GameListener {
  void onFixedUpdate();
}
