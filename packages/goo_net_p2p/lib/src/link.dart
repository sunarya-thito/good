import 'dart:io';
import 'dart:typed_data';

import 'package:goo_net/goo_net.dart';

import 'wire.dart';

/// One connection's worth of protocol: sequencing, acknowledgement,
/// retransmission, fragmentation, reassembly and liveness.
///
/// The host has one of these per client and a client has exactly one, to the
/// host - the star [NetSession] describes. Everything here is per *link*,
/// because that is the scope every one of those mechanisms actually has: two
/// clients' packet loss has nothing to do with each other.
///
/// # What is deliberately not here
///
/// Congestion control. This sends what the game asks it to, as fast as the
/// game asks for it, and reports [packetLoss] so a game can decide to send
/// less. A real congestion controller (a send-rate that backs off when loss
/// rises) is a genuine piece of work with genuine failure modes, and pretending
/// to have one by dropping packets at a fixed threshold would be worse than
/// not having one - so it is named as missing rather than approximated.
class P2PLink implements NetConnection {
  /// Built by `P2PNetTransport`, which is the only thing that can supply the
  /// four callbacks - they are how a link reaches the one socket, the one
  /// delivery queue and the one roster that the transport owns. A link that
  /// held the transport instead would be able to reach all of it, which is
  /// how a protocol layer ends up changing session state.
  P2PLink({
    required this.address,
    required this.port,
    required NetPeerId peer,
    required int nowMicros,
    required this.timeoutMicros,
    required this._send,
    required this._deliver,
    required this._deliverSystem,
    required this._lost,
  }) : // The caller names it `peer`, which is what it is to them; the
       // underscore is this class's own business, and the field is not final
       // besides - the host sets it once the slot is assigned.
       // ignore: prefer_initializing_formals
       _peer = peer,
       _lastHeardMicros = nowMicros,
       _lastSentMicros = nowMicros,
       _rawAddress = address.rawAddress;

  /// Where the other end is. A pair, not a `Datagram`: this is compared
  /// against every arriving packet's source, once per packet.
  final InternetAddress address;
  final int port;

  /// [address]'s bytes, kept because every arriving datagram is matched
  /// against every link - four byte comparisons rather than building and
  /// comparing an address string per packet per link.
  final Uint8List _rawAddress;

  /// Puts one datagram on the transport's socket.
  final void Function(P2PLink link, Uint8List datagram, int length) _send;

  /// Hands one complete game message to the transport's delivery queue.
  final void Function(
    P2PLink link,
    NetChannel channel,
    Uint8List bytes,
    int offset,
    int length,
  )
  _deliver;

  /// Hands one complete transport message - a roster update - to the
  /// transport itself.
  final void Function(P2PLink link, int message, Uint8List bytes)
  _deliverSystem;

  /// Reports a link that has gone quiet for too long.
  final void Function(P2PLink link, NetDisconnectReason reason) _lost;

  @override
  NetPeerId get peer => _peer;
  NetPeerId _peer;

  /// Set once, by the host, when the accept it sent is confirmed - and by a
  /// client when its accept arrives.
  set peer(NetPeerId value) => _peer = value;

  @override
  NetConnectionState get state => _state;
  NetConnectionState _state = NetConnectionState.connecting;

  @override
  NetDisconnectReason? get disconnectReason => _disconnectReason;
  NetDisconnectReason? _disconnectReason;

  /// Smoothed round trip, or -1 before enough packets have crossed.
  ///
  /// **It reads high on an idle link, by up to a keepalive interval.** An ack
  /// travels on the next packet the peer happens to send, and on a link with
  /// no game traffic that is the next keepalive - so a loopback link with a
  /// true round trip under a millisecond measures 15-30ms when nothing else
  /// is going on. Under actual traffic, where a packet leaves every tick, the
  /// figure is the real one. Sending an ack immediately instead would be a
  /// packet per received packet, which is a poor trade for a number that is
  /// only interesting while traffic is flowing.
  @override
  int get roundTripMicros => _rttMicros;
  int _rttMicros = -1;

