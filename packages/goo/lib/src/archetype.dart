import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'package:goo/src/asset.dart';
import 'package:goo/src/pool.dart';
import 'package:goo/src/scene.dart';
import 'package:goo/src/struct.dart';

/// Assigns every distinct `Component` type (a concrete `EntityStruct`
/// subclass, or a mixin like `Transform2D`/`Child`) one stable bit, the
/// first time `ComponentDescriptor.has<T>()` sees it.
///
/// The bit is what makes archetype matching a single machine instruction
/// later: a query compiles to a required-mask/forbidden-mask pair, and
/// "does this archetype match?" becomes `signature & required == required`
/// against [ArchetypeStorage.componentSignature] - no per-entity type
/// tests, no map lookups, in the loop that runs for every entity every
/// tick. That is the whole reason the registry exists here, ahead of the
/// query system that will consume it.
///
/// Assignment order is first-seen order, which means it depends on scene
/// declaration order. That is fine *within* a process (signatures are only
/// ever compared to other signatures produced in the same process) but
/// makes a signature meaningless to serialize - don't persist one.
abstract final class ComponentTypeRegistry {
  /// One 64-bit `int` per signature word, and we currently use exactly one
  /// word - so 64 distinct component types is the hard ceiling. Widening
  /// to a 2-word (or `Uint64List`-backed) signature is a mechanical
  /// follow-up - every consumer goes through [bitFor] and
  /// [ArchetypeStorage.componentSignature] - but it costs the "match is one
  /// AND" property above, so it is deliberately not attempted now.
  static const int maxComponentTypes = 64;

  static final Map<Type, int> _indices = <Type, int>{};

  /// A copy of the assignments, for `Game` to carry across the spawn.
  ///
  /// Static state is **per isolate** - it is not part of any object graph, so
  /// `Isolate.spawn`'s deep copy does not bring it. The declaring copy hands
  /// the table over explicitly and the spawned copy [restore]s it, which is
  /// what makes "describe once, on main" possible at all. `Type` objects are
  /// sendable; verified in `tool/spawn_registry_spike.dart`.
  @internal
  static Map<Type, int> snapshot() => Map<Type, int>.of(_indices);

  /// Adopts a [snapshot] taken on the declaring copy. Replaces rather than
  /// merges: this copy declared nothing, so anything already here would be a
  /// second, disagreeing assignment.
  @internal
  static void restore(Map<Type, int> snapshot) {
    _indices
      ..clear()
      ..addAll(snapshot);
  }

  /// Number of distinct component types seen so far.
  static int get assignedCount => _indices.length;

  /// The single-bit mask for [type], assigning a fresh bit if this is the
  /// first sighting. Returns a *mask*, not an index, because every caller
  /// wants to OR it into a signature.
  ///
  /// Note bit 63 makes the mask negative (`1 << 63` is `Dart`'s minimum
  /// int). That is harmless: every use is bitwise AND/OR, never a
  /// comparison or an arithmetic shift of the signature itself.
  static int bitFor(Type type) => 1 << indexFor(type);

  /// The bit *index* (0..63) for [type]. Exposed for diagnostics and for
  /// the future multi-word widening; [bitFor] is what callers normally
  /// want.
  static int indexFor(Type type) {
    final existing = _indices[type];
    if (existing != null) return existing;
    if (_indices.length >= maxComponentTypes) {
      throw StateError(
        'ComponentTypeRegistry is full: $maxComponentTypes distinct component '
        'types have been registered and the query signature is a single '
        '64-bit word. Widening the signature to two words is a mechanical '
        'change (see maxComponentTypes) - it has not been done yet.',
      );
    }
    final index = _indices.length;
    _indices[type] = index;
    return index;
  }

  /// Test-only escape hatch: this registry is process-global by design, so
  /// a test suite that declares many throwaway component types would
  /// otherwise march into [maxComponentTypes] for reasons that have nothing
  /// to do with the code under test.
  @visibleForTesting
  static void reset() => _indices.clear();
}

