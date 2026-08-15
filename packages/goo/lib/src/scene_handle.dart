import 'package:meta/meta.dart';

import 'package:goo/src/scene.dart';
import 'package:goo/src/struct.dart';

/// A handle to one **loaded instance** of a [SceneStruct], packed into a
/// single 64-bit int:
///
/// ```text
///   63                            32 31                            0
///  +--------------------------------+------------------------------+
///  |          generation            |             slot             |
///  +--------------------------------+------------------------------+
/// ```
///
/// `SceneStruct` is to `Scene` what `EntityStruct` is to `Entity`: the class
/// you write, and a handle to one live instance of it. Like [Entity] this is
/// an extension type over `int`, so passing one around or storing one costs
/// nothing (RULES.md rule 1), and like [Entity] it carries no references -
/// resolution goes through the process-global [SceneRegistry], for the same
/// reason `Entity.get<T>()` goes through `ArchetypeRegistry`.
///
/// # Why this one has a generation counter and [Entity] does not
///
/// `Entity` spends all 64 of its bits (16 archetype + 16 page + 32 row) and
/// has none left. `Scene` has an entire word to itself for far fewer live
/// values, so half of it pays for the thing `Entity` cannot afford: a slot
/// that has been unloaded and reused does not silently answer for its
/// successor. A handle to an unloaded scene reports [isLoaded] false and
/// throws from [get] with a diagnostic, rather than resolving to whatever was
/// loaded into that slot afterwards.
extension type const Scene(int value) {
  static const int _generationShift = 32;
  static const int _mask = 0xFFFFFFFF;

  /// Packs the two fields above. Called by [SceneRegistry.register].
  const Scene.pack(int generation, int slot)
    : value = (generation << _generationShift) | slot;

  /// Which load this handle refers to. Bumped every time [slot] is reused, so
  /// two handles to the same slot from different loads are different values.
  int get generation => (value >> _generationShift) & _mask;

  /// Position in [SceneRegistry]'s table - reused after an unload.
  int get slot => value & _mask;

  /// Whether this handle still names a loaded scene. False for a scene that
  /// has been unloaded, including when its slot has since been reused.
  bool get isLoaded => SceneRegistry.tryResolve(this) != null;

  /// The [SceneStruct] this handle names, as [T].
  ///
  /// One list index and a generation compare - the same shape and the same
  /// cost as `Entity.get<T>()`. Throws for an unloaded scene rather than
  /// returning null, so a stale handle is a diagnostic rather than a
  /// null-check every caller has to remember; use [tryGet] where absence is
  /// expected.
  T get<T extends SceneStruct>() {
    final scene = SceneRegistry.tryResolve(this);
    if (scene == null) {
      throw StateError(
        'Scene #$slot (generation $generation) is not loaded. Either it was '
        'never loaded, or it was unloaded and this handle outlived it - the '
        'generation is what tells those apart from a handle to whatever was '
        'loaded into the same slot afterwards.',
      );
    }
    if (scene is T) return scene;
    throw StateError('Scene #$slot is a ${scene.runtimeType}, not a $T.');
  }

  /// [get], but `null` instead of throwing - for a caller that legitimately
  /// works either way.
  T? tryGet<T extends SceneStruct>() {
    final scene = SceneRegistry.tryResolve(this);
    return scene is T ? scene : null;
  }

  /// Creates an entity from [prefab] in this scene - one row in the prefab's
  /// archetype, stamped with its declared field defaults - and optionally
  /// attaches it under [parent].
  ///
  /// This is where entity creation lives now: on the *instance*, not on the
  /// `SceneStruct` class, because with several instances of one struct
  /// resident at once "which scene does this row belong to" is a question the
  /// receiver has to answer, and a handle answers it by being the receiver.
  ///
  /// Allocation-free apart from what the mount dispatch itself does.
  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      get<SceneStruct>().addEntityIn(slot, prefab, parent: parent);
}

