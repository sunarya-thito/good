import 'package:meta/meta.dart';

import 'package:good/src/coroutine/coroutine.dart';
import 'package:good/src/declare.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/pool.dart';
import 'package:good/src/event.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/input.dart';
import 'package:good/src/order.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';

mixin GameSystemLifecycleListener on GameListener {
  void onMounted() {}
  void onUnmounted() {}
}

/// A system a `GameState` declared on a field - what [GameSystem.of] hands
/// back, and the only handle on a system that exists before boot.
///
/// ```dart
/// class MyState extends GameState<MyGame> {
///   final movement = GameSystem.of(MovementSystem.new);
///
///   @override
///   void onMounted() => movement.value.warmUp();
/// }
/// ```
///
/// # Declared on one copy, built on the other
///
/// This is the typed-handle rule with the isolate split running through the
/// middle of it. The declaration is made on **main**, in a `GameState` field
/// initialiser that `Game._bootMain` runs before the spawn; the system is
/// built on the **game isolate**, by `Game._bootGame`, from the tear-off this
/// carries. So the handle exists on both copies and [value] answers on one -
/// see [GameSystem.of] for why building on main would silently produce
/// queries that match nothing.
///
/// There is no name and no registry to search: the field *is* the reference,
/// the analyzer catches a typo in it immediately, and there is no way to
/// spell a system that was never declared. `GameState.getSystem` still
/// answers for a system some other class declared, which is what a library's
/// mixin contributes through.
final class SystemHandle<S extends GameSystem> {
  SystemHandle._(this._create);

  /// Builds the system, given the state the declaration is a field of.
  ///
  /// `GameSystem.of` ignores the argument; `GameSystem.owned` is the reason
  /// there is one.
  final S Function(GameState owner) _create;

  S? _system;

  /// Whether this copy has built the system yet.
  ///
  /// False on main for the whole life of the game, and false on the game
  /// isolate until `_bootGame` reaches the systems.
  bool get isBuilt => _system != null;

  /// The declared system.
  ///
  /// Available from the moment `Game._bootGame` has built it, which is before
  /// any system's `onMounted` and before `GameState.onMounted` - so a scene
  /// loaded there can already reach it.
  S get value {
    final system = _system;
    if (system == null) {
      throw StateError(
        'this $S is declared but not built on this copy of the game. A '
        'system is constructed by Game._bootGame, on the isolate that ticks, '
        'so the presentation copy holds the declaration and nothing behind '
        'it - reading one there would find an object whose queries were '
        'numbered against an empty component table.\n'
        'Inside the game isolate this reads before boot has reached the '
        'systems: a GameState field initialiser, or a Game constructor.',
      );
    }
    return system;
  }

  /// Builds the system for [owner]. Called once, by `Game._buildSystem`, with
  /// the declaration windows already open around it.
  @internal
  S build(GameState owner) => _create(owner);

  /// Keeps what `Game._buildSystem` built, once it has passed the duplicate
  /// check and been added to the state's list.
  @internal
  void bind(GameSystem system) => _system = system as S;

  /// The static type the declaration was written with - `'SpinSystem'`.
  ///
  /// Read by the boot pass for the input source and for the diagnostics that
  /// name a system before there is an object to ask for its `runtimeType`.
  @internal
  String get declaredName => '$S';
}

