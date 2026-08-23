import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:good/src/command/command.dart';
import 'package:good/src/command/param.dart';
import 'package:good/src/ring_buffer.dart';

/// Carries command batches between the two copies of a `Game`, and answers
/// them.
///
/// This is the [CommandSender] a real game runs on - the thing
/// `command_param_test.dart`'s loopback stands in for. What it adds over that
/// loopback is the whole of the transport: two ring buffers, a reply that
/// travels back as bytes, and a `Completer` per batch that the reply
/// completes.
///
/// # Two rings, one producer each
///
/// A `RingBuffer` is single-producer/single-consumer, and command traffic
/// runs in *both* directions - a HUD button spawning an entity, and a game
/// system asking the Flutter isolate for something only it can answer. So
/// there are two rings, not one, and each copy writes to exactly one of them:
///
/// ```
///   main isolate  --- commandsToGame --->  game isolate
///   main isolate  <--- commandsToMain ---  game isolate
/// ```
///
/// Both *requests* and *replies* travel on the ring belonging to the copy
/// that emits them, tagged by the ring record's own type field
/// ([requestRecord] / [replyRecord]) - so a reply to a main-issued request
/// comes back on `commandsToMain`, sharing the lane with the game isolate's
/// own outgoing requests, and ordering between the two is preserved for free.
///
/// # Batch ids
///
/// Each copy numbers its own batches from zero, and a reply echoes the id it
/// was asked under. The two copies' id spaces never meet: a reply is only
/// ever looked up in [_pending] by the copy that put it there, and the other
/// side treats the id as an opaque tag. So there is no shared counter to
/// synchronise and no handshake to get wrong.
///
/// # Where an incoming batch runs
///
/// A batch bound for the **game** isolate is queued and dispatched inside the
/// fixed tick window, before any system runs - which is what makes an entity
/// spawned by a command visible to every system on the tick it lands. A batch
/// bound for the **main** isolate runs as soon as it is noticed, because
/// nothing over there is tick-bound.
///
/// That distinction is by *destination*, not by transport, so it holds in the
/// single-copy inline configuration too: `start(inline: true)` uses no rings
/// at all, and a game-handled command still waits for the next tick rather
/// than running inside the widget callback that sent it. One timing model,
/// whichever way the game was booted.
@internal
final class CommandTransport implements CommandSender {
  /// Ring record types. Two, because both directions carry both kinds.
  static const int requestRecord = 0;
  static const int replyRecord = 1;

  /// Set immediately after construction: the registry and the transport are
  /// two halves of one thing and each needs the other, which one constructor
  /// argument cannot express.
  late final CommandRegistry registry;

  /// This copy's producer end - where requests and replies go out. Null in
  /// the inline configuration, and before `Game.start()` has finished the
  /// handoff.
  RingBuffer? outbound;

  /// This copy's consumer end - drained by [pump].
  RingBuffer? inbound;

  /// Carries a receipt-delivered batch to the other copy, or null when there
  /// is no other copy. A callback rather than a `SendPort` so this layer
  /// never learns the control port's message vocabulary - `GameRuntime`
  /// wraps these bytes in whatever shape it already speaks.
  void Function(Uint8List bytes)? controlSend;

  int _nextId = 0;

  /// Batches this copy has sent and not yet had answered, by id.
  final Map<int, _Pending> _pending = <int, _Pending>{};

  /// Batches bound for this copy that have not been run yet.
  final List<_Inbound> _inbox = <_Inbound>[];

  /// Scratch for the drained-record list, reused across pumps - the same
  /// reasoning as `RingBuffer.drainInto`'s own.
  final List<RingBufferRecord> _drained = <RingBufferRecord>[];

  /// Scratch for the id-prefixed wire image of an outgoing batch, grown on
  /// demand and reused. One memcpy per batch sent, at user-action rate: the
  /// alternative is reserving transport bytes inside every `CommandBatch`,
  /// which would put the transport's header in the record format's business.
  Uint8List _scratch = Uint8List(0);

  bool _shutdown = false;

  @override
  CommandBatch newBatch() {
    final id = _nextId;
    // Wrapped rather than left to grow, because the id crosses the wire as a
    // uint32. A batch is only in flight for a tick or two, so a wrap can only
    // collide with an id that was answered a very long time ago.
    _nextId = (id + 1) & 0xFFFFFFFF;
    return CommandBatch(id, sender: this);
  }