/// The process-global table of loaded scenes - what a [Scene] handle resolves
/// through.
///
/// Static for the same reason `ArchetypeRegistry` is: a [Scene] is a bare int
/// carrying no references, so resolving one cannot start from an object. The
/// engine already keeps `ArchetypeRegistry`, `ComponentTypeRegistry`,
/// and `HeapObjectRegistry` this way, and [reset] follows the
/// same test-teardown convention they do.
abstract final class SceneRegistry {
  /// Loaded scenes by slot. A null is a slot whose scene has been unloaded and
  /// which is available for reuse.
  static final List<SceneStruct?> _loaded = <SceneStruct?>[];

  /// One counter per slot, bumped on every reuse, so a handle from an earlier
  /// load of the same slot never compares equal to the current one.
  static final List<int> _generations = <int>[];

  /// How many slots have ever been used - the length of the table, including
  /// tombstoned slots. Not a count of live scenes.
  static int get slotCount => _loaded.length;

  /// Records [scene] in the first free slot and returns its handle.
  ///
  /// **Normally you want `GameState.loadScene`**, which does this plus the
  /// bookkeeping a load needs - asset claims, the loaded list, and the
  /// scene's own `onSceneMounted`. This is the bare registration underneath it,
  /// public for the same reason `SceneStruct.initializeScene` is: a test or a
  /// headless harness legitimately brings a scene up without a `Game`, and
  /// needs a handle to spawn through.
  static Scene register(SceneStruct scene) {
    for (var i = 0; i < _loaded.length; i++) {
      if (_loaded[i] != null) continue;
      _loaded[i] = scene;
      return Scene.pack(_generations[i], i);
    }
    _loaded.add(scene);
    _generations.add(0);
    return Scene.pack(0, _loaded.length - 1);
  }

  /// Drops [scene]'s entry and bumps its slot's generation, so every handle
  /// to it stops resolving from here on. The counterpart to [register]; a
  /// loaded scene is torn down by `GameState.unloadScene`, which also frees
  /// its pages and releases its asset claims.
  static void unregister(Scene scene) {
    final slot = scene.slot;
    if (slot < 0 || slot >= _loaded.length) return;
    if (_generations[slot] != scene.generation) return;
    _loaded[slot] = null;
    // Wrapped rather than left to grow: the generation only has to distinguish
    // a handle from its slot's *neighbouring* loads, and a scene handle does
    // not outlive 4 billion loads of one slot.
    _generations[slot] = (_generations[slot] + 1) & 0xFFFFFFFF;
  }

  // No `snapshot`/`restore` here any more - see the note in
  // `ComponentTypeRegistry`. A scene is loaded on the game isolate and
  // resolved there; main holds no `Scene` at all.

  /// The live handle for [slot], or null when nothing is loaded there.
  ///
  /// Supplies the generation half of a handle to a caller that only has the
  /// slot - which is every caller that got there from an entity, since a
  /// `MemoryPage` records `ownerSceneSlot` and nothing more. Reconstructed
  /// rather than remembered, so it cannot go stale: an unloaded slot answers
  /// null instead of a handle into whatever loaded next.
  @internal
  static Scene? handleAt(int slot) {
    if (slot < 0 || slot >= _loaded.length) return null;
    if (_loaded[slot] == null) return null;
    return Scene.pack(_generations[slot], slot);
  }

  /// The scene [handle] names, or null if it has been unloaded.
  ///
  /// The generation compare is what makes a stale handle report absence rather
  /// than resolving to whatever took its slot.
  static SceneStruct? tryResolve(Scene handle) {
    final slot = handle.slot;
    if (slot < 0 || slot >= _loaded.length) return null;
    if (_generations[slot] != handle.generation) return null;
    return _loaded[slot];
  }

  @visibleForTesting
  static void reset() {
    _loaded.clear();
    _generations.clear();
  }
}
