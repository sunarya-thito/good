import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One field of one command's parameter block - the command-side twin of
/// `DataPointer`, and deliberately the same shape: one pointer object per
/// *field*, never per call, with the call passed in as the index.
///
/// ```dart
/// myCommand.hi[call] = 123;
/// final back = myCommand.result[call];
/// ```
///
/// The index is a [CommandBuffer] rather than an `Entity` because that is
/// what a command has instead of a row: a byte range inside a batch. Reading
/// a field nobody wrote throws rather than reporting zero - see
/// [CommandBuffer].
abstract class ParamPointer<T> {
  /// Reads this field out of [call].
  T operator [](CommandBuffer call);

  /// Writes this field into [call].
  void operator []=(CommandBuffer call, T value);
}

/// A single command invocation: the bytes one call's parameters and results
/// live in.
///
/// # Not a `Map<ParamPointer, Object?>`
///
/// That was the obvious alternative and it is the wrong one twice over. It
/// allocates a map entry, boxes a value and hashes a key **per parameter per
/// call**, on a path that exists to carry a burst of unit orders; and it
/// still has to be walked and serialized before it can cross an isolate, so
/// it pays for the bytes anyway, later, plus a pass. Because
/// [ParamDescriptor] fixes every command's layout at boot, a call is a fixed
/// stride and writing a field is a bump-pointer store into a buffer the
/// sender already owns.
///
/// # Reading something nobody wrote is an error
///
/// Zero is a real value for every field kind here, so "unset" cannot be a
/// value - it has to be a separate fact, and it is: one bit per field, set on
/// write. That turns two silent bugs into exceptions - reading a parameter
/// the caller forgot to fill, and reading a *result* the handler never wrote
/// (which otherwise reads as a plausible zero and gets acted on).
final class CommandBuffer {
  @internal
  CommandBuffer(this.batch, this.maskOffset, this.offset, this.fieldCount);

  /// The batch these bytes live in.
  final CommandBatch batch;

  /// Where this call's written-mask starts inside [batch].
  ///
  /// The mask lives *in the record*, not beside it, so it crosses the isolate
  /// boundary with the bytes it describes. Keeping it in a side object would
  /// mean the receiving side could not tell a parameter the sender set from
  /// one it left alone - which is the whole distinction this exists to make.
  final int maskOffset;

  /// Where this call's payload starts inside [batch].
  final int offset;

  /// How many fields the command declared - the size of the written-mask.
  final int fieldCount;

  /// Bytes of mask a command with [fieldCount] fields needs.
  static int maskBytesFor(int fieldCount) => (fieldCount + 7) >> 3;

  ByteData get _data => batch.data;

  void _markWritten(int index) {
    final at = maskOffset + (index >> 3);
    final bytes = batch.bytes;
    bytes[at] = bytes[at] | (1 << (index & 7));
  }

  bool _isWritten(int index) =>
      batch.bytes[maskOffset + (index >> 3)] & (1 << (index & 7)) != 0;

  @override
  String toString() => 'CommandBuffer(@$offset of ${batch.length} bytes)';
}

/// A batch of calls, sent as one message.
///
/// One call is a batch of one - a bare `await damage(...)` makes one - so
/// there is a single path rather than a special case. Batching matters
/// because the round trip, not the bytes, is what costs: fifty commands in
/// one batch is one ring record, one wake-up and one reply, where fifty sends
/// are fifty of each.
final class CommandBatch {
  @internal
  CommandBatch(this.id, {CommandSender? sender, int initialBytes = 256})
      // ignore: prefer_initializing_formals
      : _sender = sender,
        // ignore: prefer_initializing_formals - _bytes is reassigned on
        // growth, so it cannot be a final initializing formal.
        _bytes = Uint8List(initialBytes) {
    _data = ByteData.sublistView(_bytes);
  }

  /// Correlates a reply with the send that asked for it.
  ///
  /// Assigned by whichever [CommandSender] made this batch, and unique only
  /// *within that sender*. That is enough, because a reply only ever travels
  /// back to the copy that sent the request: the two isolate copies both
  /// number their batches from zero and never see each other's ids as
  /// anything but an opaque tag to echo.
  final int id;

  final CommandSender? _sender;

  HandlerSide? _destination;

  /// Which isolate every call in this batch is bound for, or null while the
  /// batch is still empty.
  ///
  /// A batch is one message, so it has one destination - see [routeTo].
  @internal
  HandlerSide? get destination => _destination;

