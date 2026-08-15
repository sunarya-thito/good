import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Shared memory for a value where **only the newest copy matters** - a
/// rendered frame - handed between one writing isolate and one reading
/// isolate with neither ever blocking the other.
///
/// # Why not a RingBuffer, and why not a TripleBuffer
///
/// A `RingBuffer` keeps every record in order. That is right for commands,
/// where dropping the third of five is a bug. It is wrong for frames: the
/// instant a newer frame exists the older one is garbage, so a queue
/// faithfully preserves exactly what nobody wants - and being bounded, it
/// forces the reader to drain every tick whether it intends to draw or not,
/// or the writer starts failing.
///
/// A `TripleBuffer` is closer, but its writer cycles slots **blindly**:
/// 0, 1, 2, 0, ... with no idea where the reader is. That gives the reader
/// two publishes of grace and then reuses its slot underneath it. Safe only
/// while the reader is reliably faster than two of the writer's frames, which
/// is an assumption about scheduling rather than a guarantee - and when it
/// breaks, it breaks silently, as wrong pixels.
///
/// # The handoff
///
/// Two shared words remove the guessing. Each is written by exactly one side
/// and read by the other, so neither needs more than an aligned word store:
///
///  * **ready** - "this slot is complete, you may read it". Written by the
///    writer, read by the reader.
///  * **reading** - "I am holding this slot right now". Written by the reader,
///    read by the writer.
///
/// The writer takes any slot that is neither `ready` nor `reading`. That is
/// the whole rule, and both halves matter: not `reading`, or it would scribble
/// under the reader; not `ready`, or it would overwrite the frame the reader
/// is entitled to pick up at any moment.
///
/// # Why the reader says what it holds, not what it has released
///
/// An earlier version had the reader publish `free` - "you may write here" -
/// which sounds equivalent and is not. `free` only advances when the reader
/// reads, so the writer produced exactly one frame per read and then idled.
/// The frame waiting was therefore the one produced *just after the previous
/// read*, and by the time the reader came back it was a whole read-interval
/// stale. That is the opposite of what a renderer wants, and it defeated the
/// point of moving off the ring.
///
/// Saying what it *holds* instead lets the writer keep going: it always has a
/// slot that is neither being read nor waiting to be read, so it replaces its
/// own unread frame with a fresher one and the reader always collects the
/// newest.
///
/// # Three slots, and why two will not do
///
/// The reader holds one and the newest complete one is another, so the writer
/// needs a third to work in. With two, "neither `ready` nor `reading`" can be
/// the empty set and the writer has nowhere to go - which is exactly the
/// stalling behaviour above. Three is the minimum that lets the writer run
/// freely while a reader holds a slot for as long as it likes.
///
/// # Claim, then confirm
///
/// The reader writes `reading` and then re-reads `ready`. The writer only ever
/// enters a slot *after* publishing a different one, so if `ready` has not
/// moved since the claim, the writer cannot be inside the slot just claimed.
/// Without that second read there is a window: the reader picks up `ready`,
/// the writer publishes elsewhere and then steps into the slot the reader was
/// about to claim.
///
/// # Memory ordering
///
/// Every control word is a naturally-aligned 32-bit slot in one block, so each
/// store and load is atomic on every architecture Dart targets, and no
/// compare-and-swap is needed (stable `dart:ffi` exposes none anyway). What is
/// *not* here is an explicit fence: [publish] writes the payload, then the
/// used length, then `ready` last, and correctness relies on those retiring in
/// order as seen from the other isolate. That holds on the strongly-ordered
/// targets this engine runs on (x64/ARM64). Flagged rather than assumed away -
/// revisit with a real release-store if a weak-memory target ever matters.
class HandoffBuffer {
  /// Three: one being read, one complete and waiting, one to write into. See
  /// the class doc on why two stalls the writer.
  static const int slotCount = 3;

  // Control block layout, in 32-bit words.
  static const int _readyWord = 0;
  static const int _readingWord = 1;
  static const int _usedWord = 2; // one per slot, from here
  static const int _controlWords = _usedWord + slotCount;

  HandoffBuffer(this.slotBytes)
    : _control = calloc<Int32>(_controlWords),
      _slots = List<Pointer<Uint8>>.generate(
        slotCount,
        (_) => calloc<Uint8>(slotBytes),
        growable: false,
      ) {
    _control[_readyWord] = -1; // nothing published yet
    _control[_readingWord] = -1; // no reader holding anything
  }

