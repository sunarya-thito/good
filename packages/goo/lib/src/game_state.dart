import 'dart:async';

import 'package:meta/meta.dart';

import 'package:goo/src/asset.dart';
import 'package:goo/src/command/command.dart';
import 'package:goo/src/command/param.dart';
import 'package:goo/src/event.dart';
import 'package:goo/src/event/state.dart';
import 'package:goo/src/game.dart';
import 'package:goo/src/pool.dart';
import 'package:goo/src/scene.dart';
import 'package:goo/src/scene_handle.dart';
import 'package:goo/src/system.dart';

/// Holds asset decoding shut across `Game.start()`'s spawn.
///
/// A **library-private static**, deliberately, and not a field: a `Completer`
/// is not sendable, and anything reachable from the `Game` is serialized by
/// `Isolate.spawn`. Statics belong to no object graph and are per-isolate, so
/// this is invisible to the copy - which is exactly right, since only the copy
/// doing the spawning has anything to wait for.
Completer<void>? _bootAssetGate;

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
/// order** -> `commitTick` -> notify. Command application deliberately
/// happens before any system runs and inside the tick window, so an entity
/// spawned by a command is visible to every system on the very tick it
/// arrives. Input resolution goes first for the same class of reason: every
/// system in the tick, and every command applied during it, sees the same
/// input snapshot rather than one that shifts underneath them (see `Input`).
///
/// Ordering is declaration order - the order `SystemDescriptor.has<T>()` was
/// called in `Game.describeSystems`, then `GameSystem.compareTo` - and
/// nothing else. Dependency-based ordering ("run me after physics") is
/// deliberately deferred: it needs a declared dependency edge on
/// `GameSystem`, a topological sort, and a cycle diagnostic, none of which
/// unblock anything the engine currently does. Declaring the order explicitly
/// in one place is not a workaround for its absence; it is a perfectly good
/// answer that happens to also be the whole feature.
///
/// # Isolate affinity
///
/// `GameState` is a [GameListener] and deliberately **not** a
/// `WidgetListener`: it lives where the tick loop does and there is no
/// Flutter engine attached to that isolate. It can be `FixedTickable` and
/// `LifecycleListener`; it cannot be `BuildWidgetListener`. See `GameEvent`'s
/// doc.
abstract class GameState<T extends Game> with GameListenerMixin {
  Game? _game;
  bool _simulating = false;

  // Every loaded scene, in load order. Handles rather than structs, because a
  // struct is a *declaration* that can back several loaded scenes at once -
  // exactly as one EntityStruct backs many Entities - so the identity is the
  // handle and never the object.
  final List<Scene> _loaded = <Scene>[];

  // How many loaded scenes declared each asset. An asset is freed when the
  // last of them is unloaded, never before - see [_releaseAssetsOf].
  final Map<GameAsset, int> _assetClaims = <GameAsset, int>{};
  int _accumulatedMicros = 0;
  Timer? _timer;



  /// The `Game` this state belongs to - **this isolate's copy** of it. Set
  /// once, by `Game.start()`, before any declaration pass runs.
  T get game {
    final game = _game;
    if (game == null) {
      throw StateError(
        '$runtimeType is not bound to a Game. A GameState is created by '
        'Game.createState() during start(); one constructed by hand has no '
        'declarations to read and no tick to run on.',
      );
    }
    return game as T;
  }

  /// Whether this copy owns the simulation.
  ///
  /// True on the game isolate, and in the single-copy inline path
  /// (`Game.start(inline: true)`) where one copy does both jobs. False on the
  /// main-isolate handle, whose `GameState` exists only to re-run the same
  /// declaration passes - so that archetype ids agree across the boundary and
  /// announced pages have a pool to be adopted into - and never ticks.
  ///
  /// This replaced the old `Game.isOnIsolate`/`supportsIsolate` pair: there
  /// is no longer any notion of a platform that "doesn't support isolates",
  /// only of which copy simulates. Native spawns, web runs inline, and both
  /// answer this question the same way.
  bool get isSimulating => _simulating;

  /// Every loaded scene, in load order. The live list - do not retain it.
  ///
  /// Several scenes can be resident at once (a level plus a HUD, a preloaded
  /// next level, a background sim) and **all of them tick**. Which one is
  /// *front* is a separate question, answered by [switchScene] /
  /// `Scene.isActive`.
  List<Scene> get loadedScenes => _loaded;