  /// Records that a call bound for [side] has been added, and refuses a batch
  /// that would need to go to both isolates.
  ///
  /// A batch is the unit of transport: one ring record, one wake-up, one
  /// reply. Splitting a mixed batch in two would give back a `CommandResults`
  /// that was only half true at any instant, and quietly break the ordering
  /// guarantee the batch exists to provide - so the first call fixes where
  /// this one is going and a second opinion is an error at the call that
  /// causes it, naming both commands.
  @internal
  void routeTo(HandlerSide side, Type command) {
    final current = _destination;
    if (current == null) {
      _destination = side;
      return;
    }
    if (current == side) return;
    throw StateError(
      '$command is handled on the ${side.name} isolate, and this batch is '
      'already bound for the ${current.name} one. A batch is a single '
      'message with a single reply, so every call in it has to be going to '
      'the same place - use two batches, one per side.',
    );
  }

  /// Sends every call in this batch as one message, and completes when the
  /// other side has run all of them and the reply is back.
  ///
  /// One message, one wake-up, one reply - which is the whole reason batching
  /// exists, since the round trip costs far more than the bytes.
  Future<CommandResults> send() {
    final sender = _sender;
    if (sender == null) {
      throw StateError(
        'this batch has nowhere to send to. Build batches with '
        'Game.createCommandBatch() (or GameState.createCommandBatch()), which '
        'takes the transport with it - a bare CommandBatch is a buffer, not a '
        'channel.',
      );
    }
    return sender.send(this).then((_) => CommandResults._(this));
  }

  Uint8List _bytes;
  late ByteData _data;
  int _length = 0;

  final List<CommandBuffer> _calls = <CommandBuffer>[];

  /// Bytes used so far.
  int get length => _length;

  /// How many calls this batch holds.
  int get callCount => _calls.length;

  @internal
  ByteData get data => _data;

  @internal
  Uint8List get bytes => _bytes;

  @internal
  CommandBuffer callAt(int index) => _calls[index];

  /// Reserves [stride] bytes for one call of the command at [commandIndex],
  /// and returns the handle to write it through.
  ///
  /// Growth is amortized doubling and copies what is already there - the same
  /// "grow without losing what it held" pattern `VertexBatch2D` uses - so a
  /// batch that turns out to be bigger than guessed costs one copy, not a
  /// dropped call.
  @internal
  CommandBuffer append(int commandIndex, int stride, int fieldCount) {
    final start = _length;
    final maskBytes = CommandBuffer.maskBytesFor(fieldCount);
    final needed = start + _headerBytes + maskBytes + stride;
    if (needed > _bytes.length) {
      var size = _bytes.isEmpty ? 256 : _bytes.length;
      while (size < needed) {
        size *= 2;
      }
      final grown = Uint8List(size)..setRange(0, _length, _bytes);
      _bytes = grown;
      _data = ByteData.sublistView(grown);
    }
    _data.setUint16(start, commandIndex, Endian.little);
    // The reserved range is not guaranteed clean - a grown buffer is, but a
    // reused one is not - and a stale mask byte would report a field as
    // written that nobody wrote.
    _bytes.fillRange(start + _headerBytes, needed, 0);
    _length = needed;
    final call = CommandBuffer(
      this,
      start + _headerBytes,
      start + _headerBytes + maskBytes,
      fieldCount,
    );
    _calls.add(call);
    return call;
  }

  /// Two bytes of "which command is this", ahead of every record. The
  /// receiving side needs it to know the stride before it can step to the
  /// next one, so it cannot live anywhere but here.
  static const int _headerBytes = 2;

  @internal
  static int get headerBytes => _headerBytes;

