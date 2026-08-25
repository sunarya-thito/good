import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// A wait-free single-writer / multi-reader triple buffer over a fixed-size
/// native memory region: `slotBytes` bytes, allocated 3x (one per slot).
///
/// This is the fix for `MemoryPool`'s originally-flagged tearing problem: a
/// 2-state toggle can hand a reader a buffer the writer is still mid-write
/// on, the instant a swap lands between the reader's check and its use of
/// the pointer. With 3 slots and a fixed round-robin write order, the
/// writer always writes into the slot it last published *two* publishes
/// ago:
///
///   publish 1: write slot 0, latest = 0
///   publish 2: write slot 1, latest = 1   (slot 0 is now "previous", still
///                                           safe - a reader might have
///                                           grabbed it right before latest
///                                           flipped to 1 and still be
///                                           using it)
///   publish 3: write slot 2, latest = 2   (slot 0 hasn't been touched in
///                                           two full cycles - safe to
///                                           reuse it next)
///   publish 4: write slot 0 again, latest = 0
///
/// So a reader that captures [latestView] always gets a fully-written,
/// self-consistent slot, and gets a full extra publish cycle of grace
/// period to finish using it before the writer would touch it again. The
/// writer never blocks on a reader, and there's no reader-side locking.
///
/// Concurrency note: publishing is a single naturally-aligned word store
/// (`Pointer<Int32>.value =`) and reading it is a single aligned word load,
/// which is atomic on every architecture Dart currently targets - so this
/// needs no compare-and-swap/exchange primitive (stable `dart:ffi` doesn't
/// expose one anyway). What it does *not* have is an explicit memory
/// fence: correctness relies on the writer's own stores into the slot
/// being retired before the publish store becomes visible to another
/// isolate, which holds on the strongly-ordered architectures this engine
/// currently targets (x64/ARM64) but isn't spec-guaranteed the way a real
/// atomic release-store would be. Revisit with an explicit fence (or a
/// native mutex) if profiling on a weak-memory target ever surfaces
/// tearing - flagged here, not silently assumed away.
///
/// **Load-bearing assumption:** the "2 publish cycle" grace period above is
/// counted in *publishes*, not wall-clock time - it only holds if a reader
/// finishes with a snapshot before the writer completes two more
/// [publish] calls. For the intended usage (the game isolate calls
/// [publish] once per fixed tick, tens of milliseconds apart; a reader -
/// the render pass, a HUD query - finishes in microseconds) that margin is
/// enormous. This primitive is genuinely unsafe for an *unthrottled*
/// writer racing far ahead of a slow or blocked reader (see
/// `test/triple_buffer_test.dart` for both a realistic-pacing correctness
/// test and a comment on why an unthrottled stress run isn't a
/// representative test of this primitive) - callers must pair it with a
/// bounded publish rate, not publish in a tight loop.
class TripleBuffer {
  TripleBuffer(this.slotBytes)
    : _latest = calloc<Int32>(),
      _slots = List.generate(
        3,
        (_) => calloc<Uint8>(slotBytes),
        growable: false,
      ) {
    _latest.value = -1; // nothing published yet
  }

  /// Reconstructs a view over a triple buffer another isolate already
  /// created, from raw addresses - the same handoff pattern demonstrated in
  /// `bin/ffi_shared_memory_poc.dart`. The reconstructing isolate must
  /// never call [beginWrite]/[publish] - exactly one isolate owns writing.
  TripleBuffer.fromAddresses({
    required this.slotBytes,
    required int latestAddress,
    required List<int> slotAddresses,
  }) : _latest = Pointer<Int32>.fromAddress(latestAddress),
       _slots = [for (final a in slotAddresses) Pointer<Uint8>.fromAddress(a)];

  final int slotBytes;
  final Pointer<Int32> _latest;
  final List<Pointer<Uint8>> _slots;