  /// The front scene, or null when nothing is loaded.
  ///
  /// **Nullable on purpose.** A `GameState` with no scene is a legitimate,
  /// expected state - a game booted straight to a menu, a headless host that
  /// only runs systems, a state between transitions. Everything that touches
  /// it handles that: a renderer draws nothing and a widget shows whatever it
  /// shows when there is no world yet. It is not an error to be reported.
  Scene? get sceneHandle => SceneRegistry.active;

  /// The front scene's declaration - `sceneHandle.get<SceneStruct>()`, or null
  /// when nothing is loaded.
  SceneStruct? get scene {
    final handle = SceneRegistry.active;
    return handle == null ? null : SceneRegistry.tryResolve(handle);
  }

  /// This game's page storage - **one pool, owned here**, not one per scene.
  ///
  /// Non-null from `bindGame` onwards, so from before any declaration pass
  /// runs, which is why the tick loop no longer has to ask whether there is
  /// storage to rotate: a game with no scene loaded has an empty pool rather
  /// than no pool, and `beginTick`/`commitTick` over zero pages is free.
  ///
  /// It moved here from `SceneStruct` because a struct is a declaration that
  /// can back several loaded scenes at once - see `SceneStruct.pool`.
  MemoryPool get pool => _pool!;

  MemoryPool? _pool;

  /// Fixed ticks completed. One counter, kept on the `Game` because the
  /// handle copy needs to track it too (it learns each tick from a message);
  /// this is the simulation-side spelling of the same number.
  int get tick => game.tick;

  // --- declaration hooks ------------------------------------------------

  /// Declares this state's published state - see [Game.describeState], which
  /// carries the whole story. One of exactly three hosts that may.
  ///
  /// Declared second in the shared boot pass, after the `Game`'s own and
  /// before every declared `GameSystem`'s.
  void describeState(StateDescriptor descriptor) {}

  /// Registers the handlers that run on the **game** isolate, for commands
  /// the [Game] declared.
  ///
  /// ```dart
  /// @override
  /// void describeCommands(CommandDescriptor descriptor) {
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
  void describeCommands(CommandDescriptor descriptor) {}

  // --- scene loading ----------------------------------------------------

