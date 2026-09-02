import 'dart:ffi';

import 'package:meta/meta.dart';
import 'package:good/src/triple_buffer.dart';

// --- on porting this to the web -----------------------------------------
//
// Web is not a target today, but the seam is worth stating while it is still
// true, because the cost of keeping it open is zero and the cost of finding it
// closed later is not.
//
// **No native function is ever called.** There are no FFI bindings, no
// structs, no `DynamicLibrary`, no native library to build. Every use of
// `dart:ffi` in this package is one of four things:
//
//   * `calloc<Uint8|Int32|Uint64|Float>(n)` - 8 sites, all "give me N zeroed
//     bytes": archetype.dart, camera_view.dart, handoff_buffer.dart (x2),
//     ring_buffer.dart (x2), triple_buffer.dart (x2).
//   * `calloc.free(p)` - 9 sites, the matching release.
//   * `.address` / `Pointer.fromAddress` - naming a block with an int, which
//     is the only form in which an allocation crosses `Isolate.spawn`.
//   * `.asTypedList(n)` / `.cast<T>()` - a view over those bytes.
//
// That is exactly what a `Uint8List` already does. A web port replaces the
// allocator with one big growable buffer and makes an "address" an offset into
// it; every read and write in this engine is already expressed as a byte
// offset from a block base, so the arithmetic above the seam does not change.
//
// What would need care is `data_layout.dart` (32 of the ~69 raw `Pointer<>`
// mentions), because that is the hot read/write path and an extra indirection
// there is the one place it would be measurable. The rest is spelling.
//
// The other half is already handled: `Game.start` runs the **inline**
// configuration on the web (one copy doing both jobs, no `Isolate.spawn`), and
// that path is what 39 of the 48 test bring-ups exercise. See
// `GameRuntime.drivable` for why it is still not allowed to hand out the world.

/// Which kind of handler is running with no tick window open, if any.
///
/// Two command lanes run user code outside `beginTick`/`commitTick`: the
/// receipt-delivered one, dispatched from a control-port callback
/// (`CommandDescriptor.hasControlSink`), and the read-only one, drained once
/// per frame from `GameState.advance` (`hasReadOnlyHandler`). Both told the
/// caller not to write and neither could check it - a component write was
/// erased by the next tick with an `assert` that a release build compiles out,
/// and adding an entity, writing a `StateChannel` and unloading a scene were
/// not guarded at all (#245).
///
/// `CommandTransport` opens the matching window around the dispatch and puts
/// the previous one back after. `MemoryPool` is where it lives because the
/// pool already answers the neighbouring question - see
/// [MemoryPool.isTickOpen] - and because it is the one object every write path
/// in the engine already holds.
enum HandlerWindow {
  /// No out-of-tick handler is running: the ordinary state, and the one the
  /// engine's own bring-up and teardown run in.
  none('', ''),

  /// A receipt-delivered handler - `hasControlSink`, `hasControlSignal`.
  ///
  /// It may not touch the world. It may still publish on a `StateChannel`,
  /// which is the answer leg it has instead of a reply.
  receipt(
    'receipt-delivered',
    'Register the part that changes the world with hasSink or hasHandler, '
        'which are delivered inside the tick; keep hasControlSink for the '
        'part that has to work while the tick is stopped.',
  ),

  /// A read-only handler - `hasReadOnlyHandler`, `hasReadOnlySupplier`.
  ///
  /// It may not write anything at all, a `StateChannel` included: it has a
  /// reply leg to answer through, so a write is never how it says something.
  readOnly(
    'read-only',
    'This lane exists to answer a question while the tick is stopped, and it '
        'replies - so read, return, and let the caller decide. Register '
        'anything that changes the world with hasHandler instead.',
  );

  const HandlerWindow(this.lane, this.remedy);

  /// How the refusal names this lane.
  final String lane;

