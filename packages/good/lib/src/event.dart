import 'package:meta/meta.dart';

import 'package:good/src/scannable.dart';

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
  /// interface, not an `is GameSystem` test inside the dispatcher: the
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
abstract base class _ListenerSet<L extends GameListener>
    implements ScannableField {
  final List<L> _listeners = <L>[];

  /// Adds [candidate] if it is one of this dispatcher's listeners.
  ///
  /// The test lives here because `L` is only in scope inside the dispatcher.
  /// It used to be a closure `EventBinder` captured at the `has` call, that
  /// being the one place `L` was written - and a dispatcher read off a field
  /// has no such call for a binder to capture anything at.
  @internal
  void offer(GameListener candidate) {
    if (candidate is L) add(candidate);
  }

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
  /// **Debug and release differ here, and the difference is surprising enough
  /// to state.** The `assert` below fires in debug and nowhere else:
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
/// This is the whole point of the event system. Dispatch does not *walk* - it
/// does not go from object to object at runtime type testing each candidate,
/// visiting classes that could never accept the event. The walk happens
/// **once, at boot**: [EventDescriptor.has] creates the dispatcher and the
/// collect pass fills it, so by the time an event is dispatched the receivers
/// are already known and [dispatch] is an indexed loop over a plain list.
///
/// # Scope is the declaring owner
///
/// A dispatcher belongs to whoever declared it, and it collects from *that
/// owner's* composition and no further. Declared on an
/// `EntityStruct`, it reaches that struct's listeners only - which is what
/// makes `onEntityMounted` on `MyPlayer` fire for `MyPlayer` entities and
/// nothing else. Declared on a `GameState`, the same event reaches everything
/// beneath it, because a `GameState` collects from its scenes and a scene
/// from its prefabs.
///
/// # There is no event object
///
/// Delivery is a closure captured once, at declare time, and not a method on
/// an event class:
///
/// ```dart
/// final entityMounted = Event.of<EntityLifecycleListener, Entity>(
///   (listener, entity) => listener.onEntityMounted(entity),
/// );
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
/// payload** (the hot-path rules). The closure is built once, where the event
/// is declared, which rule 5 explicitly permits.
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
  /// are the same list read two ways, not two lists to keep in agreement.
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
/// Separate from [EventDispatcher] instead of `EventDispatcher<L, void>`,
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

/// Declares an event on the field that holds it:
///
/// ```dart
/// class Orc extends EntityStruct {
///   final wounded = Event.of<WoundListener, int>(
///     (listener, damage) => listener.onWounded(damage),
///   );
/// }
/// ```
///
/// Two statics, one per [EventDescriptor] method, minus the `has` that only
/// read as noise once the declaration moved onto the field - the same trade
/// `Field`, `Query` and `Param` made before it. [of] carries a payload,
/// [signal] carries nothing.
///
/// # The type arguments are not optional here
///
/// `descriptor.has(...)` reads `L` and `E` off the field it is assigned to.
/// An initialiser has no such context, so the dispatcher's listener type and
/// payload type are written at the call - which is the whole of what the
/// separate `late final EventDispatcher<L, E>` declaration used to say.
///
/// # Who can declare this way
///
/// Every [EventBus] there is - a [GameState], a [SceneStruct], an
/// [EntityStruct], a [GameSystem] - with no asymmetry between them and
/// nothing to remember about how the object was built.
///
/// That was not true while a binder had to be open around the constructor.
/// `SceneDescriptor.has` takes a `T Function()` and a closure may hand back an
/// object built earlier (`descriptor.has(() => _prefab)`), a `SceneStruct` is
/// constructed by the caller outright, and neither had a binder around it - so
/// a field declaration on one of those declared nothing, or worse, declared
/// into whatever binder happened to be open instead. `EntityStruct`'s and
/// `GameSystem`'s own dispatchers stayed in `describeEvents` for exactly that
/// reason, and both are fields now.
///
/// Nothing is open around one of these calls. A dispatcher is built with its
/// delivery closure and no listeners, and `EventBinder.bind` reads it off the
/// object it was declared on - whenever, and however, that object was made.
///
/// # Eager, always
///
/// `late final wounded = Event.of(...)` compiles and is wrong. The call runs
/// on the first *read*, by which time the collect pass has been and gone, so
/// the dispatcher would exist, hold an empty list, and deliver to nobody,
/// every time, silently. `good_tool --declarations` refuses the shape rather
/// than waiting for the silence.
abstract final class Event {
  /// A dispatcher delivering a payload of type [E] to listeners of type [L],
  /// via [deliver] - the field form of [EventDescriptor.has].
  ///
  /// Pass `reverse: true` for a teardown event, so listeners are told
  /// inside-out; see [EventDispatcher.reverse].
  static EventDispatcher<L, E> of<L extends GameListener, E>(
    void Function(L listener, E payload) deliver, {
    bool reverse = false,
  }) => EventDispatcher<L, E>(deliver, reverse: reverse);

  /// A dispatcher for an event that carries nothing - the field form of
  /// [EventDescriptor.hasSignal].
  static SignalDispatcher<L> signal<L extends GameListener>(
    void Function(L listener) deliver, {
    bool reverse = false,
  }) => SignalDispatcher<L>(deliver, reverse: reverse);
}

/// One owner's dispatchers, and the collector that fills them.
///
/// One object plays both roles: a dispatcher is only ever offered candidates
/// by the owner that declared it, which is precisely what makes an event's
/// reach the owner's own composition and nothing wider.
///
/// Lives here and not inside `Game` because two things bind events: the
/// boot pass, for the `GameState` and its systems, and
/// `SceneStruct.initializeScene`, for a scene and the prefabs it just
/// registered. A scene brought up headlessly never sees a `Game`, and its
/// prefabs still need their dispatchers - one home for the machinery, used by
/// both (the one-fact-one-place rule).
@internal
final class EventBinder implements EventDescriptor, ListenerCollector {
  /// Every dispatcher this owner declared, in declaration order.
  ///
  /// A plain list of dispatchers, because a dispatcher decides for itself
  /// whether a candidate is one of its listeners - see [_ListenerSet.offer].
  /// It held closures for as long as the listener type was only in scope at
  /// the `has` call that built one, and a dispatcher read off a field has no
  /// such call.
  final List<_ListenerSet<GameListener>> _dispatchers =
      <_ListenerSet<GameListener>>[];

  /// Takes the dispatchers a class's field initialisers produced.
  ///
  /// A declaration that is not a dispatcher is skipped: a column and a query
  /// are declarations too, and what they resolve against is a row layout and
  /// the component-bit registry. This binder collects listeners, and says so
  /// by taking only what collects listeners.
  void declare(Iterable<ScannableField> declarations) {
    for (final declaration in declarations) {
      if (declaration is! _ListenerSet<GameListener>) continue;
      _dispatchers.add(declaration);
    }
  }

  /// Runs all three passes over [bus] - the field declarations, the
  /// `describeEvents` body, then the collect - which is the whole of binding
  /// one owner's events.
  ///
  /// Field declarations first and the hook after, so an owner declaring
  /// through both gets them in that order. Which order they went in does not
  /// change delivery: the order listeners arrive in is the order [offer] is
  /// called, which is the collect walk and not this list.
  ///
  /// Binding twice is an error, and has to stay one. It was caught by the
  /// `late final` dispatchers this replaced - assigning one twice throws -
  /// and nothing about a `final` field would notice: the second pass would
  /// offer every candidate to the same dispatchers again and each listener
  /// would receive every event twice. `SceneStruct.bindEvents` guards its own
  /// three entry points against reaching here twice.
  static void bind(EventBus bus) {
    if (bus._didBind) {
      throw StateError(
        '${bus.runtimeType} has already had its events bound. A second '
        'collect pass would offer every candidate to the dispatchers the '
        'first one filled, and each listener would then receive every event '
        'twice.',
      );
    }
    bus._didBind = true;
    final binder = EventBinder();
    // The dispatchers the constructor produced, read off the constructed
    // object. Nothing was open while it was being built, so this is the only
    // record of what it declared - which is what makes an owner the framework
    // did not build declare exactly like one it did.
    binder.declare(collectDeclarations(bus));
    bus.describeEvents(binder);
    bus.collectListeners(binder);
  }

  @override
  EventDispatcher<L, E> has<L extends GameListener, E>(
    void Function(L listener, E payload) deliver, {
    bool reverse = false,
  }) {
    final dispatcher = EventDispatcher<L, E>(deliver, reverse: reverse);
    _dispatchers.add(dispatcher);
    return dispatcher;
  }

  @override
  SignalDispatcher<L> hasSignal<L extends GameListener>(
    void Function(L listener) deliver, {
    bool reverse = false,
  }) {
    final dispatcher = SignalDispatcher<L>(deliver, reverse: reverse);
    _dispatchers.add(dispatcher);
    return dispatcher;
  }

  @override
  void offer(GameListener candidate) {
    for (var i = 0; i < _dispatchers.length; i++) {
      _dispatchers[i].offer(candidate);
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
///   final mounted = Event.of<EntityLifecycleListener, Entity>(
///     (listener, entity) => listener.onEntityMounted(entity),
///   );
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
  /// Whether `EventBinder.bind` has run over this owner - see its note on why
  /// a second pass has to throw rather than quietly double every list.
  bool _didBind = false;

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
