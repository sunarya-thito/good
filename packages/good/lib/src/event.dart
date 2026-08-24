import 'package:meta/meta.dart';

/// Names the set of framework types that can receive events.
///
/// A pure marker - no members of its own. What it carries is *membership*, and
/// that is the load-bearing part: the classes implementing it are exactly the
/// ones the engine walks when it collects listeners at boot, so "who could
/// possibly receive this event" has a closed, written-down answer -
/// `GameState`, `SceneStruct`, `EntityStruct`, `GameSystem`.
abstract interface class GameListener {
  /// Whether this listener should receive events **right now**.
  ///
  /// The one thing a pre-collected list cannot bake, because it is genuinely
  /// runtime state: a `GameSystem` that has been disabled is still in every
  /// dispatcher's list, it just declines. One bool read per listener per
  /// dispatch, against the runtime `is` test plus virtual dispatch it
  /// replaced.
  bool get listensToEvents;

  /// Stops this listener receiving events, after it threw out of one.
  ///
  /// Called by the dispatcher that caught it. A requirement stated on the
  /// interface rather than an `is GameSystem` test inside the dispatcher: the
  /// four hosts differ in whether they can be switched off at all, and letting
  /// each answer for itself is what the no-dispatch-on-`is` rule asks for.
  void disableAfterUncaught([Object? error, StackTrace? stack]);
}

/// The default [GameListener] implementation the framework's own listener
/// types extend.
///
/// Exists for a mechanical reason: `EventBus` is bound `on GameListener`, and
/// Dart checks a mixin's constraint against the **superclass**, not against an
/// `implements` clause - so `class X with EventBus implements GameListener`
/// does not compile. Extending this satisfies it.
abstract class GameListenerBase implements GameListener {
  @override
  bool get listensToEvents => true;

  /// A no-op by default, which is the right answer for three of the four
  /// hosts. Switching off the `GameState` would stop the whole game, and a
  /// `SceneStruct` or `EntityStruct` that declined events would leave its own
  /// world half-simulated - neither is a smaller failure than the throw was.
  /// `GameSystem` overrides it, being the one host the engine can drop and
  /// keep going without.
  @override
  void disableAfterUncaught([Object? error, StackTrace? stack]) {}
}

/// The listener list every dispatcher holds, and the collection machinery
/// around it. See [EventDispatcher] and [SignalDispatcher], which differ only
/// in whether delivery carries a payload.
abstract base class _ListenerSet<L extends GameListener> {
  final List<L> _listeners = <L>[];

  /// How many listeners were collected. Diagnostics and tests - the point of
  /// the design is that this number is settled before the first dispatch.
  int get listenerCount => _listeners.length;

  @internal
  void add(L listener) {
    // Guarded because the composition walk can legitimately reach the same
    // listener twice - a prefab registered in two scenes, say - and a
    // listener that received one event twice would be a bug nobody could see
    // from the declaration site.
    for (var i = 0; i < _listeners.length; i++) {
      if (identical(_listeners[i], listener)) return;
    }
    _listeners.add(listener);
  }

  @internal
  void clear() => _listeners.clear();

  /// Reports a listener that threw out of a dispatch, and takes it out of
  /// circulation.
  ///
  /// **Debug and release differ here, deliberately, and the difference is
  /// surprising enough to state.** The `assert` below fires in debug and
  /// nowhere else:
  ///
  ///  * **In debug** the assert throws, which stops the game isolate. That is
  ///    the loud answer a developer wants, and it is no longer a silent stall:
  ///    `Game.start` installs an error port, so the death reaches the main
  ///    isolate, `Game.isRunning` goes false, a pending `stop()` completes,
  ///    and the error is rethrown there with its stack. The disable just
  ///    below never gets to matter, because nothing ticks again.
  ///  * **In release** the assert is compiled out. The listener is disabled
  ///    and the game keeps running without it, which is what a shipped game
  ///    should do when one system has a bad day. The disable is reported
  ///    to the main isolate via an engine command.
  ///
  /// So the disable is release behaviour. `GameState.enableSystem` brings a
  /// system back if the throw was transient.
  void _reportUncaught(L listener, Object error, StackTrace stack) {
    assert(false, '''
${listener.runtimeType} threw during an event dispatch and has been disabled.

$error
$stack
This assert stops the game isolate, and Game.start's error port carries it to
the main isolate rather than losing it. In release there is no assert: the
listener stays disabled and the game keeps running.
GameState.enableSystem<${listener.runtimeType}>() re-enables it if the throw was
transient.''');
  }
}

