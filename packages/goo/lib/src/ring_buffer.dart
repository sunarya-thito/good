import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

/// A wait-free single-producer/single-consumer ring buffer over a fixed-size
/// native memory region, shared across isolates by raw address (the same
/// handoff pattern as `TripleBuffer`/`bin/ffi_shared_memory_poc.dart`).
///
/// This is the one primitive behind both cross-isolate lanes that carry
/// bulk, per-tick traffic (see the project root plan's "Cross-isolate
/// architecture" section):
///   - UI isolate -> game isolate: command submission (spawn/despawn/etc)
///   - game isolate -> main isolate: the DrawData2D command buffer
/// Both are "one producer writes records whenever it wants, one consumer
/// drains everything accumulated since the last drain, once per tick" - so
/// they share this one implementation instead of each inventing their own.
///
/// Entries are flat and self-describing: an 8 byte header (Int32 record
/// type + Int32 payload length) followed by the payload, so callers don't
/// need to agree on a single fixed record size up front. [tryWrite] never
/// allocates and never blocks - the producer and consumer each own one
/// cursor (a monotonically increasing byte count, wrapped into the
/// physical buffer via `% capacityBytes`) and only ever *read* the other
/// side's cursor, so - like `TripleBuffer` - this needs no compare-and-swap
/// primitive. Records are never split across the physical wrap boundary:
/// when a record wouldn't fit contiguously before wrapping, the writer
/// either skips silently to the wrap point (if there isn't even room for a
/// header) or writes an explicit padding record the reader recognizes and
/// skips over (if a header fits but the payload doesn't) - both sides
/// derive this purely from `capacityBytes`, which is fixed at construction
/// and shared by both ends, so nothing extra needs to travel on the wire
/// for the "not enough room, skip to wrap" case.
class RingBuffer {
  RingBuffer(this.capacityBytes)
    : _writeCursorPtr = calloc<Uint64>(),
      _readCursorPtr = calloc<Uint64>(),
      _buffer = calloc<Uint8>(capacityBytes);

  /// Reconstructs a view over a ring buffer another isolate already
  /// created, from raw addresses. Whichever isolate is meant to be the
  /// producer must call [tryWrite]; the other, [drain] - never both.
  RingBuffer.fromAddresses({
    required this.capacityBytes,
    required int writeCursorAddress,
    required int readCursorAddress,
    required int bufferAddress,
  }) : _writeCursorPtr = Pointer<Uint64>.fromAddress(writeCursorAddress),
       _readCursorPtr = Pointer<Uint64>.fromAddress(readCursorAddress),
       _buffer = Pointer<Uint8>.fromAddress(bufferAddress);

  static const int headerBytes = 8;
  static const int _paddingRecordType = -1;

  final int capacityBytes;
  final Pointer<Uint64> _writeCursorPtr;
  final Pointer<Uint64> _readCursorPtr;
  final Pointer<Uint8> _buffer;

  // Owned by the producer only; never written by the consumer.
  int _writeCursor = 0;
  // Owned by the consumer only; never written by the producer.
  int _readCursor = 0;

  int get writeCursorAddress => _writeCursorPtr.address;
  int get readCursorAddress => _readCursorPtr.address;
  int get bufferAddress => _buffer.address;

  Uint8List get _bytes => _buffer.asTypedList(capacityBytes);

  void _writeHeader(int offset, int recordType, int length) {
    final bd = ByteData.sublistView(_bytes, offset, offset + headerBytes);
    bd.setInt32(0, recordType, Endian.little);
    bd.setInt32(4, length, Endian.little);
  }

  (int recordType, int length) _readHeader(int offset) {
    final bd = ByteData.sublistView(_bytes, offset, offset + headerBytes);
    return (bd.getInt32(0, Endian.little), bd.getInt32(4, Endian.little));
  }

