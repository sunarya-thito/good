import 'dart:ffi';
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
/// tearing - flagged here rather than silently assumed away.
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
      _slots = List.generate(3, (_) => calloc<Uint8>(slotBytes), growable: false) {
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
  Pointer<Uint8> beginWrite({bool copyFromLatest = true}) {
    final write = _slots[_writeSlot];
    if (copyFromLatest) {
      final latestSlot = _latest.value;
      if (latestSlot >= 0 && latestSlot != _writeSlot) {
        write.asTypedList(slotBytes).setAll(0, _slots[latestSlot].asTypedList(slotBytes));
      }
    }
    return write;
  }

  /// Cheap accessor for the current write slot's address - no copying, safe
  /// to call as many times as needed (once per field/row access) within a
  /// tick after [beginWrite] has already been called once for that tick.
  Pointer<Uint8> get writeView => _slots[_writeSlot];

  /// Publishes the slot returned by the most recent [beginWrite] as the
  /// newest complete snapshot, and advances to the next write slot in the
  /// fixed round-robin order.
  void publish() {
    _latest.value = _writeSlot;
    _writeSlot = (_writeSlot + 1) % 3;
  }

  /// Whether [publish] has ever been called - i.e. whether [latestView]
  /// would return a slot. Cheaper than calling [latestView] just to
  /// null-check it, and used by debug assertions that need to know whether
  /// the next [beginWrite] will copy something over the write slot.
  bool get hasPublished => _latest.value >= 0;

  /// A snapshot view for reading - `null` if nothing has been published
  /// yet. Safe to call from any isolate holding this `TripleBuffer`,
  /// including the writer's own.
  Pointer<Uint8>? latestView() {
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