  /// A smoothed fraction of sent packets this side believes were lost.
  ///
  /// A packet counts as lost once it has gone unacknowledged for
  /// [_lossDeadlineMicros] - several round trips, plus enough slack for the
  /// peer's next keepalive to carry the ack. Each one moves the estimate up,
  /// each acknowledgement moves it down, both at 1/20: fast enough to notice
  /// a link going bad inside a second of play, slow enough that one dropped
  /// packet does not read as total loss.
  ///
  /// The first version instead counted a packet lost when its record was
  /// recycled, 64 packets later - which is correct and useless: an idle link
  /// sends ten packets a second, so a link losing a third of everything read
  /// as flawless for the first six seconds. Loss has to be measured against
  /// the clock, not against how much has been sent since.
  @override
  double get packetLoss => _packetLoss;
  double _packetLoss = 0;

  static const double _lossWeight = 0.05;

  /// How long an unacknowledged packet is given before it counts as lost.
  /// Four round trips, floored at half a second so that an ack riding on the
  /// peer's next keepalive still arrives in time on a quiet link.
  int get _lossDeadlineMicros =>
      _rttMicros < 0 ? 500000 : (_rttMicros * 4).clamp(500000, 2000000);

  // --- outbound ----------------------------------------------------------

  /// Messages queued or in flight, oldest first.
  ///
  /// Unreliable ones leave on the first packet that has room and are dropped
  /// from here; reliable ones stay until the packet carrying them is
  /// acknowledged, which is what "reliable" means.
  final List<_Out> _outbox = <_Out>[];

  /// Spent [_Out]s, kept for reuse. A game sending 60 snapshots a second per
  /// peer would otherwise make 60 objects a second per peer, on the frame
  /// path (RULES.md rule 1).
  final List<_Out> _spare = <_Out>[];

  int _nextSequence = 0;
  int _nextMessageId = 0;
  int _nextGroupId = 0;

  /// What each of the last [_ackWindow] packets carried, so an ack can
  /// retire the right messages. A ring indexed by `seq % _ackWindow`.
  final List<_SentPacket> _sent = <_SentPacket>[
    for (var i = 0; i < _ackWindow; i++) _SentPacket(),
  ];

  static const int _ackWindow = 64;

  // --- inbound -----------------------------------------------------------

  /// The highest packet sequence heard, and a bitmap of the 32 before it.
  /// Together they are the `ack`/`ackBits` this side puts on its own packets.
  int _remoteSequence = -1;
  int _remoteBits = 0;

  /// The next reliable message id to hand upward. Anything below it has
  /// already been delivered - which is how a retransmission that crossed with
  /// its own ack is discarded instead of delivered twice.
  int _nextExpected = 0;

  /// Reliable messages that arrived out of order, waiting for the gap in
  /// front of them to fill.
  final Map<int, _In> _held = <int, _In>{};

  /// Fragments of unreliable messages, by group id. Reliable fragments do not
  /// need this - they arrive in order by construction, so they accumulate in
  /// [_assembly] instead.
  final Map<int, _Assembly> _unreliableGroups = <int, _Assembly>{};

  _Assembly? _assembly;

  // --- liveness ----------------------------------------------------------

  int _lastHeardMicros;
  int _lastSentMicros;

  /// Sent this often when there is nothing else to say. Any packet at all
  /// carries acks, so a keepalive is also what retires the peer's
  /// retransmissions on an otherwise idle link.
  static const int keepaliveMicros = 100 * 1000;

  /// Silence longer than this and the link is gone - see
  /// `P2PNetTransport.linkTimeout` for the default and why it is what it is.
  final int timeoutMicros;

  /// How long to wait for an ack before sending a reliable message again.
  int get _retransmitMicros =>
      _rttMicros < 0 ? 100 * 1000 : (_rttMicros * 2).clamp(30 * 1000, 500000);

  // --- NetConnection ------------------------------------------------------

  @override
  void send(
    NetChannel channel,
    Uint8List bytes, [
    int offset = 0,
    int? length,
  ]) {
    if (_state == NetConnectionState.disconnected) {
      assert(
        false,
        'sending to peer ${_peer.slot} on a connection that has already '
        'ended (${_disconnectReason?.name}). A send that vanishes is how a '
        'game ends up waiting forever for a reply.',
      );
      return;
    }
    _enqueue(
      channel == NetChannel.reliable
          ? FrameKind.reliable
          : FrameKind.unreliable,
      bytes,
      offset,
      length ?? bytes.length - offset,
    );
  }

