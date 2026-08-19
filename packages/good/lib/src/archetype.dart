import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'package:good/src/pool.dart';
import 'package:good/src/struct.dart';

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

  // This used to carry a `snapshot`/`restore` pair, and so did
  // `ArchetypeRegistry`, `HeapObjectRegistry` and `SceneRegistry`. Static
  // state is **per isolate** - it belongs to no object graph, so
  // `Isolate.spawn`'s deep copy does not bring it - and while the main isolate
  // ran the declaration passes it had to hand each table over explicitly for
  // the spawned copy to adopt.
  //
  // Nothing carries them now: the passes that fill these tables run on the
  // game isolate, which is also the only copy that reads them. Main's stay
  // empty for the life of the game. See `Game._bootGame`.

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

  /// Pages one archetype can hold, from `Entity`'s 16-bit page index.
  ///
  /// A limit on **churn**, not on volume. A 64 MiB page at a 128-byte stride
  /// holds around half a million rows, so this is tens of billions of
  /// entities - unreachable. But page indices are deliberately never recycled
  /// (a live `Entity` keeps addressing the right page, see [_pages]), and
  /// every scene load takes a fresh page per archetype it uses. So a game that
  /// streams rooms for long enough reaches it by loading and unloading, and
  /// the failure without a guard is silent: the index wraps and an `Entity`
  /// starts addressing somebody else's page.
  static const int maxPagesPerArchetype = 0x10000;

  static final List<ArchetypeStorage> _storages = <ArchetypeStorage>[];

  static int get count => _storages.length;

  /// Creates and registers storage for one archetype whose prefab does not
  /// exist yet.
  ///
  /// `SceneDescriptor.has` builds the prefab by calling its constructor, and
  /// the constructor's field initialisers declare columns - so the storage
  /// they declare into has to exist first. The prefab is attached with
  /// [ArchetypeStorage.bindPrefab] the moment construction returns, before
  /// anything can read it.
  static ArchetypeStorage reserve(MemoryPool pool) {
    if (_storages.length >= maxArchetypes) {
      throw StateError(
        'ArchetypeRegistry is full: $maxArchetypes archetypes have been '
        'registered, which is all a 16-bit archetype id can address (see '
        'Entity.pack). Archetype ids are process-global and are not '
        'recycled on scene unload.',
      );
    }
    final storage = ArchetypeStorage._(_storages.length, pool);
    _storages.add(storage);
    return storage;
  }

  /// [reserve] plus [ArchetypeStorage.bindPrefab], for a caller that already
  /// holds the prefab.
  static ArchetypeStorage register(MemoryPool pool, EntityStruct prefab) =>
      reserve(pool)..bindPrefab(prefab);

  /// Resolves an archetype id - the hot path behind `Entity.get<T>()`. A
  /// plain list index, no map, no allocation.
  @pragma('vm:prefer-inline')
  static ArchetypeStorage byId(int archetypeId) {
    if (archetypeId < 0 || archetypeId >= _storages.length) {
      throw StateError(
        _storages.isEmpty
            // Overwhelmingly the interesting case, and worth naming outright:
            // this is what a main-isolate component read looks like from here.
            // Main declares and allocates; it registers no archetypes, holds
            // no pages and resolves no `Entity`. Data reaches it through a
            // `StateChannel` or a draw buffer, never by reading a row.
            ? 'no archetypes are registered on this isolate, so Entity '
                  '$archetypeId cannot be resolved. Reading component data is a '
                  'game-isolate act: the main copy is presentation-only, and its '
                  'registries stay empty by design. Publish the value through a '
                  'StateChannel (Game.describeState) and read that instead.'
            : 'no archetype with id $archetypeId - ${_storages.length} are '
                  'registered. An `Entity` from a different process, or one '
                  'built by hand, does not resolve here.',
      );
    }
    return _storages[archetypeId];
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
  ArchetypeStorage._(this.archetypeId, this.pool);

  /// Index into [ArchetypeRegistry]; packed into the top 16 bits of every
  /// `Entity` this storage hands out.
  final int archetypeId;

  final MemoryPool pool;

  // --- the resolved-row cache ---------------------------------------------
  //
  // A query walks rows page by page, so consecutive accesses almost always hit
  // the same page - and every field access was independently redoing
  // `pageAt` -> `resolveRow` -> `readView` to discover that. The profile put
  // that chain at ~14% of all CPU even after inlining.
  //
  // Keyed by (epoch, pageIndex): the epoch catches the bases moving under us
  // (see `MemoryPool.epoch`), the page index catches crossing a page boundary.
  // Two int compares replace the walk, and user code does not change at all -
  // `field[entity]` is still `field[entity]`.
  //
  // The two bases are held as **`int` addresses, not `Pointer<Uint8>`**, and
  // that is a performance decision rather than a stylistic one. `Pointer` is a
  // real Dart object, so a field holding one is a boxed reference: every field
  // access loaded the box, unboxed it, and allocated a *fresh* `Pointer` for
  // `+ rowOffset` before the accessor allocated two more for its own offset and
  // cast. `tool/column_dispatch_bench.dart` isolates it - the identical
  // accessor shape costs 14.63ns/access reading through a `Pointer` field and
  // 2.25ns reading through an `int` one, with the generic megamorphic
  // `DataPointer` dispatch left in place. Addresses stay stable because the
  // memory is native (`calloc`), never GC-relocated, and `epoch` already
  // catches the bases actually moving.
  int _cacheEpoch = -1;
  int _cachePage = -1;
  late MemoryPage _cachedPage;
  late int _cacheRead;
  late int _cacheWrite;

  /// The stale-handle diagnostic. Same failure `data_layout`'s row guard
  /// reported before the cache existed: an `Entity` has no generation bits, so
  /// the only way to catch a handle that outlived its scene is to notice the
  /// page it names has been tombstoned.
  Never _staleRow(Entity entity) => throw StateError(
    'Entity ${entity.value} names page ${entity.pageIndex} of archetype '
    '$archetypeId (${prefab.runtimeType}), and that page has been freed - '
    'the scene that owned it was unloaded. The handle outlived its world; '
    'nothing here can be read or written through it.',
  );

  /// Re-resolves the cached page. Cold path: once per page per epoch.
  void _refreshRowCache(int pageIndex, Entity entity) {
    final page = pageAt(pageIndex) ?? _staleRow(entity);
    _cachedPage = page;
    _cacheRead = page.resolveRow(0).address;
    _cacheWrite = page.resolveWrite(0).address;
    _cachePage = pageIndex;
    _cacheEpoch = pool.epoch;
  }

  /// The page the cache currently holds - for the write-path assertion, which
  /// needs to ask whether anything has been published yet.
  @internal
  MemoryPage get cachedPage => _cachedPage;

  @internal
  @pragma('vm:prefer-inline')
  /// The **address** of [entity]'s published row, not a `Pointer` - see the
  /// cache fields above for why.
  int rowRead(Entity entity) {
    final index = entity.pageIndex;
    if (_cacheEpoch != pool.epoch || _cachePage != index) {
      _refreshRowCache(index, entity);
    }
    return _cacheRead + entity.rowOffset;
  }

  @internal
  @pragma('vm:prefer-inline')
  /// The **address** of [entity]'s write-slot row. See [rowRead].
  int rowWrite(Entity entity) {
    final index = entity.pageIndex;
    if (_cacheEpoch != pool.epoch || _cachePage != index) {
      _refreshRowCache(index, entity);
    }
    return _cacheWrite + entity.rowOffset;
  }

  // There is no `owner` field recording the registering `SceneStruct`. There
  // was one, read in exactly one place - the spawn-by-archetype-id path, now
  // deleted - and it was the same fact as `prefab.scene` stored a second time
  // (the one-fact-one-place rule). `SceneStruct.addEntityIn` checks
  // `prefab.scene`, which is the one home for it.

  // There is no `assets` field either. It existed for exactly one reason -
  // an object-valued field read had no other way to reach a table - and that
  // reason is gone: `hasObject`/`optObject` now take their `ObjectTable` at
  // the declare site and each field holds its own. Keeping it would have made
  // assets the one privileged population, which is the thing `ObjectTable`
  // exists to stop.

  /// The single shared struct instance that describes this archetype -
  /// what `Entity.get<T>()` returns. It holds no per-entity state; its
  /// `DataPointer` fields are (field-offset, storage) pairs that take the
  /// `Entity` as an argument.
  ///
  /// `late` because the storage outlives its own creation by a few
  /// statements: the prefab's field initialisers declare columns into this
  /// storage, so it exists first and is handed the prefab immediately after -
  /// see [ArchetypeRegistry.reserve]. Nothing reads it in between.
  late final EntityStruct prefab;

  /// Attaches the prefab whose construction declared this storage's columns.
  /// Called once, by `SceneDescriptor.has`, the statement after the
  /// constructor returns.
  @internal
  void bindPrefab(EntityStruct struct) => prefab = struct;

  /// OR of [ComponentTypeRegistry.bitFor] over every type declared through
  /// `ComponentDescriptor.has<T>()` during this archetype's `describeType`
  /// pass. Consumed by the query system (not yet written).
  int componentSignature = 0;

  /// Bit-granular allocation cursor for [declareField]. Bits, not bytes -
  /// sub-byte fields are the point.
  int _bitCursor = 0;

  /// Bits [declareField]'s byte-rounding skipped over, in bytes the cursor
  /// has already moved past. They are unreachable through the cursor - it
  /// only ever moves forward - so without this list they stay stranded for
  /// the life of the archetype. Only [declareFlagBit] draws on them, which
  /// is what keeps handing one out safe: a value field's placement still
  /// comes from the cursor alone, so no two fields can be given the same
  /// bit, and [declareField]'s stated rule is unchanged.
  final List<int> _strandedBits = <int>[];

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
  @pragma('vm:prefer-inline')
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
  void adoptPage(MemoryPage page) {
    // The same bound as the allocating side, for the same reason: this list
    // is what `Entity.pageIndex` addresses, and a reader that silently wrapped
    // would resolve handles to the wrong page while the writer was still
    // correct - a divergence between the two copies, which is worse than
    // either failing alone.
    if (_pages.length >= ArchetypeRegistry.maxPagesPerArchetype) {
      throw StateError(
        'Archetype ${prefab.runtimeType} cannot adopt another page: the '
        "${ArchetypeRegistry.maxPagesPerArchetype} an Entity's 16-bit page "
        'index can address are all taken.',
      );
    }
    _pages.add(page);
  }

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
  ///
  /// Rounding up records the bits it skipped in [_strandedBits], which is
  /// where [declareFlagBit] gets them from. That is a side effect of calling
  /// this, not a change to what it returns - the offset handed back is still
  /// the cursor's, and the cursor still only moves forward.
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
      final rounded = (_bitCursor + 7) & -8; // round up to the next byte
      for (var bit = _bitCursor; bit < rounded; bit++) {
        _strandedBits.add(bit);
      }
      _bitCursor = rounded;
    }
    final bitOffset = _bitCursor;
    _bitCursor += bitWidth;
    return bitOffset;
  }

  /// Reserves one bit for an optional field's presence flag, preferring a
  /// bit [declareField]'s rounding stranded over extending the row.
  ///
  /// A presence flag is the one field that can take a leftover bit without
  /// the caller arranging anything: it is declared by the descriptor itself,
  /// immediately before its value, so nothing outside `data_layout.dart`
  /// depends on where it lands. Value fields keep coming from the cursor, so
  /// the row still grows in declaration order and every offset is still
  /// derived from that order alone - both isolates build the same layout.
  ///
  /// Without this, each optional field wider than a byte costs a whole byte
  /// for its flag: the flag takes bit 0 of a fresh byte, then the value's
  /// rounding jumps past the other seven. Five `optEntity` fields (what a
  /// `Child` + `Parent` archetype declares) stranded five bytes that way,
  /// four of which nothing could reach. Recycling makes the flags share one
  /// byte no matter which mixin declared them, which matters because
  /// separate mixins cannot order their declarations relative to each other.
  int declareFlagBit() {
    if (_sealed) {
      throw StateError(
        'ArchetypeStorage for ${prefab.runtimeType} is sealed - fields can '
        'only be declared during its one-time describeStruct pass.',
      );
    }
    // Oldest first, so flags gather in the earliest byte that has room
    // rather than scattering backwards through the row.
    if (_strandedBits.isNotEmpty) return _strandedBits.removeAt(0);
    return declareField(1);
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
      field.writeDefault(_defaultRow.address);
    }
  }

  /// Allocates one row and returns the packed handle addressing it.
  ///
  /// Returns an `Entity` rather than the `(pageIndex, rowOffset)` record
  /// the caller might expect: `Entity` is an extension type over `int`, so
  /// this is a plain integer return with no heap traffic, whereas a record
  /// allocates. Spawning happens inside `onFixedUpdate`/game events, which
  /// the hot-path rules classifies as hot path, so a per-spawn allocation is
  /// exactly what rule 1 forbids. The storage already knows its own
  /// [archetypeId], so packing here rather than at the call site costs
  /// nothing.
  ///
  /// Grows by asking [pool] for a fresh page only when *no* page belonging to
  /// this scene slot has room. `MemoryPool.allocatePage()` still never searches
  /// - pages are stride-locked and "any page with room" is not a safe answer
  /// for a specific archetype's row size - so the search lives here, where the
  /// stride and the owning slot are both known.
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
      // Before opening a *new* page, look for an existing one with room.
      //
      // This cursor only ever moved forward, and that was a permanent leak:
      // once a page bump-filled, the next allocation made a fresh page current
      // and the old one was never allocated from again - so every row later
      // freed in it was stranded for the life of the process. Population stayed
      // flat while the walked extent grew without bound, which made every
      // `beginTick` memcpy (it copies `page.highWaterMark`, see
      // `MemoryPool.beginTick`) and every query walk get steadily more
      // expensive. Measured in `goo2d/tool/churn_bench.dart`: 22.5k live
      // entities against 201k walked rows after 600 ticks, per-tick cost
      // climbing 4.5ms -> 10.2ms and still rising.
      //
      // Only pages belonging to this scene slot qualify - a page is released
      // when *its* scene unloads (see `releaseScenePages`), so lending one to
      // another scene's entities would free rows still in use.
      //
      // The scan is O(pages) but runs only when the current page is full,
      // which is exactly the path that was about to do the far more expensive
      // thing of mapping fresh memory.
      var reused = -1;
      for (var i = 0; i < _pages.length; i++) {
        final candidate = _pages[i];
        if (candidate != null &&
            candidate.ownerSceneSlot == sceneSlot &&
            !candidate.isFull) {
          reused = i;
          break;
        }
      }
      if (reused >= 0) {
        _currentPageBySlot[sceneSlot] = reused;
        current = reused;
      } else {
        if (_pages.length >= ArchetypeRegistry.maxPagesPerArchetype) {
          throw StateError(
            'Archetype ${prefab.runtimeType} has exhausted the '
            "${ArchetypeRegistry.maxPagesPerArchetype} pages an Entity's "
            '16-bit page index can address. This is a limit on scene '
            'load/unload churn rather than on entity count: page indices are '
            'never recycled, so every load takes a fresh one. If a game '
            'legitimately gets here, the fix is recycling indices behind a '
            'generation counter, not a bigger page.',
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
  /// Stamps this field's default into the row at **address** [row]. An `int`
  /// rather than a `Pointer<Uint8>` to match the read/write path - see
  /// `ArchetypeStorage`'s row-cache fields for why addresses beat pointers
  /// here. This particular call is cold (once per archetype, in [seal]); it
  /// takes an address purely so field implementations have one row-addressing
  /// convention rather than two.
  void writeDefault(int row);
}