/// Process-global table of every [ArchetypeStorage], indexed by its
/// `archetypeId`.
///
/// Global rather than per-`SceneStruct` on purpose: an `Entity` is a bare
/// `int` (see `Entity` in struct.dart) with the archetype id packed into
/// its top bits and *no* captured reference to the scene, storage, or
/// prefab that produced it. That is what lets an entity handle be copied
/// into a ring-buffer command record, shipped to another isolate, stored
/// in a native row as a plain integer - and still resolve its own layout
/// from its bits alone. A per-scene registry would force every entity to
/// carry a scene reference (a heap pointer, so no longer a plain int) or
/// force every call site to thread the scene through, which is exactly the
/// coupling `Entity.get<T>()` exists to avoid.
///
/// The cost is that archetype ids are unique per *process*, not per scene,
/// and are never recycled when a scene unloads. With a 16-bit id that is
/// 65536 archetype registrations for the life of the process; scene
/// unload/reload reclaiming ids is future work.
abstract final class ArchetypeRegistry {
  /// `Entity` reserves 16 bits for the archetype id - see `Entity.pack`.
  static const int maxArchetypes = 0x10000;

  static final List<ArchetypeStorage> _storages = <ArchetypeStorage>[];

  static int get count => _storages.length;

  /// Creates and registers storage for one archetype. Called exactly once
  /// per `EntityStruct` subclass, from `SceneDescriptor.has`.
  static ArchetypeStorage register(
    MemoryPool pool,
    SceneStruct owner,
    GameAssets assets,
    Component prefab,
  ) {
    if (_storages.length >= maxArchetypes) {
      throw StateError(
        'ArchetypeRegistry is full: $maxArchetypes archetypes have been '
        'registered, which is all a 16-bit archetype id can address (see '
        'Entity.pack). Archetype ids are process-global and are not '
        'recycled on scene unload.',
      );
    }
    final storage =
        ArchetypeStorage._(_storages.length, pool, owner, assets, prefab);
    _storages.add(storage);
    return storage;
  }

  /// Resolves an archetype id - the hot path behind `Entity.get<T>()`. A
  /// plain list index, no map, no allocation.
  static ArchetypeStorage byId(int archetypeId) => _storages[archetypeId];

  /// The registered storages in id order, for `Game` to carry across the
  /// spawn - see [ComponentTypeRegistry.snapshot] for why this is needed.
  ///
  /// The `ArchetypeStorage`s themselves are sendable (plain fields plus a
  /// `Pointer`, which crosses at the same address), so this carries the real
  /// objects rather than a description of them: the spawned copy ends up
  /// pointing at the same default rows and the same pages.
  @internal
  static List<ArchetypeStorage> snapshot() =>
      List<ArchetypeStorage>.of(_storages);

  @internal
  static void restore(List<ArchetypeStorage> snapshot) {
    _storages
      ..clear()
      ..addAll(snapshot);
  }

  /// Test-only: see [ComponentTypeRegistry.reset]. Frees each storage's
  /// default-row scratch buffer; it does *not* touch the `MemoryPool`s the
  /// storages borrowed pages from - those belong to the scene that owns
  /// them.
  @visibleForTesting
  static void reset() {
    for (final storage in _storages) {
      storage._dispose();
    }
    _storages.clear();
  }
}

/// One archetype's bit-packed field layout plus its row storage.
///
/// **Archetype identity is the `EntityStruct` subclass, not the field set.**
/// `Player` and `Enemy` in the render example are both
/// `with Transform2D, Child` and therefore have byte-identical layouts, yet
/// they get two archetypes, two signatures, and two disjoint sets of pages.
/// That is deliberate Phase 1 scope: it keeps registration a single
/// one-time pass with no structural hashing, and it keeps `Entity.get<T>()`
/// able to hand back *the* prefab instance for a row (the one holding the
/// `DataPointer` fields the mixins wrote into their `late final`s), which a
/// deduplicated archetype could not do unambiguously. Structural archetype
/// deduplication - one storage shared by every struct with the same field
/// set, so a query touches one contiguous page instead of N - is a real
/// optimization and is not attempted here.
class ArchetypeStorage {
  ArchetypeStorage._(
    this.archetypeId,
    this.pool,
    this.owner,
    this.assets,
    this.prefab,
  );

  /// Index into [ArchetypeRegistry]; packed into the top 16 bits of every
  /// `Entity` this storage hands out.
  final int archetypeId;

