import 'package:goo/src/event.dart';

/// Opts a [GameListener] into the **presentation phase** - the pass that runs
/// after a fixed tick has committed.
///
/// # Why this exists, and how it differs from `FixedTickable`
///
/// `FixedTickable` is *simulation*: it runs inside the tick window, between
/// `MemoryPool.beginTick()` and `commitTick()`, and every read it makes sees
/// the previous tick's published snapshot. That is what makes `x[e] += 1`
/// order-independent between systems and what gives the other isolate a
/// coherent view - but it also means a value written by one system during a
/// tick is invisible to another system in that same tick.
///
/// `Tickable` is *presentation*: it runs after `commitTick()`, so its reads
/// see the snapshot the tick just published - including everything the
/// simulation derived during it. A renderer, an audio positioner, anything
/// that consumes what the simulation computed rather than contributing to it,
/// belongs here.
///
/// This is the same split Unity DOTS draws between `SimulationSystemGroup`
/// and `PresentationSystemGroup`, and for the same reason: a consumer of
/// derived data is ordered into a later phase rather than given a sharper way
/// to read the current one. See RULES.md rule 8 - it is why there is no
/// "read the uncommitted value" accessor anywhere in this engine.
///
/// # Latency
///
/// Reading published data in the presentation phase is exactly as fresh as
/// recomputing it from published inputs inside the tick. During tick N, a
/// `FixedTickable` reads state as of the end of N-1; a `Tickable` running
/// after N commits reads values derived during N *from* that same end-of-N-1
/// state. Same frame of latency, one implementation instead of two.
///
/// The bound is `on GameListener` for the same reason `FixedTickable`'s is:
/// this runs on the game isolate. Painting is `Game.buildView`, on the Flutter
/// side, and is not an event at all.
mixin Tickable on GameListener {
  /// Called once per presentation pass, with the wall-clock time elapsed
  /// since the previous one.
  ///
  /// Unlike `onFixedUpdate`, this is a *variable* delta: the presentation
  /// phase is paced independently of the simulation, so a slow frame gives a
  /// bigger delta rather than being made up by running the pass twice.
  void onTick(Duration delta);
}

// There is no `TickEvent` class. The presentation pass is an
// `EventDispatcher<Tickable, Duration>` on `GameState`, fired with
// `tickEvent.call(delta)` - the delta is the argument, so a frame costs no
// allocation at all. It used to be an immutable event object built once per
// frame, and before that a single mutable instance re-stamped with a new
// delta; passing it removes both the object and the aliasing question.
