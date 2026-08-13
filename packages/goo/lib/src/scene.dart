import 'package:meta/meta.dart';

import 'package:goo/src/archetype.dart';
import 'package:goo/src/asset.dart';
import 'package:goo/src/data/hierarchy.dart';
import 'package:goo/src/data_layout.dart';
import 'package:goo/src/event.dart';
import 'package:goo/src/game.dart';
import 'package:goo/src/pool.dart';
import 'package:goo/src/scene_handle.dart';
import 'package:goo/src/struct.dart';

abstract class SceneStruct with GameListenerMixin {
  GameAssets? _assets;

  /// The asset table this scene's declarations register into - the `Game`'s,
  /// handed over at [initializeScene] exactly as [pool] is.
  ///
  /// A headless fixture that brings a scene up without a `Game` gets its own,
  /// which is why this is not simply `game.assets`: `initializeScene` is
  /// public precisely so a test can use it, and asset *declaration* is
  /// meaningful with no game at all.
  GameAssets get assets => _assets ??= GameAssets();

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

  Game? _game;

  /// The `Game` this scene was built under, via [GameState.loadScene] - set
  /// once, during the boot pass, mirroring how `EntityStruct.bindArchetype`
  /// gets its
  /// own scene reference at registration time. Lets a prefab's
  /// `getSystem<T>()` (`Component.getSystem`, struct.dart) reach a system
  /// through `scene.game.getSystem<T>()` without the prefab needing its own
  /// direct `Game` reference.
  Game get game {
    final g = _game;
    if (g == null) {
      throw StateError(
        '$runtimeType has no Game yet - this scene has not been through '
        'GameState.loadScene() yet.',
      );
    }
    return g;
  }

  /// [game], or `null` when this scene was brought up without one - see
  /// [initializeScene], which is public precisely so a test or headless
  /// harness can. Internal: user code either has a `Game` or is a test that
  /// knows it does not.
  @internal
  Game? get tryGame => _game;

  /// Called once during the boot pass, immediately after
  /// [GameState.loadScene] returns. Not part of the user-facing API.
  @internal
  void bindGame(Game game) => _game = game;

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
  /// A plain virtual call rather than a `GameEvent`: a scene's mount only ever
  /// concerns that scene, so there is nothing to dispatch and nobody else to
  /// dispatch it to. That is also why this replaced
  /// `with LifecycleListener` - `onMounted()` with no argument cannot say
  /// *which* instance came up.
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
  void initializeScene(MemoryPool pool, {GameAssets? assets}) {
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
    final descriptor = _AssetDescriptor(this);
    describeAssets(descriptor);
    describeScene(_SceneDescriptor(this, descriptor));
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
  /// [parent]'s bound is `T extends EntityStruct<T>` rather than
  /// `T extends Child`: Dart cannot express "extends `EntityStruct<T>` *and*
  /// mixes in Child" as a single bound, and `.archetype`/`.scene` (needed to
  /// create the row at all) only exist on `EntityStruct`. So it checks
  /// `prefab is Child` at runtime instead - the same trade `Parent.addChild`
  /// already makes for its own `child` parameter, for the same reason.
  ///
  /// Allocation-free apart from what `onCreated` itself does: `Entity` is
  /// an extension type over `int`, and the row's defaults are memcpy'd
  /// from a prototype built at registration time.
  @internal
  Entity addEntityIn<T extends EntityStruct<T>>(
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
    prefab.onCreated(entity);
    // After onCreated, not before: the prefab stamps its own defaults into the
    // row first, and Child's linked-list fields are part of what addChild
    // writes - reversing these would have onCreated overwrite the link.
    if (parentComponent != null) parentComponent.addChild(parent!, entity);
    return entity;
  }

  /// [addEntity] addressed by `archetypeId` instead of by prefab instance.
  ///
  /// This is the form a command crossing an isolate boundary can carry. A
  /// prefab is a live Dart object owned by one scene on one isolate, so a
  /// "spawn an Enemy" command written into the ring buffer by the UI
  /// isolate cannot name it directly - but `ArchetypeRegistry` already
  /// assigns every registered prefab a stable process-global integer (see
  /// [ArchetypeStorage.archetypeId]), and both isolates run the same
  /// `describeScene` in the same order, so that integer means the same
  /// prefab on both sides.
  ///
  /// Deliberately not "allocate a row of archetype N": it goes through the
  /// prefab's [Component.onCreated] exactly as [addEntity] does, so a
  /// command-spawned entity is indistinguishable from a directly-spawned
  /// one. That is the whole reason this lives here rather than being
  /// open-coded as `ArchetypeRegistry.byId(id).allocateRow()` in the
  /// command processor.
  @internal
  Entity addToSceneByIdIn(int sceneSlot, int archetypeId) {
    if (archetypeId < 0 || archetypeId >= ArchetypeRegistry.count) {
      throw ArgumentError.value(
        archetypeId,
        'archetypeId',
        'no archetype with that id is registered in this isolate',
      );
    }
    final storage = ArchetypeRegistry.byId(archetypeId);
    // Recorded at registration, not inferred. This used to compare pools -
    // a scene owned its own, so pool identity *was* scene identity - and that
    // stopped being true when the pool moved to the `Game` and every scene
    // started sharing one. `ArchetypeStorage.owner` is the replacement.
    if (!identical(storage.owner, this)) {
      throw StateError(
        'Archetype $archetypeId (${storage.prefab.runtimeType}) belongs to a '
        'different SceneStruct. A spawn command is only meaningful against the '
        'scene that registered the prefab.',
      );
    }
    final entity = storage.allocateRow(sceneSlot);
    storage.prefab.onCreated(entity);
    return entity;
  }

}

abstract class SceneDescriptor {
  T has<T extends EntityStruct<T>>(T object);
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
  T has<T extends EntityStruct<T>>(T object) {
    final storage = ArchetypeRegistry.register(
      _scene.pool,
      _scene,
      _scene.assets,
      object,
    );
    object.bindArchetype(_scene, storage);
    object.describeType(ArchetypeComponentDescriptor(storage));
    // Before describeStruct, not after: `has` returns an already-addressed
    // instance, so describeStruct can hand one straight to `data.hasObject`
    // as this archetype's default row value.
    object.describeAssets(_assets);
    object.describeStruct(ArchetypeDataDescriptor(storage));
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
