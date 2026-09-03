import 'package:meta/meta.dart';

import 'package:good/src/coroutine/coroutine.dart';
import 'package:good/src/animation/animatable.dart';
import 'package:good/src/animation/struct.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/asset.dart';
import 'package:good/src/camera_view.dart';
import 'package:good/src/data/hierarchy.dart';
import 'package:good/src/data_layout.dart';
import 'package:good/src/event.dart';
import 'package:good/src/event/lifecycle.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/pool.dart';
import 'package:good/src/scannable.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';

abstract class SceneStruct extends GameListenerBase
    with EventBus, SceneLifecycleListener, Coroutines
    implements Scannable {
  /// An instance of **this** scene was loaded.
  ///
  /// Declared here and not on `GameState`, and that placement is the whole
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
  final mountedEvent = Event.of<SceneLifecycleListener, Scene>(
    (listener, scene) => listener.onSceneMounted(scene),
  );

  /// An instance of this scene is being unloaded, while its entities are still
  /// readable. Same scope as [mountedEvent].
  /// `reverse: true` is what lets the owning struct stop being a separate
  /// virtual. One collect pass offers this scene *first* and its prefabs
  /// after, so at mount the scene's own `onSceneMounted` runs before anything
  /// it composes - a listener still finds the starting entities already
  /// spawned. Reading the same list backwards at unmount puts the scene
  /// *last*, so it can still read the world when everything below it has been
  /// told. Two orders, one list.
  final unmountedEvent = Event.of<SceneLifecycleListener, Scene>(
    (listener, scene) => listener.onSceneUnmounted(scene),
    reverse: true,
  );

  /// Every prefab [describeScene] registered, in declaration order.
  ///
  /// Typed as [EventBus], not `EntityStruct`, because that is exactly the
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
  /// Delegates to each prefab's own `collectListeners` instead of offering it
  /// directly, so the walk stays uniform all the way down: a prefab that ever
  /// composes listeners of its own gets to say so in the same way a scene does.
  @override
  void collectListeners(ListenerCollector collector) {
    super.collectListeners(collector);
    for (var i = 0; i < _prefabs.length; i++) {
      _prefabs[i].collectListeners(collector);
    }
  }

  Assets? _assets;

  /// The asset table this scene's declarations register into - the `Game`'s,
  /// handed over at [initializeScene] exactly as [pool] is.
  ///
  /// A headless fixture that brings a scene up without a `Game` gets its own,
  /// so this is not simply `game.assets`: `initializeScene` is public precisely
  /// so a test can use it, and asset *declaration* is meaningful with no game
  /// at all.
  Assets get assets => _assets ??= Assets();

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
  /// Owned by the `Game` and not by the scene, which is what makes several
  /// scenes possible at once: a `SceneStruct` is a *declaration* that may back
  /// many loaded [Scene]s, so it cannot own the storage those instances
  /// allocate out of. Pool identity therefore says nothing about scene
  /// identity - see the check inside [addToSceneById].
  ///
  /// Still injectable, just one level up: `Game.pageSize`/`Game.maxPages`
  /// configure it, and a test or headless harness that brings a scene up by
  /// hand passes its own to [initializeScene] instead of paying for the
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
  /// **A `GameState`, not a `Game`** (the isolate-affinity rule): a scene only
  /// ever exists on the copy that simulates, so the object it holds is the one
  /// that simulates too. Holding a `Game` and hopping to the state through it
  /// compiles on the presentation isolate and finds nothing there. This is what
  /// lets a prefab's `getSystem<T>()` (`Component.getSystem`, struct.dart)
  /// reach a system without its own direct reference.
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
  /// "no simulation yet" itself instead of catching a `StateError`.
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

  /// Every asset declared while this scene was initialized, in declaration
  /// order: this scene's own [describeAssets] first, then each registered
  /// prefab's, in `describeScene` order. Deduplicated - two prefabs sharing a
  /// texture contribute one entry, because they share one handle and one
  /// address.
  ///
  /// Handles, not keys, because everything downstream wants one: a
  /// scene transition needs each asset's address to send across the isolate
  /// boundary and its loaded state to decide whether to bother, and both hang
  /// off the handle. The key is still reachable as `asset.key` for the one
  /// place that has to send it.
  ///
  /// This list *is* the scene's asset footprint, and what
  /// `GameState.loadScene` diffs one scene against the next to decide what to
  /// keep, load and unload.
  final List<Asset<Object?>> _declaredAssets = <Asset<Object?>>[];

  /// [_declaredAssets] - the live list, walked by index at scene-transition
  /// time. Internal because it is transition plumbing; user code holds the
  /// typed handles `describeAssets` gave it, never this.
  @internal
  List<Asset<Object?>> get declaredAssets => _declaredAssets;

  /// Declares every `EntityStruct` prefab this scene can spawn. Runs
  /// exactly once, before the first entity exists - see [initializeScene].
  @mustCallSuper
  void describeScene(SceneDescriptor descriptor) {}

  /// Declares the assets this scene needs that belong to no prefab -
  /// background music, UI chrome, a loading backdrop. The same hook
  /// `Component.describeAssets` gives a prefab, for the same reason and with
  /// the same handle-in-a-field discipline (the typed-handle rule).
  ///
  /// A scene's full asset footprint is the **union** of this and every prefab
  /// it registers, which is what `GameState.loadScene` loads and later
  /// diffs against the next scene's.
  ///
  /// Runs on both isolate copies (it assigns addresses); only the decode is
  /// main-isolate-only. See [Assets].
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
    Assets? assets,
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
    // One `_AssetDescriptor` for the whole bring-up: this scene's own
    // `describeAssets`, every asset a prefab holds in a field, and every
    // prefab `describeScene` registers all reach it. So a texture the scene
    // names and a texture a prefab names are one declaration, one address and
    // one decode, which is what makes the footprint below a set.
    final descriptor = _AssetDescriptor(this);
    // The scene's own asset fields, read off the constructed scene. A
    // `SceneStruct` is built by the caller, so its initialisers ran long
    // before this - which is exactly why the handle they built carries a key
    // and nothing else until here.
    descriptor.declare(collectDeclarations(this));
    describeAssets(descriptor);
    describeScene(_SceneDescriptor(this, descriptor));
    // A scene brought up by hand has no boot pass to bind its events, so it
    // does it now. One brought up by a `Game` waits: a prefab's
    // `collectListeners` may reach for a system (`getSystem<T>()`), and
    // `Game._bootGame` runs `describeScenes` before `describeSystems`, so no
    // system exists at this point. `Game` calls [bindEvents] once every
    // declaration exists.
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
  /// Usually reached through the handle: `Scene.addEntity` is the spelling a
  /// caller holding a [Scene] uses, and it lands on this.
  /// The two are the same method; a scene's own code (inside `onSceneMounted`)
  /// already has `this` and does not need to resolve a handle to reach it.
  ///
  /// [parent]'s bound is `T extends EntityStruct` and not `T extends Child`:
  /// Dart cannot express "extends `EntityStruct` *and*
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
    // Three declaration mistakes, all settled the first time the line runs
    // and none of them able to start being true in a shipped build. They
    // were checked outright, which put a `Parent?` registry lookup on
    // every parented spawn - five thousand of them in a five-thousand-entity
    // burst - to re-answer a question about the shape of the code.
    //
    // Nothing downstream needs the lookup either: `parent<Parent>()` below
    // does its own, and its `is` test is the one `entity<T>()` needs for
    // the cast anyway, so a bad parent still fails loudly in release. It
    // just fails there rather than here.
    assert(_declaredHere<T>(prefab));
    assert(parent == null || _attachable<T>(prefab, parent, sceneSlot));
    final entity = prefab.archetype.allocateRow(sceneSlot);
    // Before the mount event, not after: `Child`'s linked-list fields are part
    // of what addChild writes, so a listener that saw the entity first would
    // be looking at a half-built one.
    if (parent != null) parent<Parent>().addChild(entity);
    // The children this prefab declared in its own fields, in declaration
    // order, each one a full spawn of its own - so a child that declares
    // children gets them, to whatever depth the declarations go. The depth is
    // finite because the declarations are: a ring of them is a constructor
    // that calls itself, so a prefab that closed one never existed to be
    // spawned. `good_tool --declarations` names the ring.
    //
    // Also before the mount event, and for the same reason as addChild: what
    // a struct declares is part of what its entity *is*, so a listener never
    // sees a turret without its barrel. The cost is that a child's own mount
    // event fires before its parent's - the subtree is announced from the
    // bottom up.
    //
    // Here rather than in an `onEntityMounted` on `Parent`, which was the
    // other candidate and would have kept the hierarchy out of this method.
    // Two things ruled it out, both measured (`hierarchy_test.dart`'s
    // 'the lifecycle-listener route' cases): a struct's own override decides
    // whether and *when* `super.onEntityMounted` runs, so half the point -
    // children exist before anything hears about the parent - would be the
    // user's to keep; and `unmountEntitiesOf` fires the same dispatcher for
    // every row in an unloading scene, so the teardown half of that design
    // destroys rows the unload is already freeing.
    // Cast rather than promote: `is` does not promote a value whose static
    // type is unrelated to the tested mixin - `EntityStruct` is not a
    // supertype of `Parent` - so the analyzer leaves it alone and the cast is
    // the only spelling. Verified; the same shape appears below in
    // `_SceneDescriptor.declareChild`.
    if (prefab is Parent) {
      final declared = (prefab as Parent).declaredChildren;
      for (var i = 0; i < declared.length; i++) {
        final childPrefab = declared[i];
        (childPrefab as Child).declaredIn![entity] = addEntityIn(
          sceneSlot,
          childPrefab,
          parent: entity,
        );
      }
    }
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

  /// Rejects a prefab some other `SceneStruct` registered.
  ///
  /// Its archetype belongs to that scene's declaration, so a row allocated
  /// here would carry this scene's slot on another scene's storage and be
  /// freed by whichever of the two unloads first.
  bool _declaredHere<T extends EntityStruct>(T prefab) {
    if (identical(prefab.scene, this)) return true;
    throw StateError(
      '$T was registered with a different SceneStruct. Pass the instance '
      'returned by `descriptor.has(...)` in this scene\'s describeScene.',
    );
  }

  /// Rejects a prefab that cannot hang off a parent, a parent that cannot
  /// hold children, or a parent living in some other loaded scene.
  ///
  /// The scene check is not the one [_declaredHere] makes. That one compares
  /// `SceneStruct`s - declarations - and passes happily when two *instances*
  /// of one declaration are loaded at once, which is precisely when a caller
  /// holding a handle from the wrong one gets here. See
  /// `ParentAccessor._sameScene` for what the resulting edge costs.
  bool _attachable<T extends EntityStruct>(
    T prefab,
    Entity parent,
    int sceneSlot,
  ) {
    if (prefab is! Child) {
      throw ArgumentError.value(
        prefab,
        'prefab',
        '$T does not mix in Child - cannot be attached to a parent',
      );
    }
    if (!parent.has<Parent>()) {
      throw ArgumentError.value(
        parent,
        'parent',
        'does not mix in Parent - cannot accept children',
      );
    }
    final parentSlot = parent.sceneSlot;
    if (parentSlot != sceneSlot) {
      throw ArgumentError.value(
        parent,
        'parent',
        'is in scene slot $parentSlot and this spawn is into scene slot '
            '$sceneSlot. A hierarchy edge may not cross scenes: whichever of '
            'the two unloads first leaves the other naming a freed row. Spawn '
            "into the parent's own scene - `parent.scene.addEntity(...)`.",
      );
    }
    return true;
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
  ///
  /// Then, once every listener has been told,
  /// [_detachLinksLeavingScene] cuts the hierarchy edges that point out of
  /// this scene, so nothing that is staying is left naming a page this unload
  /// is about to free.
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
    _detachLinksLeavingScene(sceneSlot);
    _releaseHeapSlotsOf(sceneSlot);
  }

  /// Frees the `HeapObjectRegistry` slots every row of [sceneSlot] owns.
  ///
  /// The unload counterpart of the same call `destroy()` makes: an unloading
  /// scene frees its pages wholesale and not row by row, so without this
  /// pass every heap-object field in it leaks its slot (#49). Both entrances
  /// have to do it, and this is the one that covers stopping the game, since
  /// `GameState` tears every loaded scene down through here.
  ///
  /// **Last, after the unmount events and after the detach pass.** A listener
  /// reads the row it is being told about, and `_detachLinksLeavingScene`
  /// reads links out of it; a slot freed before either would resolve to
  /// nothing, or to whatever the next `register` put there. Freeing the row's
  /// bytes is `releaseScenePages`' job and happens later still.
  ///
  /// Skips an archetype with no heap-object field, which is every archetype
  /// the engine ships - so the common unload walks the archetype list and
  /// stops, without touching a page.
  void _releaseHeapSlotsOf(int sceneSlot) {
    for (var id = 0; id < ArchetypeRegistry.count; id++) {
      final storage = ArchetypeRegistry.byId(id);
      if (!storage.hasHeapFields) continue;
      for (var pageIndex = 0; pageIndex < storage.pageCount; pageIndex++) {
        final page = storage.pageAt(pageIndex);
        if (page == null || page.ownerSceneSlot != sceneSlot) continue;
        for (final offset in page.rowOffsets) {
          storage.releaseHeapSlots(page, offset);
        }
      }
    }
  }

  /// Unlinks every hierarchy edge between [sceneSlot] and a scene that is
  /// staying, while both sides are still readable.
  ///
  /// `ParentAccessor` asserts that an edge stays within one scene, and an
  /// assert is not there in release, so this is what stands between a shipped
  /// build and the two ways such an edge fails. The two halves are not the
  /// same check written twice: the assert states the rule at the moment the
  /// edge is made, this repairs the breach at the moment it comes due.
  ///
  /// **The surviving side loses the link and nothing else.** A parent that
  /// stays simply no longer has that child - the ordinary unlink, the one
  /// `detach()` performs - and a child that stays is left an unparented root,
  /// alive and holding its own subtree. Destroying the surviving side instead
  /// would turn "unload the pause menu" into "and delete part of the level",
  /// and it would do it through `destroy()`, which fires unmount events for
  /// entities of a scene that is not unloading, from inside the unload of one
  /// that is.
  ///
  /// **After the unmount events, not interleaved with them.** A listener
  /// therefore reads the hierarchy as it stood, and no entity is announced
  /// with its links already cut because it happened to sit in an archetype
  /// this walk reached first. The cost is a second walk of the scene's rows,
  /// which is unload-time work either way.
  ///
  /// Both directions, because either side can be the one going: a doomed row
  /// is checked for a parent that is staying, and for children that are.
  void _detachLinksLeavingScene(int sceneSlot) {
    for (var id = 0; id < ArchetypeRegistry.count; id++) {
      final storage = ArchetypeRegistry.byId(id);
      final prefab = storage.prefab;
      // Hoisted out of the row loop: one prefab describes every row of an
      // archetype, so whether these components exist is settled here and not
      // re-asked per row. Cast and do not promote, for the reason
      // `addEntityIn` gives.
      final asChild = prefab is Child ? prefab as Child : null;
      final asParent = prefab is Parent ? prefab as Parent : null;
      if (asChild == null && asParent == null) continue;
      for (var pageIndex = 0; pageIndex < storage.pageCount; pageIndex++) {
        final page = storage.pageAt(pageIndex);
        if (page == null || page.ownerSceneSlot != sceneSlot) continue;
        for (final offset in page.rowOffsets) {
          final entity = Entity.pack(id, pageIndex, offset);
          if (asChild != null) {
            final parent = asChild.childParent.readPending(entity);
            if (parent != null && parent.sceneSlot != sceneSlot) {
              parent<Parent>().unlinkChildAcrossScenes(entity);
            }
          }
          if (asParent != null) {
            var child = asParent.parentFirstChild.readPending(entity);
            while (child != null) {
              // Read before the splice, which clears it - the same order
              // `EntityLifetime.destroy` walks a subtree in.
              final after = child<Child>()
                  .component
                  .childNextSibling
                  .readPending(child);
              if (child.sceneSlot != sceneSlot) {
                entity<Parent>().unlinkChildAcrossScenes(child);
              }
              child = after;
            }
          }
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
  /// Declares one prefab and returns it, for the field that keeps it.
  ///
  /// Takes a `T Function()` rather than an instance, and what that is still
  /// for is narrower than it was. It used to be the whole mechanism: a
  /// struct's field initialisers declared into descriptors that had to be
  /// open around the constructor, so the framework had to be the one calling
  /// it. Nothing is open around it now - a declaration reaches nothing where
  /// it is written - and the registration reads what the object holds
  /// afterwards, so *when* it was built no longer changes what it declares.
  ///
  /// What the closure still buys is that the registration owns the object's
  /// lifetime: the archetype is reserved, the object built, and its
  /// declarations realized into that archetype, in one call with nothing in
  /// between. A prefab whose constructor takes arguments passes a closure -
  /// `descriptor.has(() => Bullet(speed: 5))`.
  T has<T extends EntityStruct>(T Function() create);
}

/// The one and only archetype registration point.
///
/// A row's field order is the order the columns were declared in, and there
/// are now two stretches of that order:
///
///  1. **The fields.** Dart runs a class's own field initialisers before its
///     superclass constructor, and a mixin application *is* a superclass - so
///     `class Player extends EntityStruct with Transform2D, Child` lays out
///     `Player`'s own `Field.*` columns first, then `Child`'s, then
///     `Transform2D`'s. Last mixin in the `with` clause, first in the row.
///  2. **The describe passes.** Whatever is still declared in a
///     `describeStruct` body follows, in the opposite mixin order, because
///     each override calls `super.describeStruct(data)` *first* - so
///     `Transform2D`'s body runs before `Child`'s.
///
/// Two orders, and neither is arbitrary: both are what Dart already does with
/// the same `with` clause. What matters is that they are *deterministic*, since
/// the layout is rebuilt from scratch on every run and never persisted.
/// Changing a struct's mixin list changes its layout, and always did.
///
/// The first stretch is now the order the collect pass hands the fields over
/// in, rather than the order they happened to run in: a column reserves
/// nothing where it is written, so what fixes the row is
/// `ArchetypeDataDescriptor.realize`. It is the same order either way, and
/// that is a requirement on the collector rather than a consequence of when
/// an initialiser ran.
final class _SceneDescriptor implements SceneDescriptor {
  _SceneDescriptor(this._scene, this._assets);

  final SceneStruct _scene;

  /// The scene's one `AssetDescriptor`, shared with the scene's own
  /// [SceneStruct.describeAssets] pass - so a texture the scene declares and a
  /// texture a prefab declares are the same declaration, one instance and one
  /// address, exactly as two prefabs sharing one would be.
  final _AssetDescriptor _assets;

  @override
  T has<T extends EntityStruct>(T Function() create) {
    final object = create();
    _register(object);
    return object;
  }

  /// Registers [object] - its archetype, its columns, its describe passes -
  /// and every struct it declared in a field, in the order it declared them.
  ///
  /// # Where the declared children come from
  ///
  /// A struct that owns another writes it in an ordinary field:
  ///
  /// ```dart
  /// class Turret extends EntityStruct with Transform2D, Parent {
  ///   final barrel = Barrel();
  /// }
  /// ```
  ///
  /// so by the time this runs the `Barrel` object already exists - Dart built
  /// it while it was building the `Turret`. Nothing was open around either
  /// constructor. What is left is the registration, and this is where it
  /// happens: the walk below reserves the handle column where the field sits
  /// in the row, registers the child in full, and records it on the declarer.
  ///
  /// # Why the walk is one loop and not three
  ///
  /// A row's field order is the order the fields were declared in, and a
  /// declared child contributes a column of its own - the `Entity?` handle
  /// saying which child one parent entity has. So that column has to land
  /// between the columns declared either side of it, which means the pass
  /// reserving it is the pass walking the list. Handing the whole list to
  /// `ArchetypeDataDescriptor.declare` first and registering children after
  /// would put every child handle at the end of the row instead.
  void _register(EntityStruct object) {
    // Reserved before anything is read off the object, because a declared
    // child records the archetype its handle column belongs to and that is
    // this one - see `Child.declaredInArchetype`. It carries no prefab until
    // the line below; nothing reads one in between.
    final storage = ArchetypeRegistry.reserve(_scene);
    storage.bindPrefab(object);
    object.bindArchetype(_scene, storage);
    final data = ArchetypeDataDescriptor(storage);
    final children = <EntityStruct>[];
    // What the constructor produced, in the order the class declares it. Read
    // off the constructed object rather than collected while it was being
    // built: `Field.float64`, `Asset.of` and a child's own constructor all
    // reach nothing, so the only record of what a class declared is the
    // fields it holds.
    for (final declaration in collectDeclarations(object)) {
      if (declaration is EntityStruct) {
        _declareChild(object, declaration, data, storage);
        children.add(declaration);
        continue;
      }
      // Each descriptor takes the declarations it can act on and leaves the
      // rest: a column is not an asset and an asset is not a column.
      data.declareOne(declaration);
      _assets.declareOne(declaration);
    }
    if (children.isNotEmpty) {
      if (object is! Parent) {
        throw StateError(
          '${object.runtimeType} declares ${children.length} '
          '${children.length == 1 ? 'child' : 'children'} in its own fields, '
          'but does not mix in Parent, so it has nowhere to link them. Add '
          '`with Parent` to ${object.runtimeType}.',
        );
      }
      (object as Parent).declaredChildren.addAll(children);
    }
    object.describeType(ArchetypeComponentDescriptor(storage));
    // Before describeStruct, not after: `has` returns an already-addressed
    // instance, so describeStruct can hand one straight to `data.hasObject`
    // as this archetype's default row value.
    object.describeAssets(_assets);
    object.describeStruct(data);
    // Timelines last, because keying a clip is pure declaration and depends
    // on nothing above it. Unconditional and with no `is Animations` test:
    // every `EntityStruct` has `Animations`, and its default declares
    // nothing.
    object.describeAnimation(_AnimationTypeDescriptor(_scene));
    // One reservation pass, after everything that declares and before
    // anything that reads a layout. Row order is unchanged - the field
    // initialisers' columns, then the describe passes' - and what moves is
    // *when* the bits are taken, which is what leaves an array length
    // adjustable and a camera-view table resolvable up to this line.
    data.realize();
    // Recorded for the event passes: `Game._bindEvents` gives each prefab its
    // own `describeEvents`, and `SceneStruct.collectListeners` walks this list
    // so an event declared above reaches every struct the scene can spawn.
    //
    // A declared child lands here before its declarer does, because its whole
    // registration finishes inside the walk above. Deterministic, which is all
    // the event order has ever promised.
    _scene._prefabs.add(object);
    // There is deliberately no describeState pass here. A prefab used to be
    // able to declare a state channel, threaded through the scene's `game`
    // back-reference into the boot pass's shared descriptor - and it stopped
    // working the moment scene loading moved out of boot and into
    // `GameState.loadScene`, because a channel's index has to be fixed at
    // boot and announced once. Publish scene-derived values from a
    // `GameSystem` instead; see `Game.describeState`.
    storage.seal();
  }

  /// Reserves [declarer]'s handle column for [child], registers the child, and
  /// tells it which archetype the column sits on.
  ///
  /// The column is reserved *before* the child is registered so it lands in
  /// declaration order alongside the declarer's own columns, rather than after
  /// everything the child's registration touches.
  void _declareChild(
    EntityStruct declarer,
    EntityStruct child,
    ArchetypeDataDescriptor data,
    ArchetypeStorage storage,
  ) {
    // Reserving the column is what enforces "a declared child mixes in
    // Child": only `Child` has somewhere to put it. Checked here because it is
    // a fact about the prefab and there is no reason to wait for a spawn to
    // report it.
    if (child is! Child) {
      throw ArgumentError.value(
        child,
        'child',
        '${child.runtimeType} does not mix in Child, so it cannot be declared '
            'as a child of ${declarer.runtimeType}. Add `with Child` to '
            '${child.runtimeType}.',
      );
    }
    final handle = data.optEntity();
    // The column belongs to this archetype and addresses something else on
    // any other, so the child records which one it was declared on - see
    // `Child.declaredInArchetype`, and the check every read and unlink makes
    // against it.
    (child as Child).bindDeclaration(handle, storage.archetypeId);
    _register(child);
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
  Asset<T> has<T>(AssetKey<T> key) {
    // Game-wide, not scene-local: two scenes that both use the UI atlas share
    // one handle and one address, which is what makes a transition between
    // them free of a decode round trip.
    final asset = _scene.assets.declare(key);
    _record(asset);
    return asset;
  }

  /// Addresses every asset a constructed object holds in a field.
  void declare(Iterable<ScannableField> declarations) {
    for (final declaration in declarations) {
      declareOne(declaration);
    }
  }

  /// One declaration, in the position the caller reached it - the counterpart
  /// of `ArchetypeDataDescriptor.declareOne`, and here for the same reason.
  ///
  /// A declaration that is not an asset is skipped rather than refused: a
  /// column and a dispatcher are declarations too, and what they resolve
  /// against is a row layout and a listener set. This descriptor addresses
  /// assets, and says so by taking only what it can address.
  void declareOne(ScannableField declaration) {
    if (declaration is! Asset<Object?>) return;
    // `bind` hands back the handle the identity is addressed on, which is
    // this one the first time and somebody else's the second. The footprint
    // holds that one, so a texture two prefabs named is one entry.
    _record(_scene.assets.bind(declaration));
  }

  void _record(Asset<Object?> asset) {
    final declared = _scene._declaredAssets;
    // Linear scan rather than a Set: this runs once per declaration at scene
    // bring-up over a list of at most a few dozen, and keeping only the list
    // means the order is exactly declaration order with no second structure
    // to keep in sync.
    //
    // Compared by *handle* identity, not by key. `declare` and `bind` have
    // already collapsed equal-but-distinct keys - two call sites writing
    // `AssetKey<Texture>(BundleSource('x'))` - onto one addressed handle, so
    // comparing keys here would file one asset twice and count its scene
    // claim twice.
    for (var i = 0; i < declared.length; i++) {
      if (identical(declared[i], asset)) return;
    }
    declared.add(asset);
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
  /// the entity itself and not fetched from anything more general. That is
  /// the difference between `entity.scene.addEntity(...)` - spawn where *this*
  /// one lives - and reaching for a scene from the state and assuming it is
  /// the right one.
  ///
  /// Throws when that scene has been **unloaded** instead of answering with a
  /// handle into whatever loaded into its slot afterwards - the same
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
    // The mirror of the check `allocateRow` makes, and here for the same
    // reason: freeing a row from a handler with no tick window open hands it
    // to the next spawn while the simulation is standing still. See
    // `HandlerWindow`.
    storage.pool.requireWorldMutable('An entity was destroyed');
    final page = storage.pageAt(pageIndex);
    if (page == null) return; // its scene was already unloaded

    if (has<Parent>()) {
      // The next sibling is read *before* the child is destroyed, because
      // destroying it clears the link this walk would need next.
      var child = this<Parent>().component.parentFirstChild.readPending(this);
      while (child != null) {
        final after = child<Child>().component.childNextSibling.readPending(child);
        child.destroy();
        child = after;
      }
    }

    if (has<Child>()) {
      final parent = this<Child>().component.childParent.readPending(this);
      if (parent != null) parent<Parent>().unlinkChild(this);
    }

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
    // After every listener has read the row and before the row goes: a
    // heap-object field's value is a slot in a process-global table, and
    // freeing the row reclaims the page bytes holding the address but not the
    // slot they point at. Nothing did this until #49; the table grew for the
    // life of the process. No-op for an archetype declaring no such field,
    // which is all of them in the engine itself.
    storage.releaseHeapSlots(page, rowOffset);
    page.free(rowOffset);
  }
}