/// Systems run in declaration order by default. A subclass wanting to run
/// relative to specific other systems declares an [Order] on a field:
///
/// ```dart
/// final order = Order.of().after<PhysicsSystem>().before<Renderer>();
/// ```
///
/// [Order] registers and resolves nothing. `GameState.sortSystems` reads
/// every system's declarations once, after every system has been built, and a
/// constraint naming a system nobody declared fails the boot rather than
/// doing nothing.
///
/// The older spelling is an override of [compareTo] that type-checks [other]
/// (`if (other is PhysicsSystem) return -1;` to sort before it, `1` to sort
/// after). It still works and feeds the same graph, so the two mix, but it
/// cannot say *before everything that has no opinion about me* without
/// contradicting anything that names it - which is [Order.first] - and it
/// cannot report a constraint against an absent system, because an `is` test
/// against a type nobody declared is simply never true. Both are read once
/// per boot, never on the tick hot path.
///
/// **Name the systems you mean and return 0 for everything else.** An answer
/// is a constraint, not a rank: `GameState.sortSystems` builds a graph out of
/// them and topologically sorts it, so a targeted opinion is honoured no
/// matter what any other system claims, and constraints that cannot all hold
/// are rejected as a cycle, never silently resolved. An unconditional
/// `-1` or `1` is legal and means "before/after everything", but two systems
/// that both claim the same end contradict each other, and the tie between
/// those two falls back to declaration order.
///
/// Do not reduce this to a `List.sort` over the same answers. A partial order
/// is not a comparator, and `List.sort` given one does not confine the damage
/// to the pair that disagrees - it permutes the list, so an unrelated and
/// perfectly consistent constraint elsewhere is dropped. That is what #5 was.
///
/// # One isolate, and no mirror
///
/// A `GameSystem` is a [GameListener] and nothing else: it lives where the
/// tick loop does, and only there. The `GameSystem.of` declarations are made
/// on both copies - the state object itself is built on each, so `Game2D`'s
/// `Renderer2DState` can contribute the two systems 2D rendering needs - but
/// each holds a tear-off, and it is **called** from exactly one place, the
/// boot phase that runs on the copy that ticks. Main builds nothing, so no
/// system object is ever constructed there. There is no twin to hold
/// anything.
///
/// A `Game`'s declarations all happen on main, before the spawn, and ride the
/// deep copy: `Channel.*`, `CameraView.of`, `RandomStream.of`,
/// `describeBuffers` and `describeCommands` are numbered once and the game
/// isolate inherits the numbering, which is what makes an index a wire
/// identity. Systems are the exception, and they can be because a system
/// declares no shared memory of its own: an `Input.of` field resolves against
/// a block that is the same size whatever anyone declared, its events are
/// dispatchers on its own binder, and a `Query` on a field allocates nothing
/// main has to address by index either. A system that wants
/// to publish a number reads a `StateChannel` off the `Game`, which declared
/// it on both copies for exactly that reason.
///
/// No system contributes to the widget tree, on either side. Exactly one
/// object builds widgets and it is `Game.buildView` - a method, not a dispatch
/// mechanism built for several contributors to a problem that has one. See
/// [EventDispatcher].
abstract class GameSystem extends GameListenerBase
    with EventBus, Coroutines
    implements Comparable<GameSystem> {
  /// Declares a system on a `GameState` field, from its constructor.
  ///
  /// ```dart
  /// class MyState extends GameState<MyGame> {
  ///   final movement = GameSystem.of(MovementSystem.new);
  ///   final combat = GameSystem.of(CombatSystem.new);
  /// }
  /// ```
  ///
  /// A **constructor**, not an instance, and the reason is which copy runs
  /// what. A `GameState` field initialiser runs inside `Game._bootMain`, on
  /// main, before the spawn; a system's own fields call `Query.all`, which
  /// numbers its mask out of `ComponentTypeRegistry` - a per-isolate static
  /// that main's copy never fills. A system *built* here would bake main's
  /// empty numbering into a mask and match nothing over there, with nothing
  /// to report it. So this registers the tear-off and builds nothing: the
  /// handle rides the spawn, and `Game._bootGame` calls it on the copy that
  /// ticks, where the archetypes are numbered.
  ///
  /// A system taking constructor arguments goes through a closure:
  /// `GameSystem.of(() => Box2DPhysicsSystem(gravityY: -10))`. The
  /// declaration windows a system's fields read - `Event.of`, `Event.signal`,
  /// `Input.of`, `Order.of` - are open while that closure runs, so that shape
  /// declares on fields too. What does *not* work is a closure handing back
  /// an object built earlier - `GameSystem.of(() => _spawner)` - because
  /// nothing was open around **that** construction, and a field initialiser
  /// on the state has no way to build one anyway.
  ///
  /// A closure needing the state it is declared on takes [owned] instead: a
  /// field initialiser has no `this`, and this one is handed nothing.
  static SystemHandle<S> of<S extends GameSystem>(S Function() create) {
    final handle = SystemHandle<S>._((_) => create());
    DeclarationContext.addSystem(handle);
    return handle;
  }

  /// [of], for a system whose construction needs the state that declares it.
  ///
  /// ```dart
  /// mixin Renderer2DState<G extends Game2D> on GameState<G> {
  ///   final renderer = GameSystem.owned(
  ///     (Renderer2DState<G> state) => state.createRenderer(),
  ///   );
  ///
  ///   GameRenderer2D createRenderer() => GameRenderer2D();
  /// }
  /// ```
  ///
  /// The owner arrives as an argument for `Event.of`'s reason: a field
  /// initialiser has no `this`, so what it needs is passed in rather than
  /// reached for. What that buys over a plain tear-off is **virtual
  /// dispatch** - `state.createRenderer()` is resolved against the state's
  /// runtime type, so a subclass overriding it still decides which renderer
  /// is declared, and the mixin does not have to hand the whole declaration
  /// over to be overridden.
  ///
  /// [O] is checked when the closure is called, at boot on the game isolate,
  /// against the state the field is declared on. The build itself happens
  /// exactly where [of]'s does and inside the same windows.
  static SystemHandle<S> owned<O extends GameState, S extends GameSystem>(
    S Function(O owner) create,
  ) {
    final handle = SystemHandle<S>._((owner) {
      if (owner is! O) {
        throw StateError(
          'a $S declared with GameSystem.owned<$O, $S> is held by a '
          '${owner.runtimeType}, which is not a $O. The owner a build closure '
          'is handed is the state the declaration is a field of, so the type '
          'argument has to be one that state satisfies.',
        );
      }
      return create(owner);
    });
    DeclarationContext.addSystem(handle);
    return handle;
  }

  GameState? _state;

  bool _enabled = true;

  /// Whether this system currently receives events.
  ///
  /// This is what `GameState.enableSystem`/`disableSystem` actually toggle,
  /// and it is why a pre-collected dispatcher list is still correct: a
  /// disabled system stays in every dispatcher it was collected into and
  /// simply declines. Baking membership and reading enablement is the split - one is
  /// fixed by type at declaration, the other is genuinely runtime state.
  @override
  bool get listensToEvents => _enabled;

  @internal
  set enabled(bool value) => _enabled = value;

  /// A system is the one listener the engine can switch off and carry on, so
  /// this is where the base class's no-op is overridden - see
  /// `GameListener.disableAfterUncaught`. Same flag `disableSystem` sets, so
  /// `GameState.enableSystem` brings it back.
  @override
  void disableAfterUncaught([Object? error, StackTrace? stack]) {
    _enabled = false;
    final game = _state?.game;
    if (error == null || game == null) return;
    try {
      game.reportDisabledSystem(
        runtimeType.toString(),
        error.toString(),
        stack?.toString() ?? '',
      );
    } catch (_) {
      // Swallowed on purpose, and this is the one place it is right to.
      //
      // This runs inside the `catch` that keeps the dispatch guard's promise
      // - one bad listener does not stop the ones after it - so a throw from
      // here would break that promise in exactly the situation the guard
      // exists for, and turn a survivable system failure into a dead tick.
      // It is reachable: a single-copy run (`startInline`, and every web
      // build) runs the main-side handler on this stack, so an override of
      // `Game.onSystemDisabled` that throws lands here.
      //
      // Nothing is lost that matters. In debug the dispatcher asserts with
      // the full error and stack once the loop finishes, which is the report
      // a developer reads; in release a report that could not be sent is the
      // state this whole path was added to improve on, not one it makes
      // worse.
    }
  }

  /// This system was mounted. See [GameSystemLifecycleListener].
  ///
  /// Declared through `Event.inherited`, for `EntityStruct`'s reason
  /// (struct.dart) with a sharper edge. [GameSystem.of] takes an
  /// `S Function()`, and a closure may hand back a system that already
  /// existed - `GameSystem.of(() => spawner)`, where `spawner` came in as a
  /// constructor parameter of the `GameState`. A prefab in that shape has
  /// nothing open above it. A
  /// system does: a `GameState` is itself framework-constructed, so its own
  /// window is open while its field initialisers run. `Event.inherited` reads
  /// neither, so the pair lands on this system whichever way it was built.
  ///
  /// A subclass's own `Event.of` fields have no such escape - they read the
  /// window, and in that shape the window is the state's. `EventBinder.open`
  /// refuses the system when it is handed over. Measured before that refusal:
  /// a system holding one `Event.signal` on a field, built in a `GameState`
  /// field initialiser and handed over through a closure, collected the state,
  /// itself and two unrelated systems, and firing it reached all four.
  ///
  /// A system the framework *does* build - `GameSystem.of(SpinSystem.new)`,
  /// or a closure that constructs inside itself - owns the window, so
  /// `Event.of` on a subclass field works and is the shape to reach for.
  final mountEvent = Event.inheritedSignal<GameSystemLifecycleListener>(
    (listener) => listener.onMounted(),
  );

  /// This system is being unmounted. Reverse of [mountEvent]'s order, so a
  /// system told late can still read what the earlier ones have been warned
  /// about - see [EventDispatcher.reverse].
  final unmountEvent = Event.inheritedSignal<GameSystemLifecycleListener>(
    (listener) => listener.onUnmounted(),
    reverse: true,
  );

  @override
  int compareTo(GameSystem other) => 0; // no opinion by default

  List<Order> _orders = const <Order>[];

  /// Every [Order] this system declared on a field, in declaration order.
  ///
  /// Filled by `Game._buildSystem` from the window it opened, and read
  /// once by `GameState.sortSystems`. Empty for a system that declares none,
  /// which is most of them.
  @internal
  List<Order> get declaredOrders => _orders;

  @internal
  void bindOrders(List<Order> orders) => _orders = orders;

  /// Called once by the boot pass on the game isolate, before the system's
  /// [inputDefaults] is read. Not part of the user-facing API: a system is
  /// bound by declaring it with [GameSystem.of], never by hand.
  @internal
  void bindState(GameState state) => _state = state;

  /// The simulation this system belongs to - scenes, sibling systems, the
  /// pool and the tick loop.
  ///
  /// **A `GameState`, not a `Game`, and that is the isolate boundary showing
  /// up in a field type** (the isolate-affinity rule). A system only ever exists on the
  /// copy that simulates, so the object it holds is the one that simulates
  /// too. Holding a `Game` and asking it for a state would have compiled on
  /// the presentation isolate and found nothing there.
  GameState get state {
    final state = _state;
    if (state == null) {
      throw StateError(
        '$runtimeType is not bound to a GameState. Declare it on a '
        'GameState field - `final mine = GameSystem.of($runtimeType.new);` - '
        'a system constructed by hand has no scene to query and no tick to '
        'run on.',
      );
    }
    return state;
  }

  /// The game this system was declared in - `state.game`, for the declarations
  /// that legitimately live there (buffers, state channels, camera views).
  ///
  /// Typed as the base class, so a system that wants *its* game has to say so:
  /// prefer [getGame], which says it once and diagnoses the mismatch, over
  /// `game as MyGame` at every call site.
  Game get game => state.game;

  /// This system's game, as [T].
  ///
  /// The typed counterpart to [game], and the same shape `entity<T>()` and
  /// `scene<T>()` already use. A cast at the call site is the caller
  /// asserting something the API could have carried, and when it is wrong a
  /// bare `as` reports a `TypeError` naming two classes and no reason - this
  /// names the game that is actually running and where to look.
  T getGame<T extends Game>() {
    final game = state.game;
    if (game is T) return game;
    throw StateError(
      '$runtimeType asked for its game as $T, but this run is a '
      '${game.runtimeType}. A system reaches its own game to read what that '
      'game declared, so the two are fixed together at describe time - if '
      'they disagree, the system is declared in a different game than the one '
      'it was written for.',
    );
  }

  /// This system's state, as [T]. See [getGame] - same argument, other half.
  T getState<T extends GameState>() {
    final state = this.state;
    if (state is T) return state;
    throw StateError(
      '$runtimeType asked for its state as $T, but this run has a '
      '${state.runtimeType}. `Game.createState` decides which one a run gets, '
      'so this system is declared in a game whose state is not the one it was '
      'written against.',
    );
  }

  // A system declares neither a state channel nor a draw buffer. A
  // `StateChannel` and a `BufferHandle` are backed by native memory that the
  // **main isolate** allocates before the spawn and frees on stop, and their
  // identity across the boundary is their index in that one declaration
  // pass. A system is not present for it: a system is built on the game
  // isolate, so a system's declaration would have an index on one copy and
  // none on the other, which is the same thing as not having one.
  //
  // Declare them on the `Game` - which is also the side that *reads* them,
  // since a channel exists to be shown and a draw buffer exists to be drained
  // - and write through `game.myChannel` from here. `Renderer2D` is the
  // reference shape for a library doing this: the `Game` mixin declares the
  // frame buffers and `GameRenderer2D` fills them.

  /// The type-level fallbacks this system adds - see `Game.inputDefaults`,
  /// which is the same getter on the other side.
  ///
  /// A system can declare input at all - unlike a state channel or a buffer -
  /// because a fallback allocates nothing: the raw input block is a fixed size
  /// derived from `InputKey.count`, identical whatever a game declares, and an
  /// *action* is resolved against that block by the copy that ticks, which is
  /// this one. Main writes the block and never reads an action.
  ///
  /// An action itself goes on the field that holds it - a system is
  /// framework-built, so [Input.of] has a registry to declare into:
  ///
  /// ```dart
  /// final movement = Input.of(
  ///   const Vec2Binding(up: .w, down: .s, left: .a, right: .d),
  /// );
  /// final triggerSkill = Input.of(const TriggerBinding(.spacebar));
  /// ```
  ///
  /// A *type-level* fallback hands nothing back, so it has no field to sit on
  /// and is configuration instead:
  ///
  /// ```dart
  /// @override
  /// List<InputDefault<Object?>> get inputDefaults => <InputDefault<Object?>>[
  ///   const InputDefault<double>(0),
  /// ];
  ///
  /// final throttle = Input.of<double>();
  /// ```
  ///
  /// Read on the simulating copy only, because that is the only copy a system
  /// exists on at all, and after every system has been built - so a fallback
  /// registered here is visible to an action the `Game` declared. Main's
  /// `InputRegistry` therefore holds just the `Game`'s own actions and is
  /// never sealed, which is harmless: an action's index is not a wire identity
  /// - what crosses the boundary is the raw device block, the same 16 bytes
  /// whatever anyone declared. See `Input`'s doc for what resolution is and
  /// when it happens.
  List<InputDefault<Object?>> get inputDefaults =>
      const <InputDefault<Object?>>[];

  /// A sibling system the same state declared. Reaching one
  /// directly is the escape hatch for cross-system state; note it says
  /// nothing about ordering, which is declaration order and nothing else.
  ///
  /// Goes through the [GameState], which is where the declared systems live.
  /// There is no `Game.getSystem` to shortcut through any more - a system is a
  /// game-isolate object, and the presentation copy has none.
  T getSystem<T extends GameSystem>() => state.getSystem<T>();

  @override
  @internal
  GameState get simulationState => state;

  /// The one loaded scene, as [T] - sugar for `state.singleScene<T>()`, and
  /// carrying the same precondition its name states: it throws once a second
  /// scene is resident. See `GameState.singleScene`.
  ///
  /// A system that has to work with several scenes loaded reads
  /// `state.loadedScenes`, or takes the entity it is already holding and asks
  /// that - `entity.scene` names the scene an entity belongs to without any
  /// assumption about how many exist.
  T singleScene<T extends SceneStruct>() => state.singleScene<T>();

  // GameSystem will listen to an event and run a query
}

