import 'package:meta/meta.dart';

import 'package:goo/src/archetype.dart';
import 'package:goo/src/asset.dart';
import 'package:goo/src/camera_view.dart';
import 'package:goo/src/data/hierarchy.dart';
import 'package:goo/src/data_layout.dart';
import 'package:goo/src/event.dart';
import 'package:goo/src/event/lifecycle.dart';
import 'package:goo/src/game.dart';
import 'package:goo/src/game_state.dart';
import 'package:goo/src/pool.dart';
import 'package:goo/src/scene_handle.dart';
import 'package:goo/src/struct.dart';

abstract class SceneStruct extends GameListenerBase with EventBus {
  /// An instance of **this** scene was loaded.
  ///
  /// Declared here rather than on `GameState`, and that placement is the whole
  /// point of scoping: the collect pass fills this from *this scene's*
  /// composition - itself and its prefabs - so a prefab of some other scene
  /// cannot be in the list and cannot be told. Declared one level up it would
  /// be a single list holding every scene and every prefab in the game, and
  /// unloading scene A would call `onSceneUnmounted(A)` on scene B, which
  /// would then have to compare handles to find out the event was not about
  /// it.
  ///
  /// The payload is still the [Scene], because one `SceneStruct` backs however
  /// many loaded instances: "which of mine" is a real question even here.
  late final EventDispatcher<SceneLifecycleListener, Scene> mountedEvent;

  /// An instance of this scene is being unloaded, while its entities are still
  /// readable. Same scope as [mountedEvent].
  late final EventDispatcher<SceneLifecycleListener, Scene> unmountedEvent;

  @override
  void describeEvents(EventDescriptor descriptor) {
    mountedEvent = descriptor.has(
      (listener, scene) => listener.onSceneMounted(scene),
    );
    unmountedEvent = descriptor.has(
      (listener, scene) => listener.onSceneUnmounted(scene),
    );
  }

  /// Every prefab [describeScene] registered, in declaration order.
  ///
  /// Typed as [EventBus] rather than `EntityStruct` because that is exactly the
  /// capability this list exists to serve: the prefabs in it are collected as
  /// listeners and get their own `describeEvents` pass. Nothing here needs them
  /// to be entity structs specifically.
  final List<EventBus> _prefabs = <EventBus>[];

  /// [_prefabs] - the live list, walked at boot by `Game._bindEvents` so each
  /// prefab gets its own `describeEvents` pass. Internal: user code holds the
  /// typed instances `describeScene` gave it, never this.
  @internal
  List<EventBus> get declaredPrefabs => _prefabs;

  /// Offers this scene and its prefabs to the collector, so an event declared
  /// above reaches every entity struct this scene can spawn.
  ///
  /// The explicit half of the composition walk - the event API does not know a
  /// scene has prefabs, so the scene says so. See `EventBus.collectListeners`.
  ///
  /// Delegates to each prefab's own `collectListeners` rather than offering it
  /// directly, so the walk stays uniform all the way down: a prefab that ever
  /// composes listeners of its own gets to say so in the same way a scene does.
  @override
  void collectListeners(ListenerCollector collector) {
    super.collectListeners(collector);
    for (var i = 0; i < _prefabs.length; i++) {
      _prefabs[i].collectListeners(collector);
    }
  }

  GameAssets? _assets;

  /// The asset table this scene's declarations register into - the `Game`'s,
  /// handed over at [initializeScene] exactly as [pool] is.
  ///
  /// A headless fixture that brings a scene up without a `Game` gets its own,
  /// which is why this is not simply `game.assets`: `initializeScene` is
  /// public precisely so a test can use it, and asset *declaration* is
  /// meaningful with no game at all.
  GameAssets get assets => _assets ??= GameAssets();

  CameraViewTable? _cameraViews;

  /// The camera-view table this scene's `Camera` components resolve through -
  /// the `Game`'s, handed over at [initializeScene] exactly as [assets] is,
  /// and for exactly the same reason: a headless fixture that brings a scene
  /// up without a `Game` still has to be able to *declare* a camera field,
  /// even though nothing will ever show it.
  CameraViewTable get cameraViews => _cameraViews ??= CameraViewTable();

  MemoryPool? _pool;