  /// Queues one of the transport's own messages - a roster update. Always
  /// reliable: a client that missed "player 3 left" has a wrong roster
  /// forever, and there is no later message that corrects it.
  void sendSystem(int message, List<int> body) {
    final bytes = Uint8List(1 + body.length);
    bytes[0] = message;
    bytes.setRange(1, bytes.length, body);
    _enqueue(FrameKind.system, bytes, 0, bytes.length);
  }

  @override
  void disconnect() => _lost(this, NetDisconnectReason.localClose);

  /// Marks this link finished. The transport decides what to tell the game;
  /// this just stops it sending.
  void end(NetDisconnectReason reason) {
    _state = NetConnectionState.disconnected;
    _disconnectReason = reason;
    for (var i = 0; i < _outbox.length; i++) {
      _spare.add(_outbox[i]);
    }
    _outbox.clear();
  }

  void promote() {
    if (_state == NetConnectionState.connecting) {
      _state = NetConnectionState.connected;
    }
  }

  // --- sending ------------------------------------------------------------

  /// The most payload one frame can hold, after its own header. Sized for the
  /// worst case (a fragmented reliable frame), so one number covers every
  /// frame shape rather than four that have to stay in step.
  static const int maxFramePayload =
      maxDatagramPayload - prologueBytes - payloadHeaderBytes - _maxFrameHeader;

  /// flags + messageId + groupId + index + count + length.
  static const int _maxFrameHeader = 1 + 2 + 2 + 1 + 1 + 2;

  void _enqueue(int kind, Uint8List bytes, int offset, int length) {
    if (length <= maxFramePayload) {
      _append(kind, bytes, offset, length, 0, 0, 1);
      return;
    }
    final fragments = (length + maxFramePayload - 1) ~/ maxFramePayload;
    if (fragments > 255) {
      assert(
        false,
        'a single message of $length bytes needs $fragments fragments, and '
        'the fragment index is one byte. Split it in the game, where the '
        'meaning of the split is known.',
      );
      return;
    }
    final group = _nextGroupId = (_nextGroupId + 1) & 0xFFFF;
    for (var i = 0; i < fragments; i++) {
      final at = offset + i * maxFramePayload;
      final size = (offset + length - at).clamp(0, maxFramePayload);
      _append(kind, bytes, at, size, group, i, fragments);
    }
  }

  void _append(
    int kind,
    Uint8List bytes,
    int offset,
    int length,
    int group,
    int index,
    int count,
  ) {
    final out = _spare.isEmpty ? _Out() : _spare.removeLast();
    out.kind = kind;
    if (kind == FrameKind.unreliable) {
      out.messageId = 0;
    } else {
      out.messageId = _nextMessageId;
      _nextMessageId = (_nextMessageId + 1) & 0xFFFF;
    }
    out.group = group;
    out.index = index;
    out.count = count;
    out.length = length;
    out.sentMicros = -1;
    // Copied, because a reliable message may go out again long after the
    // caller has reused the buffer it wrote - which `NetConnection.send`
    // promises it may.
    if (out.bytes.length < length) out.bytes = Uint8List(length);
    out.bytes.setRange(0, length, bytes, offset);
    _outbox.add(out);
  }

  /// Writes as many datagrams as the queue needs, into [scratch].
  ///
  /// Called from the transport's flush and from its timer. Returns without
  /// sending anything when there is nothing due and the keepalive is not.
  void pump(Uint8List scratch, ByteData view, int nowMicros) {
    if (_state == NetConnectionState.disconnected) return;
    if (nowMicros - _lastHeardMicros > timeoutMicros) {
      _lost(this, NetDisconnectReason.timeout);
      return;
    }
    _sweepLost(nowMicros);
    var wrote = false;
    var at = 0;
    while (at < _outbox.length) {
      final packet = _startPacket(scratch, view);
      var cursor = packet;
      final carried = _sentAt(_nextSequence);
      _noteRecycled(carried);
      carried.reset(_nextSequence, nowMicros);
      var any = false;
      while (at < _outbox.length) {
        final out = _outbox[at];
        if (!_isDue(out, nowMicros)) {
          at++;
          continue;
        }
        final needed = out.frameBytes;
        if (cursor + needed > maxDatagramPayload) break;
        cursor = _writeFrame(scratch, view, cursor, out);
        out.sentMicros = nowMicros;
        any = true;
        if (out.kind == FrameKind.unreliable) {
          _spare.add(out);
          _outbox.removeAt(at);
          continue;
        }
        carried.add(out.messageId);
        at++;
      }
      if (!any) break;
      _finishPacket(scratch, cursor, nowMicros);
      wrote = true;
    }
    if (!wrote && nowMicros - _lastSentMicros >= keepaliveMicros) {
      final packet = _startPacket(scratch, view);
      final record = _sentAt(_nextSequence);
      _noteRecycled(record);
      record.reset(_nextSequence, nowMicros);
      _finishPacket(scratch, packet, nowMicros);
    }
  }