/// A compiled set of archetype constraints, and the ways to walk the rows
/// that satisfy them.
///
/// # Scoping to one loaded scene
///
/// Every entry point that iterates takes an optional [Scene], and [inScene]
/// binds one for good. A scope skips at the *page* level: a `MemoryPage`
/// records the scene it was allocated for, so scoped iteration steps over
/// another scene's pages without touching a row, where the per-row
/// `Entity.sceneSlot` test a caller writes by hand pays for every row it
/// rejects. `tool/scene_scope_bench.dart` measures the difference.
///
/// **A scope named by an unloaded scene throws; it does not iterate empty.**
/// `Scene` carries a generation counter precisely so a handle held across an
/// unload is detectable, including one whose slot has since been reused by a
/// different scene - and #145 named the silently-empty alternative as the
/// dangerous one, since a system that stops seeing its entities reads as a
/// logic bug a long way from the stale handle that caused it.
///
/// The check is `Scene.get`, the same resolve `scene.addEntity` does, and it
/// runs twice:
///
///  * when the scope is applied - [run], [groups], [inScene] and
///    [QueryGroup.inScene] all throw at the call, including [run], whose body
///    is a generator and would otherwise not run until the first `moveNext`;
///  * and again when a walk starts, because a [QueryGroup] and a lazy [run]
///    both outlive the call that made them, and the scene under one can be
///    unloaded in between.
abstract class Query {
  /// Declares a query on the field that holds it, requiring every listed
  /// component:
  ///
  /// ```dart
  /// class SwirlSystem extends GameSystem with FixedTickable {
  ///   final motes = Query.all(Transform2D, Mote);
  /// }
  /// ```
  ///
  /// [where] covers the constraints this does not. Ten positional types, for
  /// the reason `_QueryBuilder._mask` gives: Dart has no varargs, and a
  /// `List<Type>` per call site is an allocation for nothing.
  ///
  /// Nothing here needs a live declaration pass, so a query is the one
  /// declaration that works wherever it is written. A query holds masks and
  /// resolves archetypes lazily in [groups], which rebuilds whenever
  /// `ArchetypeRegistry.count` moves, so one built during a system's
  /// construction picks up every archetype a scene registers afterwards.
  /// That is also why the initialiser must be eager - `late final motes =
  /// Query.all(...)` compiles and defers the call to the first read, and the
  /// engine's declaration rules forbid that shape everywhere.
  static Query all(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]) => _ArchetypeQuery(
    _QueryBuilder._mask(a, b, c, d, e, f, g, h, i, j),
    0,
    const <int>[],
  );

  /// A query requiring exactly [T], named once.
  static SingleQuery<T> has<T extends Component>() =>
      _ArchetypeSingleQuery<T>();

  /// Opens a [QueryBuilder] for the constraints [all] does not cover -
  /// [QueryBuilder.withNone], [QueryBuilder.withAny],
  /// [QueryBuilder.withOptional] - and finish it with
  /// [QueryBuilder.build]:
  ///
  /// ```dart
  /// final roots = Query.where()
  ///     .withAll(WorldTransform2D, Transform2D)
  ///     .withOptional(Child)
  ///     .build();
  /// ```
  static QueryBuilder where() => _QueryBuilder(_ArchetypeQuery.new);

  /// Whether an archetype with this signature (see
  /// `ArchetypeStorage.componentSignature`) satisfies this query. What
  /// [run]/[groups] filter archetypes with before walking any rows -
  /// public because it is the whole of a query's matching semantics, and
  /// testing it directly beats inferring it from iteration results.
  bool matches(int signature);

  /// The matching archetypes, one [QueryGroup] each.
  ///
  /// **The iteration to prefer**, and the reason is correctness before speed.
  /// A component instance belongs to an *archetype*, not to an entity -
  /// `entity<Mote>().component` returns the same object for every entity of that
  /// archetype - so resolving it inside the row loop is work repeated for
  /// every row. Hoisting it out is only *correct* per archetype, though, since
  /// one query can match several; a group is that scope made explicit.
  ///
  /// ```dart
  /// for (final group in enemies.groups()) {
  ///   final enemy = group<Enemy>();          // once per archetype
  ///   final transform = group<Transform2D>();
  ///   for (final entity in group) {
  ///     transform.transformOffsetX[entity] += 1;
  ///   }
  /// }
  /// ```
  ///
  /// The returned list is rebuilt only when the set of archetypes changes -
  /// i.e. when a scene loads - so a tick iterating it allocates one list
  /// iterator, not one per entity. [run] walks the same rows through two
  /// nested `sync*` generators instead, which a profile put at ~7% of the
  /// engine's CPU.
  ///
  /// [scene] scopes the walk to one loaded scene - see *Scoping to one loaded
  /// scene* on [Query].
  Iterable<QueryGroup> groups([Scene? scene]);

  /// A lazy `Iterable<Entity>` of matching entities.
  ///
  /// [scene] scopes the walk to one loaded scene - see *Scoping to one loaded
  /// scene* on [Query].
  Iterable<Entity> run([Scene? scene]);

  /// This query, scoped to [scene]: [groups] and [run] on what comes back
  /// walk only rows belonging to [scene], with no argument to remember at
  /// each call site.
  ///
  /// The view is a small object, so hoist it into a field instead of calling
  /// this per tick - a system's scope is settled when it learns which scene it
  /// belongs to, not once per frame. Scoping changes which rows are walked,
  /// nothing else.
  Query inScene(Scene scene);
}