/// A pre-resolved set of listeners for one event type.
///
/// This is the whole point of the event system, and the thing the old one got
/// wrong. Dispatch used to *walk* - from object to object at runtime, type
/// testing each candidate, so a class that could never accept an event was
/// still visited and still checked, every time. Here the walk happens **once,
/// at boot**: [EventDescriptor.has] creates the dispatcher and the collect
/// pass fills it, so by the time an event is dispatched the receivers are
/// already known and [dispatch] is an indexed loop over a plain list.
///
/// # Scope is the declaring owner
///
/// A dispatcher belongs to whoever declared it in `describeEvents`, and it
/// collects from *that owner's* composition and no further. Declared on an
/// `EntityStruct`, it reaches that struct's listeners only - which is what
/// makes `onEntityMounted` on `MyPlayer` fire for `MyPlayer` entities and
/// nothing else. Declared on a `GameState`, the same event reaches everything
/// beneath it, because a `GameState` collects from its scenes and a scene
/// from its prefabs.
///
/// # There is no event object
///
/// Delivery is a closure captured once, at declare time, rather than a method
/// on an event class:
///
/// ```dart
/// late final EventDispatcher<EntityLifecycleListener, Entity> entityMounted;
///
/// @override void describeEvents(EventDescriptor d) {
/// super.describeEvents(d); entityMounted =
/// d.has((listener, entity) => listener.onEntityMounted(entity)); }
///
/// // and firing it:
/// entityMounted.call(entity);
/// ```
///
/// This replaced a `GameEvent<L>` class per event with a `dispatchListener`
/// override. That design still allocated: an event carrying a payload had to
/// be constructed per dispatch, so the spawn path built one object per entity
/// and the tick built one per frame. Passing the payload as an argument
/// removes the object entirely - **zero allocation per dispatch, whatever the
/// payload** (the hot-path rules). The closure is built once during
/// `describeEvents`, which rule 5 explicitly permits.
///
/// It also deleted eight classes: an event that carries a `Duration` is now
/// `EventDispatcher<Tickable, Duration>` and needs no type of its own.
///
/// [E] is the payload type. For an event that carries nothing, see
/// [SignalDispatcher] and [EventDescriptor.hasSignal].
final class EventDispatcher<L extends GameListener, E> extends _ListenerSet<L> {
  @internal
  EventDispatcher(this._deliver, {this.reverse = false});

  final void Function(L listener, E payload) _deliver;

  /// Whether to deliver in **reverse** collection order.
  ///
  /// For teardown. Bring-up runs outside-in - the owner first, then what
  /// it composes - so tear-down has to run inside-out or a listener would
  /// be told the world is going away *after* its owner had already taken
  /// it apart. One collect pass fills both dispatchers, so the two orders
  /// are the same list read two ways rather than two lists to keep in
  /// agreement.
  final bool reverse;