  /// The pool this scene's archetypes allocate their pages from - **the
  /// `Game`'s**, handed over at [initializeScene].
  ///
  /// It used to be constructed and owned per scene. It is not any more, and
  /// that move is what makes several scenes possible at once: a `SceneStruct`
  /// is a *declaration* that may back many loaded [Scene]s, so it cannot own
  /// the storage those instances allocate out of. One pool per `Game` also
  /// makes pool identity stop meaning scene identity, which is what
  /// [addToSceneById] used to rely on - see the check inside it.
  ///
  /// Still injectable, just one level up: `Game.pageSize`/`Game.maxPages`
  /// configure it, and a test or headless harness that brings a scene up by
  /// hand passes its own to [initializeScene] rather than paying for the
  /// 64 MiB-per-page default (a page costs 3x its size, one slot per
  /// triple-buffer state).
  MemoryPool get pool {
    final pool = _pool;
    if (pool == null) {
      throw StateError(
        '$runtimeType has no MemoryPool - it has not been initialized yet. '
        'The pool belongs to the Game and is handed over by '
        'initializeScene(); a scene that has never been through that (or '
        'through GameState.loadScene, which calls it) has a layout but no '
        'storage to allocate from.',
      );
    }
    return pool;
  }

  GameState? _state;

  /// The simulation this scene was built under, via [GameState.loadScene] or
  /// `Game.describeScenes` - set once, mirroring how
  /// `EntityStruct.bindArchetype` gets its own scene reference at registration
  /// time.
  ///
  /// **A `GameState`, not a `Game`** (RULES.md rule 9): a scene only ever
  /// exists on the copy that simulates, so the object it holds is the one that
  /// simulates too. It used to hold a `Game` and reach the state through it,
  /// which is a hop that compiles on the presentation isolate and finds
  /// nothing there. Lets a prefab's `getSystem<T>()` (`Component.getSystem`,
  /// struct.dart) reach a system without its own direct reference.
  GameState get state {
    final s = _state;
    if (s == null) {
      throw StateError(
        '$runtimeType has no GameState yet - this scene has not been through '
        'GameState.loadScene() yet.',
      );
    }
    return s;
  }

  /// The game whose declarations this scene reads - buffers, channels, camera
  /// views, assets. Derived from [state]; there is no separate binding.
  Game get game => state.game;

  /// [game], or `null` when this scene was brought up without one - see
  /// [initializeScene], which is public precisely so a test or headless
  /// harness can. Internal: user code either has a `Game` or is a test that
  /// knows it does not.
  @internal
  Game? get tryGame => _state?.game;

  /// Called once during the boot pass, immediately after
  /// [GameState.loadScene] returns. Not part of the user-facing API.
  @internal
  void bindState(GameState state) => _state = state;

  /// [state], or null - for `Component.getSystem`, which wants to report
  /// "no simulation yet" itself rather than catch a `StateError`.
  @internal
  GameState? get stateOrNull => _state;

  /// This scene instance has been loaded and is ready to be populated.
  ///
  /// **Takes the [Scene] that is mounting**, and it has to: one `SceneStruct`
  /// is a declaration backing however many loaded instances, so "spawn into
  /// my scene" is not a question this object can answer on its own. The
  /// handle is the answer, and it is also what [Scene.addEntity] is called on:
  ///
  /// ```dart
  /// @override
  /// void onMounted(Scene scene) {
  ///   final player = scene.addEntity(playerPrefab);
  ///   scene.addEntity(wingmanPrefab, parent: player);
  /// }
  /// ```
  ///
  /// # Why this is a virtual and not the [mountedEvent] dispatcher
  ///
  /// Asked directly ("why have `EventDispatcher` and not use them?"), and the
  /// answer is that these two are not the same kind of thing. This hook and
  /// [onUnmounted] **bracket** the dispatch, in opposite orders:
  ///
  /// ```text
  /// mount:    onMounted(scene)          -> mountedEvent.call(scene)
  /// unmount:  unmountedEvent.call(scene) -> onUnmounted(scene)
  /// ```
  ///
  /// That ordering is a guarantee listeners rely on, and
  /// `SceneLifecycleListener.onSceneMounted` states it outright: by the time a
  /// listener hears about a mount, the scene's starting entities already
  /// exist; by the time it hears about an unmount, nothing has been torn down
  /// yet, so it can still read the world.
  ///
  /// One listener list cannot deliver that. It would have to place the owning
  /// struct **first** at mount and **last** at unmount, and a list has one
  /// order. Splitting the dispatch in two to recover it would be this virtual
  /// again, with a dispatcher wrapped around it.
  ///
  /// So the split is phase versus audience, not hook versus event: this is the
  /// scene's own *bring-up phase*, and [mountedEvent] is who gets told once it
  /// has happened. A scene that also wants to hear about **other** scenes
  /// mixes in `SceneLifecycleListener` as well, and then hears its own mount
  /// through both - which is correct, since it asked for every scene's.
  ///
  /// It also replaced `with LifecycleListener`, whose `onMounted()` took no
  /// argument and so could not say *which* instance came up.
  // TODO: change to scene lifecycle listener, and remove the virtual. The event is already there.
  void onMounted(Scene scene) {}