  final MemoryPool pool;

  /// The `SceneStruct` whose `describeScene` registered this archetype.
  ///
  /// Explicit, because the thing it replaced was not: this used to be
  /// inferred from [pool] identity - a scene owned its own pool, so "same
  /// pool" meant "same scene". The pool belongs to the `Game` now and is
  /// shared by every scene, so that inference is gone and the owner has to be
  /// recorded rather than derived. See [SceneStruct.addToSceneById], which is
  /// the check that depended on it.
  final SceneStruct owner;

  /// The asset table an object-valued field in this archetype resolves
  /// through. Held here rather than reached through [owner] because a row read
  /// is the hot path and `owner.game.assets` would be three dereferences and a
  /// throw-if-unbound getter; this is one field.
  final GameAssets assets;

  /// The single shared struct instance that describes this archetype -
  /// what `Entity.get<T>()` returns. It holds no per-entity state; its
  /// `DataPointer` fields are (field-offset, storage) pairs that take the
  /// `Entity` as an argument.
  final Component prefab;

  /// OR of [ComponentTypeRegistry.bitFor] over every type declared through
  /// `ComponentDescriptor.has<T>()` during this archetype's `describeType`
  /// pass. Consumed by the query system (not yet written).
  int componentSignature = 0;

  /// Bit-granular allocation cursor for [declareField]. Bits, not bytes -
  /// sub-byte fields are the point.
  int _bitCursor = 0;
  bool _sealed = false;

  final List<ArchetypeField> _fields = <ArchetypeField>[];
  /// Every page this archetype has ever been given, by index - and
  /// **nullable**, because unloading a scene frees its pages and nulls their
  /// slots rather than removing them. `Entity.pageIndex` is an index into this
  /// list, so compacting it would silently repoint every handle after the
  /// hole; a tombstone instead makes a stale handle resolve to nothing and say
  /// so. Indices are never reused.
  final List<MemoryPage?> _pages = <MemoryPage?>[];

  /// The page each loaded scene is currently filling, by `Scene.slot`.
  ///
  /// One cursor per scene instance, not one per archetype, and that is what
  /// makes a scene individually unloadable: rows belonging to two loaded
  /// instances of the same `SceneStruct` never share a page, so unloading one
  /// is "free the pages tagged with its slot" rather than a row-by-row
  /// reclamation that `Entity` has no spare bits to make safe.
  final Map<int, int> _currentPageBySlot = <int, int>{};

  /// A prototype row holding every field's declared default, built once at
  /// [seal] and memcpy'd into each newly allocated row. Rows get recycled
  /// (`MemoryPage.free`) and the triple buffer copies the previous tick
  /// forward, so a fresh row is *not* zeroed - stamping the prototype is
  /// what makes `hasUint8(7)` actually read back 7, and matches data.dart's
  /// "default value is stored to the memory pool during object creation,
  /// NOT accessed through `hasValue ? value : defaultValue`".
  Pointer<Uint8> _defaultRow = nullptr;

  /// Row size in bytes: the bit cursor rounded up to a whole byte.
  ///
  /// Floored at 1. A struct with no fields would otherwise produce a
  /// zero-stride page, which `MemoryPage.allocate` would happily hand out
  /// forever at offset 0 - every entity aliasing the same row, and
  /// `isFull` never becoming true.
  int get strideBytes {
    final bytes = (_bitCursor + 7) >> 3;
    return bytes == 0 ? 1 : bytes;
  }

  /// Total bits declared so far - the raw cursor, before the round-up in
  /// [strideBytes].
  int get bitLength => _bitCursor;

  bool get isSealed => _sealed;

  int get pageCount => _pages.length;

  /// The page an `Entity`'s `pageIndex` refers to. Plain list index; the
  /// per-field-access read/write path goes through here every time.
  /// The page at [index], or null if the scene that owned it has been
  /// unloaded - see [_pages].
  MemoryPage? pageAt(int index) => _pages[index];