  /// Delivers [payload] to every collected listener that is currently
  /// listening, in collection order.
  ///
  /// An indexed `for` over a plain list: no iterator, no allocation, no type
  /// test. The only per-listener work is a bool read and one call through the
  /// captured closure. Named `call`, so `dispatcher(payload)` works too.
  void call(E payload) {
    final listeners = _listeners;
    // Null unless something throws, so a healthy dispatch pays three null
    // stores and nothing else.
    L? failed;
    Object? failure;
    StackTrace? failureStack;
    for (var n = 0; n < listeners.length; n++) {
      final listener = listeners[reverse ? listeners.length - 1 - n : n];
      if (!listener.listensToEvents) continue;
      // Guarded per listener, not per dispatch: one bad system must not stop
      // the others in the same tick from running. Measured before it went in
      // - `tool/dispatch_guard_bench.dart` - and the try/catch costs nothing
      // at any realistic listener count.
      try {
        _deliver(listener, payload);
      } catch (error, stack) {
        // Disabled here, reported after the loop. Reporting inline would
        // `assert` mid-dispatch and, in debug, throw straight back out -
        // skipping every listener after this one, which is the exact thing
        // this guard exists to prevent.
        listener.disableAfterUncaught(error, stack);
        failed ??= listener;
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) _reportUncaught(failed!, failure, failureStack!);
  }
}

/// An [EventDispatcher] for an event that carries nothing.
///
/// The fixed tick is the case: it happens, and that is the whole message.
/// Separate from [EventDispatcher] rather than `EventDispatcher<L, void>`,
/// which would force every dispatch site to write `call(null)`. Same split,
/// and the same names, as `SignalCommand` beside `SinkCommand<P>`.
final class SignalDispatcher<L extends GameListener> extends _ListenerSet<L> {
  @internal
  SignalDispatcher(this._deliver, {this.reverse = false});

  final void Function(L listener) _deliver;

  /// See [EventDispatcher.reverse].
  final bool reverse;

  /// Delivers to every collected listener that is currently listening.
  void call() {
    final listeners = _listeners;
    L? failed;
    Object? failure;
    StackTrace? failureStack;
    for (var n = 0; n < listeners.length; n++) {
      final listener = listeners[reverse ? listeners.length - 1 - n : n];
      if (!listener.listensToEvents) continue;
      // See `EventDispatcher.call` - same guard, same reason.
      try {
        _deliver(listener);
      } catch (error, stack) {
        listener.disableAfterUncaught(error, stack);
        failed ??= listener;
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) _reportUncaught(failed!, failure, failureStack!);
  }
}

/// Declares the event dispatchers an [EventBus] owns - see
/// [EventBus.describeEvents].
///
/// Same one-pass declarative shape as every other `describe*` hook, and the
/// same handle-in-a-field discipline (the typed-handle rule): keep what `has`
/// returns, there is nothing to look up by name.
abstract class EventDescriptor {
  /// Declares a dispatcher delivering a payload of type [E] to listeners of
  /// type [L], via [deliver].
  ///
  /// [deliver] is captured once, here, and is what replaced an event class
  /// with a `dispatchListener` override - see [EventDispatcher]. Write it as
  /// the one-liner it is:
  ///
  /// ```dart
  /// tick = d.has<Tickable, Duration>((listener, delta) => listener.onTick(delta));
  /// ```
  /// Pass `reverse: true` for a **teardown** event, so listeners are told
  /// inside-out - see [EventDispatcher.reverse].
  EventDispatcher<L, E> has<L extends GameListener, E>(
    void Function(L listener, E payload) deliver, {
    bool reverse,
  });

  /// Declares a dispatcher for an event that carries nothing.
  ///
  /// ```dart
  /// fixedTick = d.hasSignal<FixedTickable>((listener) => listener.onFixedUpdate());
  /// ```
  SignalDispatcher<L> hasSignal<L extends GameListener>(
    void Function(L listener) deliver, {
    bool reverse,
  });
}

/// One owner's dispatchers, and the collector that fills them.
///
/// The same object plays both roles on purpose: a dispatcher is only ever
/// offered candidates by the owner that declared it, which is precisely what
/// makes an event's reach the owner's own composition and nothing wider.
///
/// Lives here rather than inside `Game` because two things bind events: the
/// boot pass, for the `GameState` and its systems, and
/// `SceneStruct.initializeScene`, for a scene and the prefabs it just
/// registered. A scene brought up headlessly never sees a `Game`, and its
/// prefabs still need their dispatchers - one home for the machinery, used by
/// both (the one-fact-one-place rule).
@internal
final class EventBinder implements EventDescriptor, ListenerCollector {
  /// One entry per declared dispatcher: test a candidate, and add it if it
  /// fits. **One list, not three.**
  ///
  /// This was `_dispatchers` + `_accepts` + `_adds` held in lockstep by index.
  /// Collapsing them found that two of the three were the same decision - a
  /// test whose only purpose was to guard the add right beside it - and that
  /// the third was never read at all.
  final List<void Function(GameListener)> _offers =
      <void Function(GameListener)>[];

