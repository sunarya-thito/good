import 'package:goo/src/event.dart';
import 'package:goo/src/scene_handle.dart';
import 'package:goo/src/struct.dart';

// --- lifecycle events -----------------------------------------------------
//
// Bring-up and tear-down, as events, so that something *other than the owner*
// can hear about them.
//
// Each level already has a plain virtual for its own bring-up -
// `GameState.onMounted()`, `SceneStruct.onMounted(Scene)`,
// `Component.onMounted(Entity)` - and those stay exactly as they are. They are
// the owner answering for itself: one receiver, framework the only caller,
// nothing to dispatch and nobody to dispatch it to.
//
// What was missing, and what these close, is the *other* direction: a
// `GameSystem` that wants to know the game has come up, or that a scene was
// loaded, had no way to be told. It could mix in the old `LifecycleListener`,
// compile cleanly, and silently never fire - the walk only ever reached the
// `GameState`. That was one of two dead capabilities found when the old event
// hierarchy came out, and it is the reason these are events rather than more
// virtuals.

/// Hears the game itself coming up and going down.
///
/// Mixed into a [GameListener] - typically a `GameSystem`, which is the case
/// that did not work before:
///
/// ```dart
/// class SpatialIndexSystem extends GameSystem with GameLifecycleListener {
///   @override
///   void onGameMounted() { /* the world exists; build the index */ }
/// }
/// ```
///
/// Both hooks default to no-ops, so a listener that only cares about one end
/// overrides one.
mixin GameLifecycleListener on GameListener {
  /// The game has come up **on the simulating copy**, after `GameState`'s own
  /// `onMounted` and after every scene it loaded has mounted - so the starting
  /// entities exist by the time this runs. That ordering is the point: a
  /// system building an index over the world wants the world already there.
  void onGameMounted() {}

  /// The game is going down, dispatched **before** anything is torn down -
  /// scenes are still loaded, entities are still readable, the pool is still
  /// alive. Anything that has to be read out of the world has to be read here.
  void onGameUnmounted() {}
}

/// Hears **any** scene being loaded or unloaded, and is told which one.
///
/// Deliberately distinct from `SceneStruct.onMounted(Scene)`, and the
/// difference is *whose* mount it reports:
///
///  * `SceneStruct.onMounted(scene)` - "an instance of **me** mounted". The
///    scene's own bring-up, where it spawns its starting entities. Narrow by
///    construction, since only that struct is called.
///  * [onSceneMounted] - "**a** scene mounted". A broadcast to every listener
///    the `GameState` collects, which is what lets a system react to scene
///    transitions at all.
///
/// A `SceneStruct` may mix this in as well, and will then hear its own mount
/// through both - which is correct rather than a quirk: it asked to hear every
/// scene mount, and its own is one of them.
mixin SceneLifecycleListener on GameListener {
  /// [scene] has been loaded and its own `onMounted` has run, so its starting
  /// entities already exist.
  void onSceneMounted(Scene scene) {}

  /// [scene] is being unloaded. Dispatched before its pages are released, so
  /// its entities are still readable here and never again afterwards.
  void onSceneUnmounted(Scene scene) {}
}

/// Hears **any** entity coming into being or going away.
///
/// The third level of the same pair every other level has: the struct's own
/// `Component.onMounted(Entity)`/`onUnmounted(Entity)` is the narrow half,
/// called directly and only for its own entities, and this is the broadcast
/// half for everything else - a spatial index, a networked replica table, an
/// editor overlay.
///
/// A listener hears **every** entity in the game, so it filters by archetype
/// itself:
///
/// ```dart
/// @override
/// void onEntityMounted(Entity entity) {
///   final body = entity.tryGet<Rigidbody>();
///   if (body != null) index.insert(entity);
/// }
/// ```
///
/// Firing this costs nothing whether or not anything is listening: the payload
/// is passed as an argument rather than wrapped in an event object, so the
/// spawn path allocates nothing at all (RULES.md rules 1 and 2). It used to
/// build an `EntityMountedEvent` per entity, which is why the dispatch sites
/// carried a `listenerCount > 0` guard - that guard is gone with the
/// allocation it was avoiding.
mixin EntityLifecycleListener on GameListener {
  /// [entity] has been created and its struct's own `onMounted` has run, so
  /// its declared field defaults are already stamped into the row.
  void onEntityMounted(Entity entity) {}

  /// [entity] is going away, because the scene holding it is being unloaded.
  /// Its row is still readable here and never again afterwards.
  ///
  /// There is no per-entity destroy yet - rows are not recycled - so scene
  /// unload is the only thing that fires this.
  void onEntityUnmounted(Entity entity) {}
}

// There are no event classes here. Every one of these is an
// `EventDispatcher<L, E>` (or a `SignalDispatcher<L>`) declared on `GameState`
// with a one-line delivery closure, so the payload travels as an argument and
// nothing is allocated per dispatch. Eight classes -
// Game/Scene/Entity x Mounted/Unmounted, plus the two tick events - came out
// when that landed.
