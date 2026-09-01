import 'package:meta/meta.dart';

import 'package:good/src/declare.dart';

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
  /// Takes the dispatchers a base class declared for this object, and records
  /// the declaration window open around the construction.
  ///
  /// This body runs after every field initialiser in the hierarchy and before
  /// any subclass constructor body, which is what makes it the point where an
  /// inherited declaration finds its owner. `EntityStruct.mountedEvent`,
  /// `SceneStruct.mountedEvent` and `GameSystem.mountEvent` are declared on
  /// fields against no owner at all - `Event.inherited` appends and returns -
  /// and the object under construction takes them here. See
  /// [DeclarationContext.takeInheritedEvents].
  ///
  /// Taking them here and not off the open window is what scopes them. An
  /// owner constructed inside someone else's window - a `SceneStruct` held on
  /// a `GameState` field - takes its own pair, so the pair reaches that
  /// scene's composition and not the state's.
  ///
  /// [_builtIn] is the window, kept for a different question:
  /// `EventBinder.open` reads it back to check that the owner it was handed is
  /// the one built inside the window it opened - see its refusal.
  GameListenerBase() {
    if (this case final EventBus self) {
      self._builtIn = DeclarationContext.eventsOrNull;
      EventBinder._takeInherited(self);
    }
  }

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
/// A dispatcher belongs to the owner that declared it, and it collects from
/// *that owner's* composition and no further. Declared on an
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
/// payload** (the hot-path rules). The closure is built once, at declaration,
/// which rule 5 explicitly permits.
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

/// Declares the event dispatchers an [EventBus] owns - see [EventBus.events],
/// which is where one comes from.
///
/// [Event.of] and [Event.signal] are the same two declarations reached from a
/// field initialiser. Either way the handle-in-a-field discipline holds (the
/// typed-handle rule): keep what `has` returns, there is nothing to look up by
/// name.
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
/// payload type are written at the call.
///
/// # Who can declare this way, and who cannot
///
/// A [GameState], an [EntityStruct] and a [GameSystem]. All three are built
/// by the framework - `Game.createState` for the first,
/// `SceneDescriptor.has(Mote.new)` or `EntityStruct.of(Barrel.new)` for the
/// second, `SystemDescriptor.has(SpinSystem.new)` for the third - so there is
/// a constructor call for the binder to be open around.
///
/// A [SceneStruct] is constructed by the caller (`final level = MainScene();`),
/// so no binder is open while its fields initialise and `Event.*` in one
/// throws out of [DeclarationContext.events]. It declares from its constructor
/// body instead, against [EventBus.events], which reads the owner rather than
/// the stack.
///
/// [inherited] and [inheritedSignal] are the framework's own route, for the
/// pair a base class declares on every subclass's behalf. They read no window
/// and no owner - see their doc.
///
/// # Let the framework build it, and mean it
///
/// All three descriptors take a `T Function()`, and a closure is free to
/// return an object built earlier - `descriptor.has(() => _prefab)`. Nothing
/// was open around *that* construction, so a field declaration on it does not
/// declare what it looks like it declares. Build inside the closure -
/// `descriptor.has(() => Bullet(speed: 5))` - or pass the constructor itself.
///
/// A prefab built with nothing above it throws, because the stack is empty.
/// One built inside another owner's window - a system held in a `GameState`
/// field - declared into that owner, and `EventBinder.open` refuses it when it
/// is handed over: measured before that refusal, such a system collected the
/// state, itself and two unrelated systems, and firing its own event reached
/// all four.
///
/// # Eager, always
///
/// `late final wounded = Event.of(...)` compiles and is wrong. The call runs
/// on the first *read*, by which time the binder is closed and the collect
/// pass has already been and gone - so the dispatcher would exist, hold an
/// empty list, and deliver to nobody, every time, silently. It does not get
/// that far: [DeclarationContext.events] throws instead.
abstract final class Event {
  /// A dispatcher delivering a payload of type [E] to listeners of type [L],
  /// via [deliver] - the field form of [EventDescriptor.has].
  ///
  /// Pass `reverse: true` for a teardown event, so listeners are told
  /// inside-out; see [EventDispatcher.reverse].
  static EventDispatcher<L, E> of<L extends GameListener, E>(
    void Function(L listener, E payload) deliver, {
    bool reverse = false,
  }) => DeclarationContext.events.has<L, E>(deliver, reverse: reverse);