  @override
  Future<void> send(CommandBatch batch) {
    final destination = batch.destination;
    // An empty batch has no destination because nothing was ever added to it.
    // Nothing to run, nothing to wait for.
    if (destination == null) return Future<void>.value();
    if (_shutdown) {
      throw StateError(
        'this game has stopped, so there is nowhere to send a command batch. '
        'The ring buffers are freed by stop().',
      );
    }
    // Receipt delivery: run on arrival, never wait for a tick window. That is
    // the whole point - a command that stops the tick cannot be delivered by
    // the tick - and it is why this completes as soon as the bytes are handed
    // over rather than when the handler has run. There is no reply leg,
    // because a reply would be pumped inside the tick this exists to work
    // without and the caller would wait forever.
    if (batch.delivery == HandlerDelivery.receipt) {
      if (registry.handles(destination)) {
        registry.dispatch(batch);
        return Future<void>.value();
      }
      final carry = controlSend;
      if (carry == null) {
        throw StateError(
          'a control command has nowhere to go: this copy of the Game is not '
          'connected to the other one. Await start() first.',
        );
      }
      carry(
        Uint8List.fromList(
          Uint8List.sublistView(
            batch.bytes,
            batch.start,
            batch.start + batch.length,
          ),
        ),
      );
      return Future<void>.value();
    }
    if (registry.handles(destination)) {
      if (destination == HandlerSide.main) {
        registry.dispatch(batch);
        return Future<void>.value();
      }
      // Handled here, but on the game side - so it waits for the tick window
      // exactly as a batch that arrived over a ring would.
      final completer = Completer<void>();
      _inbox.add(_Inbound(batch, completer));
      return completer.future;
    }

    final ring = outbound;
    if (ring == null) {
      throw StateError(
        '${batch.destination!.name}-isolate commands have nowhere to go: this '
        'copy of the Game is not connected to the other one. Await start() '
        'first - the game isolate allocates both command rings and announces '
        'their addresses as part of coming up.',
      );
    }
    // The batch itself grows to hold whatever was written into it, including
    // a variable-length field's tail, so the only bound on a record's size is
    // the ring's - and a batch over that bound will not fit however long the
    // other isolate is given to drain. Checked here rather than left to
    // [tryWrite]'s `false`, which cannot tell the two apart.
    if (_idBytes + batch.length > ring.maxPayloadBytes) {
      throw StateError(
        'this command batch is ${batch.length} bytes and the command ring can '
        'carry at most ${ring.maxPayloadBytes - _idBytes} in one record, so '
        'it will never fit - draining does not help. Raise '
        'Game.commandBufferBytes, split the batch, or send a shorter value: '
        'a variable-length parameter is bounded by the carrier rather than by '
        'its declaration, and this is that bound.',
      );
    }
    final pending = _Pending(batch, Completer<void>());
    _pending[batch.id] = pending;
    if (!_write(ring, requestRecord, batch.id, batch.bytes, batch.length)) {
      _pending.remove(batch.id);
      throw StateError(
        'the command ring is full - ${batch.callCount} more calls '
        '(${batch.length} bytes) will not fit before the other isolate drains '
        'it. Raise Game.commandBufferBytes, or send less between ticks.',
      );
    }
    return pending.completer.future;
  }

  /// Takes in everything the other copy has said since the last call, and
  /// answers whatever is due.
  ///
  /// Called once per fixed tick on the game isolate (from
  /// `GameState.runFixedStep`, inside the tick window and before any system)

  /// Runs a receipt-delivered batch that arrived over the control port.
  ///
  /// Straight to [CommandRegistry.dispatch] with no inbox: the inbox is what
  /// makes a batch wait for the tick window, and waiting is exactly what this
  /// carrier exists to avoid. Same `adoptIncoming` the ring path uses - the
  /// record format does not change with the carrier.
  void receiveControlBatch(Uint8List bytes) {
    if (_shutdown) return;
    registry.dispatch(
      CommandBatch(-1, initialBytes: bytes.length)
        ..adoptIncoming(bytes, registry),
    );
  }

  /// and once per tick notification on the main isolate. Cheap when nothing
  /// has arrived: one cursor comparison and an empty list.
  void pump() {
    _receive();
    _runInbox();
  }