/// A query over exactly one component type, from [Query.has].
abstract class SingleQuery<T extends Component> implements Query {
  @override
  SingleQuery<T> inScene(Scene scene);
}

/// Builds one query out of three constraints over the archetype signature
/// bitset (`ArchetypeStorage.componentSignature`, see archetype.dart):
/// every type in [withAll] present, every type in [withNone] absent, and at
/// least one type from each [withAny] group present.
///
/// Matching is therefore two masked compares plus one per `withAny` group -
/// no per-entity type tests, no closures, no allocation (see
/// `_ArchetypeQuery.matches`). The previous sum-of-products `&`/`|` form was
/// strictly more expressive on paper, but nothing in the engine ever used a
/// real disjunction of conjunctions, and its `matches` allocated a closure
/// per call (`clauses.any((c) => ...)`) on the hottest path there is -
/// the no-allocation, hot-event and no-closure rules.
///
/// Components are named as bare `Type` objects, not type arguments
/// (`withAll(Transform2D)`, not `With<Transform2D>()`), so one flat call can
/// name any number of them. The cost, stated plainly: the analyzer no
/// longer checks that what you pass is a `Component`, so `withAll(String)`
/// compiles. `_QueryBuilder._add` asserts against that in debug builds,
/// which is as much as can be recovered once the type argument is gone.
abstract class QueryBuilder {
  /// Every listed component must be present. Repeatable; each call ORs into
  /// the same required mask.
  QueryBuilder withAll(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]);

  /// Every listed component must be absent. Repeatable.
  QueryBuilder withNone(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]);

  /// At least one of the listed components must be present. Each *call* is
  /// its own group and every group must be satisfied, so
  /// `.withAny(A, B).withAny(C, D)` means "(A or B) and (C or D)", not
  /// "(A or B or C or D)".
  QueryBuilder withAny(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]);

  /// Declares that a match *may* have these components, without requiring
  /// or forbidding them. Pure documentation - it does not narrow the query.
  /// Its role is signalling to the reader (and, later, to codegen) that the
  /// loop body branches on whether an entity has the component;
  /// `WorldTransformSystem` is the reference usage, matching every
  /// `Transform2D` entity whether hierarchy-linked or not and asking
  /// `entity.has<Child>()` inside.
  QueryBuilder withOptional(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]);

  /// Compiles the constraints into a runnable [Query]. Call once - the
  /// builder is a one-shot describe-time object, not something to keep.
  Query build();
}

