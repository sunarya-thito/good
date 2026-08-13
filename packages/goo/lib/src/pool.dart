import 'dart:ffi';
import 'package:goo/src/triple_buffer.dart';

// Shared memory pool across isolates.
//
// The game isolate runs fixed-tick ECS systems (physics, gameplay logic)
// against this pool; the main isolate (and, per the project root plan's
// "Cross-isolate architecture" section, any other isolate holding a
// reference) reads component data directly out of it - no message passing,
// no copying, just a raw pointer into native memory (the mechanism proven
// in bin/ffi_shared_memory_poc.dart).
//
// Only the game isolate is ever allowed to write. Each page's storage is a
// TripleBuffer (see triple_buffer.dart) rather than the 2-state toggle this
// class originally had - that fixed the tearing race this file used to flag
// as an unsolved TODO: a reader could observe a buffer mid-write the
// instant a swap landed between its check and its use of the pointer.
//
// Publishing is tick-scoped, not per-allocation: the game isolate calls
// beginTick() once at the start of a fixed tick (copying each page's last
// published bytes forward so in-place mutations like
// `transformOffsetX[instance] += 1` see last tick's values), runs all
// systems (which call MemoryPage.allocate/free as entities are
// created/destroyed and mutate DataPointer fields in place), then calls
// commitTick() once at the end to publish every page's new snapshot
// atomically-per-page.
//
// Each page is stride-locked to a single row size on its first allocate()
// call - one page stores rows for exactly one archetype/component-set, so
// a page never needs to track per-row metadata beyond "used or free".
class MemoryPool {
  MemoryPool({this.pageSize = _defaultPageSize, this.maxPages = _defaultPoolSize});

  // 64 megabyte default page size.
  static const int _defaultPageSize = 64 * 1024 * 1024;
  // 128 default pages pool.
  static const int _defaultPoolSize = 128;

  final int pageSize;
  final int maxPages;

  /// Allocated pages by index, **tombstoned rather than removed** when one is
  /// freed.
  ///
  /// The index is an identity, not a position: `Game._announceNewPages` walks
  /// this list with a monotonic cursor so the reading isolate adopts pages in
  /// the same order, and compacting it would make that cursor re-announce or
  /// skip. `ArchetypeStorage._pages` tombstones for the same class of reason
  /// (`Entity.pageIndex` indexes *it*), so the two agree by construction.
  final List<MemoryPage?> _pages = [];

  int get pageCount => _pages.length;

  bool _tickOpen = false;

  /// Whether a tick's write pass is currently open - true between
  /// [beginTick] and [commitTick].
  ///
  /// Exists because writing outside that window is silent data loss, not a
  /// crash: [beginTick] copies each page's last published bytes over the
  /// write slot, so anything written before it lands is overwritten a
  /// moment later. Debug assertions on the write path (see
  /// `data_layout.dart`) use this to turn that into a loud failure. It is
  /// only meaningful in the writing isolate.
  bool get isTickOpen => _tickOpen;

  /// Read-oriented lookup by index (the order pages were allocated in) -
  /// expects the caller not to call `MemoryPage.allocate()`/`free()` on the
  /// result. Throws if [page] hasn't been allocated yet.
  MemoryPage? getPage(int page) => _pages[page];

  /// Always allocates a brand-new page (up to [maxPages]) - never searches
  /// for an existing non-full one. Deliberately dumb: since every page gets
  /// stride-locked to whichever archetype's row size calls `allocate()` on
  /// it first, "any non-full page" isn't a safe answer to "give me space
  /// for archetype X's rows" - a page some other archetype already
  /// stride-locked would just reject a mismatched size. Reusing space
  /// across an archetype's *own* pages is `ArchetypeStorage`'s job (see
  /// archetype.dart) - it keeps its own page list and only calls this when
  /// none of its own pages have room.
  ///
  /// [ownerArchetypeId] is carried purely so the page can be announced to a
  /// reading isolate later (see [MemoryPage.ownerArchetypeId]); this pool
  /// never interprets it.
  MemoryPage allocatePage({
    int ownerArchetypeId = -1,
    int ownerSceneSlot = -1,
  }) {
    if (_pages.length >= maxPages) {
      throw StateError('MemoryPool exhausted: all $maxPages pages are allocated');
    }
    final page = MemoryPage._(pageSize, ownerArchetypeId, ownerSceneSlot);
    _pages.add(page);
    return page;
  }