  /// This scene instance is being unloaded. Its entities and pages are freed
  /// immediately afterwards, so anything that has to be read out of the world
  /// has to be read here.
  void onUnmounted(Scene scene) {}

  bool _initialized = false;

  /// Every asset key declared while this scene was initialized, in
  /// declaration order: this scene's own [describeAssets] first, then each
  /// registered prefab's, in `describeScene` order. Deduplicated - two
  /// prefabs sharing a texture contribute one entry, because they share one
  /// instance and one address.
  ///
  /// This list *is* the scene's asset footprint, and what
  /// `GameState.loadScene` diffs one scene against the next to decide what to
  /// keep, load and unload.
  final List<GameAsset> _declaredAssets = <GameAsset>[];

  /// [_declaredAssets] - the live list, walked by index at scene-transition
  /// time. Internal because it is transition plumbing; user code holds the
  /// typed instance handles `describeAssets` gave it, never this.
  @internal
  List<GameAsset> get declaredAssets => _declaredAssets;

  /// Declares every `EntityStruct` prefab this scene can spawn. Runs
  /// exactly once, before the first entity exists - see [initializeScene].
  void describeScene(SceneDescriptor descriptor) {}

  /// Declares the assets this scene needs that belong to no prefab -
  /// background music, UI chrome, a loading backdrop. The same hook
  /// `Component.describeAssets` gives a prefab, for the same reason and with
  /// the same handle-in-a-field discipline (RULES.md rule 6).
  ///
  /// A scene's full asset footprint is the **union** of this and every prefab
  /// it registers, which is what `GameState.loadScene` loads and later
  /// diffs against the next scene's.
  ///
  /// Runs on both isolate copies (it assigns addresses); only the decode is
  /// main-isolate-only. See [GameAssets].
  void describeAssets(AssetDescriptor descriptor) {}

  /// Drives the one-time declaration passes: this scene's own
  /// [describeAssets], then [describeScene], where each `descriptor.has(...)`
  /// registers an archetype, walks the struct's `describeType`/
  /// `describeAssets`/`describeStruct` chain to build its layout, and freezes
  /// it.
  ///
  /// The scene's own assets come first so the whole ordering is one readable
  /// sequence - and, like every other declaration order in this engine, it
  /// only has to be *deterministic*, because it is what both isolate copies
  /// independently reproduce to arrive at the same addresses.
  ///
  /// Separate from [describeScene] because that one is the user's override
  /// point; this is the framework side of it. `GameState.loadScene` calls
  /// this, but it is public so a test or headless harness can bring a
  /// scene up without a full `Game`.
  void initializeScene(
    MemoryPool pool, {
    GameAssets? assets,
    CameraViewTable? cameraViews,
  }) {
    if (_initialized) {
      throw StateError(
        '$runtimeType is already initialized. Archetype registration is a '
        'one-time pass - re-running it would register a second archetype for '
        'every prefab.',
      );
    }
    _initialized = true;
    _pool = pool;
    if (assets != null) _assets = assets;
    if (cameraViews != null) _cameraViews = cameraViews;
    final descriptor = _AssetDescriptor(this);
    describeAssets(descriptor);
    describeScene(_SceneDescriptor(this, descriptor));
    // A scene brought up by hand has no boot pass to bind its events, so it
    // does it now. One brought up by a `Game` deliberately waits: a prefab's
    // `collectListeners` may reach for a system (`getSystem<T>()`), and
    // `describeScenes` runs *before* `describeSystems` - it has to, because
    // `describeQuery` resolves against registered archetypes. `Game`
    // calls [bindEvents] once every declaration exists.
    if (_state == null) bindEvents();
  }