  /// A dispatcher for an event that carries nothing - the field form of
  /// [EventDescriptor.hasSignal].
  static SignalDispatcher<L> signal<L extends GameListener>(
    void Function(L listener) deliver, {
    bool reverse = false,
  }) => DeclarationContext.events.hasSignal<L>(deliver, reverse: reverse);

  /// A dispatcher a base class declares on a field for every subclass that
  /// inherits it - `EntityStruct.mountedEvent` and its two siblings.
  ///
  /// The declaration and nothing else: it builds the dispatcher, records it
  /// in [DeclarationContext.registerInheritedEvent], and returns it. It reads
  /// no window, so the field initialiser works whichever way the subclass was
  /// built - by `SceneDescriptor.has(Mote.new)`, by a fixture writing
  /// `_Rock()`, or by a `GameState` field initialiser holding a scene. Which
  /// owner it belongs to is settled afterwards, in `GameListenerBase`'s
  /// constructor body, which runs once every field initialiser in the
  /// hierarchy has.
  ///
  /// [of] is the route for a declaration a *user* writes, and it reads the
  /// window on purpose: it is what refuses `late final wounded =
  /// Event.of(...)` and a prefab built with nothing open above it, neither of
  /// which this can see.
  @internal
  static EventDispatcher<L, E> inherited<L extends GameListener, E>(
    void Function(L listener, E payload) deliver, {
    bool reverse = false,
  }) {
    final dispatcher = EventDispatcher<L, E>(deliver, reverse: reverse);
    DeclarationContext.registerInheritedEvent((candidate) {
      if (candidate is L) dispatcher.add(candidate);
    });
    return dispatcher;
  }

  /// [inherited], for an event that carries nothing - `GameSystem.mountEvent`.
  @internal
  static SignalDispatcher<L> inheritedSignal<L extends GameListener>(
    void Function(L listener) deliver, {
    bool reverse = false,
  }) {
    final dispatcher = SignalDispatcher<L>(deliver, reverse: reverse);
    DeclarationContext.registerInheritedEvent((candidate) {
      if (candidate is L) dispatcher.add(candidate);
    });
    return dispatcher;
  }
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
  /// One entry per declared dispatcher: test a candidate, and add it if it
  /// fits. **One list, not three.**
  ///
  /// This was `_dispatchers` + `_accepts` + `_adds` held in lockstep by index.
  /// Collapsing them found that two of the three were the same decision - a
  /// test whose only purpose was to guard the add right beside it - and that
  /// the third was never read at all.
  final List<void Function(GameListener)> _offers =
      <void Function(GameListener)>[];

  /// Builds [create]'s object with a binder open, so the `Event.*` calls in
  /// its field initialisers declare into it, and hands the object back.
  ///
  /// The binder has to outlive the constructor: field declarations happen at
  /// construction and the collect pass happens at boot, and between those two
  /// moments sits a scene registration or an `Isolate.spawn`. It becomes the
  /// object's registrar here, or is folded into the one [_takeInherited]
  /// already made for the object's inherited pair.
  ///
  /// The pop is in a `finally`: a constructor that throws must not leave the
  /// next declaration writing into a binder nobody owns.
  ///
  /// # An object built somewhere else is refused
  ///
  /// [create] is free to hand back an object built earlier, and where that
  /// object was built decides what its field declarations did.
  ///
  /// Built with no window open - a fixture holding the prefab it is about to
  /// register - it declared nothing through `Event.*`, because those throw
  /// with an empty stack. It keeps the registrar its constructor body made
  /// and binds correctly, so it is allowed.
  ///
  /// Built inside *another* owner's window - `final _spawner = Spawner();` in
  /// a `GameState` field - its `Event.of` fields landed on that owner, and a
  /// dispatcher declared there collects that owner's whole composition:
  /// every sibling system, every scene, every prefab. Measured before this
  /// refused it: a system holding one `Event.signal` on a field, built in a
  /// `GameState` field initialiser and handed over through a closure,
  /// collected the state, itself and two unrelated systems, and firing it
  /// reached all four. That boots and ticks, so it is refused here.
  static T open<T extends EventBus>(T Function() create) {
    final binder = EventBinder();
    DeclarationContext.pushEvents(binder);
    final T bus;
    try {
      bus = create();
    } finally {
      DeclarationContext.popEvents();
    }
    final builtIn = bus._builtIn;
    if (builtIn != null && !identical(builtIn, binder)) {
      throw StateError(
        '${bus.runtimeType} was built inside another owner declaration '
        'window and handed over already constructed.\n'
        'Event.of and Event.signal on its fields declared into that window, '
        'so its dispatchers collect the other owner composition - every '
        'sibling system, every scene, every prefab - instead of its own.\n'
        'Build it where it is declared:\n'
        '  descriptor.has(Spawner.new)\n'
        '  descriptor.has(() => Spawner(rate: 3))\n'
        'A prefab a fixture built with nothing open above it is fine to hand '
        'over: Event.* throws on an empty stack, so it declared nothing '
        'anywhere else.',
      );
    }
    final own = bus._binder;
    if (own == null) {
      bus._binder = binder;
    } else {
      own._absorb(binder);
    }
    return bus;
  }

