import 'package:meta/meta.dart';

import 'package:goo/src/coroutine/coroutine.dart';
import 'package:goo/src/animation/animatable.dart';
import 'package:goo/src/animation/struct.dart';
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

abstract class SceneStruct extends GameListenerBase
    with EventBus, SceneLifecycleListener, Coroutines {
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
    // `reverse: true` is what lets the owning struct stop being a
    // separate virtual. One collect pass offers this scene *first* and
    // its prefabs after, so at mount the scene's own onSceneMounted runs
    // before anything it composes - a listener still finds the starting
    // entities already spawned. Reading the same list backwards at
    // unmount puts the scene *last*, so it can still read the world when
    // everything below it has been told. Two orders, one list.
    unmountedEvent = descriptor.has(
      (listener, scene) => listener.onSceneUnmounted(scene),
      reverse: true,
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

  @override
  @protected
  GameState get simulationState => state;

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

  // `onMounted(Scene)`/`onUnmounted(Scene)` used to live here as plain
  // virtuals beside the dispatchers, and are now the dispatchers: a
  // `SceneStruct` mixes in `SceneLifecycleListener`, so it hears its own
  // mount through [mountedEvent] like anything else.
  //
  // I argued at length that this was impossible, and was wrong. The claim
  // was that the virtuals *bracket* the dispatch in opposite orders -
  // owner first at mount, owner last at unmount - and that "one listener
  // list cannot deliver that". There are **two** lists, one per
  // dispatcher, filled by one collect pass; the orders differ because
  // [unmountedEvent] reads its list backwards. The guarantee survives and
  // the special case does not.
  //
  // Override `onSceneMounted(Scene)` / `onSceneUnmounted(Scene)`.

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
  @mustCallSuper
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
  /// The two are the same method; a scene's own code (inside `onSceneMounted`)
  /// already has `this` and does not need to resolve a handle to reach it.
  ///
  /// [parent]'s bound is `T extends EntityStruct` rather than
  /// `T extends Child`: Dart cannot express "extends `EntityStruct` *and*
  /// mixes in Child" as a single bound, and `.archetype`/`.scene` (needed to
  /// create the row at all) only exist on `EntityStruct`. So it checks
  /// `prefab is Child` at runtime instead - the same trade `Parent.addChild`
  /// already makes for its own `child` parameter, for the same reason.
  ///
  /// Allocation-free apart from what the mount dispatch does: `Entity` is
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
    // The world-observation half, from the same call site so the narrow and
    // broad views can never disagree about when a spawn happened. The prefab's
    // own listeners run first: something watching the whole world sees an
    // entity whose struct has already initialised it.
    // `stateOrNull`, not `state`: a scene brought up through the public
    // `initializeScene` rather than `GameState.loadScene` has no simulation
    // behind it - the headless-fixture case that accessor exists for. Such a
    // scene has no observers either, because nothing declared any, so
    // skipping the dispatch is not a lost event.
    stateOrNull?.entitySpawnedEvent.call(entity);
    return entity;
  }

  /// Fires the unmount event for every entity belonging to [sceneSlot].
  ///
  /// Called by `GameState.unloadScene` **before** the pages are released, so
  /// every row is still readable while a listener is looking at it. The walk
  /// mirrors `Query.run` - archetypes, then pages, then row offsets - filtered
  /// to the pages this scene owns, which is exactly the set being freed.
  ///
  /// Transition-time work, O(entities in the scene). **Not** the only way an
  /// entity goes away - `EntityLifetime.destroy` takes one at a time - and
  /// this comment claiming otherwise is why the broad `entityDespawnedEvent`
  /// went in here and not there for a while, leaking a native handle per
  /// destroyed entity. Both paths fire both events now.
  @internal
  void unmountEntitiesOf(int sceneSlot) {
    for (var id = 0; id < ArchetypeRegistry.count; id++) {
      final storage = ArchetypeRegistry.byId(id);
      final prefab = storage.prefab;
      for (var pageIndex = 0; pageIndex < storage.pageCount; pageIndex++) {
        final page = storage.pageAt(pageIndex);
        if (page == null || page.ownerSceneSlot != sceneSlot) continue;
        // Hoisted out of the row loop: same reasoning as `addEntityIn`'s use
        // of `stateOrNull`, and resolving it once per page beats once per row.
        final observers = stateOrNull;
        for (final offset in page.rowOffsets) {
          final entity = Entity.pack(id, pageIndex, offset);
          // Broad first on the way out, mirroring the way narrow goes first
          // on the way in: an observer is told while the struct that owns the
          // entity has not yet torn anything down.
          observers?.entityDespawnedEvent.call(entity);
          prefab.unmountedEvent.call(entity);
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
    // Timelines last, because keying a clip is pure declaration and depends on
    // nothing above it. Unconditional and with no `is Animations` test: every
    // `EntityStruct` has `Animations`, and its default declares nothing.
    object.describeAnimation(_AnimationTypeDescriptor(_scene));
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

/// Runs each declared timeline's own two passes and binds it to the clock.
final class _AnimationTypeDescriptor implements AnimationTypeDescriptor {
  _AnimationTypeDescriptor(this._scene);

  /// The **scene**, not its `GameState`: a scene can legitimately be brought
  /// up without one (see `SceneStruct.initializeScene`), and a timeline that
  /// grabbed the clock here would make declaring one impossible headlessly.
  final SceneStruct _scene;

  @override
  T has<T extends TimelineStruct>(T struct) {
    struct.initializeTimeline(_scene);
    return struct;
  }
}

/// Destroying an entity, which is a property of the **entity** and not a
/// choice of scene.
///
/// This lived on `Scene` as `removeEntity` for exactly one revision, and it
/// was a lie: the implementation derives archetype, page and row from the
/// handle and never consulted the receiver at all. Passing a scene in read
/// as "remove it from *this* scene" while actually meaning "remove it from
/// wherever it is" - so a caller who fetched a scene from somewhere general
/// and passed it got the right answer for the wrong reason, and would keep
/// getting it right until the day the entity was somewhere else.
///
/// An entity belongs to exactly one scene and carries which one in its own
/// handle (see `Entity.sceneSlot`). There is nothing for a caller to name.
extension EntityLifetime on Entity {
  /// The loaded scene this entity lives in.
  ///
  /// An entity belongs to exactly one scene and carries which one: its row
  /// sits on a `MemoryPage` tagged with `ownerSceneSlot`, so this is read off
  /// the entity itself rather than fetched from anything more general. That is
  /// the difference between `entity.scene.addEntity(...)` - spawn where *this*
  /// one lives - and reaching for a scene from the state and assuming it is
  /// the right one.
  ///
  /// Throws when that scene has been **unloaded**, rather than answering with
  /// a handle into whatever loaded into its slot afterwards - the same
  /// discipline `Scene.get` applies to a stale handle.
  ///
  /// It cannot tell you the entity itself is still alive, and does not
  /// pretend to: a destroyed entity's row is freed but its *page* remains, so
  /// the slot still resolves. `Entity` carries no generation (there are no
  /// spare bits - see its own doc), so nothing can distinguish a freed row
  /// from the next spawn that reuses it. Hold entity handles for a tick, not
  /// across ticks.
  Scene get scene {
    final handle = SceneRegistry.handleAt(sceneSlot);
    if (handle == null) {
      throw StateError(
        'Entity $this is not on a page belonging to a loaded scene - its '
        'scene was unloaded. Note this check cannot speak for the entity '
        'itself: a destroyed row is freed while its page stays, and an Entity '
        'carries no generation to tell a freed row from the next spawn that '
        'reuses it. Do not hold entity handles across ticks.',
      );
    }
    return handle;
  }

  /// Destroys one entity: its subtree, then its links, then its row.
  ///
  /// # What it does, in the order it has to happen
  ///
  ///  1. **Children first, recursively.** A destroyed parent leaving live
  ///     children behind would leave them pointing at a row that is about to
  ///     be handed to somebody else. Destroying a subtree is one call.
  ///  2. **Unlink from its own parent**, so the parent's chain never names a
  ///     freed row.
  ///  3. **The unmount event**, while the row is still readable - the same
  ///     guarantee scene unload gives, so one listener serves both paths.
  ///  4. **Free the row.** `MemoryPage.free` defers while a query walk is
  ///     open, so destroying an entity from inside a system's own loop is safe
  ///     and the row stays readable for the rest of that walk.
  ///
  /// # The handle is not safe to keep
  ///
  /// `Entity` packs archetype, page and row offset and has **no generation
  /// counter** - there are no spare bits (see `Entity`'s own doc). A freed row
  /// is recycled by the next `addEntity` of the same archetype, and the new
  /// entity gets a handle numerically equal to the old one. So a handle held
  /// across the destruction of what it named does not dangle detectably: it
  /// silently starts naming something else. Hold handles for the duration of a
  /// tick, not across ticks, unless you know the entity outlives the reference.
  void destroy() {
    final storage = ArchetypeRegistry.byId(archetypeId);
    final page = storage.pageAt(pageIndex);
    if (page == null) return; // its scene was already unloaded

    final parentComponent = tryGet<Parent>();
    if (parentComponent != null) {
      // The next sibling is read *before* the child is destroyed, because
      // destroying it clears the link this walk would need next.
      var child = parentComponent.firstChild.readPending(this);
      while (child != null) {
        final after = child.get<Child>().nextSibling.readPending(child);
        child.destroy();
        child = after;
      }
    }

    final childComponent = tryGet<Child>();
    final parent = childComponent?.parent.readPending(this);
    if (parent != null) parent.get<Parent>().removeChild(parent, this);

    // Broad first, then narrow - the same order `unmountEntitiesOf` uses, so
    // an entity that goes away one at a time is indistinguishable from one
    // that goes away because its scene did.
    //
    // **This was missing, and it leaked.** A system observing the world
    // through `EntitySpawnListener` heard every spawn and only *some* of the
    // despawns: scene unload told it, `destroy()` did not. Anything that
    // allocates a resource per entity - a Box2D body, a native handle, a slot
    // in a side table - therefore leaked one per destroyed entity, silently,
    // with no Dart-visible symptom. It surfaced as a physics demo whose
    // solver cost climbed without bound while its entity count held steady:
    // Box2D reported 57 882 awake bodies for a scene of 4000.
    //
    // Resolved through the registry rather than the `scene` getter, which
    // *throws* for an unloaded scene - reachable here, since unloading frees
    // pages while a destroy may still be in flight, and a teardown is no
    // place to start throwing. `stateOrNull` for the same reason
    // `addEntityIn` uses it: a scene brought up through the public
    // `initializeScene` has no bound state, and has no observers to miss.
    final handle = SceneRegistry.handleAt(sceneSlot);
    final owner = handle == null ? null : SceneRegistry.tryResolve(handle);
    owner?.stateOrNull?.entityDespawnedEvent.call(this);
    storage.prefab.unmountedEvent.call(this);
    page.free(rowOffset);
  }
}