  bool _eventsBound = false;

  /// Runs the declare-then-collect event passes over this scene and every
  /// prefab it registered.
  ///
  /// Idempotent, because three paths reach it - [initializeScene] for a
  /// headless scene, `Game._bindEvents` for a declared one, and
  /// `GameState.loadScene` for one loaded at runtime - and a `late final`
  /// dispatcher assigned twice throws. The guard is what lets each of those
  /// call it without first working out whether one of the others already did.
  @internal
  void bindEvents() {
    if (_eventsBound) return;
    _eventsBound = true;
    EventBinder.bind(this);
    for (var i = 0; i < _prefabs.length; i++) {
      EventBinder.bind(_prefabs[i]);
    }
  }

  bool get isInitialized => _initialized;

  /// Creates an entity from [prefab] - one row in the prefab's archetype,
  /// stamped with its declared field defaults - and optionally attaches it
  /// under [parent] via `Parent.addChild`.
  ///
  /// Usually reached through the handle rather than here: `Scene.addEntity`
  /// is the spelling a caller holding a [Scene] uses, and it lands on this.
  /// The two are the same method; a scene's own code (inside `onMounted`, say)
  /// already has `this` and does not need to resolve a handle to reach it.
  ///
  /// [parent]'s bound is `T extends EntityStruct` rather than
  /// `T extends Child`: Dart cannot express "extends `EntityStruct` *and*
  /// mixes in Child" as a single bound, and `.archetype`/`.scene` (needed to
  /// create the row at all) only exist on `EntityStruct`. So it checks
  /// `prefab is Child` at runtime instead - the same trade `Parent.addChild`
  /// already makes for its own `child` parameter, for the same reason.
  ///
  /// Allocation-free apart from what `onMounted` itself does: `Entity` is
  /// an extension type over `int`, and the row's defaults are memcpy'd
  /// from a prototype built at registration time.
  @internal
  Entity addEntityIn<T extends EntityStruct>(
    int sceneSlot,
    T prefab, {
    Entity? parent,
  }) {
    if (!identical(prefab.scene, this)) {
      throw StateError(
        '$T was registered with a different SceneStruct. Pass the instance '
        'returned by `descriptor.has(...)` in this scene\'s describeScene.',
      );
    }
    Parent? parentComponent;
    if (parent != null) {
      if (prefab is! Child) {
        throw ArgumentError.value(
          prefab,
          'prefab',
          '$T does not mix in Child - cannot be attached to a parent',
        );
      }
      parentComponent = parent.tryGet<Parent>();
      if (parentComponent == null) {
        throw ArgumentError.value(
          parent,
          'parent',
          'does not mix in Parent - cannot accept children',
        );
      }
    }
    final entity = prefab.archetype.allocateRow(sceneSlot);
    // Before the mount event, not after: `Child`'s linked-list fields are part
    // of what addChild writes, so a listener that saw the entity first would
    // be looking at a half-built one.
    if (parentComponent != null) parentComponent.addChild(parent!, entity);
    // The one entity-mount notification there is. A struct that wants to
    // initialise its own rows mixes in `EntityLifecycleListener` and is
    // collected into this dispatcher by the default `collectListeners`, so
    // "my own entity" and "somebody else's entity of this struct" arrive
    // through the same door. There is no separate virtual hook.
    //
    // Unguarded, because there is nothing to guard against: the `Entity`
    // travels as an argument, so a dispatch with no listeners is an empty loop
    // that allocates nothing.
    prefab.mountedEvent.call(entity);
    return entity;
  }

  /// Fires the unmount event for every entity belonging to [sceneSlot].
  ///
  /// Called by `GameState.unloadScene` **before** the pages are released, so
  /// every row is still readable while a listener is looking at it. The walk
  /// mirrors `Query.run` - archetypes, then pages, then row offsets - filtered
  /// to the pages this scene owns, which is exactly the set being freed.
  ///
  /// Transition-time work, O(entities in the scene), and the only place an
  /// entity can currently go away: rows are not recycled and there is no
  /// per-entity destroy.
  @internal
  void unmountEntitiesOf(int sceneSlot) {
    for (var id = 0; id < ArchetypeRegistry.count; id++) {
      final storage = ArchetypeRegistry.byId(id);
      final prefab = storage.prefab;
      for (var pageIndex = 0; pageIndex < storage.pageCount; pageIndex++) {
        final page = storage.pageAt(pageIndex);
        if (page == null || page.ownerSceneSlot != sceneSlot) continue;
        for (final offset in page.rowOffsets) {
          prefab.unmountedEvent.call(Entity.pack(id, pageIndex, offset));
        }
      }
    }
  }

