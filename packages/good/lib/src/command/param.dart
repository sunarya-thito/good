import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:good/src/struct.dart';

/// One field of one command's parameter block - the command-side twin of
/// `DataPointer`, and deliberately the same shape: one pointer object per
/// *field*, never per call, with the call passed in as the index.
///
/// ```dart
/// myCommand.hi[call] = 123;
/// final back = myCommand.result[call];
/// ```
///
/// The index is a [ParamBuffer] rather than an `Entity` because that is
/// what a command has instead of a row: a byte range inside a batch. Reading
/// a field nobody wrote throws rather than reporting zero - see
/// [ParamBuffer].
abstract class ParamPointer<T> {
  /// Reads this field out of [call].
  T operator [](ParamBuffer call);

  /// Writes this field into [call].
  void operator []=(ParamBuffer call, T value);
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
final class ParamBuffer {
  @internal
  ParamBuffer(this.batch, this.maskOffset, this.offset, this.fieldCount);

  /// The record set these bytes live in. Fixed for life - a handle belongs
  /// to one batch even when its *position* in that batch is re-pointed.
  final ParamBatch batch;

  /// Where this call's written-mask starts inside [batch].
  ///
  /// The mask lives *in the record*, not beside it, so it crosses the isolate
  /// boundary with the bytes it describes. Keeping it in a side object would
  /// mean the receiving side could not tell a parameter the sender set from
  /// one it left alone - which is the whole distinction this exists to make.
  int maskOffset;

  /// Where this call's payload starts inside [batch].
  int offset;

  /// How many fields the declaration has - the size of the written-mask.
  int fieldCount;

  /// Re-points this handle at another record of the same batch.
  ///
  /// The three offsets are not `final` for one reason: a batch parsed off the
  /// wire is parsed **every tick**, and allocating one handle per record per
  /// tick is exactly the per-frame garbage the no-allocation rule exists to
  /// prevent. So [ParamBatch] keeps its handles and re-points them, and these
  /// fields are mutable to let it - see [ParamBatch.reset], which is the only
  /// thing that makes an outstanding handle stale.
  void _bind(int maskOffset, int offset, int fieldCount) {
    this.maskOffset = maskOffset;
    this.offset = offset;
    this.fieldCount = fieldCount;
  }

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
  String toString() => 'ParamBuffer(@$offset of ${batch.length} bytes)';
}

/// Several records - calls, messages - packed back to back in one buffer.
///
/// The shared record container, and deliberately *not* command-specific: a
/// command batch crossing an isolate and a network message batch crossing a
/// socket are the same bytes with the same self-describing walk, so they are
/// the same class. `CommandBatch` adds the isolate transport's own facts (an
/// id, a destination, a reply); `good_net`'s message batch adds none at all.
///
/// One call is a batch of one - a bare `await damage(...)` makes one - so
/// there is a single path rather than a special case. Batching matters
/// because the round trip, not the bytes, is what costs: fifty commands in
/// one batch is one ring record, one wake-up and one reply, where fifty sends
/// are fifty of each. Over a socket the same argument reads "one datagram
/// instead of fifty".
///
/// # Why the layout is not negotiable per batch
///
/// Every record is `[uint16 index][written-mask][payload]`, and the index is
/// a position in a declaration order both ends ran. That is what lets the
/// receiver walk a buffer it did not build without a length prefix per
/// record - and what makes a *disagreement* about that order detectable
/// (see [adoptIncoming]) rather than silently misread. Across isolates the
/// two copies run the same pass, so they cannot disagree; across machines
/// they can, which is why `good_net` puts a hash of the declaration order in
/// its handshake instead of trusting it.
class ParamBatch {
  ParamBatch({int initialBytes = defaultBytes})
    // ignore: prefer_initializing_formals - _bytes is reassigned on
    // growth, so it cannot be a final initializing formal.
    : _bytes = Uint8List(initialBytes) {
    _data = ByteData.sublistView(_bytes);
  }

  /// What a batch starts out able to hold, before the first growth.
  static const int defaultBytes = 256;

  Uint8List _bytes;
  late ByteData _data;