  /// What the refusal tells the caller to do instead.
  final String remedy;
}

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
  MemoryPool({
    this.pageSize = _defaultPageSize,
    this.maxPages = _defaultPoolSize,
  });

  // 64 megabyte default page size.
  static const int _defaultPageSize = 64 * 1024 * 1024;
  // 128 default pages pool.
  static const int _defaultPoolSize = 128;

  final int pageSize;
  final int maxPages;

  /// Allocated pages by index, **tombstoned and not removed** when one is
  /// freed.
  ///
  /// The index is an identity, not a position: it is what [getPage] takes,
  /// and compacting the list would renumber every page after the hole.
  /// `ArchetypeStorage._pages` tombstones for the same class of reason
  /// (`Entity.pageIndex` indexes *it*), so the two agree by construction.
  final List<MemoryPage?> _pages = [];

  int get pageCount => _pages.length;

  /// Bumped whenever any page's read or write base could have moved.
  ///
  /// `ArchetypeStorage` caches a resolved row base per page and uses this to
  /// know when to drop it. Three moments invalidate:
  ///
  ///  * [beginTick] - the write slot rotates onto a new buffer.
  ///  * [commitTick] - `publish` moves the *published* slot, so every read
  ///    base changes. Presentation runs after this and reads through the cache,
  ///    so missing it would hand the renderer last tick's rows.
  ///  * [freePage] - a cached base would dangle into freed memory, which is
  ///    the one failure a shared-memory design cannot report.
  ///
  /// An int compare per field access, against a page lookup plus a triple
  /// buffer indirection.
  int _epoch = 0;

  @internal
  int get epoch => _epoch;

  /// [epoch] as the **write** path compares against, and the whole of what
  /// #245's guard costs the hot path: nothing.
  ///
  /// `ArchetypeStorage.rowWrite` already tested its cached epoch against
  /// [epoch] before every field write, to notice the bases moving. It tests
  /// against this instead. The two numbers are equal whenever writing
  /// component data is legitimate, so a running game compares exactly what it
  /// compared before - same field load, same branch, same cache hits.
  ///
  /// While a handler that may not write is running (see [handlerWindow]) this
  /// holds [_sealedEpoch], which no cache can be holding. Every write then
  /// misses and lands in `_refreshWriteCache`, the cold path that already
  /// exists, and that is where the refusal is a real `throw` rather than an
  /// `assert` - so it stands in a release build, which is the row of #245's
  /// table that mattered most.
  int _writeEpoch = 0;

  @internal
  int get writeEpoch => _writeEpoch;

  /// A number [_refreshRowCache] never stores, so a cache holding it is a
  /// contradiction rather than a coincidence. `ArchetypeStorage._cacheEpoch`
  /// starts at -2 for the same reason.
  static const int _sealedEpoch = -1;

  /// Which kind of no-tick-window handler is running right now, if any.
  ///
  /// Set by `CommandTransport` around the dispatch and back again after; read
  /// by every path in the engine that changes the world. There is no getter
  /// for it: nothing outside this class has a question that the two
  /// `require` methods below do not answer better.
  HandlerWindow _window = HandlerWindow.none;

  /// Whether component data may be written at this instant.
  ///
  /// A tick window trumps the handler window: `GameState.stepOnce` is a
  /// receipt-delivered handler that runs a whole fixed step, and the writes
  /// inside that step are exactly as legitimate as any other tick's.
  bool get _writable => _tickOpen || _window == HandlerWindow.none;

  void _bumpEpoch() {
    _epoch++;
    _resealWriteEpoch();
  }

  void _resealWriteEpoch() {
    _writeEpoch = _writable ? _epoch : _sealedEpoch;
  }

  /// Opens [window] around a handler about to run, and hands back the window
  /// that was open so [closeHandlerWindow] can put it back.
  ///
  /// Returns rather than counts, because a handler can send a receipt batch of
  /// its own and be dispatched from inside another one's window - a depth
  /// counter would restore the wrong *kind*.
  @internal
  HandlerWindow openHandlerWindow(HandlerWindow window) {
    final previous = _window;
    _window = window;
    _resealWriteEpoch();
    return previous;
  }

  @internal
  void closeHandlerWindow(HandlerWindow previous) {
    _window = previous;
    _resealWriteEpoch();
  }

  /// Refuses [what] when it is being asked for by a handler with no tick
  /// window open.
  ///
  /// One field test and one enum compare, on paths that are already doing far
  /// more than that - a spawn memcpys a row, an unload frees pages. The
  /// per-field write path does not call this at all; it gets the same answer
  /// out of [writeEpoch] for free.
  @internal
  void requireWorldMutable(String what) {
    if (_writable) return;
    throw StateError(_refusal(what));
  }

  /// The same refusal for a `StateChannel`, which only the read-only lane is
  /// held to.
  ///
  /// A receipt-delivered handler publishing on a channel is the answer leg it
  /// has instead of a reply, and the engine's own message for a control
  /// command that returns something says so outright ("make it a SinkCommand
  /// and publish the answer on a StateChannel"). A channel write is not
  /// tick-scoped either: it publishes into its own `TripleBuffer` on the spot,
  /// so nothing erases it. The read-only lane is a different promise - it
  /// answers through a reply - and it is held to it.
  @internal
  void requireChannelWritable() {
    if (_tickOpen || _window != HandlerWindow.readOnly) return;
    throw StateError(
      'A state channel was written from a ${_window.lane} handler. Nothing '
      'erases it - a channel publishes into its own TripleBuffer on the spot - '
      'so this is refused for what it says rather than for what it loses: the '
      'lane declared that it answers by returning. ${_window.remedy}',
    );
  }

  String _refusal(String what) =>
      '$what from a ${_window.lane} handler, which runs with no tick window '
      'open. There is no write slot outside beginTick()/commitTick(): a '
      'component write lands in a slot the next beginTick() copies over, and '
      'an entity or a scene changed here changes while the simulation is '
      'standing still. ${_window.remedy}';

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

  /// The page at [page] - the index it was allocated at - or null once that
  /// page has been freed. The slot is tombstoned, so an index names the same
  /// page after its neighbours go as it named before.
  ///
  /// Throws a `RangeError` for an index no page has ever held, i.e. one at or
  /// past [pageCount]. Allocating rows in the result belongs to
  /// `ArchetypeStorage`: a row taken straight from `MemoryPage.allocate()` is
  /// not an `Entity`, and the query walk over that page yields it anyway.
  MemoryPage? getPage(int page) => _pages[page];

  /// Always allocates a brand-new page (up to [maxPages]) - never searches
  /// for an existing non-full one. Every page gets stride-locked to whichever
  /// archetype's row size calls `allocate()` on it first, so "any non-full
  /// page" isn't a safe answer to "give me space for archetype X's rows" - a
  /// page some other archetype already stride-locked would just reject a
  /// mismatched size. Reusing space across an archetype's *own* pages is
  /// `ArchetypeStorage`'s job (see archetype.dart) - it keeps its own page
  /// list and only calls this when none of its own pages have room.
  ///
  /// [ownerArchetypeId] is recorded on the page (see
  /// [MemoryPage.ownerArchetypeId]); this pool never interprets it.
  MemoryPage allocatePage({
    int ownerArchetypeId = -1,
    int ownerSceneSlot = -1,
  }) {
    if (_pages.length >= maxPages) {
      throw StateError(
        'MemoryPool exhausted: all $maxPages pages are allocated',
      );
    }
    final page = MemoryPage._(pageSize, ownerArchetypeId, ownerSceneSlot);
    _pages.add(page);
    return page;
  }

  /// Starts a fixed tick's write pass across every page - see the class
  /// doc above. Call once, before any system runs.
  void beginTick() {
    _tickOpen = true;
    // After [_tickOpen], because the bump reseals the write epoch off it -
    // and a tick window is what makes writing legitimate again inside a
    // receipt handler that ran a step (`GameState.stepOnce`).
    _bumpEpoch();
    for (final page in _pages) {
      if (page == null) continue;
      // Before the write pass, and before any system can run a query: this is
      // the one moment no walk is part-way through, so it is where rows
      // created or freed during last tick's queries become real.
      page.flushPending();
      // Only the bytes this page has actually handed out. Rows are bump
      // allocated and recycled from below the write cursor, so everything live
      // sits under [MemoryPage.highWaterMark] and the rest is capacity the
      // game reserved and never used.
      //
      // Copying the whole slot made the per-tick cost scale with `pageSize`
      // rather than with the number of entities - so a 1 MiB page holding one
      // camera entity copied a megabyte per tick to preserve a hundred bytes,
      // and making pages bigger to reduce page churn made every tick slower.
      page._buffer.beginWrite(bytes: page.highWaterMark);
    }
  }

  /// Publishes every page's write slot as this tick's readable snapshot.
  /// Call once, after every system has finished writing.
  void commitTick() {
    for (final page in _pages) {
      page?._buffer.publish();
    }
    // After every publish, not before: the read base each page resolves to has
    // just moved, and presentation reads through the cache.
    _tickOpen = false;
    // And back under whatever handler window the step ran inside, which for
    // `stepOnce` is a receipt-delivered one.
    _bumpEpoch();
  }

  /// Frees one page and drops it from this pool.
  ///
  /// The per-scene half of [dispose]: unloading a `Scene` frees exactly the
  /// pages tagged with its slot, and leaves every other page - and therefore
  /// every live `Entity` handle into them - untouched. Both page lists
  /// **tombstone** the freed slot instead of removing it. This pool's list
  /// keeps it because a page index is what [getPage] takes;
  /// `ArchetypeStorage` keeps its own because `Entity.pageIndex` is an index
  /// into *that* list, and shifting it would silently repoint every handle
  /// after the hole.
  void freePage(MemoryPage page) {
    _bumpEpoch();
    final index = _pages.indexOf(page);
    if (index < 0) return;
    // Tombstoned, not removed - see [_pages].
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
      _capacity = capacity;

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
  /// Recorded at allocation and read by nothing in the engine - the archetype
  /// already holds its own page list. It is here for a caller inspecting a
  /// pool that wants to attribute a page to an archetype.
  final int ownerArchetypeId;

  int get capacityBytes => _capacity;

  /// Where this page's triple-buffer slots live, as raw addresses - the same
  /// form `TripleBuffer.fromAddresses`/`RingBuffer.fromAddresses` take.
  int get latestAddress => _buffer.latestAddress;
  List<int> get slotAddresses => _buffer.slotAddresses;

  int? _strideBytes;
  int _writeOffset = 0;
  final Set<int> _freeOffsets = {};

  /// Whether a walk has begun since the last tick boundary, and structural
  /// changes must therefore be held back.
  ///
  /// A latch cleared by [flushPending], **not** a scope counter, and that is
  /// forced, not chosen: a `for-in` abandoned by `break` never resumes the
  /// `sync*` body, so a `finally` in [rowOffsets] would not run and a decrement
  /// would be lost forever. `ActiveCameraResolver` breaks out of a query, so
  /// that is a live path and not a hypothetical - it would strand the page in a
  /// permanently-deferring state.
  ///
  /// Time-driven works because the tick boundary is the one moment no walk
  /// can be in progress.
  bool _deferring = false;

  /// Rows allocated while a walk was in progress. Addressable immediately -
  /// the caller has a usable `Entity` and can write its fields - but skipped
  /// by [rowOffsets] until the walk that hid them ends. See the class doc.
  final Set<int> _pendingOffsets = {};

  /// Rows freed while a walk was in progress. Still yielded by [rowOffsets]
  /// and still readable, so an unmount handler can read the row it is being
  /// told about; they join [_freeOffsets] at the flush.
  final Set<int> _pendingFrees = {};

  bool get isFull =>
      _strideBytes != null &&
      _freeOffsets.isEmpty &&
      _writeOffset + _strideBytes! > _capacity;

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

  /// How many rows in this page are currently allocated.
  ///
  /// Arithmetic, not a walk: [highWaterMark] over the stride is every row
  /// that has ever been handed out, and the free set holds the ones handed
  /// back. So a caller counting a whole world - `WorldCensus` - pays per
  /// page rather than per entity, and a hundred thousand rows cost the same
  /// as ten.
  ///
  /// Two things it deliberately does not do. It does not step [rowOffsets],
  /// which latches the page into deferring structural changes until the next
  /// tick boundary - and a paused game has no next tick boundary, so a
  /// counting walk there would strand every page it touched. And it counts a
  /// row freed while a walk is open, because [free] has only deferred it:
  /// the row is still allocated and still readable until [flushPending].
  int get liveRowCount {
    final stride = _strideBytes;
    if (stride == null) return 0;
    return _writeOffset ~/ stride - _freeOffsets.length;
  }

  /// Every currently-live row offset in this page, in ascending order -
  /// what the query system walks to find matching entities. Lazy: does not
  /// allocate a list, just steps `highWaterMark ~/ strideBytes` candidates
  /// and skips freed ones.
  ///
  /// # A row created during a walk is never seen by that walk
  ///
  /// Reading [_writeOffset] and [_freeOffsets] live would make "was the new
  /// entity included?" depend on where its row happened to land: a
  /// bump-allocated row above the cursor yielded, a row recycled from [free]
  /// below the cursor not. Same call, two behaviours, decided by allocation
  /// history.
  ///
  /// The rule is the one that does not depend on the answer: a row
  /// created during a walk is skipped by **every** walk in progress, and
  /// appears to the next one. "Append it to the end instead" cannot be
  /// honoured in general - the row may land in a page already stepped past,
  /// and several walks may be open at once, so "the end" is not a place that
  /// exists.
  ///
  /// The limit is snapshotted for the same reason, and freeing is deferred so
  /// a row stays readable for the rest of the walk that is being told about
  /// it. That also removes a real `ConcurrentModificationError`: freeing a row
  /// otherwise mutates the very `Set` this loop consults.
  ///
  /// The deferral lasts until the next tick boundary, not until this iterator
  /// finishes - see [_deferring] for why scope cannot be used here.
  /// So the rule as a user sees it is: **a structural change made once a
  /// query has run this tick takes effect next tick**, which is the same
  /// rule field writes already follow (a value written this tick is not
  /// visible to a read this tick).
  Iterable<int> get rowOffsets sync* {
    final stride = _strideBytes;
    if (stride == null) return; // nothing ever allocated
    _deferring = true;
    // Snapshotted, not re-read: rows appended during the walk live at or
    // above this and are not this walk's business.
    final limit = _writeOffset;
    // `isNotEmpty` before `contains`: a page with nothing freed and nothing
    // deferred - every page in a game that only ever spawns - has no holes to
    // step over, and two hash lookups per row to establish that showed up at
    // ~1% of total CPU in the profile. `isEmpty` is a length check; `contains`
    // hashes.
    //
    // Checked **per row, not hoisted out of the loop**. `_pendingOffsets` can
    // grow *during* this walk - that is the entire reason it exists, since a
    // row recycled mid-iteration sits below `limit` and would otherwise appear
    // halfway through. Hoisting reads correct and silently reintroduces the
    // inconsistency this page defers changes to avoid.
    for (var offset = 0; offset < limit; offset += stride) {
      if (_freeOffsets.isNotEmpty && _freeOffsets.contains(offset)) continue;
      if (_pendingOffsets.isNotEmpty && _pendingOffsets.contains(offset)) {
        continue;
      }
      yield offset;
    }
  }

  /// Opens a walk over this page and returns the row limit.
  ///
  /// The half of [rowOffsets] a hand-written iterator needs: it defers
  /// structural changes for the duration (see [_deferring]) and snapshots the
  /// high-water mark, so rows appended during the walk are not this walk's
  /// business. Paired with [isWalkable].
  @internal
  int beginWalk() {
    _deferring = true;
    return _writeOffset;
  }

  /// Whether a walk in progress should yield the row at [offset].
  ///
  /// `isEmpty` before `contains`: a page with no holes - every page in a game
  /// that only ever spawns - answers with a length check instead of two hash
  /// lookups. Checked per row and not hoisted, because [_pendingOffsets]
  /// **can grow during the walk**; that is the entire reason it exists.
  @internal
  @pragma('vm:prefer-inline')
  bool isWalkable(int offset) {
    if (_freeOffsets.isNotEmpty && _freeOffsets.contains(offset)) return false;
    if (_pendingOffsets.isNotEmpty && _pendingOffsets.contains(offset)) {
      return false;
    }
    return true;
  }

  /// Folds deferred structural changes in and reopens the page to immediate
  /// ones. Called by [MemoryPool.beginTick] - the one moment no walk can be
  /// part-way through.
  @internal
  void flushPending() {
    _deferring = false;
    if (_pendingOffsets.isNotEmpty) _pendingOffsets.clear();
    if (_pendingFrees.isEmpty) return;
    _freeOffsets.addAll(_pendingFrees);
    _pendingFrees.clear();
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
    _strideBytes ??= size;
    assert(size == _strideBytes || _wrongStride(size));
    if (_freeOffsets.isNotEmpty) {
      final offset = _freeOffsets.first;
      _freeOffsets.remove(offset);
      // A recycled row sits *below* a walk's snapshotted limit, so unlike a
      // bump-allocated one it is not hidden by the limit alone. This is the
      // half of the old inconsistency that made the behaviour depend on
      // allocation history.
      if (_deferring) _pendingOffsets.add(offset);
      return offset;
    }
    if (_writeOffset + size > _capacity) {
      throw StateError(
        'MemoryPage is full ($_capacity bytes, stride $_strideBytes)',
      );
    }
    final offset = _writeOffset;
    _writeOffset += size;
    // Recorded even though the snapshotted limit already hides it: a walk
    // that starts *later* while an earlier one is still open would otherwise
    // see it, and the rule is that no walk open at creation time does.
    if (_deferring) _pendingOffsets.add(offset);
    return offset;
  }

  /// Rejects a second stride on a page already locked to one.
  ///
  /// A page belongs to one archetype and an archetype has one row size, so
  /// two different sizes reaching one page is a wiring mistake in the
  /// allocator, not anything the running game can produce.
  bool _wrongStride(int size) => throw ArgumentError(
    'MemoryPage is locked to a $_strideBytes byte stride (set by its '
    'first allocate() call); got $size. Each page stores rows for one '
    'archetype/component-set - use a different page for a different '
    'struct layout.',
  );

  /// Recycles the row at [offset] (as returned by [allocate]) for reuse by
  /// a future [allocate] call on this page.
  ///
  /// Deferred while a walk is open, so the row stays live and readable for
  /// the rest of it - which is what lets an unmount handler read the row it
  /// is being told about (see `SceneStruct.unmountEntitiesOf`), and what
  /// keeps this from mutating the `Set` [rowOffsets] is consulting.
  void free(int offset) {
    if (_deferring) {
      _pendingFrees.add(offset);
      return;
    }
    _freeOffsets.add(offset);
  }

  /// Whether this page has ever been published - i.e. whether
  /// [resolveRead] returns a slot, and whether the next
  /// [MemoryPool.beginTick] will copy anything over the write slot.
  bool get hasPublished => _buffer.hasPublished;

  /// This tick's write-slot address for the row at [offset] - cheap, call
  /// as many times as needed per tick (once per field access). Only valid
  /// after [MemoryPool.beginTick] has run for the current tick.
  @pragma('vm:prefer-inline')
  Pointer<Uint8> resolveWrite(int offset) => _buffer.writeView + offset;

  /// The latest **published** snapshot's address for the row at [offset] -
  /// `null` before the first [MemoryPool.commitTick]. Safe to call from any
  /// isolate holding this page, including read-only ones (the main/UI
  /// isolate per the project root plan's "Cross-isolate architecture"
  /// section, lane 1).
  /// The row at [offset], readable - the published snapshot, or the write slot
  /// when nothing has been published yet.
  ///
  /// Non-nullable; see [TripleBuffer.readView] for the measurement.
  /// This is the hot path - one call per field read per entity per tick - and
  /// [resolveRead] below stays nullable for the callers that genuinely want to
  /// distinguish "nothing published" from "here it is".
  @pragma('vm:prefer-inline')
  Pointer<Uint8> resolveRow(int offset) => _buffer.readView + offset;

  Pointer<Uint8>? resolveRead(int offset) {
    final latest = _buffer.latestView();
    return latest == null ? null : latest + offset;
  }

  /// Frees this page's native memory.
  void dispose() {
    _buffer.dispose();
  }
}
