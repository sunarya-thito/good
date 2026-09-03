import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:good/src/asset.dart';
import 'package:good/src/audio/audio_clip.dart';
import 'package:good/src/audio/audio_mixer.dart';
import 'package:good/src/event.dart';
import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/event/lifecycle.dart';
import 'package:good/src/event/tick_loop.dart';
import 'package:good/src/command/command.dart';
import 'package:good/src/coroutine/coroutine.dart';
import 'package:good/src/command/param.dart';
import 'package:good/src/game.dart';
import 'package:good/src/pool.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/scannable.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/system.dart';
import 'package:good/src/time.dart';

/// The game-isolate half of a game: **mutations happen here**.
///
/// A [Game] declares; a `GameState` simulates. It owns the live [SceneStruct]
/// and its `MemoryPool`, the fixed-timestep accumulator, the command drain,
/// and the mount/unmount lifecycle. Everything it needs to *declare* -
/// systems, commands, buffers, state channels, timing - it reads off [game],
/// which is the copy of the `Game` that landed on this isolate.
///
/// ```dart
/// class MyGameState extends GameState<MyGame> {
///   @override
///   void onMounted() => loadScene(MyScene());
///
///   void onSomething() => game.score.value = 10;
/// }
/// ```
///
/// [game] is a read-only back-reference, and typed: `GameState<MyGame>` gives
/// `game.score` without a cast, which is the whole point of the type
/// parameter. It is not a way back to the main isolate - the object it names
/// is *this isolate's* copy of the `Game` (see `Game`'s "Two copies of one
/// object"), so writing to it changes nothing on the Flutter side except
/// through the channels that exist for that: state channels out, commands in.
///
/// # One fixed step
///
/// resolve inputs -> `beginTick` -> drain and apply commands -> call
/// `onFixedUpdate` on every enabled `FixedTickable` system **in declaration
/// order** -> `commitTick` -> notify. Command application happens before any
/// system runs and inside the tick window, so an entity spawned by a command
/// is visible to every system on the very tick it arrives. Input resolution
/// goes first for the same class of reason: every system in the tick, and
/// every command applied during it, sees one input snapshot instead of one
/// that shifts underneath them (see `Input`).
///
/// Ordering starts from declaration order - the order the systems were
/// declared in `Game.describeSystems` - and is then constrained by
/// whatever `GameSystem.compareTo` states. "Run me after physics" is spelled
/// there, as `other is PhysicsSystem ? 1 : 0`, and it is a constraint, not a
/// rank: [sortSystems] collects every pair's answer into a graph and
/// topologically sorts it, so one system's opinion cannot be outweighed by
/// anyone else's and a set that cannot all hold is reported as a cycle instead
/// of quietly resolved. Systems no constraint separates keep their declared
/// order.
///
/// # Isolate affinity
///
/// `GameState` is a [GameListener], and it lives where the tick loop does -
/// an isolate with no Flutter engine attached. So it can be `FixedTickable`
/// and `LifecycleListener`, and it builds no widgets: the whole Flutter-facing
/// surface is `Game.buildView`, on the other copy. See `GameEvent`'s doc.
abstract class GameState<T extends Game> extends GameListenerBase
    with EventBus, Coroutines
    implements Scannable {
  /// The simulation tick, dispatched once per fixed step to every declared
  /// `FixedTickable` system.
  ///
  /// Declared here and not hand-rolled on `Game`: the tick is not special. It
  /// is an event like any other, and it earns the same resolved-at-boot
  /// listener list every other event gets.
  final fixedTickEvent = Event.signal<FixedTickable>(
    (listener) => listener.onFixedUpdate(),
  );

  /// The presentation pass, dispatched once per *frame* - see
  /// [runPresentation].
  final tickEvent = Event.of<Tickable, Duration>(
    (listener, delta) => listener.onTick(delta),
  );

  /// The game has come up, on the simulating copy, with its scenes mounted.
  final gameMountedEvent = Event.signal<GameLifecycleListener>(
    (listener) => listener.onGameMounted(),
  );

  /// The game is going down, dispatched before anything is torn down.
  final gameUnmountedEvent = Event.signal<GameLifecycleListener>(
    (listener) => listener.onGameUnmounted(),
  );

  /// The app is no longer visible - see [AppVisibilityListener].
  final appHiddenEvent = Event.signal<AppVisibilityListener>(
    (listener) => listener.onAppHidden(),
  );

  /// The app is visible again, carrying the wall clock spent hidden.
  final appShownEvent = Event.of<AppVisibilityListener, Duration>(
    (listener, gap) => listener.onAppShown(gap),
  );

  // Scene and entity *lifecycle* are **not** declared here. They belong to the
  // scene and the prefab respectively (`SceneStruct.mountedEvent`,
  // `EntityStruct.mountedEvent`), because a dispatcher's audience is its
  // declaring owner's composition. Declared here they would be one list per
  // level holding everything in the game, so unloading scene A would call
  // `onSceneUnmounted(A)` on scene B and every prefab B owns. The game level
  // is different and stays here: `GameState` genuinely is the only object at
  // that level, so "everything below" is the right audience.
  //
  // The four *observation* events below are the deliberate other half of that.
  // They are not the lifecycle events at a wider scope - they are a different
  // question, with different names, for a listener that wants to watch the
  // whole world and expects to filter. See `event/lifecycle.dart`'s note.

  /// Any entity, anywhere, has spawned.
  final entitySpawnedEvent = Event.of<EntitySpawnListener, Entity>(
    (listener, entity) => listener.onEntitySpawned(entity),
  );

  /// Any entity, anywhere, is about to go away. Its row is still readable.
  final entityDespawnedEvent = Event.of<EntitySpawnListener, Entity>(
    (listener, entity) => listener.onEntityDespawned(entity),
  );

  /// Any scene has finished loading, its starting entities already spawned.
  final sceneLoadedEvent = Event.of<SceneLoadListener, Scene>(
    (listener, scene) => listener.onSceneLoaded(scene),
  );

  /// Any scene is about to unload. Its entities are still readable.
  // Reverse, matching SceneStruct.unmountedEvent: a listener told late can
  // still read what earlier ones have been warned about.
  final sceneUnloadedEvent = Event.of<SceneLoadListener, Scene>(
    (listener, scene) => listener.onSceneUnloaded(scene),
    reverse: true,
  );

  /// Offers every declared system to this state's dispatchers.
  ///
  /// The explicit composition walk: the event API does not know a `GameState`
  /// has systems, so this says so. A system that is a `FixedTickable` lands in
  /// [fixedTickEvent]; one that is a `Tickable` lands in [tickEvent]; one that
  /// is neither lands nowhere and is never visited again.
  @override
  void collectListeners(ListenerCollector collector) {
    super.collectListeners(collector);
    final systems = declaredSystems;
    for (var i = 0; i < systems.length; i++) {
      collector.offer(systems[i]);
    }
    // And down the composition: each declared scene offers itself and its own
    // prefabs, so an event declared here reaches every entity struct in every
    // scene. This is what `fireEvent` used to do by walking at *dispatch*
    // time, once per event - doing it here means it is walked once, ever.
    final scenes = game.declaredScenes;
    for (var i = 0; i < scenes.length; i++) {
      scenes[i].collectListeners(collector);
    }
  }

  GameRuntime? _runtime;
  bool _simulating = false;

  // Every loaded scene, in load order. Handles rather than structs, because a
  // struct is a *declaration* that can back several loaded scenes at once -
  // exactly as one EntityStruct backs many Entities - so the identity is the
  // handle and never the object.
  final List<Scene> _loaded = <Scene>[];

  // How many things are currently using each asset. An asset is freed when the
  // last of them lets go, never before - see [releaseAssetClaim].
  //
  // A loaded scene takes one claim per asset it declares, and a playing
  // [Voice] takes one on the clip it is sounding. Those are the same kind of
  // claim on purpose: a track has to survive the scene that started it, and
  // the only asset lifetime this engine has is the scene, so the voice has to
  // be a claimant in its own right or the bytes go the moment the scene does.
  //
  // Keyed by the declared *handle*, which is canonical per asset, so the
  // default identity hashing is exactly right here. Keying by key would not
  // be: two equal-but-distinct keys name one asset, and would take two claims
  // for it.
  final Map<Asset<Object?>, int> _assetClaims = <Asset<Object?>, int>{};
  int _accumulatedMicros = 0;

  /// How fast simulated time runs against wall clock - see [timeScale].
  double _timeScale = 1;

  Timer? _timer;

  /// Whether the app is currently visible - see [setVisible].
  ///
  /// Starts true: a game that never hears from a lifecycle observer at all
  /// (a test, a headless host, a tool) has to keep ticking.
  bool _visible = true;

  /// Set while the tick is stopped *because* the app went hidden, so that
  /// showing it again only restarts a timer this stopped. A game stopped for
  /// any other reason is not restarted by becoming visible.
  bool _pausedWhileHidden = false;

  /// Whether [setVisible] cancelled a running timer that it owes back.
  bool _restartTimerOnShow = false;

  /// Runs across the hidden stretch to measure it. A `Stopwatch` and not two
  /// `DateTime`s: this is the one measurement a clock adjustment mid-pause
  /// would corrupt, and a monotonic source cannot be stepped by NTP or by
  /// the user changing the time zone on a phone that was in their pocket.
  final Stopwatch _hiddenFor = Stopwatch();

  /// Fixed steps the last [advance] ran - 0 when the accumulator had not
  /// filled, up to `Game.maxFixedStepsPerAdvance` when catching up.
  int get lastStepCount => _lastSteps;
  int _lastSteps = 0;

  @override
  @protected
  GameState get simulationState => this;

  /// Every coroutine this game is running - see [CoroutineScheduler].
  ///
  /// One per state, not one per owner, and stepped from
  /// [runFixedStep] so a coroutine resumes inside the tick window. Reached
  /// through the [Coroutines] mixin from a prefab or a system; a `GameSystem`
  /// can also use `state.coroutines` directly.
  final CoroutineScheduler coroutines = CoroutineScheduler();

  /// The `Game` this state belongs to - **this isolate's copy** of it. Set
  /// once, by `Game.start()`, before any declaration pass runs.
  ///
  /// The *description*, and only that: the run this state belongs to is
  /// [runtime]. Two runs of one `Game` share this object and share nothing
  /// else.
  T get game => runtime.game as T;

  /// The run this state is the simulation half of.
  ///
  /// Internal because everything a game legitimately reaches through it has a
  /// spelling of its own here - [tick], [createCommandBatch], [isSimulating].
  /// It is the back-reference those are implemented in terms of.
  @internal
  GameRuntime get runtime {
    final runtime = _runtime;
    if (runtime == null) {
      throw StateError(
        '$runtimeType is not bound to a run. A GameState is created by '
        'Game.createState() during Game.start(); one constructed by hand has '
        'no declarations to read and no tick to run on.',
      );
    }
    return runtime;
  }

  /// Whether this copy owns the simulation.
  ///
  /// True on the game isolate, and in the single-copy inline path
  /// (`Game.start(inline: true)`) where one copy does both jobs. False on the
  /// main-isolate handle, whose `GameState` exists only to re-run the same
  /// declaration passes - so that archetype ids agree across the boundary and
  /// announced pages have a pool to be adopted into - and never ticks.
  ///
  /// There is no notion here of a platform that "doesn't support isolates",
  /// only of which copy simulates. Native spawns, web runs inline, and both
  /// answer this question the same way.
  bool get isSimulating => _simulating;

  /// Every loaded scene, in load order. The live list - do not retain it.
  ///
  /// Several scenes can be resident at once (a level plus a HUD, a preloaded
  /// next level, a background sim) and **all of them are live** - all tick,
  /// all receive input, all render. There is no front scene: a game that wants
  /// one paused or hidden either unloads it or checks a flag of its own,
  /// because only the game knows what "paused" should mean for it.
  List<Scene> get loadedScenes => _loaded;

  /// The declaration of **the** loaded scene, when there is exactly one.
  ///
  /// Throws when several are resident: a game with more than one scene loaded
  /// has to say which it means, through [loadedScenes] or the handle
  /// `loadScene` returned it. Null still means none loaded, which is a
  /// legitimate state - a game booted to a menu, a headless host that only
  /// runs systems, a state between transitions.
  SceneStruct? get scene {
    if (_loaded.isEmpty) return null;
    if (_loaded.length > 1) {
      throw StateError(
        'GameState.scene is only meaningful with one scene loaded, and '
        '${_loaded.length} are. Name the one you mean: keep the handle '
        '`loadScene` returned, or index `loadedScenes`.',
      );
    }
    return SceneRegistry.tryResolve(_loaded.first);
  }

  /// This game's page storage - **one pool, owned here**, not one per scene.
  ///
  /// Non-null from `bindGame` onwards, so from before any declaration pass
  /// runs, so the tick loop never has to ask whether there is storage to
  /// rotate: a game with no scene loaded has an empty pool, not no pool, and
  /// `beginTick`/`commitTick` over zero pages is free.
  ///
  /// It belongs here and not on `SceneStruct` because a struct is a declaration
  /// that can back several loaded scenes at once - see `SceneStruct.pool`.
  MemoryPool get pool => _pool!;

  MemoryPool? _pool;

  /// Fixed ticks completed. One counter, kept on the `Game` because the
  /// handle copy needs to track it too (it learns each tick from a message);
  /// this is the simulation-side spelling of the same number.
  int get tick => runtime.tick;

  /// Simulated time since the game came up: [tick] times `fixedTimeStep`.
  ///
  /// Derived, never accumulated (rule 10). A separate `_elapsed` field added
  /// to on every step would drift from the tick count by a float epsilon per
  /// tick, and an animation keyed in seconds would then land on a different
  /// frame in a long session than in a short one. Multiplying is exact.
  ///
  /// Wall clock has nothing to do with it: a game stepped by hand from a test
  /// and one running on a timer report the same time for the same tick, which
  /// is what makes an animation reproducible.
  Seconds get time =>
      Seconds.ofMicroseconds(tick * game.fixedTimeStep.inMicroseconds);

  // --- declaration hooks ------------------------------------------------

  // There is deliberately no `describeState` here, and it is not an oversight
  // - it used to exist and was removed. A channel's storage is allocated on
  // the main isolate before the spawn, and its identity on the wire is its
  // index in that one declaration pass; a `GameState` is built *on the game
  // isolate*, after that pass has already run and its memory been claimed, so
  // a channel declared here would have an index on one copy and none on the
  // other - which is the same thing as not having one. Declare it on the
  // [Game] and write to it from here through `game.myChannel`. See
  // `Game.describeState`.

  /// Declares every `GameSystem` this game runs - once, up front, before the
  /// fixed-tick loop starts.
  ///
  /// ```dart
  /// @override
  /// void describeSystems(SystemDescriptor descriptor) {
  ///   super.describeSystems(descriptor);
  ///   descriptor.has(MovementSystem.new);
  ///   descriptor.has(CombatSystem.new);
  /// }
  /// ```
  ///
  /// Declaration order is execution order, unless a system states an opinion
  /// (see `GameSystem.compareTo`). Systems are not registered piecemeal at
  /// runtime - [enableSystem]/[disableSystem] only pause and resume one that
  /// was declared here.
  ///
  /// # Why here and not on `Game`
  ///
  /// It was on `Game` until the systems themselves moved to this isolate, and
  /// the argument for keeping it there was real: a `Game` *mixin* has to be
  /// able to contribute a system, or `extends Game2D` stops being a single
  /// opt-in for rendering and forgetting the second half paints nothing. But
  /// "which object declares it" and "which isolate holds it" were being
  /// answered by one placement, and only the second is a hard constraint. A
  /// system is created here, ticks here, and is reachable from nowhere else -
  /// so this is where the pass belongs.
  ///
  /// The mixin case is served by narrowing instead: `Game2D.createState()`
  /// returns a `GameState2D`, which declares the two systems 2D rendering
  /// needs. A `Game2D` whose state is a plain `GameState` is a **compile
  /// error**, which is strictly better than the silent black screen the old
  /// arrangement was guarding against.
  ///
  /// Runs on the simulating copy only, from `Game._bootGame`.
  @mustCallSuper
  void describeSystems(SystemDescriptor descriptor) {}

  /// Registers the handlers that run on the **game** isolate, for commands
  /// the [Game] declared.
  ///
  /// ```dart
  /// @override
  /// void describeCommands(CommandDescriptor descriptor) {
  ///   super.describeCommands(descriptor);
  ///   descriptor.hasHandler(game.damage, (p) => p.amount * (p.crit ? 2 : 1));
  ///   descriptor.hasSink(game.spawnWave, _spawnWave);
  /// }
  /// ```
  ///
  /// **Handles only; it cannot declare.** `descriptor.has(...)` throws here.
  /// A command's index in the shared declaration order is its identity on the
  /// wire, and only `Game.describeCommands` runs on both isolate copies in a
  /// position both agree on - a command declared here would have an index on
  /// the game isolate and none on the Flutter one, which is the same thing as
  /// not having one.
  ///
  /// Registering a handler here is what makes a command run *here*, and that
  /// is the whole mechanism: there is no direction to configure and nothing
  /// to keep in sync with the declaration. A command handled on this side is
  /// dispatched inside the fixed tick window, before any system runs, so an
  /// entity it spawns is visible to every system on the tick it lands.
  ///
  /// Runs on both copies, immediately after `Game.describeCommands`, so both
  /// agree about which commands have a handler at all - which is what lets
  /// the sending side refuse a handler-less command without a round trip.
  @mustCallSuper
  void describeCommands(CommandDescriptor descriptor) {
    // The engine's own four, registered by the `Game` that declared them so
    // the fields stay private to the file that owns them (#142).
    game.describeEngineCommandHandlers(descriptor, this);
  }

  // --- scene loading ----------------------------------------------------

  /// Makes [next] the running scene, and returns a future that completes
  /// once it is fully ready to simulate.
  ///
  /// There is no `createScene()` factory: a game does not declare its starting
  /// world, it *loads* one, from `onMounted` like any other scene transition.
  /// So the first load and the fiftieth go through exactly one code path, and
  /// "no scene yet" is an ordinary state instead of a special pre-boot case
  /// ([scene] is nullable for precisely this reason).
  ///
  /// ```dart
  /// class MyState extends GameState<MyGame> with LifecycleListener {
  ///   @override
  ///   void onMounted() {
  ///     loadScene(MainScene()).then((_) => game.loading.value = false);
  ///   }
  /// }
  /// ```
  ///
  /// # Why the archetype-registering half is synchronous
  ///
  /// Archetype ids are assigned in first-registration order and must come
  /// out identical on both isolate copies (see `ArchetypeRegistry`) - that
  /// agreement is what lets a spawn command name a prefab by integer and an
  /// `Entity` handle resolve on the isolate that did not create it. So
  /// `describeScene` runs *synchronously* here, before this method's first
  /// `await`: both copies calling `loadScene` with the same scene type in
  /// the same order therefore register the same prefabs in the same order,
  /// with no chance of an interleaving `await` letting a second load
  /// renumber them. Only the genuinely asynchronous part of bring-up (asset
  /// decoding) happens after that, and the returned future is what waits on
  /// it.
  ///
  /// Await it (or `.then` it) when you need "the world is ready" - that is
  /// the signal a loading screen turns itself off on. [scene] itself is
  /// non-null as soon as this returns synchronously, because the entity
  /// layout exists by then; it is the *content* that is still arriving.
  ///
  /// # Assets
  ///
  /// The registration half above also declares every asset the incoming scene
  /// needs - its own `SceneStruct.describeAssets` plus every registered
  /// prefab's `Component.describeAssets` - which is what assigns each one its
  /// process-global address, identically on both copies (see `GameAssets`). The
  /// asynchronous half then reconciles the two scenes' footprints:
  ///
  ///  * an asset **both** scenes declare stays loaded, untouched - a UI atlas
  ///    every scene uses is decoded once for the run, never round-tripped
  ///    through unload/reload at a transition;
  ///  * an asset only the **incoming** scene declares is loaded, reporting
  ///    through [onProgress] as each one completes;
  ///  * an asset only the **outgoing** scene declared is unloaded *after* the
  ///    incoming scene is ready - never before, because unloading first would
  ///    free something the incoming scene turns out to share.
  ///
  /// [onProgress] fires **only on the copy that actually decodes** (the
  /// main/Flutter isolate - see `Game.decodesAssets`). On the game isolate it
  /// is never called, because there is nothing there to report: that copy
  /// declares and addresses every asset and decodes none of them. A loading
  /// screen is a main-isolate widget, so that is the copy that wanted the
  /// callback anyway. Reported progress is monotonic and ends at exactly 1.0.
  ///
  /// Unloading, unlike loading, runs on **both** copies: it is the undoing of
  /// a declaration, and a declaration that exists on one copy and not the
  /// other is exactly what would make one asset mean two different addresses.
  ///
  /// The outgoing scene's *pages* are not freed here - see the comment
  /// inside.
  Future<Scene> loadScene(
    SceneStruct next, {
    void Function(SceneLoadProgress)? onProgress,
  }) async {
    // Only the simulating copy loads a scene, and that is new: this used to
    // run on both, because main registered the archetypes before the spawn and
    // the game isolate inherited them. Both copies registering meant both had
    // to arrive at the same ids, which is the agreement `Game`'s registry
    // snapshot existed to preserve. One registrar has no one to agree with.
    _requireSimulating('loadScene');
    // A scene brought up from a handler with no tick window open spawns its
    // entities and runs its mount listeners with no write slot for either.
    // See `HandlerWindow` (#245).
    pool.requireWorldMutable('A scene was loaded');

    // Synchronous, order-critical half - see the doc above.
    next.bindState(this);
    // Both the pool and the asset table come from the Game: a scene declares
    // into the table its game loads from, or the two would silently be
    // different tables and every load would fail to find its declaration.
    // A scene declared in `Game.describeScenes` is already initialized, which
    // is the entire point of declaring it - loading costs no registration.
    if (!next.isInitialized) {
      next.initializeScene(
        pool,
        assets: game.assets,
        cameraViews: game.cameraViews,
      );
    }
    // Idempotent, and a no-op for a scene declared in `describeScenes` (the
    // boot pass already bound it). It matters for one loaded at runtime that
    // nothing declared: its prefabs' dispatchers have to exist before the
    // first `addEntity` fires one.
    next.bindEvents();

    // A slot, a generation, and a page group. **Loading no longer replaces
    // anything**: several instances of one `SceneStruct` can be resident at
    // once, each owning its own pages, and each individually unloadable.
    final handle = SceneRegistry.register(next);
    _loaded.add(handle);

    // One dispatch, not a virtual followed by a dispatch. The scene is
    // offered into its own dispatcher first (see `collectListeners`), so
    // its `onSceneMounted` still runs before any of its prefabs' - which
    // is what makes "a listener hearing a mount finds the starting
    // entities already spawned" true. Fired on the scene's own dispatcher,
    // so it reaches that scene's composition and no other scene's.
    next.mountedEvent.call(handle);
    // And the world-observation half: same call site as the scene's own
    // mount, so the two can never disagree about when a load happened.
    sceneLoadedEvent.call(handle);

    // Everything past this point is the asynchronous half.
    await _reconcileAssets(next, onProgress);
    return handle;
  }

  /// Unloads one loaded scene: its entities, its pages, and its claim on the
  /// assets it declared.
  ///
  /// Every `Entity` created in [scene] is invalid afterwards. There is no
  /// generation counter on `Entity` to make that detectable per handle - it
  /// spends all 64 of its bits - so the detection is at page granularity
  /// instead: the freed pages' slots are tombstoned in `ArchetypeStorage`, and
  /// resolving a handle into one reports the unload instead of reading
  /// whatever a later scene put at that address. That is exactly why a scene's
  /// rows never share a page with another scene's.
  ///
  /// The scene's *archetypes* are not unregistered. Archetype ids are
  /// process-global and never recycled, and a declared scene is expected to be
  /// loaded again - re-registering per load is what `Game.describeScenes`
  /// exists to avoid.
  void unloadScene(Scene scene) {
    _requireSimulating('unloadScene');
    // The one #245 named first: this frees the scene's native pages on the
    // spot, so a receipt handler could pull the memory out from under a
    // simulation that is merely paused. See `HandlerWindow`.
    pool.requireWorldMutable('A scene was unloaded');
    final struct = SceneRegistry.tryResolve(scene);
    if (struct == null) return;

    // Before anything is released, so a listener can still read the scene's
    // entities - after this method they are gone for good. On the struct's own
    // dispatcher: only this scene and its prefabs are told.
    // Dispatched in reverse collection order, so the scene itself is told
    // last and can still read what its prefabs have already been warned
    // about - see `SceneStruct.describeEvents`.
    sceneUnloadedEvent.call(scene);
    struct.unmountedEvent.call(scene);
    // Innermost last: the scene has said its piece, now each entity in it
    // gets its own teardown while its row is still readable.
    struct.unmountEntitiesOf(scene.slot);
    _releaseAssetsOf(struct);

    // Unregister first, then release the pages. That order is deliberate and
    // is what makes the deferred free safe: from here on nothing can resolve
    // this `Scene` or spawn into it, so the pages are unreachable through the
    // API even while the memory is still alive waiting for the reader to let
    // go. See `Game.releaseScenePages`.
    final slot = scene.slot;
    _loaded.remove(scene);
    SceneRegistry.unregister(scene);
    runtime.releaseScenePages(slot);
  }

  /// Unloads **every** loaded instance of [struct].
  ///
  /// Iterates a copy of the list, because [unloadScene] mutates it.
  void unloadAllScene(SceneStruct struct) {
    _requireSimulating('unloadAllScene');
    pool.requireWorldMutable('Every loaded instance of a scene was unloaded');
    final doomed = <Scene>[
      for (final scene in _loaded)
        if (identical(SceneRegistry.tryResolve(scene), struct)) scene,
    ];
    for (var i = 0; i < doomed.length; i++) {
      unloadScene(doomed[i]);
    }
  }

  // `switchScene` was deleted here. It named a "front" scene that gated
  // nothing - every loaded scene already ticked and received input - so all it
  // really did was tell the renderer and the mouse picker to ignore two of the
  // three scenes you had loaded. That is a *view* decision wearing a
  // `GameState` method's clothes, and it does not survive more than one view:
  // with two `GameView`s open there is no single answer to "which scene is
  // front". What replaced it is the camera - a view draws the scene its camera
  // is in - which is a question each view answers for itself.
  //
  // A game that wants a scene inert unloads it, or checks a flag of its own;
  // only the game knows whether "paused" means frozen, hidden, or silent.

  /// Loads what the incoming scene added and unloads what the outgoing scene
  /// took with it - see [loadScene]'s doc for the policy this implements.
  ///
  /// Transition-time code: it allocates a `SceneLoadProgress` per completed
  /// asset and a `Set` for the keep-set, both of which are exactly the kind
  /// of allocation the no-allocation rule is *not* about. Nothing here runs per
  /// entity or per tick.
  Future<void> _reconcileAssets(
    SceneStruct next,
    void Function(SceneLoadProgress)? onProgress,
  ) async {
    final incoming = next.declaredAssets;
    // One claim per *loaded scene*, taken before any decode. This replaced a
    // pairwise `previous -> next` diff, which could not survive several
    // scenes being resident: with A and C both using an atlas and B not,
    // A -> B unloaded it and B -> C decoded it again. A count cannot make
    // that mistake, and it is also the only thing that can answer "is anyone
    // still using this" when scenes are unloaded out of order.
    for (var i = 0; i < incoming.length; i++) {
      claimAsset(incoming[i]);
    }

    if (!runtime.decodesAssets) {
      // This copy declared the assets - that is what gave them their addresses
      // - but it cannot decode one, because decoding needs Flutter. So it asks
      // the copy that can and waits.
      //
      // This used to be a bare `return`, and that was a real bug rather than a
      // simplification: it was invisible only because main ran `loadScene`
      // itself during boot. A `loadScene` at *runtime* took its asset claims
      // here and then decoded nothing, anywhere, leaving every payload read
      // from that scene to fail.
      await runtime.requestAssetLoad(
        <int>[for (var i = 0; i < incoming.length; i++) incoming[i].pack()],
        // The keys travel with their addresses: the decoding copy has no
        // declaration pass of its own to resolve an address against, so the
        // request has to carry the whole identity. See
        // `GameRuntime.requestAssetLoad`.
        <AssetKey<Object?>>[
          for (var i = 0; i < incoming.length; i++) incoming[i].key,
        ],
        onProgress == null
            ? null
            : (address, completed, pending) => onProgress(
                SceneLoadProgress(
                  game.assets.tryGetAt(address)?.debugLabel ?? 'asset $address',
                  completed / pending,
                ),
              ),
      );
      onProgress?.call(SceneLoadProgress('${next.runtimeType}', 1));
      return;
    }

    // Counted up front so the denominator is the number of decodes this load
    // will actually perform - a scene whose assets are all already resident
    // reports one 1.0 and does no work.
    var pending = 0;
    for (var i = 0; i < incoming.length; i++) {
      if (!incoming[i].isLoaded) pending++;
    }
    var completed = 0;
    for (var i = 0; i < incoming.length; i++) {
      final asset = incoming[i];
      if (asset.isLoaded) continue;
      await game.assets.load(asset.key);
      completed++;
      onProgress?.call(
        SceneLoadProgress(asset.debugLabel, completed / pending),
      );
    }
    // A scene load is a burst of reads that all want the same few chunks, and
    // the moment it ends those chunks are dead weight: what the game needs
    // from here on is the decoded `ui.Image`, not the compressed bytes it came
    // from. This is the one place that knows the burst is over, which is why
    // the pack does not try to guess it with a timer.
    //
    // A no-op in a development build, where nothing is mounted.
    AssetMounts.release();

    // The terminal report, always sent, so a caller can hang "hide the
    // loading screen" off `progress == 1.0` without also having to handle
    // "this scene needed no decodes at all".
    onProgress?.call(SceneLoadProgress('${next.runtimeType}', 1));
  }

  /// Drops [struct]'s claim on every asset it declared, and unloads the ones
  /// no remaining loaded scene still claims.
  ///
  /// The counting half of [unloadScene]. An asset shared by two loaded scenes
  /// survives the first unload and is freed by the second - which is the whole
  /// reason claims are counted and not diffed.
  void _releaseAssetsOf(SceneStruct struct) {
    final declared = struct.declaredAssets;
    // Addresses freed on this copy, to be freed on the other one too. Captured
    // before `unload`, which is what releases the address - reading it
    // afterwards would throw.
    final freed = <int>[];
    for (var i = 0; i < declared.length; i++) {
      final address = _dropClaim(declared[i]);
      if (address != null) freed.add(address);
    }
    // The other copy holds the decoded payload, so dropping the declaration
    // here is only half of it. The mirror of `requestAssetLoad`: without this,
    // a scene unloaded on the game isolate leaves its images alive on main
    // with nothing left that could name them.
    if (!runtime.decodesAssets) runtime.requestAssetUnload(freed);
  }

  /// Takes one claim on [asset], keeping its payload resident until whoever
  /// took it lets go.
  ///
  /// Internal because the two claimants are both inside the engine - a scene
  /// load, and a [Voice]. A game asks for a scene or a sound and the claim
  /// follows; a claim taken by hand is one nothing would ever release.
  @internal
  void claimAsset(Asset<Object?> asset) =>
      _assetClaims.update(asset, (n) => n + 1, ifAbsent: () => 1);

  /// Drops one claim on [asset], unloading it if that was the last.
  ///
  /// The single-asset spelling of what [_releaseAssetsOf] does for a whole
  /// scene, and the one a voice ending uses.
  @internal
  void releaseAssetClaim(Asset<Object?> asset) {
    final address = _dropClaim(asset);
    if (address != null && !runtime.decodesAssets) {
      runtime.requestAssetUnload(<int>[address]);
    }
  }

  /// Drops one claim and returns the address freed by doing so, or null if
  /// somebody else is still holding one.
  ///
  /// Does not tell the other copy: the scene path batches a whole scene's
  /// worth of addresses into one message, and this is the half both callers
  /// share.
  int? _dropClaim(Asset<Object?> asset) {
    final remaining = (_assetClaims[asset] ?? 0) - 1;
    if (remaining > 0) {
      _assetClaims[asset] = remaining;
      return null;
    }
    _assetClaims.remove(asset);
    final address = asset.pack();
    // Unloading runs on both copies - it is the undoing of a declaration,
    // and the two copies have to agree on what is declared for an address
    // to mean the same thing on both sides.
    game.assets.unload(asset.key);
    return address;
  }

  /// How many claims [asset] is currently under - what decides whether it
  /// survives the next unload.
  @visibleForTesting
  int assetClaimCount(Asset<Object?> asset) => _assetClaims[asset] ?? 0;

  // --- audio ------------------------------------------------------------

  AudioMixer? _mixer;

  /// Whether this game declared an audio backend at all - see
  /// `Game.createAudioBackend`.
  ///
  /// Checking this never builds one. A game with no backend has no mixer, no
  /// audio device and no mixing thread, and reading [audio] on it throws by
  /// name rather than handing back something that silently plays nothing.
  bool get hasAudio => game.createAudioBackend() != null;

  /// This game's mixer - what plays a clip. See [AudioMixer].
  ///
  /// Built on first use, and the backend is opened later still, on the first
  /// [AudioMixer.play]. So the cost of audio is paid by a game that makes a
  /// sound and by nothing else: declaring a backend costs one method call,
  /// touching this costs one object, and the device only opens when something
  /// is actually going to come out of it.
  ///
  /// Throws on the copy that does not simulate. The mixer lives where the
  /// decisions are - the system that decides a footstep happened, the
  /// `Asset<AudioClip>` it names and the scene whose claim keeps that clip
  /// alive are all on this isolate - and nothing about starting a sound
  /// crosses the boundary.
  AudioMixer get audio {
    _requireSimulating('audio');
    final existing = _mixer;
    if (existing != null) return existing;
    final backend = game.createAudioBackend();
    if (backend == null) {
      throw StateError(
        '${game.runtimeType} declared no audio backend, so there is nothing '
        'to play through. Override Game.createAudioBackend() and return one - '
        'SoLoudAudioBackend from package:good_audio_soloud is the '
        'implementation this engine ships. It is a separate package on '
        'purpose: a native audio engine is a plugin with a platform build, '
        'and a game that ships no sound should not have to compile one.',
      );
    }
    return _mixer = AudioMixer(
      backend,
      this,
      maxVoicesPerBus: game.maxVoicesPerBus,
    );
  }

  /// The bytes of [clip], on this isolate, for a backend to upload.
  ///
  /// Two routes, and which one runs is the ordinary decoding split. The copy
  /// that decodes has the payload already and reads it. The game isolate has
  /// only the address, so it asks - and audio is the asset kind where that
  /// works, because a clip's payload is a `Uint8List` and a `Uint8List`
  /// crosses. A texture's is a `ui.Image` and does not, which is why there is
  /// no general version of this.
  @internal
  Future<Uint8List> readAudioBytes(Asset<AudioClip> clip) async {
    if (!runtime.decodesAssets) return runtime.requestAudioBytes(clip.pack());
    if (!clip.isLoaded) {
      throw StateError(
        '${clip.debugLabel} is declared but not loaded, so there is nothing '
        'to play. An audio clip is loaded by the scene that declares it: put '
        "it in a SceneStruct's or a Component's describeAssets and play it "
        'from a scene that is loaded.',
      );
    }
    return clip.value.bytes;
  }

  // --- bring-up ---------------------------------------------------------

  /// Called once by `Game.start()`, before any declaration pass. Not part of
  /// the user-facing API: a state is bound by being returned from
  /// `Game.createState()`, never by hand.
  @internal
  void bindRuntime(GameRuntime runtime, {required bool simulating}) {
    _runtime = runtime;
    _simulating = simulating;
    final game = runtime.game;
    // Before every declaration pass, because registering an archetype binds it
    // to the pool its pages will come from (see `_SceneDescriptor.has`), and
    // that happens during those passes.
    _pool = MemoryPool(pageSize: game.pageSize, maxPages: game.maxPages);
  }

  // There is deliberately no asset gate here any more.
  //
  // A decoded asset owns a native payload - a `dart:ui.Image` for a texture -
  // which is **not sendable**, and the user keeps the instance in a field on
  // their scene, which is reachable from the `Game` that gets copied. While
  // main ran `mount()` before the spawn, a decode that finished before
  // `Isolate.spawn` serialized the message would fail the spawn, and would do
  // it intermittently, which is worse; a `Completer` held shut across the
  // spawn turned that race into an ordering guarantee.
  //
  // `mount()` runs on the game isolate now, after the spawn, so no scene is
  // loaded and no decode is started until the message is long gone. The race
  // is not managed, it is unreachable.

  /// Takes over the simulating role on the spawned copy.
  ///
  /// Main booted with `simulates: false` and this object was deep-copied with
  /// that value; the game isolate flips it once, at the top of
  /// `GameRuntime.runOnIsolate`, before anything ticks.
  @internal
  void markSimulating() => _simulating = true;

  // `mountScene()` used to live here: a second entry point that fired the
  // scene half of bring-up, because main ran `mount()` before the spawn and
  // `loadScene` deliberately left every scene unmounted there. Both copies had
  // to run the registering half and exactly one the spawning half, and the
  // seam between them was this method.
  //
  // There is no seam now. `mount()` runs once, on the game isolate, and does
  // all of it - so `loadScene` mounts what it loads, on the first load and the
  // fiftieth, through one path.

  /// The game has come up. Where a game loads its first scene.
  ///
  /// ```dart
  /// @override
  /// void onMounted() => loadScene(game.mainScene);
  /// ```
  ///
  /// **Runs on the game isolate**, after the spawn, and it is the first thing
  /// in the process that can create an entity. That is a change worth knowing
  /// about if you have code from when it ran on main: an `await` or a `.then`
  /// in here now resolves on the copy that actually simulates, so
  /// `loadScene(...).then((s) => level = s)` works. It silently did nothing
  /// before, because the callback fired on a copy that was about to be
  /// discarded.
  ///
  /// A plain virtual call, not an event: there is exactly one receiver and
  /// the framework is the only caller, so a dispatch mechanism was ceremony
  /// around a method call. The scene and entity levels went the other way -
  /// their virtuals became `SceneLifecycleListener`/`EntityLifecycleListener`,
  /// because there the owner is genuinely one listener among several. Here it
  /// is not: nothing else can be a `GameState`. Something
  /// *else* wanting to hear the game come up is a different question, and
  /// [GameLifecycleListener] is its answer - note that it fires after this
  /// does, once every scene loaded here is standing.
  void onMounted() {}

  /// The game is going down. The pool is disposed immediately afterwards.
  ///
  /// Runs *after* [gameUnmountedEvent] has been dispatched and after every
  /// loaded scene has come down, so the world is already gone by here. A
  /// listener that needs to read something out of it wants
  /// [GameLifecycleListener.onGameUnmounted].
  void onUnmounted() {}

  @internal
  void mount() {
    _requireSimulating('mount');
    onMounted();
    // After `onMounted`, never before: `onMounted` is where scenes are loaded,
    // and a listener told "the game came up" should find that world already
    // standing. Unconditional now - only the simulating copy ever reaches
    // here, because main stopped mounting its state at all.
    gameMountedEvent.call();
    // Then each system's own lifecycle signal, in declaration order.
    for (var i = 0; i < _systems.length; i++) {
      _systems[i].mountEvent.call();
    }
  }

  @internal
  void unmount() {
    // Unconditional, like [mount], and for the same reason: only the
    // simulating copy ever loaded anything, so only it has anything to take
    // down. The `if (_simulating)` guards that used to wrap each step were
    // there for main's copy, which no longer mounts and no longer unmounts.
    _requireSimulating('unmount');
    // First, while everything is still standing: scenes loaded, entities
    // readable, pool alive. The mirror of mount's ordering, not a copy of it -
    // bring-up tells you once the world exists, tear-down tells you while it
    // still does.
    gameUnmountedEvent.call();
    // Newest first, so a scene loaded on top of another comes down first.
    final doomed = List<Scene>.of(_loaded.reversed);
    for (var i = 0; i < doomed.length; i++) {
      final handle = doomed[i];
      final struct = SceneRegistry.tryResolve(handle);
      sceneUnloadedEvent.call(handle);
      struct?.unmountedEvent.call(handle);
      // Same order as unloadScene: scene first, then its entities, all
      // while the pool is still alive. `Game` disposes the pool wholesale
      // on stop, so this is the last moment a row is readable.
      struct?.unmountEntitiesOf(handle.slot);
      _loaded.remove(handle);
      // Releasing the slot at all matters because SceneRegistry is
      // process-global (like ArchetypeRegistry): a stopped game that kept its
      // entries would leave those slots resolving for a game that no longer
      // exists, and a second game in the same process would inherit them. The
      // pages go with the pool, which `Game` disposes wholesale on stop, so
      // there is no per-scene page release here.
      SceneRegistry.unregister(handle);
    }
    // Before the scenes go: a coroutine holds closures over entities whose
    // rows are about to be freed, and one left running would resume against
    // released pages on a game that has been restarted in the same isolate.
    coroutines.stopAll();
    onUnmounted();

    // **Last, and in reverse declaration order.**
    //
    // `GameSystem.unmountEvent` was declared from the start and *never fired
    // by anything* - a teardown hook that existed in name only, like
    // `EntityLifecycleListener`'s broadcast half did. So a system holding a
    // native resource had nowhere to release it, and
    // `Box2DPhysicsSystem.dispose` had to document "call this yourself after
    // stopping" - which nothing ever did. The Box2D world and, once the demo
    // started threading, its worker threads were leaked by every run.
    //
    // After the scenes, because releasing a world while entities still hold
    // bodies in it is a use-after-free, and that one is a native crash with
    // no Dart exception at all. Reverse order, mirroring how a scene loaded
    // on top of another comes down first: a system declared later may depend
    // on an earlier one and should let go before it does.
    for (var i = _systems.length - 1; i >= 0; i--) {
      _systems[i].unmountEvent.call();
    }

    // After the systems, because a system's own teardown may well be where a
    // sound is stopped, and stopping one after the mixer has gone would throw
    // on a game that is already halfway down.
    //
    // Not awaited, and it does not need to be: `AudioMixer.close` releases
    // every live voice's asset claim before its first `await`, so by the time
    // this returns the claim ledger is settled and only the native device is
    // still closing. There is nothing left here for it to race.
    unawaited(_mixer?.close() ?? Future<void>.value());
    _mixer = null;
  }

  /// Starts the wall-clock-paced tick loop. Called by `Game.start()` unless
  /// `autoTick: false`.
  @internal
  void startTimer() {
    final clock = Stopwatch()..start();
    var last = Duration.zero;
    // Paced by a real timer at roughly the fixed step, then reconciled by
    // the accumulator - not a tight loop. A timer never fires exactly on
    // time, which is the entire reason [advance] measures elapsed wall
    // clock instead of assuming one callback means one step.
    _timer = Timer.periodic(game.fixedTimeStep, (_) {
      final now = clock.elapsed;
      final elapsed = now - last;
      last = now;
      advance(elapsed);
    });
  }

  @internal
  void stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Whether the app is visible. False once every view is hidden.
  bool get isVisible => _visible;

  /// How fast simulated time runs against the wall clock. 1 is real time,
  /// 0.25 is quarter speed, 0 stops the simulation.
  ///
  /// # This scales the *rate*, never the step
  ///
  /// A fixed timestep means a constant step - that is the whole contract, and
  /// it is why anything integrating over it is stable. So [timeScale] changes
  /// **how often** a fixed tick happens, not how big it is. Every
  /// `onFixedUpdate` still represents exactly `Game.fixedTimeStep`, at every
  /// scale, and a system integrating over it needs to know nothing about this.
  ///
  /// That is also why there is no `unscaledDt` to look for. The engine already
  /// has both clocks under other names: the fixed loop is scaled simulation
  /// time, and `Tickable.onTick` is real wall clock that keeps running while
  /// the simulation is stopped. Anything that must ignore pause and scale - a
  /// UI animation, a network heartbeat, an autosave timer - is a `Tickable`,
  /// which is where it already belonged.
  ///
  /// # Zero runs no ticks at all
  ///
  /// At 0 the accumulator stops filling, so **no fixed tick runs** - rather
  /// than running with a zero-size step. Nothing divides by zero, no query
  /// walks for a step that changes nothing, and gameplay code never sees a
  /// step it was not written for. Presentation is untouched either way, which
  /// is what lets a pause menu draw.
  ///
  /// # There is a ceiling, and it is not this
  ///
  /// A large scale meets `Game.maxFixedStepsPerAdvance` and stops there: at
  /// 60Hz and the default cap of 5, a frame affords 5 steps however much
  /// scaled time it earned, and the rest is dropped. So scales past about 5
  /// run the game *slower* than asked instead of faster. Raise
  /// `maxFixedStepsPerAdvance` if a game genuinely needs fast-forward. This
  /// leaves that guard alone, and the guard is what stops a slow machine
  /// spiralling.
  double get timeScale => _timeScale;

  set timeScale(double value) {
    assert(
      value >= 0,
      'timeScale must not be negative (got $value). Nothing in this engine '
      'is reversible - a negative delta would run the accumulator backwards '
      'and corrupt the step arithmetic rather than rewind anything.',
    );
    assert(!value.isNaN, 'timeScale must be a number (got NaN).');
    _timeScale = value;
  }

  /// Whether the game has paused its own simulation.
  ///
  /// Separate from a [timeScale] of 0, and both stop the fixed tick. A game
  /// that pauses at half speed and then unpauses is back at half speed,
  /// which one number could not express.
  ///
  /// Unrelated to the app being hidden. That is `Game.pauseWhenHidden` and
  /// [setVisible], and the two compose: a game paused here stays paused
  /// across being hidden and shown again.
  bool paused = false;

  /// Whether a fixed tick can run at all right now.
  bool get _simulationRunning => !paused && _timeScale > 0;

  /// Runs exactly one fixed step, whatever the clock and [timeScale] say.
  ///
  /// For stepping a paused game forward - a debugger, a replay, a test. It
  /// goes straight to [runFixedStep] and **does not touch the accumulator**,
  /// so stepping a paused game leaves its timing exactly as it found it and
  /// unpausing afterwards resumes from where it was.
  ///
  /// One fixed *step*, not one frame: no presentation pass runs here. The
  /// frame loop is still going while paused, so the step is drawn by the
  /// next frame like any other.
  void stepOnce() {
    _requireSimulating('stepOnce');
    runFixedStep();
  }

  /// Reports the app becoming hidden or visible, from the main isolate's
  /// lifecycle observer - see `Game.pauseWhenHidden`.
  ///
  /// Idempotent, because the states that collapse onto each of these are not
  /// one message each: Flutter walks `inactive -> hidden -> paused` on the way
  /// down and back up again on the way out, so "hidden" arrives twice around
  /// any real backgrounding.
  ///
  /// # Why the gap is discarded and not caught up
  ///
  /// The accumulator is reset to zero, not left holding the hidden stretch.
  /// Left alone it would not run a step per hidden second - the
  /// spiral guard in [advance] already caps a single advance at
  /// `Game.maxFixedStepsPerAdvance` and drops the rest - so the choice here is
  /// between **five** catch-up steps on the first frame back and **none**.
  ///
  /// None is right. Those five steps would simulate 83ms of a world the player
  /// stopped watching some time ago, landing on the frame that is already
  /// paying to rebuild and redraw everything. A game that genuinely needs to
  /// account for the missing time gets it as
  /// [AppVisibilityListener.onAppShown]'s gap and can decide for itself -
  /// resynchronise from a server, advance a timer, do nothing.
  @internal
  void setVisible(bool visible) {
    _requireSimulating('setVisible');
    if (visible == _visible) return;
    _visible = visible;

    if (!visible) {
      _hiddenFor
        ..reset()
        ..start();
      if (game.pauseWhenHidden) {
        _pausedWhileHidden = true;
        // Whether to put a timer *back*, which is not the same question as
        // whether to pause. A host driving `advance` by hand has no timer to
        // stop, and starting one for it on the way out would hand it a second
        // tick source it never asked for.
        _restartTimerOnShow = _timer != null;
        stopTimer();
      }
      appHiddenEvent.call();
      return;
    }

    _hiddenFor.stop();
    final gap = _hiddenFor.elapsed;
    if (_pausedWhileHidden) {
      _pausedWhileHidden = false;
      // Before the timer, not after: `startTimer` begins measuring from now,
      // so anything left here is time earned before the pause.
      _accumulatedMicros = 0;
      if (_restartTimerOnShow) startTimer();
      _restartTimerOnShow = false;
    }
    appShownEvent.call(gap);
  }

  // --- the scheduler ----------------------------------------------------

  /// Accumulates [elapsed] wall-clock time and runs however many whole fixed
  /// steps it now affords, up to `Game.maxFixedStepsPerAdvance`. Returns the
  /// number of steps actually run.
  ///
  /// Time left over stays in the accumulator for next time, so steps land at
  /// the right long-run rate even though no timer fires on schedule. Time
  /// beyond the step cap is *discarded*, never carried - see
  /// `Game.maxFixedStepsPerAdvance`; the leftover is reduced modulo the step
  /// so the sub-step phase survives and the very next [advance] isn't
  /// immediately capped again by a backlog it can never clear.
  ///
  /// An app that was hidden does **not** come back to a catch-up burst, and it
  /// never could have: the cap above bounds a single frame however long the
  /// gap, and what survives a call is always under one step. [setVisible]
  /// discards that remainder too, so the first frame back spends nothing it
  /// earned before the app went away.
  ///
  /// A step whose systems threw is **not** retried. The subtraction above
  /// happens before the step runs, so the time is already spent by the time
  /// anything can fail - which is the right way round: a system that throws
  /// deterministically would otherwise be handed the same step forever.
  int advance(Duration elapsed) {
    _requireSimulating('advance');
    final game = this.game;
    final step = game.fixedTimeStep.inMicroseconds;
    // Scaled on the way *in*, which is the whole of time scale: the step
    // below is always `Game.fixedTimeStep`, and a slower scale earns one
    // less often. Nothing downstream - not the cap, not the modulo, not a
    // single system - knows this happened. See [timeScale].
    //
    // Stopped means adding nothing, not adding zero-size steps. The
    // accumulator keeps whatever phase it had, so unpausing resumes mid-step
    // instead of snapping to a step boundary.
    if (_simulationRunning) {
      _accumulatedMicros += (elapsed.inMicroseconds * _timeScale).round();
    }

    var steps = 0;
    final cap = game.maxFixedStepsPerAdvance;
    while (_accumulatedMicros >= step && steps < cap) {
      _accumulatedMicros -= step;
      runFixedStep();
      steps++;
    }
    if (_accumulatedMicros >= step) {
      _accumulatedMicros = _accumulatedMicros % step;
    }

    // Presentation runs once per frame, after however many simulation steps
    // this frame afforded - not once per step. Three catch-up steps still
    // produce one rendered frame, which is the whole point of separating the
    // two: the simulation rate is fixed, the presentation rate is whatever
    // the host is actually managing.
    //
    // Deliberately also runs on a frame that afforded *zero* steps. A
    // Tickable is presentation, and a frame in which the simulation did not
    // advance is still a frame - an interpolating renderer or a camera
    // smoothing toward a target has work to do on it.
    runPresentation(elapsed);
    _lastSteps = steps;
    // Replies only, and deliberately here rather than in [runFixedStep].
    // `pumpCommands` runs inside a fixed step, so a frame that afforded no
    // step - a paused game, a zero time scale - adopted nothing, and a
    // caller on this isolate awaiting a main-isolate answer waited out the
    // pause for a reply main had already written into the ring. Main has no
    // such gap: its pump rides the tick notification, which this method
    // sends on every frame. See `CommandTransport.adoptReplies` for why this
    // is not the whole pump - running a handler here would be user code
    // outside the tick window.
    runtime.adoptCommandReplies();
    // And the read-only lane, which is the other half of the same problem:
    // the adopt above answers a question this isolate asked, and this answers
    // a question the other one asked. Its handlers run here rather than in
    // [runFixedStep] because that is what makes them reachable on a frame
    // that afforded no step - a paused game, a zero time scale. They promise
    // not to write, and the transport opens a `HandlerWindow` around the
    // dispatch so the pool can hold them to it (#245); see
    // `CommandDescriptor.hasReadOnlyHandler`.
    //
    // After the presentation pass and after the adopt, so a request that
    // arrived on this frame is answered on it: `presentFrame` below is what
    // tells the other copy to come and look.
    runtime.runReadOnlyCommands();
    // Only now is the frame actually complete: the simulation advanced and
    // the presentation pass wrote whatever it produces. See
    // `Game.presentFrame` for why the announcement cannot happen earlier.
    runtime.presentFrame();
    return steps;
  }

  /// Runs exactly one fixed step - see the class doc for the sequence.
  /// Public so a headless host can drive its own loop; [advance] is what
  /// decides *how many* of these a real frame is worth.
  ///
  /// # A tick that throws publishes nothing
  ///
  /// The tick is atomic with respect to what a reader sees, and it is worth
  /// saying because the opposite is the natural assumption. A system throwing
  /// half way through leaves the *write* slot half updated - but
  /// [fixedTickEvent] runs before `pool.commitTick()`, so a tick that did not
  /// finish never publishes, and the next `pool.beginTick()` copies the last
  /// published state back over the write slot before anything runs. The
  /// half-simulated frame is overwritten, never shown.
  ///
  /// A throwing system is caught per listener and disabled - see
  /// `GameListener.disableAfterUncaught`. A throwing *coroutine* is handled
  /// separately, in `CoroutineScheduler.step`, which removes it and completes
  /// its handle with the error.
  void runFixedStep() {
    _requireSimulating('runFixedStep');
    final game = this.game;
    // First thing in the tick, before commands and before any system: every
    // declared input action is resolved from one raw device snapshot, so the
    // whole tick sees one coherent picture of what the player is doing. See
    // `Game.resolveInputs` and `Input`.
    game.resolveInputs();
    // Null with no scene loaded: there is no page storage to rotate, but the
    // systems still run - a system that only reads input or publishes state
    // does not need a world.
    final pool = this.pool;
    pool.beginTick();
    // Inside the tick window and before any system, deliberately and
    // unconditionally: an entity a command spawns has to be visible to every
    // system on the very tick the command lands. Not a declared `GameSystem`
    // for exactly that reason - it has no query, and letting it be
    // disabled or reordered would only create ways to break the engine.
    runtime.pumpCommands();
    // Coroutines next, on the same argument as commands and before any system
    // for the same reason: what a coroutine does when it resumes is write
    // component data, and every system on this tick should see it.
    //
    // **Inside the tick window is the whole point.** A coroutine is a `sync*`
    // generator precisely so it can be resumed from here - an `async*` one
    // would resume on a microtask, after `commitTick`, and every write it made
    // would be discarded by the next `beginTick`. See `Coroutine`'s doc.
    coroutines.step(Seconds.ofDuration(game.fixedTimeStep));
    // One dispatch over a list resolved at boot. `const` because the event
    // carries nothing, so the hottest event in the engine allocates nothing.
    fixedTickEvent.call();
    pool.commitTick();
    runtime.completeTick();
  }

  /// Runs the presentation pass: fires `TickEvent` at every enabled
  /// [Tickable] system, in the same sorted order the simulation uses.
  ///
  /// **Strictly after `commitTick`.** That placement is the whole contract:
  /// a `Tickable` reads the snapshot the simulation just published, so it
  /// sees everything the tick derived - `WorldTransform2D` most of all -
  /// without any second read path into the uncommitted slot (the no-specialised-variant rule). Reading published data here is exactly as fresh as recomputing it
  /// from published inputs inside the tick, so a renderer that moves from
  /// `FixedTickable` to `Tickable` loses no responsiveness and stops
  /// duplicating what the simulation already computed.
  ///
  /// Driven from [advance] after its fixed steps, so a frame that ran three
  /// simulation steps still presents once - presentation is per *frame*, not
  /// per step.
  void runPresentation(Duration delta) {
    _requireSimulating('runPresentation');
    // The delta travels as an argument, so a frame allocates nothing.
    tickEvent.call(delta);
  }

  // --- commands ---------------------------------------------------------

  /// A batch to build several calls into, sent and answered as one message -
  /// `Game.createCommandBatch` from the simulation side.
  ///
  /// The same object either way: there is one command channel per game, and
  /// this spelling exists so a system or a scene reaching through its state
  /// does not have to say `game.` to find it.
  CommandBatch createCommandBatch() => runtime.createCommandBatch();

  // --- reaching the rest of the engine ----------------------------------

  /// The one loaded scene, as [S].
  ///
  /// **Named for its precondition, because that is the whole hazard.** This
  /// throws the moment a second scene is resident, and several scenes resident
  /// at once is an ordinary thing here - a level plus a HUD, a pause menu over
  /// a game. Called `getScene`, it read as "get me the scene" and worked right
  /// through development, then started throwing on the first tick after
  /// something loaded a second one. The name is the only place that
  /// precondition can be seen at the call site.
  ///
  /// Use it when the game genuinely has one scene. When it does not, keep the
  /// handle `loadScene` returned, or index [loadedScenes].
  ///
  /// Throws when no scene is loaded too - [scene] is nullable by design, and
  /// none loaded is a legitimate state.
  S singleScene<S extends SceneStruct>() {
    final scene = this.scene;
    if (scene == null) {
      throw StateError(
        '$runtimeType has no scene loaded, so there is no $S to get. '
        'GameState.scene is nullable by design - check it rather than '
        'assuming a world exists.',
      );
    }
    if (scene is S) return scene;
    throw StateError('The running scene is ${scene.runtimeType}, not $S.');
  }

  // --- systems ----------------------------------------------------------
  //
  // Declared by `Game.describeSystems` and held here, which is the split the
  // whole isolate design turns on: *where a pass is written* is an API
  // question (a `Game` mixin has to be able to contribute a system - that is
  // what makes `extends Game2D` the whole opt-in for rendering), while *where
  // its results live* is an isolate question. The pass runs inside
  // `Game._bootGame`, so every system object exists on this copy and on no
  // other. A `Game` has no `getSystem` at all any more: on the presentation
  // isolate it would have compiled, read as though it worked, and found
  // nothing.

  final List<GameSystem> _systems = <GameSystem>[];
  final Map<Type, int> _systemIndex = <Type, int>{};

  /// Every declared system, in post-sort execution order. The live list, not
  /// a copy.
  @internal
  List<GameSystem> get declaredSystems => _systems;

  /// Where [type] sits in execution order, or null if it was never declared -
  /// what `GameSystemDescriptor` checks a duplicate against.
  @internal
  int? systemIndexOf(Type type) => _systemIndex[type];

  /// Appends a freshly declared system. Called once per `descriptor.has(...)`.
  @internal
  S addDeclaredSystem<S extends GameSystem>(S system) {
    _systemIndex[system.runtimeType] = _systems.length;
    _systems.add(system);
    return system;
  }

  /// Whether the system at declaration index [i] currently receives events.
  @internal
  bool isSystemEnabledAt(int i) => _systems[i].listensToEvents;

  /// Orders [declaredSystems] so that every constraint `GameSystem.compareTo`
  /// states is honoured, breaking ties on original declaration index - a system
  /// that expresses no opinion keeps its declared position relative to every
  /// other opinion-less system. Runs once, right after `Game.describeSystems`.
  ///
  /// # Why this is a graph and not a `List.sort`
  ///
  /// `compareTo` is a **partial** order here: most pairs of systems have no
  /// opinion about each other, and the ones that do usually name a single other
  /// type (`other is WorldTransformSystem ? -1 : 0`). That is not a comparator.
  /// It is neither antisymmetric - two systems that each return -1 to
  /// everything both claim to be first - nor transitive, and `List.sort` is
  /// only defined for a comparator that is both. Given one that is not, it does
  /// not merely mis-order the offending pair: it permutes the whole list, and
  /// unrelated constraints elsewhere are silently dropped.
  ///
  /// That is not hypothetical. The swarm demo declares two profiling markers
  /// that each return -1 unconditionally, and their contradiction cost
  /// `CritterSystem` its "-1 against `WorldTransformSystem`" - the spawner
  /// sorted *after* the pass that composes what it writes, so every entity it
  /// created was composed a tick late and drew one frame at the world origin
  /// (#5). Asking both directions does not help: the comparator was already
  /// being consulted correctly, and the sort scrambled it anyway.
  ///
  /// So each unordered pair is asked once, in declaration order, and the answer
  /// becomes an edge. Kahn's algorithm then emits the systems, always taking
  /// the lowest declaration index among those whose predecessors have all run,
  /// which is what keeps unconstrained systems in declared order. A constraint
  /// no longer competes with anything - it either holds or the graph has a
  /// cycle and this throws.
  ///
  /// O(n^2) comparisons against the old O(n log n), paid once at boot for a
  /// list that holds tens of systems. Nothing here runs per tick.
  @internal
  void sortSystems() {
    final n = _systems.length;
    if (n < 2) return;
    final after = List<List<int>>.generate(n, (_) => <int>[], growable: false);
    final blockedBy = List<int>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final si = _systems[i];
      for (var j = i + 1; j < n; j++) {
        final sj = _systems[j];
        // Both directions, for the reason the old comparator gave: a system
        // stating its position by overriding `compareTo` may be either operand,
        // and only one of the two calls carries the opinion. `sj.compareTo(si)`
        // returning -1 means "j wants to be before i", hence the negation.
        var cmp = si.compareTo(sj);
        if (cmp == 0) cmp = -sj.compareTo(si);
        if (cmp == 0) continue; // no opinion either way; declaration order
        final first = cmp < 0 ? i : j;
        final second = cmp < 0 ? j : i;
        after[first].add(second);
        blockedBy[second]++;
      }
    }
    final sorted = <GameSystem>[];
    final ready = <int>[];
    for (var i = 0; i < n; i++) {
      if (blockedBy[i] == 0) ready.add(i);
    }
    while (ready.isNotEmpty) {
      var pick = 0;
      for (var k = 1; k < ready.length; k++) {
        if (ready[k] < ready[pick]) pick = k;
      }
      final i = ready.removeAt(pick);
      sorted.add(_systems[i]);
      final unblocked = after[i];
      for (var k = 0; k < unblocked.length; k++) {
        if (--blockedBy[unblocked[k]] == 0) ready.add(unblocked[k]);
      }
    }
    if (sorted.length != n) _cyclicSystemOrder(blockedBy);
    _systems
      ..clear()
      ..addAll(sorted);
    _systemIndex.clear();
    for (var i = 0; i < _systems.length; i++) {
      _systemIndex[_systems[i].runtimeType] = i;
    }
  }

  /// Rejects a set of `compareTo` opinions that cannot all be satisfied.
  ///
  /// Whatever is still blocked when Kahn's algorithm runs dry sits on a cycle
  /// or downstream of one, so naming those systems names the argument. Every
  /// pair was resolved to a single edge before this point, so two systems each
  /// claiming to precede everything cannot land here - it takes three or more
  /// systems whose stated positions genuinely disagree.
  Never _cyclicSystemOrder(List<int> blockedBy) {
    final stuck = <Type>[
      for (var i = 0; i < blockedBy.length; i++)
        if (blockedBy[i] > 0) _systems[i].runtimeType,
    ];
    throw StateError(
      'The systems $stuck cannot be ordered: their GameSystem.compareTo '
      'results form a cycle, so each one is required to run before another '
      'that is required to run before it. Ordering is a set of constraints, '
      'not a ranking - a system should name the specific systems it must run '
      'before or after and return 0 for the rest.',
    );
  }

  /// A system declared in `Game.describeSystems`.
  S getSystem<S extends GameSystem>() {
    final index = _systemIndex[S];
    if (index == null) {
      throw ArgumentError(
        '$S is not declared in ${game.runtimeType}.describeSystems - systems '
        'are declared once, up front, and cannot be added at runtime.',
      );
    }
    return _systems[index] as S;
  }

  /// [getSystem], but `null` instead of throwing when [S] was never declared -
  /// for a caller that legitimately works either way.
  S? tryGetSystem<S extends GameSystem>() {
    final index = _systemIndex[S];
    return index == null ? null : _systems[index] as S;
  }

  /// Whether [S] currently receives events.
  bool isSystemEnabled<S extends GameSystem>() =>
      _systems[_requireSystemIndex(S)].listensToEvents;

  /// Resumes a system already declared in `Game.describeSystems` - a runtime
  /// pause/resume toggle, not registration.
  ///
  /// **Synchronous, and no wire index.** This runs on the isolate that holds
  /// the systems, so there is no control message to send and nothing to await.
  /// Main asks for a pause by declaring a command that means one and calling
  /// this in the handler.
  void enableSystem<S extends GameSystem>() => setSystemEnabled(S, true);

  /// Pauses a system already declared in `Game.describeSystems` - it stops
  /// ticking until re-enabled, but is not removed from the declared set.
  void disableSystem<S extends GameSystem>() => setSystemEnabled(S, false);

  void enableSystems(Iterable<Type> systems) {
    for (final type in systems) {
      setSystemEnabled(type, true);
    }
  }

  void disableSystems(Iterable<Type> systems) {
    for (final type in systems) {
      setSystemEnabled(type, false);
    }
  }

  /// The `Type`-taking form, for the plural spellings and for a caller holding
  /// a `Type` instead of a type argument.
  void setSystemEnabled(Type type, bool enabled) {
    _systems[_requireSystemIndex(type)].enabled = enabled;
  }

  int _requireSystemIndex(Type type) {
    final index = _systemIndex[type];
    if (index == null) {
      throw ArgumentError(
        '$type is not declared in ${game.runtimeType}.describeSystems.',
      );
    }
    return index;
  }

  void _requireSimulating(String what) {
    if (!_simulating) {
      throw StateError(
        '$what() was called on a GameState that does not own the simulation. '
        'The copy the main isolate holds after start() exists only so that '
        'command handlers are registered identically on both sides - the game '
        'isolate\'s copy is the one that ticks, holds the scenes and holds the '
        'systems. See the class doc on Game.',
      );
    }
  }
}

/// One progress report from [GameState.loadScene] - what is being brought up
/// and how far along the transition as a whole is.
///
/// Named for *scene loading*, not for assets. Asset decoding is the only stage
/// that reports today, but the later stages of bring-up (spawning a scene's
/// initial entities, warming a render pipeline) are the same kind of "this
/// transition is N% done" news to the same loading screen, and they will report
/// through this type instead of a second one that forces every consumer to
/// handle both.
///
/// Allocated once per reported step, at transition time. That is not a
/// no-allocation rule concern: a scene transition is not the hot path, and
/// there is nothing per-entity or per-tick anywhere near it.
class SceneLoadProgress {
  const SceneLoadProgress(this.label, this.progress);

  /// What is being loaded right now - an asset's `GameAsset.debugLabel`
  /// while assets are decoding, the scene's own type name on the terminal
  /// report. Diagnostics and loading-screen text; nothing keys off it.
  final String label;

  /// Overall transition progress, `0..1`. Monotonically non-decreasing across
  /// one [GameState.loadScene] call, and exactly `1.0` on the last report.
  final double progress;

  @override
  String toString() => 'SceneLoadProgress($label, $progress)';
}