  /// Appends a page this storage did **not** allocate - the mirror half of
  /// [allocateRow]'s `pool.allocatePage()`, used by a reading isolate that
  /// re-ran the same scene registration and now has to line its page list up
  /// with the writer's (see `MemoryPool.adoptPage` and `Game`'s page
  /// announcements).
  ///
  /// Correctness rests on one thing: the writer announces its pages in
  /// allocation order, one archetype at a time, and a `SendPort` preserves
  /// message order - so appending here reproduces the writer's list index
  /// for index, which is exactly what `Entity.pageIndex` addresses.
  @internal
  void adoptPage(MemoryPage page) => _pages.add(page);

  /// Frees every page belonging to the scene at [sceneSlot] and tombstones
  /// its slot. Called by `GameState.unloadScene`.
  ///
  /// Only the copy that allocated the pages may call this; the other holds
  /// views and must be told to drop them first (the un-adopt handshake,
  /// which does not exist yet - see `GameState.unloadScene`).
  @internal
  void releaseScene(int sceneSlot, MemoryPool pool) {
    for (var i = 0; i < _pages.length; i++) {
      final page = _pages[i];
      if (page == null || page.ownerSceneSlot != sceneSlot) continue;
      pool.freePage(page);
      _pages[i] = null;
    }
    _currentPageBySlot.remove(sceneSlot);
  }

  /// Reserves [bitWidth] bits and returns the field's **bit** offset from
  /// the start of the row.
  ///
  /// Two placement rules, both chosen so that no field ever spans a byte
  /// boundary:
  ///
  ///  * Sub-byte (`bitWidth` 1/2/4): packed into the current byte's
  ///    remaining bits if it fits, otherwise the cursor jumps to the next
  ///    byte first. Never straddling a byte keeps every access a single
  ///    byte load, a shift and a mask - no multi-byte assembly, no
  ///    endianness question.
  ///  * Byte-and-wider (8/16/32/64): the cursor is rounded up to a byte
  ///    boundary, then the field occupies whole bytes, accessed as one
  ///    `Pointer<Uint8>.cast<Uint32>()`-style load/store.
  ///
  /// Note "byte-aligned" is all this guarantees: a `hasFloat64` declared
  /// after a 1-bit flag lands at byte 1, and rows themselves start at
  /// multiples of [strideBytes], so wide fields are routinely *not*
  /// naturally aligned. That is intentional - natural alignment would cost
  /// both intra-row padding and stride padding, and normal (non-atomic)
  /// loads and stores tolerate unaligned addresses on every architecture
  /// this engine targets (x64, ARM64), at worst a small penalty when a
  /// value straddles a cache line. Revisit with alignment padding if
  /// profiling ever shows it; do not assume it is required for
  /// correctness. (`test/data_layout_test.dart` round-trips a
  /// deliberately-misaligned float64 to keep this honest.)
  int declareField(int bitWidth) {
    if (_sealed) {
      throw StateError(
        'ArchetypeStorage for ${prefab.runtimeType} is sealed - fields can '
        'only be declared during its one-time describeStruct pass.',
      );
    }
    switch (bitWidth) {
      case 1:
      case 2:
      case 4:
      case 8:
      case 16:
      case 32:
      case 64:
        break;
      default:
        throw ArgumentError.value(
          bitWidth,
          'bitWidth',
          'must be 1, 2, 4, 8, 16, 32 or 64 bits',
        );
    }
    if (bitWidth >= 8 || (_bitCursor & 7) + bitWidth > 8) {
      _bitCursor = (_bitCursor + 7) & -8; // round up to the next byte
    }
    final bitOffset = _bitCursor;
    _bitCursor += bitWidth;
    return bitOffset;
  }

  /// Registers a field so its default gets stamped into every new row. The
  /// `DataDescriptor` implementation calls this once per declared field;
  /// note a nullable field registers only its wrapper, not the inner value
  /// field, so the has-bit decides whether the value default is written at
  /// all.
  void registerField(ArchetypeField field) {
    if (_sealed) {
      throw StateError('ArchetypeStorage for ${prefab.runtimeType} is sealed.');
    }
    _fields.add(field);
  }

  /// Freezes the layout and builds the default-row prototype. Called once,
  /// right after `describeStruct` returns.
  void seal() {
    if (_sealed) return;
    _sealed = true;
    _defaultRow = calloc<Uint8>(strideBytes);
    for (final field in _fields) {
      field.writeDefault(_defaultRow);
    }
  }