  /// Copies a reply's bytes back over this batch's own, so the
  /// [CommandBuffer]s the caller is still holding read the results.
  ///
  /// Same length by construction - a reply is the same records with the
  /// result fields filled in - so this is a memcpy, not a re-parse.
  /// Rebuilds the call handles for a batch that arrived as bytes.
  ///
  /// The wire format is self-describing given the command list: each record
  /// starts with its command index, and the index gives the stride, so the
  /// walk needs nothing the receiving side does not already have. It is also
  /// what makes a mismatched command list *detectable* rather than silently
  /// misread - a stride that does not add up runs off the end of the buffer
  /// and says so.
  @internal
  void adoptIncoming(Uint8List wire, CommandLayouts layouts) {
    _bytes = wire;
    _data = ByteData.sublistView(wire);
    _length = wire.length;
    _calls.clear();
    var at = 0;
    while (at < _length) {
      final index = _data.getUint16(at, Endian.little);
      final fieldCount = layouts.fieldCountOf(index);
      final maskBytes = CommandBuffer.maskBytesFor(fieldCount);
      final maskAt = at + _headerBytes;
      final payloadAt = maskAt + maskBytes;
      final end = payloadAt + layouts.strideOf(index);
      if (end > _length) {
        throw StateError(
          'a command batch ran off its own end: record at byte $at claims '
          'command #$index, whose record is ${end - at} bytes, and only '
          '${_length - at} remain. The two isolate copies disagree about the '
          'command list.',
        );
      }
      _calls.add(CommandBuffer(this, maskAt, payloadAt, fieldCount));
      at = end;
    }
  }

  @internal
  void adoptReply(Uint8List reply) {
    // Same length and same layout by construction - a reply is these records
    // with the handler's writes added - so the CommandBuffers the caller is
    // still holding keep pointing at the right offsets, and the masks that
    // come back are the ones the handler set.
    _bytes.setRange(0, reply.length, reply);
  }
}

/// Proof that a batch has been sent and its replies are back.
///
/// The only way to get one is to await [CommandBatch.send], and the only
/// thing that takes one is a `CommandKey`. So reading a result before its
/// batch has been sent is not a mistake you can make - there is nothing to
/// index with.
final class CommandResults {
  const CommandResults._(this.batch);

  /// The batch these results came from - what a key checks itself against.
  final CommandBatch batch;
}

/// Which isolate a command's handler runs on. Not chosen directly - it
/// follows from *where* the handler was registered, which is the point: the
/// declaration site is the answer, so there is no second thing to keep in
/// sync with it.
///
/// Lives here rather than beside the command shapes because it is transport
/// vocabulary: a batch's [CommandBatch.destination] and a [CommandSender]'s
/// routing decision are the only things that read it.
@internal
enum HandlerSide { main, game }

@internal
abstract interface class CommandSender {
  /// A new, empty batch, tagged with an id that correlates its reply.
  CommandBatch newBatch();

  /// Carries [batch] to the isolate that handles its calls, and completes
  /// once every one of them has run and the reply is back.
  Future<void> send(CommandBatch batch);
}

/// What a batch needs to know about the commands in it to walk received
/// bytes: how wide each record is, and how many fields its mask covers.
///
/// An interface rather than a direct reference to the command registry, only
/// because the registry lives a layer up and pointing back down at it would
/// be a cycle. It has one implementation.
@internal
abstract interface class CommandLayouts {
  /// Payload bytes for the command at [index], excluding header and mask.
  int strideOf(int index);

  /// How many fields the command at [index] declared.
  int fieldCountOf(int index);
}

/// Declares one command's parameter and result fields.
///
/// The vocabulary is `DataDescriptor`'s, on purpose: a game that knows how to
/// lay out a component already knows how to lay out a command, and the two
/// really are the same problem - a fixed-width, bit-packed record. What is
/// deliberately absent is anything variable-length: a command record has a
/// stride, exactly like an archetype row, so a `String` or a `List` field
/// declares its capacity up front and a value that does not fit is an error
/// rather than a resize.
abstract class ParamDescriptor {
  ParamPointer<int> hasUint1([int defaultValue = 0]);
  ParamPointer<int> hasUint2([int defaultValue = 0]);
  ParamPointer<int> hasUint4([int defaultValue = 0]);
  ParamPointer<int> hasUint8([int defaultValue = 0]);
  ParamPointer<int> hasUint16([int defaultValue = 0]);
  ParamPointer<int> hasUint32([int defaultValue = 0]);
  ParamPointer<int> hasInt8([int defaultValue = 0]);
  ParamPointer<int> hasInt16([int defaultValue = 0]);
  ParamPointer<int> hasInt32([int defaultValue = 0]);
  ParamPointer<int> hasInt64([int defaultValue = 0]);
  ParamPointer<double> hasFloat32([double defaultValue = 0]);
  ParamPointer<double> hasFloat64([double defaultValue = 0]);

