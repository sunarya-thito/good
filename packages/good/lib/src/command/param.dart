import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:good/src/declare.dart';
import 'package:good/src/struct.dart';

/// One field of one command's parameter block - the command-side twin of
/// `DataPointer`, and the same shape: one pointer object per *field*, never
/// per call, with the call passed in as the index.
///
/// ```dart
/// myCommand.hi[call] = 123;
/// final back = myCommand.result[call];
/// ```
///
/// The index is a [ParamBuffer], not an `Entity`: a byte range inside a batch
/// is what a command has in place of a row. Reading a field nobody wrote
/// throws instead of reporting zero - see [ParamBuffer].
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
  ParamBuffer(
    this.batch,
    this.ordinal,
    this.layout,
    this.maskOffset,
    this.offset,
  );

  /// The record set these bytes live in. Fixed for life - a handle belongs
  /// to one batch even when its *position* in that batch is re-pointed.
  final ParamBatch batch;

  /// Which record of [batch] this is, counting from zero.
  ///
  /// A record's tail sits directly behind its head, so a record that grows
  /// pushes every record behind it along. That fix-up has to find the records
  /// behind this one, and the ordinal is how.
  int ordinal;

  /// The declaration these bytes are laid out by: where the fixed head ends,
  /// how many fields the mask covers, and where the tail length is kept.
  ParamLayout layout;

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
  int get fieldCount => layout.fieldCount;

  /// Where this record's variable-length tail starts inside [batch], which is
  /// directly behind its fixed head. For a declaration with no
  /// variable-length field this is simply where the record ends.
  int get tailAt => offset + layout.strideBytes;

  /// Re-points this handle at another record of the same batch.
  ///
  /// The offsets are not `final` for one reason: a batch parsed off the
  /// wire is parsed **every tick**, and allocating one handle per record per
  /// tick is exactly the per-frame garbage the no-allocation rule exists to
  /// prevent. So [ParamBatch] keeps its handles and re-points them, and these
  /// fields are mutable to let it - see [ParamBatch.reset], which is the only
  /// thing that makes an outstanding handle stale.
  void _bind(int ordinal, ParamLayout layout, int maskOffset, int offset) {
    this.ordinal = ordinal;
    this.layout = layout;
    this.maskOffset = maskOffset;
    this.offset = offset;
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
/// The shared record container, and *not* command-specific: a command batch
/// crossing an isolate and a network message batch crossing a socket are the
/// same bytes with the same self-describing walk, so they are the same class.
/// `CommandBatch` adds the isolate transport's own facts (an id, a destination,
/// a reply); `good_net`'s message batch adds none at all.
///
/// One call is a batch of one - a bare `await damage(...)` makes one - so there
/// is a single path and no special case. Batching matters because the round
/// trip, not the bytes, is what costs: fifty commands in one batch is one ring
/// record, one wake-up and one reply, where fifty sends are fifty of each. Over
/// a socket the same argument reads "one datagram instead of fifty".
///
/// # Why the layout is not negotiable per batch
///
/// Every record is `[uint16 index][written-mask][head][tail]`, and the index
/// is a position in a declaration order both ends ran. That is what lets the
/// receiver walk a buffer it did not build without a length prefix per
/// record - and what makes a *disagreement* about that order detectable
/// (see [adoptIncoming]) instead of silently misread. Across isolates the two
/// copies run the same pass, so they cannot disagree; across machines they can,
/// so `good_net` puts a hash of the declaration order in its handshake instead
/// of trusting it.
///
/// The head is the declaration's stride and is where every pointer resolves
/// to. The tail is present only for a declaration that has a variable-length
/// field, holds those fields' bytes, and carries its own total length in the
/// head - so the walk stays a forward walk over records whose size it can
/// work out, without the record having to be one fixed size. See
/// [ParamDescriptor], which is where the difference between this and an
/// archetype row is set out.
class ParamBatch {
  ParamBatch({int initialBytes = defaultBytes, this.maxRecordBytes = unbounded})
    // ignore: prefer_initializing_formals - _bytes is reassigned on
    // growth, so it cannot be a final initializing formal.
    : _bytes = Uint8List(initialBytes) {
    _data = ByteData.sublistView(_bytes);
  }

  /// What a batch starts out able to hold, before the first growth.
  static const int defaultBytes = 256;

  /// [maxRecordBytes] for a batch nothing has told a bound to.
  static const int unbounded = -1;

  /// The largest one record of this batch may become - its header, its mask,
  /// its head and its tail - or [unbounded].
  ///
  /// A variable-length field has no capacity of its own to overrun, so the
  /// only thing bounding it is whatever carries the record, and a carrier is
  /// not something the record layer can know about. Whatever does know - a
  /// transport with an MTU, a ring with a capacity - says so here when it
  /// builds the batch, and a write that would carry a record past it throws
  /// at that write instead of at a send half a frame later.
  ///
  /// Per **record**, not per batch: a batch is splittable and
  /// a record is not. Every record starts with the declaration index that
  /// gives its length, so a carrier that cannot take a whole batch can take
  /// it in pieces cut at record boundaries ([startAt] is where those are),
  /// and the only thing no amount of cutting answers is a single record
  /// bigger than one piece.
  final int maxRecordBytes;

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

  /// Whether [_bytes] belongs to this batch.
  ///
  /// False for a batch parsed by [adoptIncoming], which is a window onto
  /// someone else's buffer - a transport's receive buffer, holding other
  /// batches on either side of this one. Reading through that window is the
  /// whole point; *growing* a record inside it would write over a neighbour,
  /// so the first write that needs room takes a private copy first. See
  /// [_growTail], which is the only thing that needs the distinction today.
  bool _owned = true;

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
  /// A method, not something every consumer works out from
  /// `callAt(i).maskOffset - headerBytes`: two places doing that arithmetic is
  /// two places to get it wrong when the header changes (the one-fact-one-place
  /// rule), and the header is this class's business anyway.
  int indexAt(int index) => _data.getUint16(startAt(index), Endian.little);

  /// Where the record at [index] starts in [bytes], its two header bytes
  /// included - so `startAt(i)` up to `startAt(i + 1)` is exactly one record,
  /// and a batch too big for its carrier can be cut at those boundaries
  /// instead of refused. See [maxRecordBytes].
  int startAt(int index) => _calls[index].maskOffset - _headerBytes;

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

  /// Whether a record of [recordBytes] is within [maxRecordBytes].
  bool _fitsRecord(int recordBytes) =>
      maxRecordBytes < 0 || recordBytes <= maxRecordBytes;

  /// Refuses a record that has outgrown what carries this batch.
  ///
  /// [tailBytes] is how much of it a variable-length field put there, which is
  /// zero when it is the fixed head alone that will not fit.
  Never _refuseRecord(int declaration, int recordBytes, int tailBytes) {
    final inTail = tailBytes == 0
        ? ''
        : ', $tailBytes of them written into a variable-length field';
    throw StateError(
      'one record of declaration #$declaration is $recordBytes bytes$inTail, '
      'and what carries this batch takes at most $maxRecordBytes in one '
      'record. A field with no declared length is bounded by its carrier '
      'rather than by its declaration, and this is that bound: send a shorter '
      'value, or split it across several records, where the meaning of the '
      'split is known.',
    );
  }

  /// Takes the last record back off this batch, handle and all.
  ///
  /// What a refused write leaves behind: the record cannot be completed, and
  /// a half-written one that went out anyway would fail on the *reading*
  /// side, at a field nobody wrote, one machine away from the mistake that
  /// caused it. Everything already in the batch is still sendable.
  void _dropLast() {
    if (_callCount == 0) return;
    _end = startAt(_callCount - 1);
    _callCount--;
  }

  /// A handle for the record range just reserved - pooled, see [reset].
  ParamBuffer _record(int maskAt, int payloadAt, ParamLayout layout) {
    final ordinal = _callCount++;
    if (ordinal < _calls.length) {
      final reused = _calls[ordinal];
      reused._bind(ordinal, layout, maskAt, payloadAt);
      return reused;
    }
    final made = ParamBuffer(this, ordinal, layout, maskAt, payloadAt);
    _calls.add(made);
    return made;
  }

  /// Grows the backing buffer to hold at least [needed] bytes, keeping what
  /// is already there.
  ///
  /// Amortized doubling and a copy - the same "grow without losing what it
  /// held" pattern `VertexBatch2D` uses - so a batch that turns out bigger
  /// than guessed costs one copy, not a dropped call.
  void _reserve(int needed) {
    if (needed <= _bytes.length) return;
    var size = _bytes.isEmpty ? defaultBytes : _bytes.length;
    while (size < needed) {
      size *= 2;
    }
    final grown = Uint8List(size)..setRange(0, _end, _bytes);
    _bytes = grown;
    _data = ByteData.sublistView(grown);
  }

  /// Copies an adopted view into a buffer this batch owns, rebased to zero.
  void _privatize() {
    final length = _end - _base;
    final fresh = Uint8List(length)..setRange(0, length, _bytes, _base);
    for (var i = 0; i < _callCount; i++) {
      final call = _calls[i];
      call.maskOffset -= _base;
      call.offset -= _base;
    }
    _bytes = fresh;
    _data = ByteData.sublistView(fresh);
    _base = 0;
    _end = length;
    _owned = true;
  }

  /// Makes room for [count] bytes at the end of [call]'s tail, and answers
  /// where in [bytes] they start.
  ///
  /// A record's tail sits directly behind its own head, not in a pool
  /// at the end of the batch, so that a record stays one contiguous run of
  /// bytes and [adoptIncoming] can keep walking forwards. The cost is that
  /// growing a record in the middle of a batch moves every record behind it.
  /// That is a memmove and a handle fix-up instead of a refusal, because the
  /// case it exists for is a handler writing a variable-length **result**
  /// into a call that is not the last one in its batch, and "send fewer calls
  /// per batch" is no kind of answer to that.
  int _growTail(ParamBuffer call, int count) {
    assert(
      call.layout.hasTail,
      'only a declaration with a variable-length field has a tail to grow',
    );
    if (!_owned) _privatize();
    final slot = call.offset + call.layout.tailSlotByte;
    final tailBytes = _data.getUint32(slot, Endian.little);
    final at = call.tailAt + tailBytes;
    final recordBytes = at + count - startAt(call.ordinal);
    if (!_fitsRecord(recordBytes)) {
      final declaration = indexAt(call.ordinal);
      // Only when it is the last one. A record in the middle is a handler
      // writing a variable-length *result* into a call that is not the last
      // in its batch, and taking that one out would move every record behind
      // it - which is the very thing this refusal is saying it cannot do.
      if (call.ordinal == _callCount - 1) _dropLast();
      _refuseRecord(declaration, recordBytes, tailBytes + count);
    }
    _reserve(_end + count);
    // Backwards, because source and destination overlap.
    for (var i = _end - 1; i >= at; i--) {
      _bytes[i + count] = _bytes[i];
    }
    _bytes.fillRange(at, at + count, 0);
    _end += count;
    for (var i = call.ordinal + 1; i < _callCount; i++) {
      final later = _calls[i];
      later.maskOffset += count;
      later.offset += count;
    }
    _data.setUint32(slot, tailBytes + count, Endian.little);
    return at;
  }

  /// Reserves one record of the declaration at [index] - header, mask and
  /// fixed head - and returns the handle to write it through.
  ///
  /// Only the head is reserved here. A variable-length field appends its
  /// bytes to the record's tail as it is written, which is what lets a
  /// declaration hold a string nobody sized in advance.
  ParamBuffer append(int index, ParamLayout layout) {
    final start = _end;
    final maskBytes = ParamBuffer.maskBytesFor(layout.fieldCount);
    final needed = start + _headerBytes + maskBytes + layout.strideBytes;
    // Nothing to drop: this record does not exist yet.
    if (!_fitsRecord(needed - start)) _refuseRecord(index, needed - start, 0);
    _reserve(needed);
    _data.setUint16(start, index, Endian.little);
    // The reserved range is not guaranteed clean - a grown buffer is, but a
    // reused one is not - and a stale mask byte would report a field as
    // written that nobody wrote. It is also what starts the tail length at
    // zero, which every variable-length write counts up from.
    _bytes.fillRange(start + _headerBytes, needed, 0);
    _end = needed;
    return _record(
      start + _headerBytes,
      start + _headerBytes + maskBytes,
      layout,
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
  /// record starts with its index, the index gives the head stride, and a
  /// declaration that carries a tail keeps that tail's length in its own
  /// head. So the walk needs nothing the receiving side does not already
  /// have. It is also what makes a mismatched declaration list *detectable*
  /// instead of silently misread - a record whose length does not add up runs
  /// off the end of the buffer and says so.
  ///
  /// Reads the records in `[offset, offset + length)` of [wire], defaulting
  /// to the whole of it.
  ///
  /// **Allocation-free on a repeat call**, which is what the network path
  /// needs: [wire] is adopted, not copied, the `ByteData` view over it is kept
  /// when the same buffer comes back (a transport reuses one receive buffer for
  /// the life of the session, so it always does), and the record handles come
  /// from the pool [reset] maintains. A batch parsed this way is a *view*, only
  /// valid until the transport reuses those bytes, so read what you need inside
  /// the call and never keep the record.
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
    _owned = false;
    _base = offset;
    _end = offset + (length ?? wire.length - offset);
    _callCount = 0;
    var at = _base;
    while (at < _end) {
      final index = _data.getUint16(at, Endian.little);
      final layout = layouts.layoutOf(index);
      final maskBytes = ParamBuffer.maskBytesFor(layout.fieldCount);
      final maskAt = at + _headerBytes;
      final payloadAt = maskAt + maskBytes;
      var end = payloadAt + layout.strideBytes;
      // The tail length is read out of the head, so the head has to be inside
      // the buffer before it can be trusted - a truncated record would
      // otherwise be read as a wild length rather than as the overrun it is.
      if (end <= _end && layout.hasTail) {
        end += _data.getUint32(payloadAt + layout.tailSlotByte, Endian.little);
      }
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
      _record(maskAt, payloadAt, layout);
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

  /// How this batch travels - see [HandlerDelivery]. Null until the first
  /// call is routed into it.
  HandlerDelivery? _delivery;

  /// How this batch travels, once something has been routed into it.
  HandlerDelivery? get delivery => _delivery;

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
  void routeTo(HandlerSide side, HandlerDelivery delivery, Type command) {
    final currentDelivery = _delivery;
    if (currentDelivery != null && currentDelivery != delivery) {
      throw StateError(
        '$command is ${delivery.name}-delivered and this batch already holds '
        '${currentDelivery.name}-delivered calls. Each delivery is its own '
        'lane - the tick window, the control port, the per-frame read-only '
        'drain - and a batch is one message down one of them, so they cannot '
        'share it. Use two batches.',
      );
    }
    _delivery = delivery;
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
  void adoptReply(Uint8List reply, ParamLayouts layouts) {
    // Re-walked rather than copied over the bytes that are here. A reply is
    // these records with the handler's writes added, and a handler that wrote
    // a variable-length result made its record longer - so the offsets the
    // caller's ParamBuffers hold are no longer where those records are.
    // [adoptIncoming] re-points the very same pooled handles in the very same
    // record order they were appended in, so a caller still holding the
    // buffer it wrote its parameters through reads its own results back out
    // of it.
    adoptIncoming(reply, layouts);
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
/// Lives here and not beside the command shapes because it is transport
/// vocabulary: a batch's [CommandBatch.destination] and a [CommandSender]'s
/// routing decision are the only things that read it.
@internal
enum HandlerSide { main, game }

/// When a command's handler runs, which decides how its batch travels.
///
/// See `CommandDescriptor.hasControlSink` for what a receipt-delivered
/// command may and may not do.
enum HandlerDelivery {
  /// The default. The batch rides the command ring and is pumped inside the
  /// tick window, so a handler can write component data and a spawned entity
  /// is visible to every system on the tick its command lands.
  ///
  /// It also means the batch arrives **only if the tick runs**: a command
  /// that would stop the tick cannot be delivered this way, because the
  /// message that restarts it would need the tick it stopped.
  tick,

  /// The batch is carried over the control port and run when the port
  /// callback fires, with no tick involved. That is the whole point - it
  /// works while the fixed tick is stopped - and the whole cost: there is no
  /// open write window, so a handler must not touch component data.
  receipt,

  /// The batch rides the command ring exactly as a [tick]-delivered one does,
  /// reply leg and all - but it is queued in its own inbox and run once per
  /// *frame*, from `GameState.advance`, whether or not that frame afforded a
  /// fixed step. So it is answered while the tick is stopped, and answered
  /// over the ring rather than needing a second carrier.
  ///
  /// Two inboxes and not one, because the two cannot share a queue: a single
  /// arrival-ordered inbox drained per frame would run [tick]-delivered
  /// handlers outside the tick window, which is the hazard
  /// `_ControlMessage.stop`'s doc describes. The price of the split is that
  /// there is no ordering *between* the lanes, only within each.
  ///
  /// The handler runs with no tick open, so it must not write - see
  /// `CommandDescriptor.hasReadOnlySupplier`, which is where that promise is
  /// set out and where it is admitted that nothing checks it.
  frame,
}

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
/// An interface, not a direct reference to the registry that owns the
/// declarations: that registry lives a layer up, and pointing back down at it
/// would be a cycle. `CommandRegistry` implements it for commands; `good_net`'s
/// message registry implements it for messages.
abstract interface class ParamLayouts {
  /// The layout of the declaration at [index].
  ///
  /// One method, not a getter per fact. A walk needs the head stride,
  /// the field count and where the tail length is kept, and those three are
  /// one object's business already - handing back the [ParamLayout] keeps
  /// them where they are computed instead of copying each onto whatever
  /// declared it and hoping the copies stay in step.
  ParamLayout layoutOf(int index);
}

/// Declares one command's parameter and result fields.
///
/// The vocabulary is `DataDescriptor`'s: a game that knows how to lay out a
/// component already knows how to lay out a command, and the two
/// really are the same problem - a bit-packed record.
///
/// # Where it stops being the same problem
///
/// An archetype row genuinely needs a stride: a page is an array of rows and
/// a row is *reached* by multiplying, so a variable-length field would break
/// random access outright. A record is not reached that way. It is walked
/// forwards from the front of a batch, and pre-built handles hold absolute
/// offsets, so the stride is used as a record *length* and never as a
/// multiplier. That is the weaker requirement, and it is what lets a record
/// carry a variable-length field where a row cannot.
///
/// So a record has a fixed **head** and, if it declares a variable-length
/// field, a **tail** behind it. [hasString] and [hasBytes] put an offset and
/// a length in the head and their payload in the tail; the record's total
/// tail length lives in the head too, which is what keeps the walk
/// self-describing. A pointer still resolves to a fixed offset in the head,
/// so nothing about the `XPointer` pattern changes.
///
/// [hasFixedString] and [hasFixedBytes] are the other answer, kept because it
/// is sometimes the right one: capacity reserved inline, no tail, and a value
/// that does not fit is an error instead of a resize. Reach for them when
/// the field really does have a bound - a four-character country code, a
/// 16-byte digest - and for anything else declare the length-free kind.
abstract class ParamDescriptor {
  ParamPointer<int> hasUint1();
  ParamPointer<int> hasUint2();
  ParamPointer<int> hasUint4();
  ParamPointer<int> hasUint8();
  ParamPointer<int> hasUint16();
  ParamPointer<int> hasUint32();
  ParamPointer<int> hasInt8();
  ParamPointer<int> hasInt16();
  ParamPointer<int> hasInt32();
  ParamPointer<int> hasInt64();
  ParamPointer<double> hasFloat32();
  ParamPointer<double> hasFloat64();

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

  /// A string of no declared length.
  ///
  /// The head carries an offset and a length; the bytes go in the record's
  /// tail as they are written, so nothing has to be sized in advance and
  /// nothing is reserved for a value that never arrives. What bounds it is
  /// the carrier the record leaves through, not the declaration - see
  /// [ParamBatch.maxRecordBytes], which a carrier sets and which throws at
  /// the write, and `CommandTransport.send`, which refuses a whole batch the
  /// command ring could never carry.
  ///
  /// **Written once per record.** The tail is filled by appending, so a
  /// second value cannot take the first one's place without moving everything
  /// declared behind it; a second write throws instead of silently
  /// rearranging the record. Build the value, then write it.
  ParamPointer<String> hasString({Encoding encoding = utf8});

  /// A string of at most [maxBytes] **bytes** - not characters, since that is
  /// what the buffer actually reserves and a caller sizing a field should be
  /// thinking in the unit that can overflow.
  ///
  /// Reserved inline in every record of this declaration, whether it is
  /// written or not, and a longer value is an error at the write. Use
  /// [hasString] unless the bound is real.
  ParamPointer<String> hasFixedString(int maxBytes, {Encoding encoding = utf8});

  /// Bytes of no declared length - the untyped twin of [hasString], and what
  /// a list of anything is packed into.
  ///
  /// Reading one hands back a **view** onto the batch's own buffer, not a
  /// copy, which is what keeps a per-tick network message off the allocator. A
  /// batch parsed off a wire is only valid until its transport reuses those
  /// bytes, so read what you need inside the call and never keep the list - the
  /// same rule `ParamBatch.adoptIncoming` states for the record as a whole.
  ///
  /// **Written once per record**, for [hasString]'s reason.
  ParamPointer<Uint8List> hasBytes();

  /// Bytes with capacity reserved inline, at most [maxBytes] of them - the
  /// untyped twin of [hasFixedString], and reading one is a view for
  /// [hasBytes]'s reason.
  ParamPointer<Uint8List> hasFixedBytes(int maxBytes);
}

/// Declares a command's or a message's parameter on the field that holds it:
///
/// ```dart
/// class SpawnEnemy extends SinkCommand<int> {
///   final flags = Param.uint2();
///
///   @override
///   void bufferFromParams(ParamBuffer call, int params) =>
///       flags[call] = params;
///
///   @override
///   int paramsFromBuffer(ParamBuffer call) => flags[call];
/// }
/// ```
///
/// One name per [ParamDescriptor] method, minus the `has` that only ever
/// read as noise once the declaration moved to the field - the same trade
/// `Field` made for a component column.
///
/// # Why the framework has to construct the command
///
/// A [ParamLayout] is a bit cursor. Every field takes its offset from where
/// the one before it stopped, so the layout has to be *open* before the
/// first initialiser runs - and an initialiser cannot see `this`, let alone
/// an argument a later method would have been handed. So the layout goes on
/// [DeclarationContext] first and the object is built second, which is why
/// `CommandDescriptor.has` and `NetDescriptor.has` take `SpawnEnemy.new`
/// and not `SpawnEnemy()`.
///
/// # Eager, always
///
/// `late final flags = Param.uint2()` compiles and is wrong twice over. The
/// call runs on the first *read*, so the bit offsets follow whatever order
/// something happened to touch the fields; two builds that touch them
/// differently lay the record out differently and the two ends disagree
/// about where a parameter is, silently, on bytes that still parse. It is
/// also outside the window the framework opened, so it throws - see
/// [DeclarationContext.params] and [ParamLayout.seal], which catch the two
/// halves of it.
///
/// `describeParams` is not going anywhere; a command may declare through
/// either, and one that declares through both gets its fields first and its
/// hook's second.
abstract final class Param {
  /// See [ParamDescriptor.hasUint1].
  static ParamPointer<int> uint1() => DeclarationContext.params.hasUint1();

  /// See [ParamDescriptor.hasUint2].
  static ParamPointer<int> uint2() => DeclarationContext.params.hasUint2();

  /// See [ParamDescriptor.hasUint4].
  static ParamPointer<int> uint4() => DeclarationContext.params.hasUint4();

  /// See [ParamDescriptor.hasUint8].
  static ParamPointer<int> uint8() => DeclarationContext.params.hasUint8();

  /// See [ParamDescriptor.hasUint16].
  static ParamPointer<int> uint16() => DeclarationContext.params.hasUint16();

  /// See [ParamDescriptor.hasUint32].
  static ParamPointer<int> uint32() => DeclarationContext.params.hasUint32();

  /// See [ParamDescriptor.hasInt8].
  static ParamPointer<int> int8() => DeclarationContext.params.hasInt8();

  /// See [ParamDescriptor.hasInt16].
  static ParamPointer<int> int16() => DeclarationContext.params.hasInt16();

  /// See [ParamDescriptor.hasInt32].
  static ParamPointer<int> int32() => DeclarationContext.params.hasInt32();

  /// See [ParamDescriptor.hasInt64].
  static ParamPointer<int> int64() => DeclarationContext.params.hasInt64();

  /// See [ParamDescriptor.hasFloat32].
  static ParamPointer<double> float32() =>
      DeclarationContext.params.hasFloat32();

  /// See [ParamDescriptor.hasFloat64].
  static ParamPointer<double> float64() =>
      DeclarationContext.params.hasFloat64();

  /// See [ParamDescriptor.hasEntity], including its warning that a stored
  /// handle outlives the entity it names.
  static ParamPointer<Entity> entity() => DeclarationContext.params.hasEntity();

  /// See [ParamDescriptor.hasString], including its rule that a record's
  /// tail is written once.
  static ParamPointer<String> string({Encoding encoding = utf8}) =>
      DeclarationContext.params.hasString(encoding: encoding);

  /// See [ParamDescriptor.hasFixedString].
  static ParamPointer<String> fixedString(
    int maxBytes, {
    Encoding encoding = utf8,
  }) => DeclarationContext.params.hasFixedString(maxBytes, encoding: encoding);

  /// See [ParamDescriptor.hasBytes], including its rule that reading one
  /// hands back a view onto the batch's own buffer.
  static ParamPointer<Uint8List> bytes() =>
      DeclarationContext.params.hasBytes();

  /// See [ParamDescriptor.hasFixedBytes].
  static ParamPointer<Uint8List> fixedBytes(int maxBytes) =>
      DeclarationContext.params.hasFixedBytes(maxBytes);
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
  int _tailSlotByte = -1;
  final List<int> _signature = <int>[];
  Uint8List? _signatureBytes;

  /// The record's fixed head, in bytes, rounded up from the bit cursor.
  ///
  /// Still a stride in the sense that matters - every record of this
  /// declaration has the same head, and every pointer resolves to a fixed
  /// offset in it - but no longer the whole record. A declaration with a
  /// variable-length field carries a tail behind the head whose length is
  /// decided by what was written; see [tailSlotByte].
  int get strideBytes => (_bitCursor + 7) >> 3;

  int get fieldCount => _fieldCount;

  /// Where in the head this record's total tail length is kept, as a
  /// little-endian uint32 - or -1 for a declaration with no variable-length
  /// field, which is what [hasTail] asks.
  ///
  /// One number per record, not a sum over the variable fields.
  /// [ParamBatch.adoptIncoming] reads it to find where a record ends, and a
  /// walk that had to add fields up would first have to consult the
  /// written-mask to know which of them contributed anything.
  int get tailSlotByte => _tailSlotByte;

  /// Whether records of this declaration can carry a tail at all.
  bool get hasTail => _tailSlotByte >= 0;

  /// A compact description of what this record's fields *are*, in declaration
  /// order: per field a kind code and either its width in bits or, for a
  /// capacity-capped string or byte field, that capacity; plus, for a string,
  /// the name of its encoding.
  ///
  /// `good_net` mixes this into its handshake hash. #141's rule is that the
  /// hash carries the wire format and nothing else, and a field's kind is
  /// wire format twice over. A variable-length field's four head bytes are an
  /// offset into the tail, not a value, so a peer that declared a `uint32`
  /// where the sender declared a [hasString] does not misread one field - it
  /// computes the wrong tail length and loses every record behind it. And
  /// `hasInt32` against `hasFloat32` has always been invisible to a hash made
  /// of stride and field count, which are equal for both.
  Uint8List get signature {
    final bytes = _signatureBytes;
    if (bytes == null) {
      throw StateError(
        'a layout signature is only settled once its describeParams pass has '
        'run, and seal() has not been called on this one yet.',
      );
    }
    return bytes;
  }

  void seal() {
    if (_sealed) return;
    _sealed = true;
    _signatureBytes = Uint8List.fromList(_signature);
  }

  /// Builds [create]'s object with this layout open, so the `Param.*` calls
  /// in its field initialisers declare into it, and hands the object back.
  ///
  /// The one place the window is opened. `CommandRegistry.declare` and
  /// `good_net`'s `NetRegistry.declare` both come through here rather than
  /// touching [DeclarationContext] themselves - a command crossing an
  /// isolate and a message crossing a socket are the same record, and two
  /// copies of "when is a layout open" is exactly the drift this file's
  /// one-packing-rule note is about.
  ///
  /// The pop is in a `finally`: a constructor that throws must not leave the
  /// next declaration writing into a layout nobody owns.
  T open<T>(T Function() create) {
    DeclarationContext.pushParams(this);
    try {
      return create();
    } finally {
      DeclarationContext.popParams();
    }
  }

  /// Records what the field just declared is, for [signature].
  void _note(int kind, int detail) {
    _signature
      ..add(kind)
      ..add(detail & 0xFF)
      ..add((detail >> 8) & 0xFF);
  }

  /// The encoding's own name - `utf-8`, `iso-8859-1` - which is a value the
  /// codec declares about itself and not a Dart class name, so it is stable
  /// under a rename and under `--obfuscate`. That is exactly the
  /// distinction #141 turned on.
  void _noteEncoding(Encoding encoding) {
    final name = encoding.name;
    _signature.add(name.length & 0xFF);
    for (var i = 0; i < name.length; i++) {
      _signature.add(name.codeUnitAt(i) & 0xFF);
    }
  }

  /// Reserves the record's tail-length slot, once, at the first
  /// variable-length field to ask for it. Both ends run the same declaration
  /// pass, so both put it in the same place.
  void _declareTailSlot() {
    if (_tailSlotByte < 0) _tailSlotByte = _declare(32) >> 3;
  }

  /// Reserves a variable-length field's head - `[uint32 offset][uint32
  /// length]` - and answers where it starts. The offset is counted from the
  /// start of the record's tail, not from the batch, so it survives the record
  /// being moved along by a neighbour that grew.
  int _declareTailSlots() {
    _declareTailSlot();
    final slot = _declare(32) >> 3;
    _declare(32);
    return slot;
  }

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

  ParamPointer<int> _int(int bitWidth, bool signed, [int? kind]) {
    final bitOffset = _declare(bitWidth);
    _note(kind ?? (signed ? _FieldKind.sint : _FieldKind.uint), bitWidth);
    final index = _fieldCount++;
    if (bitWidth < 8) {
      return _SubBytePointer(index, bitOffset >> 3, bitOffset & 7, bitWidth);
    }
    return _IntPointer(index, bitOffset >> 3, bitWidth, signed);
  }

  @override
  ParamPointer<int> hasUint1() => _int(1, false);
  @override
  ParamPointer<int> hasUint2() => _int(2, false);
  @override
  ParamPointer<int> hasUint4() => _int(4, false);
  @override
  ParamPointer<int> hasUint8() => _int(8, false);
  @override
  ParamPointer<int> hasUint16() => _int(16, false);
  @override
  ParamPointer<int> hasUint32() => _int(32, false);
  @override
  ParamPointer<int> hasInt8() => _int(8, true);
  @override
  ParamPointer<int> hasInt16() => _int(16, true);
  @override
  ParamPointer<int> hasInt32() => _int(32, true);
  @override
  ParamPointer<int> hasInt64() => _int(64, true);

  @override
  ParamPointer<double> hasFloat32() {
    final byte = _declare(32) >> 3;
    _note(_FieldKind.float, 32);
    return _FloatPointer(_fieldCount++, byte, 32);
  }

  @override
  ParamPointer<double> hasFloat64() {
    final byte = _declare(64) >> 3;
    _note(_FieldKind.float, 64);
    return _FloatPointer(_fieldCount++, byte, 64);
  }

  /// Signed 64-bit, like [hasInt64] and for its reason: `Entity.pack` shifts
  /// the archetype id up into the sign position, so only a signed slot
  /// round-trips every handle unchanged.
  @override
  ParamPointer<Entity> hasEntity() =>
      _EntityPointer(_int(64, true, _FieldKind.entity));

  @override
  ParamPointer<String> hasString({Encoding encoding = utf8}) {
    final slot = _declareTailSlots();
    _note(_FieldKind.stringTail, 0);
    _noteEncoding(encoding);
    return _TailStringPointer(_fieldCount++, slot, encoding);
  }

  @override
  ParamPointer<Uint8List> hasBytes() {
    final slot = _declareTailSlots();
    _note(_FieldKind.bytesTail, 0);
    return _TailBytesPointer(_fieldCount++, slot);
  }

  @override
  ParamPointer<String> hasFixedString(
    int maxBytes, {
    Encoding encoding = utf8,
  }) {
    final lengthByte = _declareInline(maxBytes, 'hasFixedString');
    _note(_FieldKind.stringFixed, maxBytes);
    _noteEncoding(encoding);
    return _StringPointer(_fieldCount++, lengthByte, maxBytes, encoding);
  }

  @override
  ParamPointer<Uint8List> hasFixedBytes(int maxBytes) {
    final lengthByte = _declareInline(maxBytes, 'hasFixedBytes');
    _note(_FieldKind.bytesFixed, maxBytes);
    return _BytesPointer(_fieldCount++, lengthByte, maxBytes);
  }

  /// A 16-bit length followed by [maxBytes] reserved bytes, and the head
  /// offset of that length. Both are byte-aligned because the length is
  /// declared as a 16-bit field, which forces alignment first.
  int _declareInline(int maxBytes, String at) {
    if (maxBytes <= 0 || maxBytes > 0xFFFF) {
      throw ArgumentError.value(
        maxBytes,
        'maxBytes',
        'a $at field reserves this many bytes in every record of this '
            'declaration, so it has to be a positive number that fits its own '
            '16-bit length prefix. For a field with no real bound, declare it '
            'with hasString() or hasBytes() and let it live in the tail',
      );
    }
    final lengthByte = _declare(16) >> 3;
    for (var i = 0; i < maxBytes; i++) {
      _declare(8);
    }
    return lengthByte;
  }
}

/// What kind of thing a field is, as it goes into [ParamLayout.signature] and
/// from there into `good_net`'s handshake hash.
///
/// **These numbers are on the wire.** Renumbering one makes two builds of the
/// same source refuse each other at handshake, so add at the end and never
/// reuse a code.
abstract final class _FieldKind {
  static const int uint = 0;
  static const int sint = 1;
  static const int float = 2;
  static const int entity = 3;
  static const int stringFixed = 4;
  static const int stringTail = 5;
  static const int bytesFixed = 6;
  static const int bytesTail = 7;
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
/// Delegation, not a fifth `_Pointer` subclass: the byte offset, the
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

/// Shared mechanics for a field whose capacity is reserved inline: a 16-bit
/// length at [lengthByte], then [maxBytes] bytes of room behind it, written
/// or not.
abstract class _InlinePointer<T> extends _Pointer<T> {
  const _InlinePointer(super.index, this.lengthByte, this.maxBytes);

  final int lengthByte;
  final int maxBytes;

  /// Which declaration to name when a value will not fit, and which
  /// length-free declaration to point at instead.
  String get declaredBy;
  String get insteadOf;

  int _length(ParamBuffer call) =>
      call._data.getUint16(call.offset + lengthByte, Endian.little);

  int _payloadAt(ParamBuffer call) => call.offset + lengthByte + 2;

  /// Refuses a value the declaration cannot hold instead of storing as much of
  /// it as fits. A truncated string is a value the receiver has no way to
  /// tell from a short one, and it crosses an isolate or a socket before
  /// anyone finds out.
  void _store(ParamBuffer call, List<int> encoded, Object value) {
    if (encoded.length > maxBytes) {
      throw ArgumentError.value(
        value,
        'value',
        'is ${encoded.length} bytes, and this field reserved $maxBytes. A '
            '$declaredBy field reserves its capacity inline in every record, '
            'so the capacity is part of the declaration - raise it at '
            '$declaredBy(), send less, or declare the field with $insteadOf(), '
            'which reserves nothing and has no capacity to overrun',
      );
    }
    final at = call.offset + lengthByte;
    call._data.setUint16(at, encoded.length, Endian.little);
    call.batch.bytes.setRange(at + 2, at + 2 + encoded.length, encoded);
    call._markWritten(index);
  }
}

final class _StringPointer extends _InlinePointer<String> {
  const _StringPointer(
    super.index,
    super.lengthByte,
    super.maxBytes,
    this.encoding,
  );

  final Encoding encoding;

  @override
  String get declaredBy => 'hasFixedString';
  @override
  String get insteadOf => 'hasString';

  @override
  String operator [](ParamBuffer call) {
    _requireWritten(call);
    final length = _length(call);
    if (length == 0) return '';
    final at = _payloadAt(call);
    return encoding.decode(
      Uint8List.sublistView(call.batch.bytes, at, at + length),
    );
  }

  @override
  void operator []=(ParamBuffer call, String value) =>
      _store(call, encoding.encode(value), value);
}

final class _BytesPointer extends _InlinePointer<Uint8List> {
  const _BytesPointer(super.index, super.lengthByte, super.maxBytes);

  @override
  String get declaredBy => 'hasFixedBytes';
  @override
  String get insteadOf => 'hasBytes';

  @override
  Uint8List operator [](ParamBuffer call) {
    _requireWritten(call);
    final at = _payloadAt(call);
    return Uint8List.sublistView(call.batch.bytes, at, at + _length(call));
  }

  @override
  void operator []=(ParamBuffer call, Uint8List value) =>
      _store(call, value, value);
}

/// Shared mechanics for a field whose payload lives in the record's tail.
///
/// The head holds `[uint32 offset][uint32 length]` at [slotByte], so the
/// pointer still resolves to a fixed offset in a fixed head and the
/// `XPointer` pattern is untouched - what stops being constant is only the
/// record's total size. The offset is counted from the start of the record's
/// tail, not from the batch, so it stays correct when a record in front of
/// this one grows and pushes this one along.
abstract class _TailPointer<T> extends _Pointer<T> {
  const _TailPointer(super.index, this.slotByte);

  final int slotByte;

  int _payloadAt(ParamBuffer call) =>
      call.tailAt + call._data.getUint32(call.offset + slotByte, Endian.little);

  int _length(ParamBuffer call) =>
      call._data.getUint32(call.offset + slotByte + 4, Endian.little);

  /// Appends [payload] to this record's tail and records where it landed.
  ///
  /// The declaration has no capacity to overrun, so what refuses an
  /// oversized value is the carrier instead: a batch built with
  /// [ParamBatch.maxRecordBytes] throws here, at the write, and
  /// `CommandTransport.send` refuses a whole batch the command ring could
  /// never carry. Neither one truncates.
  void _store(ParamBuffer call, List<int> payload) {
    if (call._isWritten(index)) {
      throw StateError(
        'field #$index of this record has already been written, and a '
        'variable-length field is written once. Its bytes were appended to '
        'the tail, so a second value cannot take the first one\'s place '
        'without moving every field declared behind it. Build the whole value '
        'first, then write it.',
      );
    }
    final at = call.batch._growTail(call, payload.length);
    final slot = call.offset + slotByte;
    call._data
      ..setUint32(slot, at - call.tailAt, Endian.little)
      ..setUint32(slot + 4, payload.length, Endian.little);
    call.batch.bytes.setRange(at, at + payload.length, payload);
    call._markWritten(index);
  }
}

final class _TailStringPointer extends _TailPointer<String> {
  const _TailStringPointer(super.index, super.slotByte, this.encoding);

  final Encoding encoding;

  @override
  String operator [](ParamBuffer call) {
    _requireWritten(call);
    final length = _length(call);
    if (length == 0) return '';
    final at = _payloadAt(call);
    return encoding.decode(
      Uint8List.sublistView(call.batch.bytes, at, at + length),
    );
  }

  @override
  void operator []=(ParamBuffer call, String value) =>
      _store(call, encoding.encode(value));
}

final class _TailBytesPointer extends _TailPointer<Uint8List> {
  const _TailBytesPointer(super.index, super.slotByte);

  @override
  Uint8List operator [](ParamBuffer call) {
    _requireWritten(call);
    final at = _payloadAt(call);
    return Uint8List.sublistView(call.batch.bytes, at, at + _length(call));
  }

  @override
  void operator []=(ParamBuffer call, Uint8List value) => _store(call, value);
}