  /// Allocates one row and returns the packed handle addressing it.
  ///
  /// Returns an `Entity` rather than the `(pageIndex, rowOffset)` record
  /// the caller might expect: `Entity` is an extension type over `int`, so
  /// this is a plain integer return with no heap traffic, whereas a record
  /// allocates. Spawning happens inside `onFixedUpdate`/game events, which
  /// RULES.md rule 2 classifies as hot path, so a per-spawn allocation is
  /// exactly what rule 1 forbids. The storage already knows its own
  /// [archetypeId], so packing here rather than at the call site costs
  /// nothing.
  ///
  /// Grows by asking [pool] for a fresh page only when the current page
  /// reports `isFull` - `MemoryPool.allocatePage()` never searches, because
  /// pages are stride-locked and "any page with room" is not a safe answer
  /// for a specific archetype's row size. Note a page that filled up and
  /// later had rows freed is not revisited: recycling across an
  /// archetype's older pages lands with the despawn API, which does not
  /// exist yet.
  /// [sceneSlot] is the `Scene.slot` of the loaded scene this row belongs to,
  /// and it decides which *page group* the row lands in - see
  /// [_currentPageBySlot]. Pass -1 for a row outside any scene.
  Entity allocateRow(int sceneSlot) {
    if (!_sealed) {
      throw StateError(
        'ArchetypeStorage for ${prefab.runtimeType} has no layout yet - it '
        'must be registered through SceneDescriptor.has() before entities '
        'can be created from it.',
      );
    }
    var current = _currentPageBySlot[sceneSlot] ?? -1;
    if (current < 0 || _pages[current] == null || _pages[current]!.isFull) {
      if (_pages.length >= 0x10000) {
        throw StateError(
          'Archetype ${prefab.runtimeType} has exhausted the 65536 pages an '
          "Entity's 16-bit page index can address.",
        );
      }
      _pages.add(
        pool.allocatePage(
          ownerArchetypeId: archetypeId,
          ownerSceneSlot: sceneSlot,
        ),
      );
      current = _pages.length - 1;
      _currentPageBySlot[sceneSlot] = current;
    }
    final page = _pages[current]!;
    final stride = strideBytes;
    final rowOffset = page.allocate(stride);

    // Byte loops rather than `asTypedList(...).setAll(...)`: the typed-list
    // view is itself a heap object, and this runs once per spawn.
    final row = page.resolveWrite(rowOffset);
    for (var i = 0; i < stride; i++) {
      row[i] = _defaultRow[i];
    }

    // A new row is stamped into the *published* snapshot as well, not just
    // this tick's write slot. Two bugs, both silent, both caught by
    // test/archetype_test.dart's 'a fresh row' cases:
    //
    //  1. Spawning outside a tick window lost the defaults entirely - the
    //     next `beginTick` copies the published slot over the write slot,
    //     erasing everything written before it.
    //  2. Reading a just-spawned entity resolved through `resolveRead`, so
    //     it saw whatever the previous tenant of that offset left behind
    //     instead of the declared defaults - `hasUint8(7)` read 0 until the
    //     following tick.
    //
    // Writing into a slot readers may be holding is safe *for this row
    // specifically*: the row was either never used or was freed, so no
    // live `Entity` anywhere addresses it. A reader still holding a handle
    // to a freed row is already reading a dead entity, which no snapshot
    // discipline can fix.
    final published = page.resolveRead(rowOffset);
    if (published != null) {
      for (var i = 0; i < stride; i++) {
        published[i] = _defaultRow[i];
      }
    }
    return Entity.pack(archetypeId, current, rowOffset);
  }

  void _dispose() {
    if (_defaultRow != nullptr) {
      calloc.free(_defaultRow);
      _defaultRow = nullptr;
    }
  }
}

/// A field that knows how to stamp its declared default into a raw row.
///
/// Declared here rather than in the data-layout implementation so
/// [ArchetypeStorage] can hold the field list without depending on the
/// `DataDescriptor` implementation (the dependency runs the other way).
abstract interface class ArchetypeField {
  void writeDefault(Pointer<Uint8> row);
}
