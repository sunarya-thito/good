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
///  * **free** - "I am not using this slot, you may write it". Written by the
///    reader, read by the writer.
///
/// The writer only ever writes where `free` points, and **never writes the
/// slot `ready` points at**. That second rule is the one that closes the hole:
/// without it the writer would publish a slot and then immediately begin
/// overwriting it, and a reader that started just then would walk into a
/// half-written frame.
///
/// When `free` still names the slot it just published, the reader has not
/// handed anything back yet, so [beginWrite] returns null and the writer skips
/// that frame. That is not a stall - the simulation keeps running, it simply
/// stops producing frames nobody could have read. It also paces production to
/// the consumer: a game ticking at 200Hz against a 60Hz display stops building
/// and discarding two frames out of every three.
///
/// # Two slots, not three
///
/// With the handoff, two is sufficient and a third is never touched: the
/// reader holds one and hands back the other, so the writer always has exactly
/// one target. Three slots are what a *blind* writer needs, to buy grace it
/// cannot otherwise have. Told where to go, it needs no grace.
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
  /// Two, and see the class doc on why a third would be dead weight.
  static const int slotCount = 2;

  // Control block layout, in 32-bit words.
  static const int _readyWord = 0;
  static const int _freeWord = 1;
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
    _control[_freeWord] = 0; // slot 0 is the writer's to begin with
  }

  /// Rebuilds a view over a buffer the other isolate allocated. The
  /// reconstructing side gets the same native memory at the same addresses -
  /// see `Game`'s notes on what survives `Isolate.spawn`.
  HandoffBuffer.fromAddresses({
    required this.slotBytes,
    required int controlAddress,
    required List<int> slotAddresses,
  })  : _control = Pointer<Int32>.fromAddress(controlAddress),
        _slots = <Pointer<Uint8>>[
          for (final address in slotAddresses) Pointer<Uint8>.fromAddress(address),
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

  /// The slot to fill, or **null when there is nowhere safe to write**.
  ///
  /// Null means the reader has not handed a slot back since the last
  /// [publish], so the only free slot is the one `ready` points at. Skip the
  /// frame; do not fall back to writing somewhere else.
  Pointer<Uint8>? beginWrite() {
    final free = _control[_freeWord];
    // `free == ready` is the reader having not moved since the last publish.
    // Writing there would overwrite the frame the reader is entitled to pick
    // up at any moment.
    if (free < 0 || free == _control[_readyWord]) return null;
    _writeSlot = free;
    return _slots[free];
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

  /// Takes the newest complete slot, or **null when nothing new has been
  /// published** since the last call.
  ///
  /// Taking a slot also hands the previous one back to the writer, which is
  /// what lets it carry on. A reader that stops calling this stops the writer
  /// producing frames - which is correct, since nothing would read them.
  Pointer<Uint8>? beginRead() {
    final ready = _control[_readyWord];
    if (ready < 0 || ready == _readSlot) return null;
    _readSlot = ready;
    // Everything that is not the slot just taken is now the writer's. With
    // two slots that is exactly one, and it is the slot this reader was on
    // until a moment ago.
    _control[_freeWord] = ready == 0 ? 1 : 0;
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
