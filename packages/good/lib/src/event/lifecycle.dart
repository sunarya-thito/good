import 'package:good/src/event.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';

// --- lifecycle events -----------------------------------------------------
//
// Bring-up and tear-down, as events, so that something *other than the owner*
// can hear about them.
//
// An owner answering for *itself* is a plain virtual and needs none of this.
// `GameState.onMounted()` is one; so are `SceneStruct.onSceneMounted(Scene)`
// and `EntityStruct.onEntityMounted(Entity)`, and their two teardown halves.
// One receiver, the framework the only caller, nothing to dispatch and nobody
// to dispatch it to.
//
// What a virtual cannot do, and what these events are for, is tell somebody
// else. A `GameSystem` that wants to know the game has come up is not the
// owner of anything and has no virtual to override, so `GameLifecycleListener`
// below is how it asks. `SceneLoadListener` and `EntitySpawnListener`, further
// down, are the same shape for the two levels under it.

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

// --- world observation ----------------------------------------------------
//
// A DIFFERENT QUESTION FROM THE VIRTUALS ON THE STRUCTS, and that is why these
// are events with names of their own rather than the same hook opened up to a
// wider audience.
//
// *Mounted*/*unmounted* mean "I am coming up" / "I am going away". They are
// `SceneStruct.onSceneMounted` and `EntityStruct.onEntityMounted`: the engine
// calls the struct about the struct's own scene, or the struct's own entity,
// so the receiver never has to ask whether the call was about it. That was
// worth a dispatcher's worth of machinery once, when it was one; it is a
// method call now, and it means the same thing.
//
// *Spawned*/*despawned* and *loaded*/*unloaded* mean "something happened in
// the world". They are for an observer that legitimately wants to watch
// everything - a physics backend creating a body per entity, a spatial index,
// a replication table, an editor overlay. Such a listener expects to filter
// by archetype, because seeing everything is what it asked for.
//
// So the two are not the same event at different volumes; they answer
// different questions, and a listener picks by which question it is asking.
// Deleting the narrow half would not have merged them - it would have left
// every struct filtering a game-wide feed for its own rows.

/// Hears **every** entity spawning and despawning, anywhere in the game.
///
/// The broad counterpart to `EntityStruct.onEntityMounted`. Mixed into a
/// [GameListener] - a `GameSystem` or the `GameState` - so it hears the whole
/// world:
///
/// ```dart
/// class SpatialIndexSystem extends GameSystem with EntitySpawnListener {
///   @override
///   void onEntitySpawned(Entity entity) {
///     if (entity.has<Collider2D>()) index.insert(entity);
///   }
/// }
/// ```
///
/// Filtering by archetype is expected here, not a smell: a listener here asked
/// to see everything. Override `EntityStruct.onEntityMounted` instead when a
/// struct only cares about its own entities - that one needs no filter.
mixin EntitySpawnListener on GameListener {
  /// [entity] has been created, with its field defaults already stamped into
  /// the row. Fired from the same call site as
  /// `EntityStruct.onEntityMounted`, so the two cannot disagree about when a
  /// spawn happened.
  void onEntitySpawned(Entity entity) {}

  /// [entity] is going away. Its row is still readable here and never again
  /// afterwards.
  void onEntityDespawned(Entity entity) {}
}

/// Hears **every** scene loading and unloading, anywhere in the game.
///
/// The broad counterpart to `SceneStruct.onSceneMounted`. Same split as
/// [EntitySpawnListener]: a scene hears its *own* bring-up through that
/// virtual, while anything that wants to watch the whole world - a loading
/// screen, an asset budget, a save system - uses this.
mixin SceneLoadListener on GameListener {
  /// [scene] has been loaded and its starting entities have already spawned,
  /// matching the ordering `SceneStruct.onSceneMounted` gives.
  void onSceneLoaded(Scene scene) {}

  /// [scene] is being unloaded. Its entities are still readable here; they
  /// are despawned immediately after.
  void onSceneUnloaded(Scene scene) {}
}

// There are no event classes here. Every one of these is an
// `EventDispatcher<L, E>` (or a `SignalDispatcher<L>`) with a one-line delivery
// closure declared on `GameState`, so the payload travels as an argument and
// nothing is allocated per dispatch. Eight classes - Game/Scene/Entity x
// Mounted/Unmounted, plus the two tick events - came out when that landed.

/// Hears the app becoming hidden and visible again.
///
/// Mixed into a [GameListener] - typically a `GameSystem`:
///
/// ```dart
/// class AutosaveSystem extends GameSystem with AppVisibilityListener {
///   @override
///   void onAppHidden() => save();
/// }
/// ```
///
/// # Visibility, not focus
///
/// Flutter reports five `AppLifecycleState`s and the engine collapses them to
/// two. `resumed` and `inactive` both count as visible; `hidden`, `paused` and
/// `detached` all count as hidden.
///
/// `inactive` does **not** hide. It is a window losing focus, a
/// phone call arriving, the notification shade coming down, an app sitting in
/// the switcher - the app is still on screen. Pausing there is why some games
/// stop when you alt-tab to a browser. A game that genuinely wants focus can
/// read it from Flutter directly.
///
/// # There is no "about to be killed" hook
///
/// [onAppHidden] is the last moment worth writing a save in, and it is a
/// reliable one: iOS and Android both synthesise `hidden` *before* `paused`
/// exactly so cross-platform code has one place to handle it.
///
/// `detached` is not that place, and nothing here fires on it. It is also the
/// state an app is in *before* it starts, a process killed while
/// hidden never sends it at all, and no platform promises time to act on it.
/// A hook that returned a future for the engine to await would be describing
/// an intention, not a behaviour - so a save belongs in [onAppHidden], and a
/// process killed after that has already had its chance.
mixin AppVisibilityListener on GameListener {
  /// The app is no longer visible.
  ///
  /// The fixed tick has already stopped unless `Game.pauseWhenHidden` is
  /// false. This is the last point at which anything is guaranteed to run,
  /// so it is where a save goes.
  void onAppHidden() {}

  /// The app is visible again.
  ///
  /// [gap] is the wall-clock time spent hidden. It has already been
  /// **discarded** from the fixed-step accumulator, not caught up, so no
  /// fixed steps ran for it and none are queued - see `GameState.advance`.
  void onAppShown(Duration gap) {}
}
