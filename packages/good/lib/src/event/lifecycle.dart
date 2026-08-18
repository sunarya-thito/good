import 'package:good/src/event.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';

// --- lifecycle events -----------------------------------------------------
//
// Bring-up and tear-down, as events, so that something *other than the owner*
// can hear about them.
//
// Only the top level still has a plain virtual for its own bring-up:
// `GameState.onMounted()`, which is the owner answering for itself - one
// receiver, framework the only caller, nothing to dispatch and nobody to
// dispatch it to. The scene and entity levels used to have one too
// (`SceneStruct.onMounted(Scene)`, `Component.onMounted(Entity)`) and no
// longer do: those owners mix in the listener below and hear their own
// bring-up through the dispatcher like anything else. See scene.dart's note
// on why the ordering the virtuals guaranteed survives that.
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
/// Two different questions land on the same hook, and which one a listener is
/// asking depends on where it is mixed in:
///
///  * On a `SceneStruct` - "an instance of **me** mounted". Every scene struct
///    mixes this in, so this is where a scene spawns its starting entities.
///    It is narrow because the struct's own [SceneStruct.mountedEvent] only
///    ever collects that struct.
///  * On a `GameSystem` (or anything the `GameState` collects) - "**a** scene
///    mounted". The broadcast, which is what lets a system react to scene
///    transitions at all.
///
/// A `SceneStruct` hearing its own mount through both is correct rather than a
/// quirk: it asked to hear every scene mount, and its own is one of them.
mixin SceneLifecycleListener on GameListener {
  /// [scene] has been loaded. A listener collected by the `GameState` sees
  /// this after the scene struct's own [onSceneMounted] has run, so the
  /// starting entities already exist - that is what the mount dispatcher's
  /// forward order buys.
  void onSceneMounted(Scene scene) {}

  /// [scene] is being unloaded. Dispatched before its pages are released, so
  /// its entities are still readable here and never again afterwards.
  void onSceneUnmounted(Scene scene) {}
}

/// Hears **any** entity coming into being or going away.
///
/// The third level of the same pair every other level has, and the same mixin
/// serves both halves. Mixed into an `EntityStruct` it is the narrow half -
/// that struct's [EntityStruct.mountedEvent] collects only itself, so it fires
/// for its own entities and nothing else. Mixed in anywhere the `GameState`
/// collects it is the broadcast half, for a spatial index, a networked replica
/// table, an editor overlay.
///
/// A broadcast listener hears **every** entity in the game, so it filters by
/// archetype itself:
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
  /// [entity] has been created and its declared field defaults are already
  /// stamped into the row - by the storage layer at creation, not by a write
  /// on this tick, so a struct that only needs its defaults needs no override
  /// here at all.
  void onEntityMounted(Entity entity) {}

  /// [entity] is going away, because the scene holding it is being unloaded.
  /// Its row is still readable here and never again afterwards.
  ///
  /// There is no per-entity destroy yet - rows are not recycled - so scene
  /// unload is the only thing that fires this.
  void onEntityUnmounted(Entity entity) {}
}

// --- world observation ----------------------------------------------------
//
// A DIFFERENT QUESTION FROM THE LIFECYCLE EVENTS ABOVE, and that is why these
// are separate events with separate names rather than a wider scope on the
// existing ones.
//
// *Mounted*/*unmounted* mean "I am coming up" / "I am going away". They are
// delivered to the thing itself and its own composition - a `SceneStruct`
// hears its own scene, an `EntityStruct` hears its own entities - so a
// listener never has to ask whether an event was about it. That locality is
// the point, and widening it would destroy the property: one list per level
// holding everything in the game means unloading scene A tells scene B, which
// then has to filter.
//
// *Spawned*/*despawned* and *loaded*/*unloaded* mean "something happened in
// the world". They are for an observer that legitimately wants to watch
// everything - a physics backend creating a body per entity, a spatial index,
// a replication table, an editor overlay. Such a listener expects to filter
// by archetype, because seeing everything is what it asked for.
//
// So the two are not the same event at different volumes; they answer
// different questions, and a listener picks by which question it is asking.

/// Hears **every** entity spawning and despawning, anywhere in the game.
///
/// The broad counterpart to [EntityLifecycleListener]. Mixed into a
/// [GameListener] - typically a `GameSystem` - and collected by `GameState`'s
/// composition walk, so it hears the whole world:
///
/// ```dart
/// class SpatialIndexSystem extends GameSystem with EntitySpawnListener {
///   @override
///   void onEntitySpawned(Entity entity) {
///     if (entity.tryGet<Collider2D>() != null) index.insert(entity);
///   }
/// }
/// ```
///
/// Filtering by archetype is expected here, not a smell: a listener at this
/// scope asked to see everything. Use [EntityLifecycleListener] instead when
/// a struct only cares about its own entities - that one needs no filter.
mixin EntitySpawnListener on GameListener {
  /// [entity] has been created, with its field defaults already stamped into
  /// the row. Fired from the same call site as
  /// [EntityLifecycleListener.onEntityMounted], so the two cannot disagree
  /// about when a spawn happened.
  void onEntitySpawned(Entity entity) {}

  /// [entity] is going away. Its row is still readable here and never again
  /// afterwards.
  void onEntityDespawned(Entity entity) {}
}

/// Hears **every** scene loading and unloading, anywhere in the game.
///
/// The broad counterpart to `SceneLifecycleListener`. Same split as
/// [EntitySpawnListener]: a scene hears its *own* bring-up through the
/// lifecycle listener, while anything that wants to watch the whole world
/// - a loading screen, an asset budget, a save system - uses this.
mixin SceneLoadListener on GameListener {
  /// [scene] has been loaded and its starting entities have already spawned,
  /// matching the ordering guarantee `SceneLifecycleListener` gives.
  void onSceneLoaded(Scene scene) {}

  /// [scene] is being unloaded. Its entities are still readable here; they
  /// are despawned immediately after.
  void onSceneUnloaded(Scene scene) {}
}

// There are no event classes here. Every one of these is an
// `EventDispatcher<L, E>` (or a `SignalDispatcher<L>`) declared on `GameState`
// with a one-line delivery closure, so the payload travels as an argument and
// nothing is allocated per dispatch. Eight classes -
// Game/Scene/Entity x Mounted/Unmounted, plus the two tick events - came out
// when that landed.
