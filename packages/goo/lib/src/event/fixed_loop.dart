import 'package:goo/src/event.dart';

/// Opts a [GameListener] into the fixed-tick loop.
///
/// The bound is `on GameListener`, not `implements GameListener`, and that is
/// load-bearing: a fixed tick only happens on the game isolate, so this mixin
/// must be impossible to apply to something that lives on the main one. `Game`
/// is not a [GameListener], so `class MyGame extends Game with FixedTickable`
/// does not compile - which is the entire point of the split. Put the tick on
/// the `GameState`, a `SceneStruct`, an `EntityStruct` or a `GameSystem`, all
/// of which are game-isolate types.
mixin FixedTickable on GameListener {
  void onFixedUpdate();
}

// There is no `FixedTickEvent` class. The tick carries nothing, so it is a
// `SignalDispatcher<FixedTickable>` declared on `GameState` and fired with
// `fixedTickEvent.call()` - no event object to construct, which on the
// hottest path in the engine is the whole point. See `EventDispatcher`.