  /// Where this batch's records start in [_bytes], and where they end.
  ///
  /// Zero and "bytes written so far" for a batch being built. A batch
  /// *parsed* off a wire is a slice of a transport's own receive buffer -
  /// see [adoptIncoming] - so it does not start at zero and the buffer
  /// around it is not its own.
  int _base = 0;
  int _end = 0;

  /// Record handles, live ones first. Longer than [callCount] once a batch
  /// has held more records than it holds now - those are pooled, not leaked.
  final List<ParamBuffer> _calls = <ParamBuffer>[];

  int _callCount = 0;

  /// Bytes this batch's records occupy.
  int get length => _end - _base;

  /// Where those bytes start in [bytes] - zero unless this batch was parsed
  /// out of the middle of someone else's buffer.
  int get start => _base;

  /// How many records this batch holds.
  int get callCount => _callCount;

  /// The raw bytes, for a transport to put on a wire. Only the first
  /// [length] of them are this batch's.
  Uint8List get bytes => _bytes;

  ByteData get data => _data;

  /// The record at [index], `0 <= index < callCount`.
  ParamBuffer callAt(int index) => _calls[index];

  /// Which declaration the record at [index] is - the two header bytes in
  /// front of it, which is what routes it back to the command or message that
  /// wrote it.
  ///
  /// A method rather than something every consumer works out from
  /// `callAt(i).maskOffset - headerBytes`: two places doing that arithmetic is
  /// two places to get it wrong when the header changes (the one-fact-one-place
  /// rule), and the header is this class's business anyway.
  int indexAt(int index) =>
      _data.getUint16(_calls[index].maskOffset - _headerBytes, Endian.little);

  /// Empties this batch for reuse, keeping its buffer and its record handles.
  ///
  /// **Invalidates every [ParamBuffer] handed out so far** - they are the
  /// handles being reused. That is right for a transport that fills a batch,
  /// sends it and forgets it (what `good_net` does, once per frame per
  /// channel), and wrong for the command path, where a caller holds a buffer
  /// across an `await` to read the result out of it afterwards. So commands
  /// never reset: they take a fresh batch per send and let it go.
  void reset() {
    _base = 0;
    _end = 0;
    _callCount = 0;
  }

  /// A handle for the record range just reserved - pooled, see [reset].
  ParamBuffer _record(int maskAt, int payloadAt, int fieldCount) {
    if (_callCount < _calls.length) {
      final reused = _calls[_callCount++];
      reused._bind(maskAt, payloadAt, fieldCount);
      return reused;
    }
    final made = ParamBuffer(this, maskAt, payloadAt, fieldCount);
    _calls.add(made);
    _callCount++;
    return made;
  }

  /// Reserves [stride] bytes for one record of the declaration at [index],
  /// and returns the handle to write it through.
  ///
  /// Growth is amortized doubling and copies what is already there - the same
  /// "grow without losing what it held" pattern `VertexBatch2D` uses - so a
  /// batch that turns out to be bigger than guessed costs one copy, not a
  /// dropped call.
  ParamBuffer append(int index, int stride, int fieldCount) {
    final start = _end;
    final maskBytes = ParamBuffer.maskBytesFor(fieldCount);
    final needed = start + _headerBytes + maskBytes + stride;
    if (needed > _bytes.length) {
      var size = _bytes.isEmpty ? 256 : _bytes.length;
      while (size < needed) {
        size *= 2;
      }
      final grown = Uint8List(size)..setRange(0, _end, _bytes);
      _bytes = grown;
      _data = ByteData.sublistView(grown);
    }
    _data.setUint16(start, index, Endian.little);
    // The reserved range is not guaranteed clean - a grown buffer is, but a
    // reused one is not - and a stale mask byte would report a field as
    // written that nobody wrote.
    _bytes.fillRange(start + _headerBytes, needed, 0);
    _end = needed;
    return _record(
      start + _headerBytes,
      start + _headerBytes + maskBytes,
      fieldCount,
    );
  }

  /// Two bytes of "which declaration is this", ahead of every record. The
  /// receiving side needs it to know the stride before it can step to the
  /// next one, so it cannot live anywhere but here.
  static const int _headerBytes = 2;