  /// A UTF-8 string of at most [maxBytes] **bytes** - not characters, since
  /// that is what the buffer actually reserves and a caller sizing a field
  /// should be thinking in the unit that can overflow.
  ParamPointer<String> hasString(int maxBytes, {Encoding encoding = utf8});
}

/// Builds one command's layout, then serves as the accessor for it.
///
/// Sealed off behind [ParamDescriptor] for the same reason
/// `ArchetypeDataDescriptor` is: the descriptor is alive only during the
/// command's single `describeParams` pass, while the pointers it hands back
/// live as long as the command does.
@internal
final class CommandParamDescriptor implements ParamDescriptor {
  int _bitCursor = 0;
  int _fieldCount = 0;
  bool _sealed = false;

  /// The record's stride in bytes, rounded up from the bit cursor.
  int get strideBytes => (_bitCursor + 7) >> 3;

  int get fieldCount => _fieldCount;

  void seal() => _sealed = true;

  /// The same packing rule `ArchetypeStorage.declareField` uses, and it has
  /// to be the same: two descriptors that packed differently would be two
  /// mental models for one idea.
  int _declare(int bitWidth) {
    if (_sealed) {
      throw StateError(
        'a command\'s fields can only be declared during its one-time '
        'describeParams pass - this descriptor is sealed.',
      );
    }
    if (bitWidth >= 8 || (_bitCursor & 7) + bitWidth > 8) {
      _bitCursor = (_bitCursor + 7) & -8;
    }
    final offset = _bitCursor;
    _bitCursor += bitWidth;
    return offset;
  }

  ParamPointer<int> _int(int bitWidth, bool signed) {
    final bitOffset = _declare(bitWidth);
    final index = _fieldCount++;
    if (bitWidth < 8) {
      return _SubBytePointer(index, bitOffset >> 3, bitOffset & 7, bitWidth);
    }
    return _IntPointer(index, bitOffset >> 3, bitWidth, signed);
  }

  @override
  ParamPointer<int> hasUint1([int defaultValue = 0]) => _int(1, false);
  @override
  ParamPointer<int> hasUint2([int defaultValue = 0]) => _int(2, false);
  @override
  ParamPointer<int> hasUint4([int defaultValue = 0]) => _int(4, false);
  @override
  ParamPointer<int> hasUint8([int defaultValue = 0]) => _int(8, false);
  @override
  ParamPointer<int> hasUint16([int defaultValue = 0]) => _int(16, false);
  @override
  ParamPointer<int> hasUint32([int defaultValue = 0]) => _int(32, false);
  @override
  ParamPointer<int> hasInt8([int defaultValue = 0]) => _int(8, true);
  @override
  ParamPointer<int> hasInt16([int defaultValue = 0]) => _int(16, true);
  @override
  ParamPointer<int> hasInt32([int defaultValue = 0]) => _int(32, true);
  @override
  ParamPointer<int> hasInt64([int defaultValue = 0]) => _int(64, true);

  @override
  ParamPointer<double> hasFloat32([double defaultValue = 0]) {
    final byte = _declare(32) >> 3;
    return _FloatPointer(_fieldCount++, byte, 32);
  }

  @override
  ParamPointer<double> hasFloat64([double defaultValue = 0]) {
    final byte = _declare(64) >> 3;
    return _FloatPointer(_fieldCount++, byte, 64);
  }

  @override
  ParamPointer<String> hasString(int maxBytes, {Encoding encoding = utf8}) {
    if (maxBytes <= 0 || maxBytes > 0xFFFF) {
      throw ArgumentError.value(
        maxBytes,
        'maxBytes',
        'a string field reserves this many bytes in every call of this '
            'command, so it has to be a positive number that fits its own '
            '16-bit length prefix',
      );
    }
    // A 16-bit length, then the bytes. Both are byte-aligned because the
    // length is declared as a 16-bit field, which forces alignment first.
    final lengthByte = _declare(16) >> 3;
    for (var i = 0; i < maxBytes; i++) {
      _declare(8);
    }
    return _StringPointer(_fieldCount++, lengthByte, maxBytes, encoding);
  }
}

/// Shared bookkeeping: every pointer knows its own index in the written-mask
/// and refuses to read a field nobody has written.
abstract class _Pointer<T> implements ParamPointer<T> {
  const _Pointer(this.index);

  final int index;

