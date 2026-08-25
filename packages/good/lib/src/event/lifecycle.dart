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
// What was missing, and what `GameLifecycleListener` closes, is the *other*
// direction: a `GameSystem` that wants to know the game has come up had no way
// to be told. It could mix in the old `LifecycleListener`, compile cleanly, and
// silently never fire - the walk only ever reached the `GameState`. That was
// one of two dead capabilities found when the old event hierarchy came out, and
// it is the reason these are events rather than more virtuals.
//
// The two levels below it are **not** widened the same way, and this file used
// to claim they were. A dispatcher's audience is its declaring owner's
// composition, and scene and entity lifecycle are declared on the `SceneStruct`
// and the `EntityStruct` (see the note beside `GameState`'s observation
// dispatchers for why). A system mixing one of those in is offered to nobody
// that delivers it. `SceneLoadListener` and `EntitySpawnListener`, further
// down, are the events a system uses to watch the world.

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

/// Hears an instance of **one scene struct** being loaded or unloaded, and is
/// told which instance.
///
/// Narrow, always. The only dispatchers that deliver it are that struct's own
/// `SceneStruct.mountedEvent`/`unmountedEvent`, and those collect the struct
/// and the prefabs it declared - nothing else. Every `SceneStruct` mixes this
/// in, so a scene spawns its starting entities in [onSceneMounted] and needs
/// no separate virtual, and a prefab may mix it in to hear the scene it
/// belongs to.
///
/// **On a `GameSystem` this never fires.** `GameState` declares no
/// `SceneLifecycleListener` dispatcher, and no scene offers a system to its
/// own, so the mixin compiles and the hook silently never runs. A system that
/// wants to react to scene transitions wants [SceneLoadListener], the
/// world-observation counterpart `GameState` does declare. (A struct can still
/// let one system in, by offering it from `collectListeners` - that is the
/// struct widening its own audience, not a game-wide hook.)
///
/// A `SceneStruct` that also mixes in [SceneLoadListener] hears its own mount
/// twice, and that is correct: `GameState` collects the scenes, so it asked to
/// hear every scene load and its own is one of them.
mixin SceneLifecycleListener on GameListener {
  /// [scene] has been loaded. The struct's own [onSceneMounted] runs before
  /// any of its prefabs', so a prefab hearing the mount finds the starting
  /// entities already spawned - that is what the mount dispatcher's forward
  /// order buys.
  void onSceneMounted(Scene scene) {}

  /// [scene] is being unloaded. Dispatched before its pages are released, so
  /// its entities are still readable here and never again afterwards.
  void onSceneUnmounted(Scene scene) {}
}

/// Hears the entities of **one entity struct** coming into being or going
/// away.
///
/// The third level of the same scoping the two above it have, and narrow for
/// the same reason: the only dispatchers that deliver it are that struct's own
/// [EntityStruct.mountedEvent]/[EntityStruct.unmountedEvent], which collect the
/// struct itself. So it fires for its own entities and nothing else, and a
/// listener never has to ask whether the entity was one of its own.
///
/// **There is no broadcast half.** `GameState` declares no
/// `EntityLifecycleListener` dispatcher, so a `GameSystem` mixing this in
/// compiles and silently never fires - a spatial index, a networked replica
/// table or an editor overlay wants [EntitySpawnListener], which `GameState`
/// does declare. (A struct can offer one system into its own dispatcher from
/// `collectListeners`, which lets that system hear *that struct's* entities
/// and no others.)
///
/// Firing this costs nothing whether or not anything is listening: the payload
/// is passed as an argument, never wrapped in an event object, so the spawn
/// path allocates nothing at all (the hot-path rules) and the dispatch sites
/// need no `listenerCount > 0` guard.
mixin EntityLifecycleListener on GameListener {
  /// [entity] has been created and its declared field defaults are already
  /// stamped into the row - by the storage layer at creation, not by a write
  /// on this tick, so a struct that only needs its defaults needs no override
  /// here at all.
  void onEntityMounted(Entity entity) {}

  /// [entity] is going away, either because `Entity.destroy()` was called on
  /// it (or on an ancestor, which destroys the subtree) or because the scene
  /// holding it is being unloaded. Both paths dispatch in the same order -
  /// [EntitySpawnListener.onEntityDespawned] first, then this - so the two are
  /// indistinguishable from in here.
  ///
  /// Its row is still readable during the dispatch and released immediately
  /// afterwards. Rows **are** recycled: after a destroy the next entity of the
  /// same archetype can be handed that row, and `Entity` has no generation
  /// counter, so a handle kept past this point silently starts naming
  /// something else instead of reading as dead.
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
// `EventDispatcher<L, E>` (or a `SignalDispatcher<L>`) with a one-line delivery
// closure - declared on `GameState` for the game-level and world-observation
// events, and on the `SceneStruct`/`EntityStruct` for the two scoped lifecycle
// ones - so the payload travels as an argument and nothing is allocated per
// dispatch. Eight classes -
// Game/Scene/Entity x Mounted/Unmounted, plus the two tick events - came out
// when that landed.

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
