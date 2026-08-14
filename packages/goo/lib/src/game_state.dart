import 'dart:async';

import 'package:meta/meta.dart';

import 'package:goo/src/asset.dart';
import 'package:goo/src/event.dart';
import 'package:goo/src/event/fixed_loop.dart';
import 'package:goo/src/event/lifecycle.dart';
import 'package:goo/src/event/tick_loop.dart';
import 'package:goo/src/command/command.dart';
import 'package:goo/src/command/param.dart';
import 'package:goo/src/game.dart';
import 'package:goo/src/pool.dart';
import 'package:goo/src/scene.dart';
import 'package:goo/src/scene_handle.dart';
import 'package:goo/src/system.dart';

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
abstract class GameState<T extends Game> extends GameListenerBase
    with EventBus {
  /// The simulation tick, dispatched once per fixed step to every declared
  /// `FixedTickable` system.
  ///
  /// Declared here rather than hand-rolled on `Game` because the tick is not
  /// special: it is an event like any other, and it earns the same
  /// resolved-at-boot listener list every other event gets. Before this it was
  /// a bespoke pair of filtered lists - the right idea implemented once, for
  /// one case, generalising to nothing.
  late final SignalDispatcher<FixedTickable> fixedTickEvent;

  /// The presentation pass, dispatched once per *frame* - see [runPresentation].
  late final EventDispatcher<Tickable, Duration> tickEvent;

  /// The game has come up, on the simulating copy, with its scenes mounted.
  late final SignalDispatcher<GameLifecycleListener> gameMountedEvent;

  /// The game is going down, dispatched before anything is torn down.
  late final SignalDispatcher<GameLifecycleListener> gameUnmountedEvent;

  // Scene and entity lifecycle are **not** declared here. They belong to the
  // scene and the prefab respectively (`SceneStruct.mountedEvent`,
  // `EntityStruct.mountedEvent`), because a dispatcher's audience is its
  // declaring owner's composition. Declared here they would be one list per
  // level holding everything in the game, so unloading scene A would call
  // `onSceneUnmounted(A)` on scene B and every prefab B owns. The game level
  // is different and stays here: `GameState` genuinely is the only object at
  // that level, so "everything below" is the right audience.

  @override
  void describeEvents(EventDescriptor descriptor) {
    fixedTickEvent = descriptor.hasSignal(
      (listener) => listener.onFixedUpdate(),
    );
    tickEvent = descriptor.has((listener, delta) => listener.onTick(delta));
    gameMountedEvent = descriptor.hasSignal(
      (listener) => listener.onGameMounted(),
    );
    gameUnmountedEvent = descriptor.hasSignal(
      (listener) => listener.onGameUnmounted(),
    );
  }

  /// Offers every declared system to this state's dispatchers.
  ///
  /// The explicit composition walk: the event API does not know a `GameState`
  /// has systems, so this says so. A system that is a `FixedTickable` lands in
  /// [fixedTick]; one that is a `Tickable` lands in [tick]; one that is
  /// neither lands nowhere and is never visited again.
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
  /// next level, a background sim) and **all of them are live** - all tick,
  /// all receive input, all render. There is no front scene: a game that wants
  /// one paused or hidden either unloads it or checks a flag of its own,
  /// because only the game knows what "paused" should mean for it.
  List<Scene> get loadedScenes => _loaded;

  /// The **first** loaded scene, or null when nothing is loaded.
  ///
  /// A convenience for the overwhelmingly common single-scene game, not a
  /// statement that this scene is special. It used to mean "the front one",
  /// set by a `switchScene` that gated nothing; deleting that left the name
  /// needing an honest meaning, and "first loaded" is the one that is
  /// *derived* rather than stored - there is no second source of truth to
  /// drift, and no setter to call at the wrong time. A game with several
  /// scenes resident should say which it means and use [loadedScenes].
  ///
  /// **Nullable on purpose.** A `GameState` with no scene is a legitimate,
  /// expected state - a game booted straight to a menu, a headless host that
  /// only runs systems, a state between transitions. Everything that touches
  /// it handles that: a renderer draws nothing and a widget shows whatever it
  /// shows when there is no world yet. It is not an error to be reported.
  Scene? get sceneHandle => _loaded.isEmpty ? null : _loaded.first;

  /// The first loaded scene's declaration - `sceneHandle.get<SceneStruct>()`,
  /// or null when nothing is loaded.
  SceneStruct? get scene {
    final handle = sceneHandle;
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
  ///   descriptor.has(MovementSystem());
  ///   descriptor.has(CombatSystem());
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
  void describeSystems(SystemDescriptor descriptor) {}

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
    // Only the simulating copy loads a scene, and that is new: this used to
    // run on both, because main registered the archetypes before the spawn and
    // the game isolate inherited them. Both copies registering meant both had
    // to arrive at the same ids, which is the agreement `Game`'s registry
    // snapshot existed to preserve. One registrar has no one to agree with.
    _requireSimulating('loadScene');

    // Synchronous, order-critical half - see the doc above.
    next.bindState(this);
    // Both the pool and the asset table come from the Game: a scene declares
    // into the table its game loads from, or the two would silently be
    // different tables and every load would fail to find its declaration.
    // A scene declared in `Game.describeScenes` is already initialized, which
    // is the entire point of declaring it - loading costs no registration.
    if (!next.isInitialized) {
      next.initializeScene(pool,
          assets: game.assets, cameraViews: game.cameraViews);
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

    // The instance's own bring-up, and where it spawns. It takes the handle
    // because a `SceneStruct` is a declaration that may back several loaded
    // scenes, so "spawn into my scene" is a question only the handle answers.
    next.onMounted(handle);
    // After the scene's own mount, never before: a listener told "a scene
    // loaded" should find its starting entities already there. Fired on the
    // scene's own dispatcher, so it reaches that scene's composition and no
    // other scene's.
    next.mountedEvent.call(handle);

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

    // Before anything is released, so a listener can still read the scene's
    // entities - after this method they are gone for good. On the struct's own
    // dispatcher: only this scene and its prefabs are told.
    struct.unmountedEvent.call(scene);
    struct.onUnmounted(scene);
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
  /// of allocation RULES.md rule 1 is *not* about. Nothing here runs per
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
      _assetClaims.update(incoming[i], (n) => n + 1, ifAbsent: () => 1);
    }

    if (!game.decodesAssets) {
      // This copy declared the assets - that is what gave them their addresses
      // - but it cannot decode one, because decoding needs Flutter. So it asks
      // the copy that can and waits.
      //
      // This used to be a bare `return`, and that was a real bug rather than a
      // simplification: it was invisible only because main ran `loadScene`
      // itself during boot. A `loadScene` at *runtime* took its asset claims
      // here and then decoded nothing, anywhere, leaving every payload read
      // from that scene to fail.
      await game.requestAssetLoad(
        <int>[
          for (var i = 0; i < incoming.length; i++)
            game.assets.tryGet(incoming[i])!.address,
        ],
        // The keys travel with their addresses: main has no declaration pass
        // of its own to resolve an address against, so the request has to
        // carry the whole identity. See `Game.requestAssetLoad`.
        incoming,
        onProgress == null
            ? null
            : (address, completed, pending) => onProgress(
                SceneLoadProgress(
                  game.assets
                          .tryResolve<GameAssetInstance>(address)
                          ?.debugLabel ??
                      'asset $address',
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
    // Addresses freed on this copy, to be freed on the other one too. Captured
    // before `unload`, which is what releases the address - reading it
    // afterwards would throw.
    final freed = <int>[];
    for (var i = 0; i < declared.length; i++) {
      final key = declared[i];
      final remaining = (_assetClaims[key] ?? 0) - 1;
      if (remaining > 0) {
        _assetClaims[key] = remaining;
        continue;
      }
      _assetClaims.remove(key);
      final address = game.assets.tryGet(key)?.address;
      // Unloading runs on both copies - it is the undoing of a declaration,
      // and the two copies have to agree on what is declared for an address
      // to mean the same thing on both sides.
      game.assets.unload(key);
      if (address != null) freed.add(address);
    }
    // The other copy holds the decoded payload, so dropping the declaration
    // here is only half of it. The mirror of `requestAssetLoad`: without this,
    // a scene unloaded on the game isolate leaves its images alive on main
    // with nothing left that could name them.
    if (!game.decodesAssets) game.requestAssetUnload(freed);
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
  /// `Game._runOnIsolate`, before anything ticks.
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
  /// around a method call. `SceneStruct.onMounted` is the same shape. Something
  /// *else* wanting to hear the game come up is a different question, and
  /// [GameLifecycleListener] is its answer - note that it fires after this
  /// does, once every scene loaded here is standing.
  void onMounted() {}

  /// The game is going down. The pool is disposed immediately afterwards.
  ///
  /// Runs *after* [GameUnmountedEvent] has been dispatched and after every
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
      struct?.unmountedEvent.call(handle);
      struct?.onUnmounted(handle);
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
    onUnmounted();
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
    // One dispatch over a list resolved at boot. `const` because the event
    // carries nothing, so the hottest event in the engine allocates nothing.
    fixedTickEvent.call();
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

  /// Sorts [declaredSystems] by `GameSystem.compareTo`, breaking ties on
  /// original declaration index rather than relying on `List.sort`'s stability
  /// (which Dart does not guarantee) - a system that expresses no opinion keeps
  /// its declared position relative to every other opinion-less system. Runs
  /// once, right after `Game.describeSystems`.
  @internal
  void sortSystems() {
    final order = List<int>.generate(_systems.length, (i) => i);
    order.sort((a, b) {
      final sa = _systems[a];
      final sb = _systems[b];
      // Ask both directions: a sort only ever calls compare(a, b) with a
      // given pair in one order, so a system that expresses its opinion by
      // overriding compareTo would be silently ignored half the time if
      // only a.compareTo(b) were consulted - it might land as the "b"
      // argument instead. sb.compareTo(sa) returning -1 means "b wants to
      // be before a", i.e. a should sort after b, hence the negation.
      var cmp = sa.compareTo(sb);
      if (cmp == 0) cmp = -sb.compareTo(sa);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
    final sorted = <GameSystem>[for (final i in order) _systems[i]];
    _systems
      ..clear()
      ..addAll(sorted);
    _systemIndex.clear();
    for (var i = 0; i < _systems.length; i++) {
      _systemIndex[_systems[i].runtimeType] = i;
    }
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
  /// **Synchronous, and no wire index.** This used to be `Game.enableSystem`,
  /// returning a `Future` because it sent a control message to the isolate
  /// that held the systems. This *is* that isolate. Main asks for a pause by
  /// declaring a command that means one and calling this in the handler.
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
  /// a `Type` rather than a type argument.
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