  /// Runs both passes over [bus] - declare, then collect - which is the whole
  /// of binding one owner's events.
  static void bind(EventBus bus) {
    final binder = EventBinder();
    bus.describeEvents(binder);
    bus.collectListeners(binder);
  }

  @override
  EventDispatcher<L, E> has<L extends GameListener, E>(
    void Function(L listener, E payload) deliver, {
    bool reverse = false,
  }) {
    final dispatcher = EventDispatcher<L, E>(deliver, reverse: reverse);
    _accept(dispatcher.add);
    return dispatcher;
  }

  @override
  SignalDispatcher<L> hasSignal<L extends GameListener>(
    void Function(L listener) deliver, {
    bool reverse = false,
  }) {
    final dispatcher = SignalDispatcher<L>(deliver, reverse: reverse);
    _accept(dispatcher.add);
    return dispatcher;
  }

  /// Captured here, once per declared dispatcher at boot, because `L` is only
  /// in scope at the `has`/`hasSignal` call that created it. Closures at
  /// declare time are explicitly fine (the no-closure rule); what matters is
  /// that none of this happens per dispatch. `is L` also promotes, so neither
  /// the dispatcher nor the candidate needs a cast.
  void _accept<L extends GameListener>(void Function(L) add) {
    _offers.add((candidate) {
      if (candidate is L) add(candidate);
    });
  }

  @override
  void offer(GameListener candidate) {
    for (var i = 0; i < _offers.length; i++) {
      _offers[i](candidate);
    }
  }
}

/// Collects the listeners a dispatcher will deliver to.
///
/// Handed to [EventBus.collectListeners] during boot. An owner offers itself
/// and whatever it composes; the collector decides what each declared
/// dispatcher accepts, by listener type.
abstract class ListenerCollector {
  /// Offers [candidate] to every dispatcher whose listener type it satisfies.
  void offer(GameListener candidate);
}

/// Opts a [GameListener] into declaring and dispatching its own events.
///
/// ```dart
/// class MyPlayer extends EntityStruct with EventBus {
///   late final EventDispatcher<EntityLifecycleListener> mounted;
///
///   @override
///   void describeEvents(EventDescriptor descriptor) {
///     super.describeEvents(descriptor);
///     mounted = descriptor.has<EntityLifecycleListener>();
///   }
/// }
/// ```
///
/// # The composition walk is explicit, and has to be
///
/// This API does not know the engine's hierarchy - it does not know a
/// `GameState` has scenes or that a scene has prefabs. So each level says so
/// itself, by overriding [collectListeners] and offering what it composes.
/// That is what makes an event declared high up reach everything below it
/// while one declared on a prefab reaches only that prefab.
mixin EventBus on GameListener {
  /// Declares this owner's dispatchers. Runs once, at boot, before
  /// [collectListeners].
  @mustCallSuper
  void describeEvents(EventDescriptor descriptor) {}

  /// Offers this owner's listeners to its own dispatchers.
  ///
  /// The default offers `this`, which is what makes a struct's own
  /// `onEntityMounted` fire for its own events. An owner that composes others
  /// overrides it, calls `super`, and offers them too:
  ///
  /// ```dart
  /// @override
  /// void collectListeners(ListenerCollector collector) {
  ///   super.collectListeners(collector);
  ///   for (final scene in declaredScenes) collector.offer(scene);
  /// }
  /// ```
  @mustCallSuper
  void collectListeners(ListenerCollector collector) => collector.offer(this);
}