/// The one [QueryBuilder] implementation. Accumulates masks as it is
/// chained, then hands them to an [_ArchetypeQuery] at [build].
final class _QueryBuilder implements QueryBuilder {
  _QueryBuilder(this._storageOf);

  /// How a compiled query reaches the archetype table - injected rather
  /// than reached statically so the descriptor stays the only thing that
  /// knows about `ArchetypeRegistry`.
  final _ArchetypeQuery Function(
    int required,
    int forbidden,
    List<int> anyGroups,
  )
  _storageOf;

  int _required = 0;
  int _forbidden = 0;

  /// One mask per `withAny` call. Almost always empty, so it starts as a
  /// shared const and only becomes a real list when something uses it -
  /// this is describe-time, but a per-query empty list for a feature nobody
  /// used is still waste worth not paying.
  List<int> _anyGroups = const <int>[];

  static int _bitOf(Type type) {
    assert(
      type != String && type != int && type != double && type != bool,
      'a query names Component types, and $type is not one. Passing a bare '
      'Type means the analyzer cannot check this for you (see QueryBuilder\'s '
      'doc) - the bit would be allocated to $type and quietly consume one of '
      'ComponentTypeRegistry\'s 64 slots.',
    );
    return ComponentTypeRegistry.bitFor(type);
  }