  /// Encodes and appends one record. Returns `false` if the buffer is full
  /// (the caller decides the overflow policy - assert in debug, log + drop
  /// in release; this method itself never blocks or allocates). Only the
  /// single producer isolate may call this.
  bool tryWrite(int recordType, Uint8List payload) {
    final needed = headerBytes + payload.length;
    if (needed > capacityBytes) return false; // can never fit, ever

    var freeSpace = capacityBytes - (_writeCursor - _readCursorPtr.value);
    var physicalOffset = _writeCursor % capacityBytes;
    var remaining = capacityBytes - physicalOffset;

    if (remaining < headerBytes) {
      // Not even room for a header before the wrap - nothing to write,
      // just skip to the wrap point.
      if (freeSpace < remaining) return false;
      _writeCursor += remaining;
      freeSpace -= remaining;
      physicalOffset = 0;
      remaining = capacityBytes;
    }

    if (remaining < needed) {
      // A header fits, the payload doesn't - mark the rest of the buffer
      // as padding so the reader knows to skip straight to the wrap point.
      if (freeSpace < remaining) return false;
      _writeHeader(physicalOffset, _paddingRecordType, remaining - headerBytes);
      _writeCursor += remaining;
      freeSpace -= remaining;
      physicalOffset = 0;
      remaining = capacityBytes;
    }

    if (freeSpace < needed) return false; // genuinely full

    _writeHeader(physicalOffset, recordType, payload.length);
    _bytes.setAll(physicalOffset + headerBytes, payload);
    _writeCursor += needed;
    _writeCursorPtr.value = _writeCursor; // publish
    return true;
  }

  /// Drains everything written since the last drain, in write order,
  /// allocating a fresh list to hold it. Convenience wrapper over
  /// [drainInto] - prefer that one anywhere this runs every tick.
  List<RingBufferRecord> drain() {
    final records = <RingBufferRecord>[];
    drainInto(records);
    return records;
  }

  /// Drains everything written since the last drain, in write order,
  /// **appending** to [records]. Only the single consumer isolate may call
  /// this - typically once per tick (or once per completed frame, for the
  /// draw-command direction).
  ///
  /// Takes the destination rather than returning one so a per-tick consumer
  /// (`Game`'s command drain) can keep reusing a single list instead of
  /// allocating one per tick for what is usually zero records - RULES.md
  /// rule 1 against a loop that runs 60 times a second. The caller owns
  /// clearing it.
  void drainInto(List<RingBufferRecord> records) {
    final localWrite = _writeCursorPtr.value; // snapshot once per drain
    final bytes = _bytes;

    while (true) {
      final available = localWrite - _readCursor;
      if (available < headerBytes) break;

      var physicalOffset = _readCursor % capacityBytes;
      final remaining = capacityBytes - physicalOffset;

      if (remaining < headerBytes) {
        _readCursor += remaining;
        continue;
      }

      final (recordType, length) = _readHeader(physicalOffset);
      if (recordType == _paddingRecordType) {
        _readCursor += headerBytes + length;
        continue;
      }

      final recordTotal = headerBytes + length;
      if (available < recordTotal) break; // producer hasn't finished it yet

      final payloadStart = physicalOffset + headerBytes;
      // Zero-copy view directly over the pool's backing bytes - only the
      // small RingBufferRecord wrapper is allocated, proportional to the
      // number of records actually written, not to tick frequency.
      final payload = Uint8List.sublistView(bytes, payloadStart, payloadStart + length);
      records.add(RingBufferRecord(recordType, payload));
      _readCursor += recordTotal;
    }

    _readCursorPtr.value = _readCursor; // publish once for the whole drain
  }

  void dispose() {
    calloc.free(_buffer);
    calloc.free(_writeCursorPtr);
    calloc.free(_readCursorPtr);
  }
}

/// A decoded record handed back by [RingBuffer.drain]. [payload] is a
/// zero-copy view directly over the ring's backing bytes, valid only until
/// the *next* [RingBuffer.drain] call (which may recycle that region) -
/// copy it out if you need to keep it longer.
class RingBufferRecord {
  const RingBufferRecord(this.recordType, this.payload);

  final int recordType;
  final Uint8List payload;
}