  /// Makes [next] the running scene, and returns a future that completes
  /// once it is fully ready to simulate.
  ///
  /// There is deliberately no `createScene()` factory: a game does not
  /// declare its starting world, it *loads* one, from `onMounted` like any
  /// other scene transition. So the first load and the fiftieth go through
  /// exactly one code path, and "no scene yet" is an ordinary state rather
  /// than a special pre-boot case ([scene] is nullable for precisely this
  /// reason).
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
  /// needs - its own `SceneStruct.describeAssets` plus every registered prefab's
  /// `Component.describeAssets` - which is what assigns each one its
  /// process-global address, identically on both copies (see `GameAssets`).
  /// The asynchronous half then reconciles the two scenes' footprints:
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
  /// The outgoing scene's *pages* are still deliberately not freed - see the
  /// comment inside.
  Future<Scene> loadScene(
    SceneStruct next, {
    void Function(SceneLoadProgress)? onProgress,
  }) async {
    // Deliberately **not** `_requireSimulating`. Both copies run this: main
    // runs it before the spawn, which is what registers the archetypes and
    // declares the assets, and the spawned copy inherits the result. Only the
    // *spawning* half below is simulation-side.
    //
    // Synchronous, order-critical half - see the doc above.
    next.bindGame(game);
    // Both the pool and the asset table come from the Game: a scene declares
    // into the table its game loads from, or the two would silently be
    // different tables and every load would fail to find its declaration.
    // A scene declared in `Game.describeScenes` is already initialized, which
    // is the entire point of declaring it - loading costs no registration.
    if (!next.isInitialized) {
      next.initializeScene(pool, assets: game.assets);
    }

    // A slot, a generation, and a page group. **Loading no longer replaces
    // anything**: several instances of one `SceneStruct` can be resident at
    // once, each owning its own pages, and each individually unloadable.
    final handle = SceneRegistry.register(next);
    _loaded.add(handle);
    // The first scene loaded becomes the active one, because a game with
    // exactly one scene should not have to call switchScene to see it. Every
    // later load leaves the front scene alone - loading and switching are
    // separate on purpose.
    if (SceneRegistry.active == null) SceneRegistry.setActive(handle);

    // The instance's own bring-up, and where it spawns - so only on the copy
    // that simulates. Main registers and stops; the game isolate runs this for
    // every scene main loaded, from `mountScene()`, after the spawn. It takes
    // the handle because a `SceneStruct` is a declaration that may back
    // several loaded scenes, so "spawn into my scene" is a question only the
    // handle answers.
    if (_simulating) next.onMounted(handle);

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
  /// resolving a handle into one reports the unload rather than reading
  /// whatever a later scene put at that address. That is exactly why a scene's
  /// rows never share a page with another scene's.
  ///
  /// The scene's *archetypes* are not unregistered. Archetype ids are
  /// process-global and never recycled, and a declared scene is expected to be
  /// loaded again - re-registering per load is what `Game.describeScenes`
  /// exists to avoid.
  void unloadScene(Scene scene) {
    _requireSimulating('unloadScene');
    final struct = SceneRegistry.tryResolve(scene);
    if (struct == null) return;

    struct.onUnmounted(scene);
    _releaseAssetsOf(struct);

    // Unregister first, then release the pages. That order is deliberate and
    // is what makes the deferred free safe: from here on nothing can resolve
    // this `Scene` or spawn into it, so the pages are unreachable through the
    // API even while the memory is still alive waiting for the reader to let
    // go. See `Game.releaseScenePages`.
    final slot = scene.slot;
    _loaded.remove(scene);
    SceneRegistry.unregister(scene);
    game.releaseScenePages(slot);
  }

  /// Unloads **every** loaded instance of [struct].
  ///
  /// Iterates a copy of the list, because [unloadScene] mutates it.
  void unloadAllScene(SceneStruct struct) {
    _requireSimulating('unloadAllScene');
    final doomed = <Scene>[
      for (final scene in _loaded)
        if (identical(SceneRegistry.tryResolve(scene), struct)) scene,
    ];
    for (var i = 0; i < doomed.length; i++) {
      unloadScene(doomed[i]);
    }
  }

  /// Makes [scene] the front scene.
  ///
  /// **Informational, and deliberately so.** It does not gate simulation -
  /// every loaded scene ticks, so a background level keeps running - and
  /// nothing is enforced. It records which scene is front, and consumers ask
  /// (`Scene.isActive`). The framework's own renderer and mouse picker honour
  /// it; a user's system is free to.
  void switchScene(Scene scene) {
    _requireSimulating('switchScene');
    SceneRegistry.setActive(scene);
  }


  /// Loads what the incoming scene added and unloads what the outgoing scene
  /// took with it - see [loadScene]'s doc for the policy this implements.
  ///
  /// Transition-time code: it allocates a `SceneLoadProgress` per completed
  /// asset and a `Set` for the keep-set, both of which are exactly the kind
  /// of allocation RULES.md rule 1 is *not* about. Nothing here runs per
  /// entity or per tick.
  Future<void> _reconcileAssets(
    SceneStruct next,
    void Function(SceneLoadProgress)? onProgress,
  ) async {
    // Nothing decodes until the spawn has happened - see
    // [releaseAssetLoading]. Null (and so a no-op) everywhere except the one
    // window inside `Game.start()`.
    final gate = _bootAssetGate;
    if (gate != null) await gate.future;

    final incoming = next.declaredAssets;
    // One claim per *loaded scene*, taken before any decode. This replaced a
    // pairwise `previous -> next` diff, which could not survive several
    // scenes being resident: with A and C both using an atlas and B not,
    // A -> B unloaded it and B -> C decoded it again. A count cannot make
    // that mistake, and it is also the only thing that can answer "is anyone
    // still using this" when scenes are unloaded out of order.
    for (var i = 0; i < incoming.length; i++) {
      _assetClaims.update(incoming[i], (n) => n + 1, ifAbsent: () => 1);
    }

    if (!game.decodesAssets) return;

    // Counted up front so the denominator is the number of decodes this load
    // will actually perform - a scene whose assets are all already resident
    // reports one 1.0 and does no work.
    var pending = 0;
    for (var i = 0; i < incoming.length; i++) {
      if (game.assets.tryGet(incoming[i])?.isLoaded != true) pending++;
    }
    var completed = 0;
    for (var i = 0; i < incoming.length; i++) {
      final key = incoming[i];
      if (game.assets.tryGet(key)?.isLoaded == true) continue;
      await game.assets.load(key);
      completed++;
      onProgress?.call(SceneLoadProgress(key.debugLabel, completed / pending));
    }
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
  /// reason claims are counted rather than diffed.
  void _releaseAssetsOf(SceneStruct struct) {
    final declared = struct.declaredAssets;
    for (var i = 0; i < declared.length; i++) {
      final key = declared[i];
      final remaining = (_assetClaims[key] ?? 0) - 1;
      if (remaining > 0) {
        _assetClaims[key] = remaining;
        continue;
      }
      _assetClaims.remove(key);
      // Unloading runs on both copies - it is the undoing of a declaration,
      // and the two copies have to agree on what is declared for an address
      // to mean the same thing on both sides.
      game.assets.unload(key);
    }
  }


  // --- bring-up ---------------------------------------------------------

  /// Called once by `Game.start()`, before any declaration pass. Not part of
  /// the user-facing API: a state is bound by being returned from
  /// `Game.createState()`, never by hand.
  @internal
  void bindGame(Game game, {required bool simulating}) {
    _game = game;
    _simulating = simulating;
    // Before every declaration pass, because registering an archetype binds it
    // to the pool its pages will come from (see `_SceneDescriptor.has`), and
    // that happens during those passes.
    _pool = MemoryPool(pageSize: game.pageSize, maxPages: game.maxPages);
  }

  /// Holds asset decoding shut, and opens it again once the spawn is done.
  ///
  /// A decoded asset owns a native payload - a `dart:ui.Image` for a texture -
  /// which is **not sendable**, and the user keeps the instance in a field on
  /// their scene, which is reachable from the `Game` that gets copied. So a
  /// decode finishing before `Isolate.spawn` serialized the message would fail
  /// the spawn, and would do it intermittently, which is worse. Closing the
  /// gate before `mount()` and opening it after the spawn turns that race into
  /// an ordering guarantee.
  ///
  /// Only `Game.start()`'s spawning path uses it; inline never closes it.
  @internal
  void closeAssetGate() => _bootAssetGate = Completer<void>();

  @internal
  void releaseAssetLoading() {
    final gate = _bootAssetGate;
    _bootAssetGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  /// Takes over the simulating role on the spawned copy.
  ///
  /// Main booted with `simulates: false` and this object was deep-copied with
  /// that value; the game isolate flips it once, at the top of
  /// `Game._runOnIsolate`, before anything ticks.
  @internal
  void markSimulating() => _simulating = true;

  /// Fires `MountEvent` at the **loaded scene**, which is where its starting
  /// entities are spawned.
  ///
  /// Split from [mount] because the two halves of bring-up now happen on
  /// different copies. Main runs [mount], whose `onMounted` calls [loadScene],
  /// which registers archetypes and declares assets - the declarative half.
  /// `loadScene` sees `simulates: false` there and deliberately leaves the
  /// scene unmounted. This is the other half, run once on the game isolate
  /// after the spawn, and it is the first thing in the process that creates an
  /// entity.
  @internal
  void mountScene() {
    _requireSimulating('mountScene');
    // Every scene main loaded, in load order. Main ran `loadScene`'s
    // registering half for each; this is the spawning half it deliberately
    // left undone.
    for (var i = 0; i < _loaded.length; i++) {
      final handle = _loaded[i];
      SceneRegistry.tryResolve(handle)?.onMounted(handle);
    }
  }

  /// Fires `MountEvent` at this state - which is where a game calls
  /// [loadScene] and so where its world actually comes into being.
  ///
  /// Called by `Game.start()` on **both** isolate copies (after `ready` in
  /// the spawned configuration, so any page the load allocates is announced
  /// by the first tick). Both must run it because both must register the
  /// same archetypes in the same order; only the simulating copy goes on to
  /// fire `MountEvent` at the scene itself and spawn entities - see
  /// [loadScene].
  ///
  /// The scene is deliberately not mounted here: at this point there is no
  /// scene yet. `loadScene` mounts whatever it loads, including every later
  /// transition, so there is one path rather than a special first one.
  @internal
  void mount() => fireEvent(MountEvent());

  @internal
  void unmount() {
    // Newest first, so a scene loaded on top of another comes down first.
    final doomed = List<Scene>.of(_loaded.reversed);
    for (var i = 0; i < doomed.length; i++) {
      final handle = doomed[i];
      if (_simulating) SceneRegistry.tryResolve(handle)?.onUnmounted(handle);
      _loaded.remove(handle);
      // Releasing the slot at all matters because SceneRegistry is
      // process-global (like ArchetypeRegistry): a stopped game that kept its
      // entries would leave `Scene.isActive` answering for a game that no
      // longer exists. The pages go with the pool, which `Game` disposes
      // wholesale on stop, so there is no per-scene page release here.
      SceneRegistry.unregister(handle);
    }
    fireEvent(UnmountEvent());
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

  // --- the scheduler ----------------------------------------------------

  /// Accumulates [elapsed] wall-clock time and runs however many whole fixed
  /// steps it now affords, up to `Game.maxFixedStepsPerAdvance`. Returns the
  /// number of steps actually run.
  ///
  /// Time left over stays in the accumulator for next time, so steps land at
  /// the right long-run rate even though no timer fires on schedule. Time
  /// beyond the step cap is *discarded* rather than carried - see
  /// `Game.maxFixedStepsPerAdvance`; the leftover is reduced modulo the step
  /// so the sub-step phase survives and the very next [advance] isn't
  /// immediately capped again by a backlog it can never clear.
  int advance(Duration elapsed) {
    _requireSimulating('advance');
    final game = this.game;
    final step = game.fixedTimeStep.inMicroseconds;
    _accumulatedMicros += elapsed.inMicroseconds;

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
    // Only now is the frame actually complete: the simulation advanced and
    // the presentation pass wrote whatever it produces. See
    // `Game.presentFrame` for why the announcement cannot happen earlier.
    game.presentFrame();
    return steps;
  }

  /// Runs exactly one fixed step - see the class doc for the sequence.
  /// Public so a headless host can drive its own loop; [advance] is what
  /// decides *how many* of these a real frame is worth.
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
    game.pumpCommands();
    // The simulating systems only, filtered once at boot (see
    // `Game._bakeTickPhases`) - a direct call, no event object, no runtime
    // type test. Enablement stays a runtime read because it is runtime state.
    final systems = game.fixedTickables;
    final indices = game.fixedTickableIndices;
    for (var i = 0; i < systems.length; i++) {
      if (!game.isSystemEnabledAt(indices[i])) continue;
      systems[i].onFixedUpdate();
    }
    pool.commitTick();
    game.completeTick();
  }

  /// Runs the presentation pass: fires `TickEvent` at every enabled
  /// [Tickable] system, in the same sorted order the simulation uses.
  ///
  /// **Strictly after `commitTick`.** That placement is the whole contract:
  /// a `Tickable` reads the snapshot the simulation just published, so it
  /// sees everything the tick derived - `WorldTransform2D` most of all -
  /// without any second read path into the uncommitted slot (RULES.md rule
  /// 8). Reading published data here is exactly as fresh as recomputing it
  /// from published inputs inside the tick, so a renderer that moves from
  /// `FixedTickable` to `Tickable` loses no responsiveness and stops
  /// duplicating what the simulation already computed.
  ///
  /// Driven from [advance] after its fixed steps, so a frame that ran three
  /// simulation steps still presents once - presentation is per *frame*, not
  /// per step.
  void runPresentation(Duration delta) {
    _requireSimulating('runPresentation');
    final game = this.game;
    // The presenting systems only - same baked-at-boot shape as the fixed
    // step above.
    final systems = game.tickables;
    final indices = game.tickableIndices;
    for (var i = 0; i < systems.length; i++) {
      if (!game.isSystemEnabledAt(indices[i])) continue;
      systems[i].onTick(delta);
    }
  }

  // --- commands ---------------------------------------------------------

  /// A batch to build several calls into, sent and answered as one message -
  /// `Game.createCommandBatch` from the simulation side.
  ///
  /// The same object either way: there is one command channel per game, and
  /// this spelling exists so a system or a scene reaching through its state
  /// does not have to say `game.` to find it.
  CommandBatch createCommandBatch() => game.createCommandBatch();

  // --- reaching the rest of the engine ----------------------------------

  /// The running scene, as [S]. Throws if there is no scene, or if it is
  /// some other type - use [scene] directly when absence is expected.
  S getScene<S extends SceneStruct>() {
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

  /// A system declared in `Game.describeSystems` - *this isolate's* twin of
  /// it, which on the simulating copy is the one that ticks.
  S getSystem<S extends GameSystem>() => game.getSystem<S>();

  void _requireSimulating(String what) {
    if (!_simulating) {
      throw StateError(
        '$what() was called on a GameState that does not own the simulation. '
        'The copy the main isolate holds after start() exists only to mirror '
        'declarations and adopt pages - the game isolate\'s copy is the one '
        'that ticks. See the class doc on Game.',
      );
    }
  }
}

/// One progress report from [GameState.loadScene] - what is being brought up
/// and how far along the transition as a whole is.
///
/// Named for *scene loading*, not for assets, deliberately. Asset decoding is
/// the only stage that reports today, but the later stages of bring-up
/// (spawning a scene's initial entities, warming a render pipeline) are the
/// same kind of "this transition is N% done" news to the same loading screen,
/// and they will report through this type rather than through a second one
/// that forces every consumer to handle both.
///
/// Allocated once per reported step, at transition time. That is not a
/// RULES.md rule 1 concern: a scene transition is not the hot path, and there
/// is nothing per-entity or per-tick anywhere near it.
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