  /// ORs every non-null argument's bit together. Ten explicit parameters, not
  /// a `List<Type>` at each call site: Dart has no varargs, and this keeps
  /// `withAll(A, B)` from allocating a list per call.
  static int _mask(
    Type a,
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ) {
    var mask = _bitOf(a);
    if (b != null) mask |= _bitOf(b);
    if (c != null) mask |= _bitOf(c);
    if (d != null) mask |= _bitOf(d);
    if (e != null) mask |= _bitOf(e);
    if (f != null) mask |= _bitOf(f);
    if (g != null) mask |= _bitOf(g);
    if (h != null) mask |= _bitOf(h);
    if (i != null) mask |= _bitOf(i);
    if (j != null) mask |= _bitOf(j);
    return mask;
  }

  @override
  QueryBuilder withAll(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]) {
    _required |= _mask(a, b, c, d, e, f, g, h, i, j);
    return this;
  }

  @override
  QueryBuilder withNone(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]) {
    _forbidden |= _mask(a, b, c, d, e, f, g, h, i, j);
    return this;
  }

  @override
  QueryBuilder withAny(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]) {
    if (_anyGroups.isEmpty) _anyGroups = <int>[];
    _anyGroups.add(_mask(a, b, c, d, e, f, g, h, i, j));
    return this;
  }

  @override
  QueryBuilder withOptional(
    Type a, [
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]) {
    // Computed and discarded: naming a type here still registers its bit
    // (and runs the assert above), which is the only side effect optional
    // components have. Matching is deliberately untouched.
    _mask(a, b, c, d, e, f, g, h, i, j);
    return this;
  }

  @override
  Query build() => _storageOf(_required, _forbidden, _anyGroups);
}

/// Concrete `Query`: matches archetypes against a compiled [QueryBuilder]
/// and walks their live rows.
///
/// [groups] is the walk to reach for and its own doc says why. [run] is what
/// it is preferred over, and both are allocation-free per step:
///  * [run] - a lazy `Iterable<Entity>`, for a plain `for (final e in
///    query.run())` loop. It earns its place where the walk stops early
///    instead of covering every row: `ActiveCameraResolver.resolve` in
///    `goo2d` takes the first `Camera` occupying a view and breaks on the
///    second, over a query that matches one or two entities. The early exit
///    is the part to copy - its per-entity `get<Camera>()` is affordable
///    only because of it, and that same line over a whole archetype is what
///    `docs/guide/performance.md` calls the single most common cost in this
///    engine. The `Iterable`/`Iterator` themselves are the one allocation,
///    made once per call to `run()`, not once per entity.
class _ArchetypeQuery implements Query {
  _ArchetypeQuery(this._required, this._forbidden, this._anyGroups);

  final int _required;
  final int _forbidden;

  /// One mask per `withAny` group; empty in every query the engine itself
  /// currently writes, so [matches] usually never enters the loop at all.
  final List<int> _anyGroups;