  /// Counts packets that have gone unanswered long enough to be lost.
  ///
  /// Runs on every pump, which is every frame and every timer tick: cheap
  /// (64 field comparisons) and the only thing that makes [packetLoss] move
  /// on a link that is quiet because it is broken.
  void _sweepLost(int nowMicros) {
    final deadline = _lossDeadlineMicros;
    for (var i = 0; i < _sent.length; i++) {
      final record = _sent[i];
      if (record.sequence < 0 || record.retired || record.counted) continue;
      if (nowMicros - record.sentMicros < deadline) continue;
      record.counted = true;
      _packetLoss += (1 - _packetLoss) * _lossWeight;
    }
  }

  bool _isDue(_Out out, int nowMicros) {
    if (out.sentMicros < 0) return true;
    if (out.kind == FrameKind.unreliable) return false;
    return nowMicros - out.sentMicros >= _retransmitMicros;
  }

  int _startPacket(Uint8List scratch, ByteData view) {
    scratch[0] = magic0;
    scratch[1] = magic1;
    scratch[2] = protocolVersion;
    scratch[3] = PacketType.payload;
    view.setUint16(4, _nextSequence, Endian.little);
    view.setUint16(6, _remoteSequence < 0 ? 0 : _remoteSequence, Endian.little);
    view.setUint32(8, _remoteBits, Endian.little);
    // Zero is a real sequence number - the first packet either side sends -
    // so "I have not heard anything yet" cannot be encoded as an ack of zero.
    // It got its own bit after exactly that bug: a peer that had received
    // nothing still ack'd packet 0, and the very first reliable message on
    // the link was retired without ever having been delivered.
    scratch[12] = _remoteSequence < 0 ? 0 : 1;
    return prologueBytes + payloadHeaderBytes;
  }

  void _finishPacket(Uint8List scratch, int length, int nowMicros) {
    _nextSequence = (_nextSequence + 1) & 0xFFFF;
    _lastSentMicros = nowMicros;
    _send(this, scratch, length);
  }

  int _writeFrame(Uint8List scratch, ByteData view, int at, _Out out) {
    var cursor = at;
    final fragmented = out.count > 1;
    scratch[cursor++] = out.kind | (fragmented ? FrameKind.fragmented : 0);
    if (out.kind != FrameKind.unreliable) {
      view.setUint16(cursor, out.messageId, Endian.little);
      cursor += 2;
    }
    if (fragmented) {
      view.setUint16(cursor, out.group, Endian.little);
      cursor += 2;
      scratch[cursor++] = out.index;
      scratch[cursor++] = out.count;
    }
    view.setUint16(cursor, out.length, Endian.little);
    cursor += 2;
    scratch.setRange(cursor, cursor + out.length, out.bytes);
    return cursor + out.length;
  }

  _SentPacket _sentAt(int sequence) => _sent[sequence % _ackWindow];

  /// A record about to be overwritten, whose deadline had not passed yet, is
  /// still a packet whose ack is now never going to be matched to anything.
  void _noteRecycled(_SentPacket record) {
    if (record.sequence < 0 || record.retired || record.counted) return;
    _packetLoss += (1 - _packetLoss) * _lossWeight;
  }

  // --- receiving ----------------------------------------------------------

  /// Whether a datagram from this source belongs to this link.
  bool isFrom(Uint8List rawAddress, int port) {
    if (this.port != port || _rawAddress.length != rawAddress.length) {
      return false;
    }
    for (var i = 0; i < rawAddress.length; i++) {
      if (_rawAddress[i] != rawAddress[i]) return false;
    }
    return true;
  }