  static int get headerBytes => _headerBytes;

  /// Rebuilds the record handles for a batch that arrived as bytes.
  ///
  /// The wire format is self-describing given the declaration list: each
  /// record starts with its index, and the index gives the stride, so the
  /// walk needs nothing the receiving side does not already have. It is also
  /// what makes a mismatched declaration list *detectable* rather than
  /// silently misread - a stride that does not add up runs off the end of the
  /// buffer and says so.
  ///
  /// Reads the records in `[offset, offset + length)` of [wire], defaulting
  /// to the whole of it.
  ///
  /// **Allocation-free on a repeat call**, which is what the network path
  /// needs: [wire] is adopted rather than copied, the `ByteData` view over it
  /// is kept when the same buffer comes back (a transport reuses one receive
  /// buffer for the life of the session, so it always does), and the record
  /// handles come from the pool [reset] maintains. A batch parsed this way is
  /// a *view* - it is only valid until the transport reuses those bytes,
  /// which is why every message handler reads what it needs inside the call
  /// rather than keeping the record.
  void adoptIncoming(
    Uint8List wire,
    ParamLayouts layouts, [
    int offset = 0,
    int? length,
  ]) {
    if (!identical(wire, _bytes)) {
      _bytes = wire;
      _data = ByteData.sublistView(wire);
    }
    _base = offset;
    _end = offset + (length ?? wire.length - offset);
    _callCount = 0;
    var at = _base;
    while (at < _end) {
      final index = _data.getUint16(at, Endian.little);
      final fieldCount = layouts.fieldCountOf(index);
      final maskBytes = ParamBuffer.maskBytesFor(fieldCount);
      final maskAt = at + _headerBytes;
      final payloadAt = maskAt + maskBytes;
      final end = payloadAt + layouts.strideOf(index);
      if (end > _end) {
        throw StateError(
          'a param batch ran off its own end: record at byte ${at - _base} '
          'claims declaration #$index, whose record is ${end - at} bytes, and '
          'only ${_end - at} remain. The two ends disagree about the '
          'declaration list - across isolates that means describeCommands did '
          'not run identically on both copies, and across a network it means '
          'the two peers are not running the same build.',
        );
      }
      _record(maskAt, payloadAt, fieldCount);
      at = end;
    }
  }
}

/// A batch of command calls, sent to the other isolate as one message.
///
/// [ParamBatch] holds the records; this adds what the *isolate* transport
/// needs and a network one does not: an id to correlate the reply, a
/// destination every call in the batch has to agree on, and the reply itself.
final class CommandBatch extends ParamBatch {
  @internal
  CommandBatch(
    this.id, {
    CommandSender? sender,
    super.initialBytes = ParamBatch.defaultBytes,
    // ignore: prefer_initializing_formals
  }) : _sender = sender;

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