  /// Adds a read-only *view* of a page some other isolate allocated, from
  /// the addresses that page published (see [MemoryPage.latestAddress] /
  /// [MemoryPage.slotAddresses]).
  ///
  /// This is the pool half of the cross-isolate handoff `Game` performs:
  /// pages are allocated lazily, by the writing isolate, long after the
  /// spawn message has been copied - so a reader can't be handed the whole
  /// pool up front. Instead the writer announces each new page as it
  /// appears and the reader adopts it here, in the same order, so page
  /// indices line up on both sides.
  ///
  /// The returned page knows nothing about row occupancy - [MemoryPage]'s
  /// stride, high-water mark and free list are writer-local Dart state, not
  /// shared memory. An adopted page therefore supports [MemoryPage.resolveRead]
  /// (resolving an `Entity` handle the reader was told about) and nothing
  /// else: no `allocate`, no `rowOffsets`, no queries. It also never frees
  /// the memory it points at - the allocating pool owns that.
  MemoryPage adoptPage({
    required int ownerArchetypeId,
    required int latestAddress,
    required List<int> slotAddresses,
    int ownerSceneSlot = -1,
  }) {
    final page = MemoryPage._adopted(
      pageSize,
      ownerArchetypeId,
      ownerSceneSlot,
      latestAddress,
      slotAddresses,
    );
    _pages.add(page);
    return page;
  }

  /// Starts a fixed tick's write pass across every page - see the class
  /// doc above. Call once, before any system runs.
  void beginTick() {
    _tickOpen = true;
    for (final page in _pages) {
      page?._buffer.beginWrite();
    }
  }

  /// Publishes every page's write slot as this tick's readable snapshot.
  /// Call once, after every system has finished writing.
  void commitTick() {
    for (final page in _pages) {
      page?._buffer.publish();
    }
    _tickOpen = false;
  }

  /// Frees one page and drops it from this pool.
  ///
  /// The per-scene half of [dispose]: unloading a `Scene` frees exactly the
  /// pages tagged with its slot, and leaves every other page - and therefore
  /// every live `Entity` handle into them - untouched. The pool's own list is
  /// compacted, but `ArchetypeStorage` **tombstones** its slot instead of
  /// removing it, because `Entity.pageIndex` is an index into *that* list and
  /// shifting it would silently repoint every handle after the hole.
  void freePage(MemoryPage page) {
    final index = _pages.indexOf(page);
    if (index < 0) return;
    // Tombstoned, not removed - see [_pages]. `dispose` is a no-op on an
    // adopted page, so the reading isolate drops its view through the same
    // call the writing isolate frees through.
    _pages[index] = null;
    page.dispose();
  }

  void dispose() {
    for (final page in _pages) {
      page?.dispose();
    }
    _pages.clear();
  }
}

class MemoryPage {
  MemoryPage._(int capacity, this.ownerArchetypeId, this.ownerSceneSlot)
    : _buffer = TripleBuffer(capacity),
      _capacity = capacity,
      _ownsMemory = true;

  MemoryPage._adopted(
    int capacity,
    this.ownerArchetypeId,
    this.ownerSceneSlot,
    int latestAddress,
    List<int> slotAddresses,
  ) : _buffer = TripleBuffer.fromAddresses(
        slotBytes: capacity,
        latestAddress: latestAddress,
        slotAddresses: slotAddresses,
      ),
      _capacity = capacity,
      _ownsMemory = false;

  final TripleBuffer _buffer;
  final int _capacity;

  /// Which loaded [Scene] this page's rows belong to, as `Scene.slot`, or -1
  /// for a page allocated outside any scene.
  ///
  /// This is what makes a scene individually unloadable. Rows of one archetype
  /// from two loaded instances of the same `SceneStruct` never share a page,
  /// so unloading one instance is "free every page tagged with its slot" -
  /// no row-by-row reclamation, and no generation counter on `Entity`, which
  /// has no spare bits for one.
  final int ownerSceneSlot;

  /// The `ArchetypeStorage.archetypeId` that asked [MemoryPool.allocatePage]
  /// for this page, or -1 if it was allocated without one.
  ///
  /// Not used for anything on the writing side - the archetype already knows
  /// its own pages. It exists so a page announcement crossing to a reading
  /// isolate can say *which* archetype's page list to append the adopted
  /// view to, which is what keeps `Entity.pageIndex` resolving to the same
  /// page on both sides.
  final int ownerArchetypeId;

  /// False for a page adopted from another isolate (see
  /// [MemoryPool.adoptPage]) - such a page must never free the memory it
  /// points at, and cannot allocate rows.
  final bool _ownsMemory;

  int get capacityBytes => _capacity;