  /// Takes one payload packet apart: acks first, then frames.
  void onPayload(Uint8List data, int length, int nowMicros) {
    if (length < prologueBytes + payloadHeaderBytes) return;
    final view = ByteData.sublistView(data);
    _lastHeardMicros = nowMicros;
    promote();

    final sequence = view.getUint16(4, Endian.little);
    _noteReceived(sequence);
    if (data[12] != 0) {
      _processAcks(
        view.getUint16(6, Endian.little),
        view.getUint32(8, Endian.little),
        nowMicros,
      );
    }

    var at = prologueBytes + payloadHeaderBytes;
    while (at < length) {
      final flags = data[at++];
      final kind = flags & FrameKind.mask;
      final fragmented = flags & FrameKind.fragmented != 0;
      var messageId = 0;
      if (kind != FrameKind.unreliable) {
        if (at + 2 > length) return;
        messageId = view.getUint16(at, Endian.little);
        at += 2;
      }
      var group = 0;
      var index = 0;
      var count = 1;
      if (fragmented) {
        if (at + 4 > length) return;
        group = view.getUint16(at, Endian.little);
        at += 2;
        index = data[at++];
        count = data[at++];
      }
      if (at + 2 > length) return;
      final size = view.getUint16(at, Endian.little);
      at += 2;
      if (at + size > length) return;
      _receiveFrame(kind, messageId, group, index, count, data, at, size);
      at += size;
    }
  }

  void _noteReceived(int sequence) {
    if (_remoteSequence < 0) {
      _remoteSequence = sequence;
      return;
    }
    if (sequenceGreaterThan(sequence, _remoteSequence)) {
      final shift = (sequence - _remoteSequence) & 0xFFFF;
      _remoteBits = shift >= 32
          ? 0
          : ((_remoteBits << shift) | (1 << (shift - 1)));
      _remoteBits &= 0xFFFFFFFF;
      _remoteSequence = sequence;
      return;
    }
    final behind = (_remoteSequence - sequence) & 0xFFFF;
    if (behind >= 1 && behind <= 32) {
      _remoteBits |= 1 << (behind - 1);
    }
  }

  void _processAcks(int ack, int ackBits, int nowMicros) {
    _retire(ack, nowMicros);
    for (var bit = 0; bit < 32; bit++) {
      if (ackBits & (1 << bit) == 0) continue;
      _retire((ack - bit - 1) & 0xFFFF, nowMicros);
    }
  }

  void _retire(int sequence, int nowMicros) {
    final record = _sentAt(sequence);
    if (record.sequence != sequence || record.retired) return;
    record.retired = true;
    _packetLoss -= _packetLoss * _lossWeight;
    if (record.sentMicros >= 0) {
      final sample = nowMicros - record.sentMicros;
      // Exponential smoothing at 1/8, the weight TCP has used since 1988: it
      // follows a real change in a handful of samples without letting one
      // slow packet move the estimate far.
      _rttMicros = _rttMicros < 0
          ? sample
          : _rttMicros + ((sample - _rttMicros) >> 3);
    }
    for (var i = 0; i < record.messageIds.length; i++) {
      final id = record.messageIds[i];
      for (var j = 0; j < _outbox.length; j++) {
        if (_outbox[j].messageId != id ||
            _outbox[j].kind == FrameKind.unreliable) {
          continue;
        }
        _spare.add(_outbox[j]);
        _outbox.removeAt(j);
        break;
      }
    }
    record.messageIds.clear();
  }

  void _receiveFrame(
    int kind,
    int messageId,
    int group,
    int index,
    int count,
    Uint8List data,
    int offset,
    int length,
  ) {
    if (kind == FrameKind.unreliable) {
      if (count == 1) {
        _deliver(this, NetChannel.unreliable, data, offset, length);
        return;
      }
      _reassembleUnreliable(group, index, count, data, offset, length);
      return;
    }
    // Already delivered: a retransmission that crossed its own ack. Anything
    // at or ahead of the cursor is still wanted; anything behind it has been
    // handed up once already and must not go up twice.
    if (messageId != _nextExpected &&
        !sequenceGreaterThan(messageId, _nextExpected)) {
      return;
    }
    if (_held.containsKey(messageId)) return;
    final held = _In()
      ..kind = kind
      ..index = index
      ..count = count
      ..bytes = Uint8List.sublistView(data, offset, offset + length);
    _held[messageId] = held;
    _drainInOrder();
  }

