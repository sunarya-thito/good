import 'dart:async';

import 'package:meta/meta.dart';

import 'package:goo/src/game.dart';
import 'package:goo/src/game_state.dart';

/// A running game, from the main isolate's side.
///
/// ```dart
/// final handle = await Game.start(MyGame());
/// final score = handle.game.score;      // a StateChannel, read by a widget
/// await handle.stop();
/// ```
///
/// # Why a handle rather than methods on `Game`
///
/// A [Game] is a *description*: the systems, commands, buffers, channels and
/// timing that make up a game, and nothing that is running. `Game.start()`
/// turns one into a live game and hands back this - which is the same shape
/// Flutter uses, where a `StatefulWidget` describes and an element runs it.
///
/// That split is what stops the presentation isolate reaching into the
/// simulation. There is deliberately **no `state` here**: on the spawned
/// configuration the `GameState` is on another heap, so a `state` accessor
/// could only ever be a null check that compiles everywhere and works in one
/// place. Reaching the world is [InlineGameHandle]'s job, and that type is
/// only ever handed to a caller who asked for the single-isolate
/// configuration.
///
/// What crosses instead is what a presentation layer actually needs, and both
/// lanes are on [game]: a `StateChannel` for a value to show, and a command
/// for a thing to ask for.
///
/// # There is no `tick` and no `addTickListener`
///
/// Both existed and were removed, and the reason is worth keeping. The tick
/// *ping* is load-bearing - it is what makes this isolate re-read the state
/// channels and fire their listeners - but that is plumbing, not an API. The
/// one real consumer of the public hook was the 2D renderer, which moved to a
/// `SchedulerBinding` frame callback: a repaint scheduled when a port message
/// happens to land waits most of a frame for the next vsync, so sampling at
/// the top of a frame is strictly better. A game that wants a visible tick
/// count publishes one with `describeState`, through the lane that already
/// exists for "a number main should see".
abstract class GameHandle<G extends Game> {
  @internal
  GameHandle(this.game);

  /// The description this handle is running - **this isolate's copy** of it.
  ///
  /// Synchronous, deliberately: `start()` is already a future, and by the time
  /// you hold a handle the game is fully described. Making this a `Future` too
  /// would suggest the instance might not exist yet.
  ///
  /// Everything main is meant to touch hangs off here: state channels, camera
  /// views, commands, the input device. Nothing that reads the world does.
  final G game;

  /// Whether the game is still running - false once [stop] completes.
  bool get isRunning;

  /// Brings the game down and releases every shared allocation.
  ///
  /// In the spawned configuration this asks the game isolate to unmount and
  /// waits for it, then frees the memory this copy owns. Calling it twice is a
  /// no-op.
  Future<void> stop();

  // --- per-run state, for whoever needs some -----------------------------

  final Map<Object, Object> _attachments = <Object, Object>{};

  /// Per-run storage, created on first ask and keyed by [key].
  ///
  /// This exists because a `Game` is a **prefab**: one instance can back
  /// several live runs, so anything that varies per run cannot be a field on
  /// it. `Renderer2D` is the motivating case and was the concrete violation -
  /// it kept its decoded frame surfaces, its `_listening` flag and its
  /// scheduler callback id on the `Game` mixin, so two runs of one `MyGame`
  /// would have shared one surface map and one frame callback.
  ///
  /// A keyed slot rather than fields on this class, because the things that
  /// need per-run state live in *other packages* - `_ViewSurface` is private
  /// to goo2d and the kernel must not learn what a frame is. Pass a private
  /// symbol or a static token as [key]; the owner is whoever holds it.
  ///
  /// Anything stored that implements [RunAttachment] is disposed when the run
  /// stops.
  T attachment<T extends Object>(Object key, T Function() create) =>
      _attachments.putIfAbsent(key, create) as T;