  /// One cached `Uint8List` per slot, built once.
  ///
  /// `Pointer.asTypedList` **allocates** - it builds a new view object every
  /// call. [beginWrite] runs once per page per tick, so building two of them
  /// there was two heap objects per page per tick on the hottest path in the
  /// engine, which is exactly what the hot-path rules forbid. Views over
  /// native memory stay valid for the life of the pointer, so there is no
  /// reason to build them more than once.
  ///
  /// Not rebuilt after `Isolate.spawn`: this object is only ever *written* by
  /// the copy that owns it, and a `TripleBuffer` that crossed the spawn is
  /// reconstructed from addresses (see [TripleBuffer.fromAddresses]), which
  /// runs this initializer again on the far side.
  late final List<Uint8List> _views = <Uint8List>[
    for (final slot in _slots) slot.asTypedList(slotBytes),
  ];

  // Writer-local bookkeeping. Never read by another isolate, so it needs no
  // synchronization of its own - only the single owning isolate touches it.
  int _writeSlot = 0;

  int get latestAddress => _latest.address;
  List<int> get slotAddresses => [for (final s in _slots) s.address];

  /// Starts this tick's write pass: returns the slot to mutate. If
  /// [copyFromLatest] (the default) and something has already been
  /// published, the previously-published slot's bytes are copied forward
  /// first, so in-place read-modify-write mutations (e.g.
  /// `transformOffsetX[instance] += 1`) see last tick's values instead of
  /// stale/zeroed memory from 3 cycles ago. Call once per tick, not once
  /// per allocation - the copy is a single bulk memcpy up front.
  /// [bytes] limits the copy to the first N bytes of the slot, for a caller
  /// that knows the rest is dead. A `MemoryPage` does: rows are bump-allocated
  /// and recycled from below its write cursor, so everything live sits under
  /// it and the remaining capacity holds nothing worth carrying forward.
  ///
  /// That matters more than it sounds. A page is sized for the archetype's
  /// worst case, so a 1 MiB page holding one camera entity was copying a
  /// megabyte per tick to preserve a hundred bytes - and the cost scaled with
  /// the *page size a game configured*, not with the entities it actually had.
  /// Omitting it copies the whole slot, which is the safe default for any
  /// caller with no cursor to offer.
  Pointer<Uint8> beginWrite({bool copyFromLatest = true, int? bytes}) {
    final write = _slots[_writeSlot];
    _writeBase = write;
    // Refreshed here rather than lazily: this is the one moment per tick when
    // the published snapshot is known to be settled, and doing it here keeps
    // `latestView` a plain field read for the rest of the tick.
    final publishedSlot = _latest.value;
    _hasReadBase = publishedSlot >= 0;
    if (_hasReadBase) _readBase = _slots[publishedSlot];
    if (copyFromLatest) {
      final latestSlot = _latest.value;
      if (latestSlot >= 0 && latestSlot != _writeSlot) {
        final count = bytes == null || bytes > slotBytes ? slotBytes : bytes;
        if (count > 0) {
          // `setRange`, not `setAll`: on two typed lists of the same element
          // type this takes the bulk-move fast path, where `setAll` goes
          // through the generic `Iterable` protocol element by element. Same
          // bytes, very different loop.
          _views[_writeSlot].setRange(0, count, _views[latestSlot]);
        }
      }
    }
    return write;
  }

  /// Cheap accessor for the current write slot's address - no copying, safe
  /// to call as many times as needed (once per field/row access) within a
  /// tick after [beginWrite] has already been called once for that tick.
  /// The slot the current tick is writing into.
  ///
  /// Cached for the same reason as [_readBase] and with none of its subtlety:
  /// [_writeSlot] is plain Dart state that only [beginWrite] and [publish]
  /// touch, and only the writing copy calls either. There is no shared-memory
  /// question here at all - this is purely removing a bounds-checked list
  /// index from a path taken once per field *written*, per entity, per tick.
  @pragma('vm:prefer-inline')
  Pointer<Uint8> get writeView => _writeBase;
  late Pointer<Uint8> _writeBase = _slots[_writeSlot];