  /// Hands up every reliable message whose predecessors have all arrived.
  void _drainInOrder() {
    while (true) {
      final next = _held.remove(_nextExpected);
      if (next == null) return;
      _nextExpected = (_nextExpected + 1) & 0xFFFF;
      if (next.count == 1) {
        _deliverWhole(next.kind, next.bytes, 0, next.bytes.length);
        continue;
      }
      // Fragments of a reliable message arrive in order by construction, so
      // reassembly is an append and a length check - no map, no timer, no
      // "what if fragment 4 never comes" (it does, or nothing after it is
      // delivered either).
      final assembly = _assembly ??= _Assembly();
      if (next.index == 0) assembly.begin(next.count);
      assembly.add(next.index, next.bytes);
      if (next.index != next.count - 1) continue;
      _deliverWhole(next.kind, assembly.take(), 0, assembly.length);
      assembly.clear();
    }
  }

  void _deliverWhole(int kind, Uint8List bytes, int offset, int length) {
    if (kind == FrameKind.system) {
      _deliverSystem(
        this,
        bytes[offset],
        Uint8List.sublistView(bytes, offset + 1, offset + length),
      );
      return;
    }
    _deliver(this, NetChannel.reliable, bytes, offset, length);
  }

  void _reassembleUnreliable(
    int group,
    int index,
    int count,
    Uint8List data,
    int offset,
    int length,
  ) {
    final assembly = _unreliableGroups.putIfAbsent(group, _Assembly.new);
    if (assembly.count != count) assembly.begin(count);
    assembly.add(index, Uint8List.sublistView(data, offset, offset + length));
    if (!assembly.isComplete) {
      // A group whose missing fragment is never coming would otherwise sit
      // here forever. Unreliable means unreliable: keep only the newest few.
      if (_unreliableGroups.length > 4) {
        _unreliableGroups.remove(_unreliableGroups.keys.first);
      }
      return;
    }
    _deliver(this, NetChannel.unreliable, assembly.take(), 0, assembly.length);
    _unreliableGroups.remove(group);
  }
}

/// One queued outgoing message, or one fragment of one. Pooled.
class _Out {
  int kind = FrameKind.reliable;
  int messageId = 0;
  int group = 0;
  int index = 0;
  int count = 1;
  Uint8List bytes = Uint8List(64);
  int length = 0;

  /// When it last went out, or -1 if it has not. Drives both "send this now"
  /// and "send this again".
  int sentMicros = -1;

  int get frameBytes =>
      1 +
      (kind == FrameKind.unreliable ? 0 : 2) +
      (count > 1 ? 4 : 0) +
      2 +
      length;
}

/// One received reliable message, waiting its turn.
class _In {
  int kind = FrameKind.reliable;
  int index = 0;
  int count = 1;
  Uint8List bytes = Uint8List(0);
}

/// What one sent packet carried, so an ack can retire it.
class _SentPacket {
  int sequence = -1;
  int sentMicros = -1;
  bool retired = false;

  /// Whether this packet has already been counted against [P2PLink.packetLoss]
  /// - so that one lost packet moves the estimate once, however many sweeps
  /// see it sitting there.
  bool counted = false;

  final List<int> messageIds = <int>[];

  void reset(int sequence, int sentMicros) {
    this.sequence = sequence;
    this.sentMicros = sentMicros;
    retired = false;
    counted = false;
    messageIds.clear();
  }

  void add(int messageId) => messageIds.add(messageId);
}

/// A message being put back together out of fragments.
class _Assembly {
  Uint8List bytes = Uint8List(0);
  int length = 0;
  int count = 0;
  int have = 0;

  bool get isComplete => count > 0 && have == count;

  void begin(int count) {
    this.count = count;
    have = 0;
    length = 0;
  }

  void add(int index, Uint8List fragment) {
    final end = length + fragment.length;
    if (bytes.length < end) {
      final grown = Uint8List(end * 2)..setRange(0, length, bytes);
      bytes = grown;
    }
    bytes.setRange(length, end, fragment);
    length = end;
    have++;
  }

  /// Hands the assembled bytes over and starts again on a fresh buffer.
  ///
  /// The buffer has to be given away rather than lent: a reassembled message
  /// is queued as a *view* and read at the next poll, so an assembly that
  /// kept its buffer would be filling the bytes a queued message is still
  /// pointing at. One allocation per fragmented message, which is a message
  /// of at least 1178 bytes - the copy it replaces would have been bigger.
  Uint8List take() {
    final assembled = bytes;
    bytes = Uint8List(0);
    return assembled;
  }

  void clear() {
    length = 0;
    count = 0;
    have = 0;
  }
}