  /// Rebuilds a view over a buffer the other isolate allocated. The
  /// reconstructing side gets the same native memory at the same addresses -
  /// see `Game`'s notes on what survives `Isolate.spawn`.
  HandoffBuffer.fromAddresses({
    required this.slotBytes,
    required int controlAddress,
    required List<int> slotAddresses,
  }) : _control = Pointer<Int32>.fromAddress(controlAddress),
       _slots = <Pointer<Uint8>>[
         for (final address in slotAddresses)
           Pointer<Uint8>.fromAddress(address),
       ];

  /// Capacity of one slot. A frame that would exceed it is the caller's
  /// problem to bound - see `GameRenderer2D.maxSpritesPerTick`.
  final int slotBytes;

  final Pointer<Int32> _control;
  final List<Pointer<Uint8>> _slots;

  int get controlAddress => _control.address;
  List<int> get slotAddresses => <int>[for (final s in _slots) s.address];

  // Writer-local. Never read across the boundary.
  int _writeSlot = -1;

  // Reader-local. Never read across the boundary.
  int _readSlot = -1;

  // --- writer side ------------------------------------------------------

  /// The slot to fill: any that is neither the newest complete one nor the one
  /// a reader is holding.
  ///
  /// With three slots at most two are excluded, so this always finds one and
  /// **the writer never waits on a reader**. The null return exists only so a
  /// mis-sized buffer fails visibly rather than corrupting; it is unreachable
  /// at [slotCount] 3.
  Pointer<Uint8>? beginWrite() {
    final ready = _control[_readyWord];
    final reading = _control[_readingWord];
    for (var slot = 0; slot < slotCount; slot++) {
      if (slot == ready || slot == reading) continue;
      _writeSlot = slot;
      return _slots[slot];
    }
    return null;
  }

  /// Marks the slot from the last [beginWrite] complete and readable.
  ///
  /// [usedBytes] is how much of the slot the frame actually occupies, so the
  /// reader copies that rather than the whole capacity. It matters more than
  /// it looks: a fixed-size read against a variable-size write is a race that
  /// gets *worse* as the scene empties, because the writer finishes sooner
  /// while the reader still moves the full slot.
  void publish(int usedBytes) {
    assert(_writeSlot >= 0, 'publish() without a matching beginWrite()');
    assert(
      usedBytes >= 0 && usedBytes <= slotBytes,
      'usedBytes $usedBytes is outside the slot ($slotBytes bytes)',
    );
    _control[_usedWord + _writeSlot] = usedBytes;
    // Last, and it has to be: this is what makes the slot visible to the
    // reader, so everything the reader will look at must already be written.
    _control[_readyWord] = _writeSlot;
    _writeSlot = -1;
  }

  // --- reader side ------------------------------------------------------

  /// Takes the newest complete slot and holds it, or **null when nothing new
  /// has been published** since the last call.
  ///
  /// Holding it is what keeps the writer out; the hold lasts until the next
  /// call, so a reader may take as long as it likes over the bytes. The writer
  /// carries on regardless, replacing its own unread frames, so the slot
  /// returned here is always the newest complete one rather than the oldest
  /// since the last read.
  Pointer<Uint8>? beginRead() {
    var ready = _control[_readyWord];
    if (ready < 0) return null;
    // Claim, then confirm - see the class doc. The writer only enters a slot
    // after publishing a different one, so an unchanged `ready` proves it is
    // not inside the slot just claimed. Bounded in practice: it takes a
    // publish to invalidate a claim, and the writer publishes at tick rate.
    while (true) {
      _control[_readingWord] = ready;
      final confirmed = _control[_readyWord];
      if (confirmed == ready) break;
      ready = confirmed;
    }
    if (ready == _readSlot) return null;
    _readSlot = ready;
    return _slots[ready];
  }

  /// How many bytes of the slot from the last [beginRead] are real.
  int get readUsedBytes {
    assert(_readSlot >= 0, 'readUsedBytes before a successful beginRead()');
    return _control[_usedWord + _readSlot];
  }

  /// Whether anything has ever been published - for a reader that wants to
  /// distinguish "no frame yet" from "no *new* frame".
  bool get hasPublished => _control[_readyWord] >= 0;

  void dispose() {
    for (final slot in _slots) {
      calloc.free(slot);
    }
    calloc.free(_control);
  }
}