  /// Publishes the slot returned by the most recent [beginWrite] as the
  /// newest complete snapshot, and advances to the next write slot in the
  /// fixed round-robin order.
  void publish() {
    // **Dropped, not retargeted.** Retargeting it here looks like a free win -
    // the slot just published *is* the newest - and it silently breaks the
    // spawned configuration: this object is deep-copied by `Isolate.spawn`,
    // and a cache left valid crosses with it. The reading isolate then answers
    // every read from a base frozen at spawn time and never sees another
    // publish. Two isolate tests caught it; nothing in the single-isolate
    // suite would have.
    //
    // Clearing keeps the invariant the whole design rests on: only a copy that
    // called `beginWrite` may trust this, and a reader never calls it.
    _hasReadBase = false;
    _latest.value = _writeSlot;
    _writeSlot = (_writeSlot + 1) % 3;
    // Kept in step with the rotation, so a caller reading `writeView` between
    // publish and the next beginWrite gets the slot that will actually be
    // written rather than the one just published.
    _writeBase = _slots[_writeSlot];
  }

  /// Whether [publish] has ever been called - i.e. whether [latestView]
  /// would return a slot. Cheaper than calling [latestView] just to
  /// null-check it, and used by debug assertions that need to know whether
  /// the next [beginWrite] will copy something over the write slot.
  bool get hasPublished => _latest.value >= 0;

  /// A snapshot view for reading - `null` if nothing has been published
  /// yet. Safe to call from any isolate holding this `TripleBuffer`,
  /// including the writer's own.
  /// The published snapshot's base pointer, cached for the duration of a tick.
  ///
  /// **Writer-only, and that is what makes it safe.** [_latest] lives in shared
  /// native memory precisely so a *reader* isolate sees the writer's publishes;
  /// caching it there would freeze the reader on one snapshot forever. But only
  /// the writing copy calls [beginWrite], so only the writing copy ever fills
  /// this - a reader leaves it null and keeps taking the live read below.
  ///
  /// On the writer it cannot go stale either: [_latest] changes only in
  /// [publish], which clears it. Between `beginWrite` and `publish` - the whole
  /// tick window - the published snapshot is by definition fixed.
  ///
  /// A `bool` plus a non-nullable field, not a nullable one: reading a
  /// `Pointer<T>?` and branching costs 3.39ns against 1.43ns for a plain field
  /// (`tool/field_access_bench.dart`). Smaller than the 9x a nullable *return*
  /// costs, but this is read once per field access and the flag is free.
  bool _hasReadBase = false;
  late Pointer<Uint8> _readBase;

  /// The newest published snapshot, falling back to the write slot when
  /// nothing has been published yet.
  ///
  /// **Non-nullable, and that is the whole point.** A `Pointer<T>?` cannot be
  /// unboxed, so returning one allocates a box - measured at 14.4ns per access
  /// against 1.65ns for the same chain returning a plain pointer
  /// (`tool/field_access_bench.dart`). This is called once per field read, per
  /// entity, per tick, so a 9x factor there is not a micro-optimisation.
  ///
  /// The fallback is the pre-publish case, which is real: a scene writes its
  /// starting rows before anything has been published, and those writes have to
  /// be readable back. Spelling it `resolveRead(o) ?? resolveWrite(o)` in
  /// `_readRow` pays the box on every read.
  @pragma('vm:prefer-inline')
  Pointer<Uint8> get readView {
    if (_hasReadBase) return _readBase;
    final slot = _latest.value;
    return slot < 0 ? _writeBase : _slots[slot];
  }

  /// The newest published snapshot, or null if nothing has been published.
  ///
  /// Called **once per field access** on the read path, and the cache above
  /// exists for it: without that, this is a load from native memory plus a
  /// bounds-checked list index, paid per field, per entity, per tick. A system
  /// touching 20 fields across 10k entities pays it 200,000 times a frame.
  Pointer<Uint8>? latestView() {
    if (_hasReadBase) return _readBase;
    final slot = _latest.value;
    if (slot < 0) return null;
    return _slots[slot];
  }

  void dispose() {
    for (final s in _slots) {
      calloc.free(s);
    }
    calloc.free(_latest);
  }
}