  /// The attachment at [key], or null if nothing has created one - for a
  /// teardown path that must not resurrect what it is trying to release.
  T? tryAttachment<T extends Object>(Object key) => _attachments[key] as T?;

  // --- how many GameViews are showing this run ---------------------------

  int _mountedViews = 0;

  /// Whether anything is on screen showing this run.
  ///
  /// Refcounted rather than a bool because two views on one run is a supported
  /// shape (two cameras, or one camera at two sizes), and disposing the second
  /// must not stop the first from painting.
  bool get hasView => _mountedViews > 0;

  @internal
  void attachView() {
    if (_mountedViews++ == 0) game.onViewAttached(this);
  }

  @internal
  void detachView() {
    if (--_mountedViews == 0) game.onViewDetached(this);
  }

  /// Releases every attachment. Called by the implementations' [stop].
  @protected
  void disposeAttachments() {
    for (final value in _attachments.values) {
      if (value is RunAttachment) value.disposeForRun();
    }
    _attachments.clear();
  }
}

/// Per-run state that needs releasing when the run stops - native memory, a
/// decoded frame, a scheduler callback.
///
/// Deliberately not named `dispose`: a `ChangeNotifier` or a `Listenable`
/// stored as an attachment already has one, and silently overriding it with
/// different lifetime rules is how a double-dispose gets written.
abstract interface class RunAttachment {
  void disposeForRun();
}

/// A game running on the calling isolate - one copy doing both jobs.
///
/// Handed back by `Game.startInline()`, and by `Game.start()` on the web,
/// where there are no isolates in the shared-memory sense. It is a
/// [GameHandle] plus the things that only make sense when the simulation is
/// *here*: the [state], and the ability to drive the clock by hand.
///
/// The typing is the enforcement. A test or a headless host asks for this type
/// and gets the world; an app asks for [GameHandle] and cannot reach it, and
/// that is a compile error rather than a null check that happens to pass on
/// one configuration. Note that `Game.start()` on the web returns the inline
/// implementation *typed as the base*, so a web game still cannot touch the
/// state - the platform decides the mechanism, the call decides the surface.
abstract class InlineGameHandle<G extends Game> extends GameHandle<G> {
  @internal
  InlineGameHandle(super.game);

  /// The simulation half - scenes, systems, the pool, the command drain.
  GameState get state;

  /// Advances the clock by [elapsed], running as many fixed steps as it
  /// affords and then one presentation pass. Returns the number of fixed steps
  /// taken.
  ///
  /// This is the whole scheduler; the timer that `autoTick` installs does
  /// nothing but call it. Driving it by hand is not a reduced-fidelity
  /// stand-in for the real loop, it *is* the real loop.
  int advance(Duration elapsed) => state.advance(elapsed);

  /// Runs exactly one fixed step, whatever the clock says. For a test that
  /// wants a step rather than a duration.
  void runFixedStep() => state.runFixedStep();
}

/// A game running on a spawned isolate, held from main.
///
/// Note how little there is: the handle's whole job is lifetime. Everything
/// that crosses the boundary at runtime does so through shared memory the
/// `Game` already addresses - state channels, the draw buffers, the input
/// block - or through the command rings, and none of that needs a message
/// from here.
@internal
final class IsolateGameHandle<G extends Game> extends GameHandle<G> {
  IsolateGameHandle(super.game);

  @override
  bool get isRunning => game.isRunning;

  @override
  Future<void> stop() async {
    disposeAttachments();
    await game.shutDown();
  }
}

/// The single-copy implementation. Also what the web gets, where there is no
/// second isolate to be had - see [InlineGameHandle].
@internal
final class SingleIsolateGameHandle<G extends Game> extends InlineGameHandle<G> {
  SingleIsolateGameHandle(super.game, this.state);

  @override
  final GameState state;

  @override
  bool get isRunning => game.isRunning;

  @override
  Future<void> stop() async {
    disposeAttachments();
    await game.shutDown();
  }
}