  void _requireWritten(CommandBuffer call) {
    if (call._isWritten(index)) return;
    throw StateError(
      'field #$index of this command has not been written, so there is '
      'nothing to read. On the sending side that means a parameter was left '
      'out; on the receiving side it means a result the handler never '
      'produced. Zero is a real value for every field kind here, so the '
      'engine reports the omission instead of inventing one.',
    );
  }
}

final class _IntPointer extends _Pointer<int> {
  const _IntPointer(super.index, this.byte, this.bitWidth, this.signed);

  final int byte;
  final int bitWidth;
  final bool signed;

  @override
  int operator [](CommandBuffer call) {
    _requireWritten(call);
    final at = call.offset + byte;
    final data = call._data;
    return switch ((bitWidth, signed)) {
      (8, false) => data.getUint8(at),
      (8, true) => data.getInt8(at),
      (16, false) => data.getUint16(at, Endian.little),
      (16, true) => data.getInt16(at, Endian.little),
      (32, false) => data.getUint32(at, Endian.little),
      (32, true) => data.getInt32(at, Endian.little),
      _ => data.getInt64(at, Endian.little),
    };
  }

  @override
  void operator []=(CommandBuffer call, int value) {
    final at = call.offset + byte;
    final data = call._data;
    switch ((bitWidth, signed)) {
      case (8, false):
        data.setUint8(at, value);
      case (8, true):
        data.setInt8(at, value);
      case (16, false):
        data.setUint16(at, value, Endian.little);
      case (16, true):
        data.setInt16(at, value, Endian.little);
      case (32, false):
        data.setUint32(at, value, Endian.little);
      case (32, true):
        data.setInt32(at, value, Endian.little);
      default:
        data.setInt64(at, value, Endian.little);
    }
    call._markWritten(index);
  }
}

final class _SubBytePointer extends _Pointer<int> {
  const _SubBytePointer(super.index, this.byte, this.shift, this.bitWidth);

  final int byte;
  final int shift;
  final int bitWidth;

  int get _mask => ((1 << bitWidth) - 1) << shift;

  @override
  int operator [](CommandBuffer call) {
    _requireWritten(call);
    final raw = call._data.getUint8(call.offset + byte);
    return (raw & _mask) >> shift;
  }

  @override
  void operator []=(CommandBuffer call, int value) {
    final at = call.offset + byte;
    final data = call._data;
    // Read-modify-write of the byte, not of the field: neighbours share it.
    final raw = data.getUint8(at);
    data.setUint8(at, (raw & ~_mask) | ((value << shift) & _mask));
    call._markWritten(index);
  }
}

final class _FloatPointer extends _Pointer<double> {
  const _FloatPointer(super.index, this.byte, this.bitWidth);

  final int byte;
  final int bitWidth;

  @override
  double operator [](CommandBuffer call) {
    _requireWritten(call);
    final at = call.offset + byte;
    return bitWidth == 32
        ? call._data.getFloat32(at, Endian.little)
        : call._data.getFloat64(at, Endian.little);
  }

  @override
  void operator []=(CommandBuffer call, double value) {
    final at = call.offset + byte;
    if (bitWidth == 32) {
      call._data.setFloat32(at, value, Endian.little);
    } else {
      call._data.setFloat64(at, value, Endian.little);
    }
    call._markWritten(index);
  }
}

final class _StringPointer extends _Pointer<String> {
  const _StringPointer(super.index, this.lengthByte, this.maxBytes, this.encoding);

  final int lengthByte;
  final int maxBytes;
  final Encoding encoding;

  @override
  String operator [](CommandBuffer call) {
    _requireWritten(call);
    final at = call.offset + lengthByte;
    final length = call._data.getUint16(at, Endian.little);
    if (length == 0) return '';
    return encoding.decode(
      Uint8List.sublistView(call.batch.bytes, at + 2, at + 2 + length),
    );
  }

  @override
  void operator []=(CommandBuffer call, String value) {
    final encoded = encoding.encode(value);
    if (encoded.length > maxBytes) {
      throw ArgumentError.value(
        value,
        'value',
        'is ${encoded.length} bytes encoded, and this field reserved '
            '$maxBytes. A command record has a fixed stride, so the capacity '
            'is part of the declaration - raise it at hasString(), or send '
            'less',
      );
    }
    final at = call.offset + lengthByte;
    call._data.setUint16(at, encoded.length, Endian.little);
    call.batch.bytes.setRange(at + 2, at + 2 + encoded.length, encoded);
    call._markWritten(index);
  }
}