  /// Whether an archetype with this signature satisfies every constraint.
  ///
  /// Two masked compares, then one per `withAny` group. The loop is an
  /// indexed `for` and not `_anyGroups.every(...)`: this runs once per
  /// archetype per query per tick, and a closure here is exactly the hot-path
  /// allocation the no-allocation, hot-event and no-closure rules forbid.
  @override
  bool matches(int signature) {
    if (signature & _required != _required) return false;
    if (signature & _forbidden != 0) return false;
    for (var i = 0; i < _anyGroups.length; i++) {
      if (signature & _anyGroups[i] == 0) return false;
    }
    return true;
  }

  /// Rebuilt only when the archetype set changes - i.e. when a scene loads.
  ///
  /// A `Query` outlives every tick, so the groups do too: iterating this costs
  /// one list iterator per tick, not the per-archetype allocation a
  /// freshly-built list would.
  final List<QueryGroup> _groups = <QueryGroup>[];

  /// The same list scoped to a scene, keyed by *slot* and not by handle: a
  /// slot is reused, so a map keyed by the handle would grow one dead entry
  /// per load for the life of the process, while slots are bounded by how
  /// many scenes are ever resident at once. Each entry remembers which load
  /// built it, so a reused slot rebuilds instead of serving the previous
  /// scene's groups - the groups themselves carry the handle, and iterating one
  /// built for a dead load throws.
  final Map<int, _ScopedGroups> _scopedGroups = <int, _ScopedGroups>{};
  int _groupsBuiltFor = -1;

  @override
  Iterable<QueryGroup> groups([Scene? scene]) {
    final count = ArchetypeRegistry.count;
    if (_groupsBuiltFor != count) {
      _groups.clear();
      _scopedGroups.clear();
      for (var archetypeId = 0; archetypeId < count; archetypeId++) {
        final storage = ArchetypeRegistry.byId(archetypeId);
        if (matches(storage.componentSignature)) {
          _groups.add(QueryGroup(storage));
        }
      }
      _groupsBuiltFor = count;
    }
    if (scene == null) return _groups;
    scene<SceneStruct>();
    final slot = scene.slot;
    var cached = _scopedGroups[slot];
    if (cached == null || cached.scene != scene) {
      final scoped = <QueryGroup>[];
      for (var i = 0; i < _groups.length; i++) {
        scoped.add(QueryGroup(_groups[i].storage, scene));
      }
      cached = _ScopedGroups(scene, scoped);
      _scopedGroups[slot] = cached;
    }
    return cached.groups;
  }

  @override
  Iterable<Entity> run([Scene? scene]) {
    // Resolved here as well as inside the generator. A `sync*` body does not
    // start until the first `moveNext`, so without this a dead scope would be
    // reported at whatever line happened to iterate rather than at the call
    // that named it - and a caller that only asked `isEmpty` would be told
    // "no rows" instead.
    if (scene != null) scene<SceneStruct>();
    return _run(scene);
  }

  Iterable<Entity> _run(Scene? scene) sync* {
    final int? sceneSlot;
    if (scene != null) {
      scene<SceneStruct>();
      sceneSlot = scene.slot;
    } else {
      sceneSlot = null;
    }
    final archetypeCount = ArchetypeRegistry.count;
    for (var archetypeId = 0; archetypeId < archetypeCount; archetypeId++) {
      final storage = ArchetypeRegistry.byId(archetypeId);
      if (!matches(storage.componentSignature)) continue;
      for (var pageIndex = 0; pageIndex < storage.pageCount; pageIndex++) {
        // Null for a page whose scene has been unloaded - the slot is
        // tombstoned rather than removed so that live `Entity.pageIndex`
        // values keep addressing the right pages, so a query has to step
        // over the holes.
        final page = storage.pageAt(pageIndex);
        if (page == null) continue;
        if (sceneSlot != null && page.ownerSceneSlot != sceneSlot) continue;
        for (final offset in page.rowOffsets) {
          yield Entity.pack(archetypeId, pageIndex, offset);
        }
      }
    }
  }

  @override
  Query inScene(Scene scene) {
    scene<SceneStruct>();
    return _ScopedQuery(this, scene);
  }
}

/// [SingleQuery]: a [Query] pre-filtered to one required component, so
/// `descriptor.has<T>()` is `descriptor.query().withAll(T).build()` with the
/// component named once.
final class _ArchetypeSingleQuery<T extends Component> extends _ArchetypeQuery
    implements SingleQuery<T> {
  _ArchetypeSingleQuery()
    : super(ComponentTypeRegistry.bitFor(T), 0, const <int>[]);

  @override
  SingleQuery<T> inScene(Scene scene) {
    scene<SceneStruct>();
    return _ScopedSingleQuery<T>(this, scene);
  }
}

/// One [_ArchetypeQuery._scopedGroups] entry: the groups, and which load of
/// the slot they were built for.
final class _ScopedGroups {
  _ScopedGroups(this.scene, this.groups);

  final Scene scene;
  final List<QueryGroup> groups;
}

class _ScopedQuery implements Query {
  _ScopedQuery(this._query, this._scene);

  final _ArchetypeQuery _query;
  final Scene _scene;

  @override
  bool matches(int signature) => _query.matches(signature);

  @override
  Iterable<QueryGroup> groups([Scene? scene]) =>
      _query.groups(scene ?? _scene);