  // There is deliberately no spawn-by-`archetypeId` variant. One existed for
  // the built-in `SpawnEntityCommand` and both are gone: an archetype id is
  // `_storages.length` at registration time, so it is stable only within one
  // process run and only while declaration order is unchanged. Persisting one
  // to a level file or putting one on a wire looks like it works and silently
  // means a different prefab the moment someone reorders a `descriptor.has`
  // line. A command handler runs on the game isolate, where the prefab object
  // is in scope, so [addEntityIn] is the only spelling needed.
}

abstract class SceneDescriptor {
  T has<T extends EntityStruct>(T object);
}

/// The one and only archetype registration point.
///
/// The order of the two describe passes matters and mirrors the
/// `@mustCallSuper` chains in `EntityStruct`/`Transform2D`/`Child`: each
/// mixin calls `super.describeStruct(data)` *first*, so the mixin
/// application order (Dart's linearization: `with Transform2D, Child` runs
/// `Transform2D`'s fields before `Child`'s) is exactly the field order in
/// the row. Changing a struct's mixin list changes its layout - which is
/// fine, because the layout is rebuilt from scratch on every run and never
/// persisted.
final class _SceneDescriptor implements SceneDescriptor {
  _SceneDescriptor(this._scene, this._assets);

  final SceneStruct _scene;

  /// The scene's one `AssetDescriptor`, shared with the scene's own
  /// [SceneStruct.describeAssets] pass - so a texture the scene declares and a
  /// texture a prefab declares are the same declaration, one instance and one
  /// address, exactly as two prefabs sharing one would be.
  final _AssetDescriptor _assets;

  @override
  T has<T extends EntityStruct>(T object) {
    final storage = ArchetypeRegistry.register(_scene.pool, object);
    object.bindArchetype(_scene, storage);
    object.describeType(ArchetypeComponentDescriptor(storage));
    // Before describeStruct, not after: `has` returns an already-addressed
    // instance, so describeStruct can hand one straight to `data.hasObject`
    // as this archetype's default row value.
    object.describeAssets(_assets);
    object.describeStruct(ArchetypeDataDescriptor(storage));
    // Recorded for the event passes: `Game._bindEvents` gives each prefab its
    // own `describeEvents`, and `SceneStruct.collectListeners` walks this list
    // so an event declared above reaches every struct the scene can spawn.
    _scene._prefabs.add(object);
    // There is deliberately no describeState pass here. A prefab used to be
    // able to declare a state channel, threaded through the scene's `game`
    // back-reference into the boot pass's shared descriptor - and it stopped
    // working the moment scene loading moved out of boot and into
    // `GameState.loadScene`, because a channel's index has to be fixed at
    // boot and announced once. Publish scene-derived values from a
    // `GameSystem` instead; see `Game.describeState`.
    storage.seal();
    return object;
  }
}

/// The one and only asset declaration point, and the collector of one
/// scene's asset footprint.
///
/// One instance per [SceneStruct.initializeScene] call, shared by the scene's
/// own `describeAssets` and by every prefab `_SceneDescriptor.has` registers,
/// so the whole scene contributes to a single deduplicated, ordered list.
final class _AssetDescriptor implements AssetDescriptor {
  _AssetDescriptor(this._scene);

  final SceneStruct _scene;

  @override
  T has<T extends GameAssetInstance>(GameAsset<T> key) {
    // Process-global, not scene-local: two scenes that both use the UI atlas
    // share one instance and one address, which is what makes a transition
    // between them free of a decode round trip.
    final instance = _scene.assets.declare(key);
    final declared = _scene._declaredAssets;
    // Linear scan rather than a Set: this runs once per declaration at scene
    // bring-up over a list of at most a few dozen, and keeping only the list
    // means the order is exactly declaration order with no second structure
    // to keep in sync.
    for (var i = 0; i < declared.length; i++) {
      if (identical(declared[i], key)) return instance;
    }
    declared.add(key);
    return instance;
  }
}