  @internal
  void adoptReply(Uint8List reply) {
    // Same length and same layout by construction - a reply is these records
    // with the handler's writes added - so the ParamBuffers the caller is
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

/// What a batch needs to know about the declarations in it to walk received
/// bytes: how wide each record is, and how many fields its mask covers.
///
/// An interface rather than a direct reference to the registry that owns the
/// declarations, because that registry lives a layer up and pointing back
/// down at it would be a cycle. `CommandRegistry` implements it for
/// commands; `good_net`'s message registry implements it for messages.
abstract interface class ParamLayouts {
  /// Payload bytes for the declaration at [index], excluding header and
  /// mask.
  int strideOf(int index);

  /// How many fields the declaration at [index] has.
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

  /// A field holding an [Entity] handle - the same signed 64-bit storage
  /// [hasInt64] gives, with the type saying what the field holds.
  ///
  /// `Entity` is an extension type over `int` (see struct.dart), so this is
  /// the int64 read and write path exactly: no conversion, no allocation.
  /// What changes is the declare and call sites - an entity handle and a
  /// score stop being assignable to each other.
  ///
  /// That matters more here than on a component column. A parameter crosses
  /// an isolate boundary, where both are eight little-endian bytes: swapping
  /// one for the other survives the crossing intact and surfaces as wrong
  /// behaviour on the far side, a long way from the call that wrote it.
  ///
  /// A handle names a *row*, and a row is reused once the entity in it is
  /// destroyed, so one held across ticks can come to name a different entity
  /// - `DataDescriptor.hasEntity` writes that out in full.
  ParamPointer<Entity> hasEntity();

  /// A UTF-8 string of at most [maxBytes] **bytes** - not characters, since
  /// that is what the buffer actually reserves and a caller sizing a field
  /// should be thinking in the unit that can overflow.
  ParamPointer<String> hasString(int maxBytes, {Encoding encoding = utf8});
}

/// Builds one command's layout, then serves as the accessor for it.
///
/// Sealed off behind [ParamDescriptor] for the same reason
/// `ArchetypeDataDescriptor` is: the descriptor is alive only during the one
/// `describeParams` pass, while the pointers it hands back live as long as
/// the thing that declared them does.
///
/// Public because it is not command machinery - it is *record* machinery, and a
/// network message declares its fields with the identical vocabulary (see
/// [ParamBatch]). One packing rule, one implementation of it: two would be two
/// mental models for one idea, and the one-fact-one-place rule is about exactly
/// that.
final class ParamLayout implements ParamDescriptor {
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

  /// Signed 64-bit, like [hasInt64] and for its reason: `Entity.pack` shifts
  /// the archetype id up into the sign position, so only a signed slot
  /// round-trips every handle unchanged.
  @override
  ParamPointer<Entity> hasEntity() => _EntityPointer(_int(64, true));

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

  void _requireWritten(ParamBuffer call) {
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
  int operator [](ParamBuffer call) {
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
  void operator []=(ParamBuffer call, int value) {
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

/// An `Entity` view over the `int64` field [ParamDescriptor.hasEntity]
/// declares.
///
/// Delegation rather than a fifth `_Pointer` subclass: the byte offset, the
/// 64-bit load and store and the written-mask bookkeeping are already right
/// in the [_IntPointer] this wraps, and a parallel implementation would be a
/// second copy of them to keep in step (the one-fact-one-place rule). It is
/// the command-side twin of `data_layout.dart`'s `_EntityHandleField`, which
/// wraps the component column the same way.
///
/// `Entity` is an extension type over `int`, so it erases: the value handed
/// back is the very `int` the field read, and `Entity(...)` compiles to
/// nothing. The wrapper costs one virtual call per access and no allocation.
final class _EntityPointer implements ParamPointer<Entity> {
  const _EntityPointer(this._raw);

  final ParamPointer<int> _raw;

  @override
  Entity operator [](ParamBuffer call) => Entity(_raw[call]);

  @override
  void operator []=(ParamBuffer call, Entity value) => _raw[call] = value.value;
}

final class _SubBytePointer extends _Pointer<int> {
  const _SubBytePointer(super.index, this.byte, this.shift, this.bitWidth);

  final int byte;
  final int shift;
  final int bitWidth;

  int get _mask => ((1 << bitWidth) - 1) << shift;

  @override
  int operator [](ParamBuffer call) {
    _requireWritten(call);
    final raw = call._data.getUint8(call.offset + byte);
    return (raw & _mask) >> shift;
  }

  @override
  void operator []=(ParamBuffer call, int value) {
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
  double operator [](ParamBuffer call) {
    _requireWritten(call);
    final at = call.offset + byte;
    return bitWidth == 32
        ? call._data.getFloat32(at, Endian.little)
        : call._data.getFloat64(at, Endian.little);
  }

  @override
  void operator []=(ParamBuffer call, double value) {
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
  const _StringPointer(
    super.index,
    this.lengthByte,
    this.maxBytes,
    this.encoding,
  );

  final int lengthByte;
  final int maxBytes;
  final Encoding encoding;

  @override
  String operator [](ParamBuffer call) {
    _requireWritten(call);
    final at = call.offset + lengthByte;
    final length = call._data.getUint16(at, Endian.little);
    if (length == 0) return '';
    return encoding.decode(
      Uint8List.sublistView(call.batch.bytes, at + 2, at + 2 + length),
    );
  }

  @override
  void operator []=(ParamBuffer call, String value) {
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