  /// Drains the inbound ring: requests join the inbox, replies complete the
  /// send that asked for them.
  void _receive() {
    final ring = inbound;
    if (ring == null) return;
    final drained = _drained..clear();
    ring.drainInto(drained);
    for (var i = 0; i < drained.length; i++) {
      final record = drained[i];
      final payload = record.payload;
      final id = ByteData.sublistView(payload).getUint32(0, Endian.little);
      // Copied out of the ring rather than viewed in place. drainInto has
      // already published the read cursor, so the producer may overwrite
      // these bytes at any moment - and both a queued request (which runs
      // later in this same pump, after arbitrary handler code) and a reply
      // (which is copied over a batch the caller still holds) outlive this
      // loop.
      final bytes = Uint8List.fromList(
        Uint8List.sublistView(payload, _idBytes),
      );
      if (record.recordType == requestRecord) {
        _inbox.add(
          _Inbound(
            CommandBatch(id, initialBytes: bytes.length)
              ..adoptIncoming(bytes, registry),
            null,
          ),
        );
        continue;
      }
      final pending = _pending.remove(id);
      if (pending == null) {
        // Only reachable if the other copy echoed an id this one never sent,
        // which means the wire is out of step with the code on it.
        assert(
          false,
          'a command reply names batch #$id, which this copy is '
          'not waiting for',
        );
        continue;
      }
      pending.batch.adoptReply(bytes, registry);
      pending.completer.complete();
    }
  }

  /// Runs the batches waiting for this copy, in arrival order, and answers
  /// each one.
  void _runInbox() {
    // Snapshotted before the loop: a handler may itself send a batch back to
    // this same side, and running that one here too would let one command
    // decide how many more run this tick. It waits for the next pump, like
    // anything else that arrives after this one started.
    final due = _inbox.length;
    if (due == 0) return;
    for (var i = 0; i < due; i++) {
      final inbound = _inbox[i];
      final batch = inbound.batch;
      registry.dispatch(batch);
      final local = inbound.local;
      if (local != null) {
        // Never crossed a boundary - the caller is still holding this exact
        // batch, with the handler's writes already in it.
        local.complete();
        continue;
      }
      final ring = outbound;
      if (ring == null) continue;
      if (!_write(ring, replyRecord, batch.id, batch.bytes, batch.length)) {
        // The sender is awaiting this and will now wait forever, so it is worth
        // being loud about (the assert-not-print rule). Dropping is still
        // better than blocking a tick on a ring only the other isolate can
        // drain.
        assert(
          false,
          'the reply ring is full, so batch #${batch.id} has been run but its '
          'caller will never hear back. Raise Game.commandBufferBytes.',
        );
      }
    }
    _inbox.removeRange(0, due);
  }

  /// The batch id in front of every ring record - see [_write].
  static const int _idBytes = 4;

  /// Writes `[uint32 id][batch bytes]` as one ring record.
  bool _write(
    RingBuffer ring,
    int recordType,
    int id,
    Uint8List bytes,
    int length,
  ) {
    final needed = _idBytes + length;
    if (_scratch.length < needed) _scratch = Uint8List(needed);
    final scratch = _scratch;
    ByteData.sublistView(
      scratch,
      0,
      _idBytes,
    ).setUint32(0, id, Endian.little);
    scratch.setRange(_idBytes, needed, bytes);
    return ring.tryWrite(recordType, Uint8List.sublistView(scratch, 0, needed));
  }

  /// Drops the rings and fails everything still in flight.
  ///
  /// Called from `Game.stop()`. A batch whose answer was going to arrive over
  /// memory that has just been freed is never going to arrive, and an
  /// `await` that hangs forever is the worst way to report that.
  void shutdown() {
    _shutdown = true;
    outbound = null;
    inbound = null;
    _inbox.clear();
    if (_pending.isEmpty) return;
    final abandoned = _pending.values.toList(growable: false);
    _pending.clear();
    for (var i = 0; i < abandoned.length; i++) {
      abandoned[i].completer.completeError(
        StateError(
          'the game stopped before command batch #${abandoned[i].batch.id} '
          'was answered.',
        ),
      );
    }
  }
}

/// A batch this copy sent, waiting for its reply.
final class _Pending {
  _Pending(this.batch, this.completer);

  final CommandBatch batch;
  final Completer<void> completer;
}

/// A batch bound for this copy, waiting to be run.
final class _Inbound {
  _Inbound(this.batch, this.local);

  final CommandBatch batch;

  /// Non-null when the batch never left this isolate - there is a caller to
  /// complete directly rather than a reply to write.
  final Completer<void>? local;
}