  @override
  Iterable<Entity> run([Scene? scene]) => _query.run(scene ?? _scene);

  @override
  Query inScene(Scene scene) {
    scene<SceneStruct>();
    return _ScopedQuery(_query, scene);
  }
}

final class _ScopedSingleQuery<T extends Component> extends _ScopedQuery
    implements SingleQuery<T> {
  _ScopedSingleQuery(super.query, super.scene);

  @override
  SingleQuery<T> inScene(Scene scene) {
    scene<SceneStruct>();
    return _ScopedSingleQuery<T>(_query, scene);
  }
}

/// One matching archetype inside a [Query], and the rows it holds.
///
/// Exists so a component can be resolved **once per archetype** instead of once
/// per entity. `entity<Mote>().component` is not a per-entity lookup pretending to be
/// cheap - it genuinely returns the same object every time, because a component
/// describes an archetype's layout and every row shares it. A profile put the
/// repeated resolution (`Accessor.component`, `ArchetypeRegistry.byId`) at
/// ~7% of the engine's CPU.
///
/// Hoisting it by hand is only correct when a query matches exactly one
/// archetype, which is not something a caller can see from the query. This
/// makes the scope explicit: inside a group there is exactly one archetype, so
/// [get] is both hoistable and obviously correct.
final class QueryGroup extends Iterable<Entity> {
  @internal
  QueryGroup(this.storage, [this.scene]);

  /// The archetype this group iterates.
  final ArchetypeStorage storage;

  /// The loaded scene this group is scoped to, or null when it walks every
  /// scene's rows.
  ///
  /// The handle and not the bare slot, so that a group outliving the scene it
  /// was built for is caught: a slot alone would go on matching whatever
  /// loaded into it next. See *Scoping to one loaded scene* on [Query].
  final Scene? scene;

  /// This group, scoped to [scene] - the rows of this one archetype that
  /// belong to that scene.
  QueryGroup inScene(Scene scene) {
    scene<SceneStruct>();
    return QueryGroup(storage, scene);
  }

  /// This archetype's instance of [T] - the prefab, viewed as one of the
  /// components it mixes in.
  ///
  /// ```dart
  /// final transform = group<Transform2D>();   // throws if absent
  /// final maybe = group<Transform2D?>();      // null if absent
  /// ```
  ///
  /// Resolve it before the row loop and use it for every row. Write [T]
  /// nullable where the archetype may not have the component: the bound is
  /// `Component?` so that `Transform2D?` is a legal argument, and `null is T`
  /// is what picks the answer for an archetype that lacks it.
  T call<T extends Component?>() {
    // Widened to `Object` first: `prefab` is an `EntityStruct` and `T` is a
    // `Component?`, and Dart will not promote between two class types neither
    // of which is a subtype of the other.
    final Object prefab = storage.prefab;
    if (prefab is T) return prefab as T;
    if (null is T) return null as T;
    throw StateError(
      '${prefab.runtimeType} is not a $T. The query matched this archetype, '
      'so it satisfies the query\'s constraints - but $T is not among them. '
      'Add it to the query (withAll) or ask for $T?.',
    );
  }

  /// A hand-written walk over this archetype's live rows.
  ///
  /// Not a `sync*` generator: those cost a `_SyncStarIterator` state machine
  /// per `moveNext`, which a profile put at ~5% of total CPU when the query
  /// ran through two of them nested (`run()` yielding through `rowOffsets`).
  @override
  Iterator<Entity> get iterator => _GroupIterator(storage, scene);
}

final class _GroupIterator implements Iterator<Entity> {
  _GroupIterator(this._storage, Scene? scene)
    : _archetypeId = _storage.archetypeId,
      _sceneSlot = scene?.slot {
    // Checked when the walk starts, not only when the group was built. A
    // group is held across ticks, so its scene can be unloaded between the
    // two - and a freed page answers `pageAt` with null, which would make an
    // unloaded scope look like an archetype with no rows in it.
    // Spelled `.call` because a null-aware invocation has no sugar:
    // `scene?<SceneStruct>()` does not parse.
    scene?.call<SceneStruct>();
  }

  final ArchetypeStorage _storage;
  final int _archetypeId;
  final int? _sceneSlot;

  int _pageIndex = -1;
  MemoryPage? _page;
  int _stride = 0;
  int _limit = 0;
  int _offset = 0;
  Entity _current = Entity(0);

  @override
  Entity get current => _current;

  @override
  bool moveNext() {
    while (true) {
      final page = _page;
      if (page != null) {
        while (_offset < _limit) {
          final offset = _offset;
          _offset += _stride;
          if (page.isWalkable(offset)) {
            _current = Entity.pack(_archetypeId, _pageIndex, offset);
            return true;
          }
        }
        _page = null;
      }
      // On to the next page. Tombstoned slots (a scene unloaded) and pages
      // nothing ever allocated into are stepped over rather than ending the
      // walk - `Entity.pageIndex` indexes this list, so it is never compacted.
      _pageIndex++;
      if (_pageIndex >= _storage.pageCount) return false;
      final next = _storage.pageAt(_pageIndex);
      if (next == null) continue;
      if (_sceneSlot != null && next.ownerSceneSlot != _sceneSlot) continue;
      final stride = next.strideBytes;
      if (stride == null || stride <= 0) continue;
      _page = next;
      _stride = stride;
      _limit = next.beginWalk();
      _offset = 0;
    }
  }
}