  /// The addresses another isolate needs to reconstruct a read-only view of
  /// this page via [MemoryPool.adoptPage] - the same raw-address handoff
  /// `TripleBuffer.fromAddresses`/`RingBuffer.fromAddresses` use.
  int get latestAddress => _buffer.latestAddress;
  List<int> get slotAddresses => _buffer.slotAddresses;

  int? _strideBytes;
  int _writeOffset = 0;
  final Set<int> _freeOffsets = {};

  bool get isFull =>
      _strideBytes != null && _freeOffsets.isEmpty && _writeOffset + _strideBytes! > _capacity;

  /// The row stride locked in by this page's first [allocate] call, or
  /// `null` if nothing has been allocated yet. The query system (see
  /// system.dart) needs this to step through [rowOffsets].
  int? get strideBytes => _strideBytes;

  /// The bump-allocation high-water mark: every offset below this that
  /// isn't in the free set holds a live row. Offsets at or above this were
  /// never allocated.
  int get highWaterMark => _writeOffset;

  /// Whether the row at [offset] is currently allocated (not freed). O(1) -
  /// the free list is a `Set` specifically so the query system can afford
  /// to call this once per candidate row while iterating a page.
  bool isLive(int offset) => !_freeOffsets.contains(offset);

  /// Every currently-live row offset in this page, in ascending order -
  /// what the query system walks to find matching entities. Lazy: does not
  /// allocate a list, just steps `highWaterMark ~/ strideBytes` candidates
  /// and skips freed ones.
  Iterable<int> get rowOffsets sync* {
    final stride = _strideBytes;
    if (stride == null) return; // nothing ever allocated
    for (var offset = 0; offset < _writeOffset; offset += stride) {
      if (!_freeOffsets.contains(offset)) yield offset;
    }
  }

  /// Allocates one row of [size] bytes, returning its **offset** within the
  /// page - not a raw pointer. The underlying triple-buffer slot rotates
  /// every tick (see [MemoryPool.beginTick]/[MemoryPool.commitTick]), so a
  /// raw address is only valid for the tick it was resolved in; the offset
  /// is stable for the row's lifetime. This is exactly what `Entity`/
  /// `DataPointer` store and re-resolve each tick via [resolveWrite]/
  /// [resolveRead]. Prefers a recycled row from [free] over growing the
  /// page. Every call on a given page must pass the same [size] - see the
  /// class doc.
  int allocate(int size) {
    if (!_ownsMemory) {
      throw StateError(
        'MemoryPage was adopted from another isolate (see '
        'MemoryPool.adoptPage) - only the isolate that allocated it may '
        'create rows in it.',
      );
    }
    _strideBytes ??= size;
    if (size != _strideBytes) {
      throw ArgumentError(
        'MemoryPage is locked to a $_strideBytes byte stride (set by its '
        'first allocate() call); got $size. Each page stores rows for one '
        'archetype/component-set - use a different page for a different '
        'struct layout.',
      );
    }
    if (_freeOffsets.isNotEmpty) {
      final offset = _freeOffsets.first;
      _freeOffsets.remove(offset);
      return offset;
    }
    if (_writeOffset + size > _capacity) {
      throw StateError('MemoryPage is full ($_capacity bytes, stride $_strideBytes)');
    }
    final offset = _writeOffset;
    _writeOffset += size;
    return offset;
  }

  /// Recycles the row at [offset] (as returned by [allocate]) for reuse by
  /// a future [allocate] call on this page.
  void free(int offset) => _freeOffsets.add(offset);

  /// Whether this page has ever been published - i.e. whether
  /// [resolveRead] returns a slot, and whether the next
  /// [MemoryPool.beginTick] will copy anything over the write slot.
  bool get hasPublished => _buffer.hasPublished;

  /// This tick's write-slot address for the row at [offset] - cheap, call
  /// as many times as needed per tick (once per field access). Only valid
  /// after [MemoryPool.beginTick] has run for the current tick.
  Pointer<Uint8> resolveWrite(int offset) => _buffer.writeView + offset;

  /// The latest **published** snapshot's address for the row at [offset] -
  /// `null` before the first [MemoryPool.commitTick]. Safe to call from any
  /// isolate holding this page, including read-only ones (the main/UI
  /// isolate per the project root plan's "Cross-isolate architecture"
  /// section, lane 1).
  Pointer<Uint8>? resolveRead(int offset) {
    final latest = _buffer.latestView();
    return latest == null ? null : latest + offset;
  }

  /// Frees this page's native memory - a no-op for an adopted page, which
  /// only holds addresses into another isolate's allocation.
  void dispose() {
    if (_ownsMemory) _buffer.dispose();
  }
}