  /// Walks [bus]'s composition and fills the dispatchers it declared, which
  /// is the whole of binding one owner's events.
  ///
  /// Every dispatcher exists by now. They are created while the owner is
  /// constructed - by `Event.of` on a field, by `Event.inherited` on a base
  /// class's field, or by a scene declaring against [EventBus.events] in its
  /// constructor body - and this pass only decides who receives them.
  ///
  /// Binding twice is an error, and has to stay one: the second pass would
  /// offer every candidate to the dispatchers the first one filled, and each
  /// listener would then receive every event twice. `SceneStruct.bindEvents`
  /// guards its own three entry points against reaching here twice.
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
    bus.collectListeners(bus._binder ??= EventBinder());
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

  /// Moves the dispatchers a base class declared for [bus] onto [bus]'s own
  /// registrar, making one if it has none yet.
  ///
  /// The resolve half of an inherited declaration - see [Event.inherited] for
  /// the register half, and `GameListenerBase`'s constructor body for why
  /// this is the moment the owner is known.
  ///
  /// The registrar it makes here is the same one [open] finds and absorbs
  /// into, and the same one [bind] falls back to for an owner no window was
  /// ever open around.
  static void _takeInherited(EventBus bus) {
    final declared = DeclarationContext.takeInheritedEvents();
    if (declared.isEmpty) return;
    (bus._binder ??= EventBinder())._offers.addAll(declared);
  }

  /// Folds [other]'s declarations into this one.
  ///
  /// Two binders exist for one owner whenever a base class declares a pair:
  /// that pair goes to the owner's own registrar, made by [_takeInherited],
  /// and a subclass's `Event.of` fields went to the window `open` pushed.
  /// Position in this list is not delivery order - an entry decides for
  /// itself whether a candidate fits, and the order listeners arrive in is
  /// the order [offer] is called - so appending is the whole of the merge.
  void _absorb(EventBinder other) => _offers.addAll(other._offers);

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
/// class MyPlayer extends EntityStruct {
///   final wounded = Event.of<WoundListener, int>(
///     (listener, damage) => listener.onWounded(damage),
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
  /// This owner's registrar, made on first use by [events] or by
  /// `EventBinder._takeInherited`, and set by `EventBinder.open` for an owner
  /// whose fields declared into a window.
  ///
  /// Not an initialiser: a mixin's fields initialise *after* the subclass's,
  /// so a binder created here would arrive too late for the very declarations
  /// it exists to catch.
  EventBinder? _binder;

  /// The window that was open while this owner was constructed, or null.
  /// Recorded by `GameListenerBase`, read once by `EventBinder.open`.
  EventBinder? _builtIn;

  /// Whether `EventBinder.bind` has run over this owner - see its note on why
  /// a second pass has to throw rather than quietly double every list.
  bool _didBind = false;

  /// This owner's own registrar, for a declaration a field initialiser cannot
  /// make.
  ///
  /// `Event.of` and `Event.signal` read the window the framework opens around
  /// a constructor call, and a [SceneStruct] has none - the caller constructs
  /// it. A scene has `this` in its constructor body, so that is where it
  /// declares, against this getter, which reads the owner and never the stack:
  ///
  /// ```dart
  /// class MainScene extends SceneStruct {
  ///   late final EventDispatcher<WaveListener, int> waveCleared;
  ///
  ///   MainScene() {
  ///     waveCleared = events.has((listener, wave) => listener.onWave(wave));
  ///   }
  /// }
  /// ```
  ///
  /// Reach for `Event.of` on a field wherever the framework builds the owner.
  /// This is the same declaration, made where a field initialiser cannot
  /// reach. The pair every scene, prefab and system inherits takes a third
  /// route, [Event.inherited], which needs neither a window nor an owner.
  @protected
  EventDescriptor get events => _binder ??= EventBinder();

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
