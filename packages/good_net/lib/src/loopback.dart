import 'dart:typed_data';

import 'channel.dart';
import 'connection.dart';
import 'listener.dart';
import 'peer.dart';
import 'session.dart';
import 'transport.dart';

/// A backend that never leaves the isolate: peers are other
/// [LoopbackNetTransport] instances in the same process, and a "datagram" is
/// a copy into another one's queue.
///
/// This is not a stub. It is a real implementation of the contract, and it is
/// what the conformance suite runs first: every rule the interface states -
/// nothing delivered outside [poll], a roster both sides agree on, a peer id
/// whose generation moves when its slot is reused, sends that queue before a
/// session exists - is enforced here, where there is no packet loss to hide
/// behind. A backend that passes over UDP but fails here has a bug in its
/// session bookkeeping, not in its socket code.
///
/// It is also useful outside tests: two players in one process is how
/// split-screen and "run a host and a client in one app while debugging"
/// work, and neither should need a socket.
///
/// # Scope: one isolate
///
/// The switchboard is a `static`, and statics are per-isolate in Dart, so two
/// isolates cannot find each other through this. That is the honest boundary
/// of an in-memory backend: crossing an isolate means serialising and going
/// through a port, which is a transport of its own and not this one.
class LoopbackNetTransport extends NetTransport {
  /// Every open session in this isolate, by code. Hosting puts one in,
  /// joining looks one up, closing takes it out.
  static final Map<String, _Room> _rooms = <String, _Room>{};

  /// Ends every session in this isolate.
  ///
  /// For a test's teardown: the switchboard outlives any one transport, so a
  /// test that threw partway through would otherwise leave a code taken and
  /// the next test would fail for a reason that has nothing to do with it.
  static void reset() {
    final rooms = _rooms.values.toList(growable: false);
    for (var i = 0; i < rooms.length; i++) {
      rooms[i].close(NetDisconnectReason.sessionClosed);
    }
    _rooms.clear();
  }

  @override
  String get name => 'loopback';

  @override
  NetSession? get session => _session;
  _View? _session;

  /// What has arrived and not yet been handed to [poll], oldest first.
  ///
  /// One queue for peers and messages both, so a message from a peer can
  /// never be delivered before the join that introduced it - an ordering bug
  /// that two queues make easy to write and very confusing to debug.
  final List<_Event> _inbox = <_Event>[];

  /// Spent events, kept for reuse. Delivery is not a hot path in a test, but
  /// this backend also runs split-screen games, where per-message garbage is
  /// per-frame garbage (the no-allocation rule).
  final List<_Event> _spare = <_Event>[];

  bool _closed = false;

  @override
  Future<NetSession> host([
    SessionOptions options = const SessionOptions(),
  ]) async {
    _requireOpen();
    _requireNoSession();
    final id = options.id ?? SessionId.random();
    if (_rooms.containsKey(id.value)) {
      throw NetException(
        'session code $id is already open in this isolate',
        transport: name,
      );
    }
    final room = _Room(id, options, schemaHash);
    _rooms[id.value] = room;
    return _session = room.admitHost(this);
  }

  @override
  Future<NetSession> join(SessionId id) async {
    _requireOpen();
    _requireNoSession();
    final room = _rooms[id.value];
    if (room == null) {
      throw NetException('no session with code $id', transport: name);
    }
    if (room.schemaHash != schemaHash) {
      throw NetException(
        'the host is running a different build: its message declarations '
        'hash to ${room.schemaHash} and this build hashes to $schemaHash. '
        'See NetTransport.schemaHash.',
        transport: name,
      );
    }
    return _session = room.admit(this);
  }

  @override
  Future<List<SessionInfo>> discover({
    Duration timeout = const Duration(seconds: 1),
  }) async {
    final found = <SessionInfo>[];
    for (final room in _rooms.values) {
      if (!room.advertise) continue;
      found.add(
        SessionInfo(
          id: room.id,
          name: room.name,
          peerCount: room.members.length,
          maxPeers: room.maxPeers,
        ),
      );
    }
    return found;
  }

  @override
  void poll(NetListener listener) {
    // Snapshotted: a handler may send, and a send to a peer that is also in
    // this isolate must not be delivered inside the poll that caused it -
    // no real backend would do that, so this one does not either.
    final due = _inbox.length;
    if (due == 0) return;
    for (var i = 0; i < due; i++) {
      final event = _inbox[i];
      switch (event.kind) {
        case _EventKind.peerJoined:
          listener.onPeerJoined(event.peer);
        case _EventKind.peerLeft:
          listener.onPeerLeft(event.peer, event.reason);
        case _EventKind.message:
          listener.onMessage(
            event.peer,
            event.channel,
            event.bytes,
            0,
            event.length,
          );
        case _EventKind.sessionClosed:
          _session = null;
          listener.onSessionClosed(event.reason);
      }
      _spare.add(event);
    }
    _inbox.removeRange(0, due);
  }

  /// Nothing to do: a loopback send is a copy that has already happened.
  /// Real backends batch here.
  @override
  void flush() {}

  @override
  Future<void> close() async {
    _closed = true;
    await _session?.leave();
    _session = null;
    _inbox.clear();
  }

  // --- delivery, called by the room ---------------------------------------

  _Event _event(_EventKind kind, NetPeerId peer) {
    final event = _spare.isEmpty ? _Event() : _spare.removeLast();
    event.kind = kind;
    event.peer = peer;
    return event;
  }

  void _deliverJoined(NetPeerId peer) =>
      _inbox.add(_event(_EventKind.peerJoined, peer));

  void _deliverLeft(NetPeerId peer, NetDisconnectReason reason) =>
      _inbox.add(_event(_EventKind.peerLeft, peer)..reason = reason);

  void _deliverClosed(NetDisconnectReason reason) => _inbox.add(
    _event(_EventKind.sessionClosed, NetPeerId.none)..reason = reason,
  );

  void _deliverMessage(
    NetPeerId from,
    NetChannel channel,
    Uint8List bytes,
    int offset,
    int length,
  ) {
    final event = _event(_EventKind.message, from)
      ..channel = channel
      ..length = length;
    if (event.bytes.length < length) event.bytes = Uint8List(length);
    event.bytes.setRange(0, length, bytes, offset);
    _inbox.add(event);
  }

  void _forget() => _session = null;

  void _requireOpen() {
    if (!_closed) return;
    throw NetException('this transport has been closed', transport: name);
  }

  void _requireNoSession() {
    if (_session == null) return;
    throw NetException(
      'this transport is already in session ${_session!.id}. Leave that one '
      'first - one transport is one peer.',
      transport: name,
    );
  }
}

enum _EventKind { peerJoined, peerLeft, message, sessionClosed }

/// One queued delivery. Mutable and pooled - see `LoopbackNetTransport._spare`.
class _Event {
  _EventKind kind = _EventKind.message;
  NetPeerId peer = NetPeerId.none;
  NetDisconnectReason reason = NetDisconnectReason.remoteClose;
  NetChannel channel = NetChannel.reliable;
  Uint8List bytes = Uint8List(64);
  int length = 0;
}

/// The shared state of one session: who is in it, and what its code is.
///
/// Not itself a [NetSession] - each peer gets its own [_View] onto this,
/// because almost every question a session answers ("what is my id", "who can
/// I reach") is a question about *which* peer is asking. A single shared
/// object would have to be told, which is a context variable, which is the
/// bug that finds you two weeks later.
class _Room {
  _Room(this.id, SessionOptions options, this.schemaHash)
    : name = options.name,
      maxPeers = options.maxPeers,
      advertise = options.advertise;

  final SessionId id;
  final String name;
  final int maxPeers;
  final bool advertise;

  /// The host's, checked against every joiner's.
  final int schemaHash;

  /// Everyone in the session, host first. One list rather than peers and
  /// transports side by side: a peer's transport is a property of that peer
  /// (the one-fact-one-place rule).
  final List<_Member> members = <_Member>[];

  /// How many times each slot has been handed out - what makes a recycled
  /// slot a different [NetPeerId] from the one that vacated it.
  final Map<int, int> _generations = <int, int>{};

  bool open = true;

  _Member get host => members[0];

  _Member? memberOf(NetPeerId peer) {
    for (var i = 0; i < members.length; i++) {
      if (members[i].peer == peer) return members[i];
    }
    return null;
  }

  _View admitHost(LoopbackNetTransport transport) {
    final member = _Member(NetPeerId.host, transport);
    members.add(member);
    return member.view = _View(this, member);
  }

  _View admit(LoopbackNetTransport transport) {
    if (!open) {
      throw NetException('session $id has closed', transport: transport.name);
    }
    if (members.length >= maxPeers) {
      throw NetException(
        'session $id is full ($maxPeers peers)',
        transport: transport.name,
      );
    }
    final slot = _freeSlot();
    final generation = _generations.update(
      slot,
      (previous) => (previous + 1) & 0xFFFF,
      ifAbsent: () => 0,
    );
    final member = _Member(NetPeerId.pack(slot, generation), transport);
    member.view = _View(this, member);
    member.toHost = _LoopbackConnection(this, member, host);
    member.fromHost = _LoopbackConnection(this, host, member);
    // Everyone already here hears about the arrival. The joiner does not: its
    // roster is complete the moment `join` returns, and `NetworkSystem`
    // announces it from there.
    for (var i = 0; i < members.length; i++) {
      members[i].transport._deliverJoined(member.peer);
    }
    members.add(member);
    return member.view;
  }

  int _freeSlot() {
    for (var slot = 1; slot < maxPeers; slot++) {
      if (_slotTaken(slot)) continue;
      return slot;
    }
    throw StateError('no free slot in a session that is not full');
  }

  bool _slotTaken(int slot) {
    for (var i = 0; i < members.length; i++) {
      if (members[i].peer.slot == slot) return true;
    }
    return false;
  }

  /// A client leaves: it is told its session ended, everyone else is told it
  /// left.
  void remove(_Member member, NetDisconnectReason reason) {
    if (!members.remove(member)) return;
    member.transport
      .._deliverClosed(NetDisconnectReason.localClose)
      .._forget();
    for (var i = 0; i < members.length; i++) {
      members[i].transport._deliverLeft(member.peer, reason);
    }
  }

  /// The host ends it: everyone, host included, is told the session closed.
  void close(NetDisconnectReason reason) {
    if (!open) return;
    open = false;
    LoopbackNetTransport._rooms.remove(id.value);
    for (var i = 0; i < members.length; i++) {
      final member = members[i];
      member.transport
        .._deliverClosed(i == 0 ? NetDisconnectReason.localClose : reason)
        .._forget();
    }
    members.clear();
  }
}

/// One participant of a [_Room]: who they are, where their traffic goes, and
/// the two ends of their link to the host.
class _Member {
  _Member(this.peer, this.transport);

  final NetPeerId peer;
  final LoopbackNetTransport transport;

  late final _View view;

  /// This client's link to the host, and the host's to it. Both null for the
  /// host's own member - the host has no link to itself.
  _LoopbackConnection? toHost;
  _LoopbackConnection? fromHost;
}

/// One peer's view of a [_Room] - the [NetSession] that peer holds.
class _View implements NetSession {
  _View(this._room, this._self);

  final _Room _room;
  final _Member _self;

  @override
  SessionId get id => _room.id;

  @override
  String get name => _room.name;

  @override
  int get maxPeers => _room.maxPeers;

  @override
  NetPeerId get localPeer => _self.peer;

  @override
  bool get isHost => _self.peer.isHost;

  @override
  bool get isOpen => _room.open && _room.members.contains(_self);

  @override
  int get peerCount => _room.members.length - 1;

  @override
  NetPeerId peerAt(int index) {
    // Everyone except this peer, in join order. The host is index 0 for a
    // client, because it is member 0 of the room and never this peer.
    var seen = 0;
    for (var i = 0; i < _room.members.length; i++) {
      final member = _room.members[i];
      if (identical(member, _self)) continue;
      if (seen++ == index) return member.peer;
    }
    return NetPeerId.none;
  }

  @override
  bool hasPeer(NetPeerId peer) =>
      peer != _self.peer && _room.memberOf(peer) != null;

  @override
  NetConnection? connectionTo(NetPeerId peer) {
    if (peer == _self.peer) return null;
    if (!isHost) return peer.isHost ? _self.toHost : null;
    return _room.memberOf(peer)?.fromHost;
  }

  @override
  void sendToAll(
    NetChannel channel,
    Uint8List bytes, [
    int offset = 0,
    int? length,
  ]) {
    if (!isHost) {
      _self.toHost?.send(channel, bytes, offset, length);
      return;
    }
    final members = _room.members;
    for (var i = 0; i < members.length; i++) {
      members[i].fromHost?.send(channel, bytes, offset, length);
    }
  }

  @override
  Future<void> leave() async {
    if (isHost) {
      _room.close(NetDisconnectReason.sessionClosed);
      return;
    }
    _room.remove(_self, NetDisconnectReason.remoteClose);
  }
}

/// One direction of one link: [_from] sending to [_to]. Two of these per
/// link, one owned by each end, so that "who is sending" is a property of the
/// object rather than something the session has to be told.
///
/// Loopback has no handshake and no loss, so most of [NetConnection] is a
/// constant here.
class _LoopbackConnection implements NetConnection {
  _LoopbackConnection(this._room, this._from, this._to);

  final _Room _room;
  final _Member _from;
  final _Member _to;

  @override
  NetPeerId get peer => _to.peer;

  @override
  NetConnectionState get state => _room.open && _room.members.contains(_to)
      ? NetConnectionState.connected
      : NetConnectionState.disconnected;

  @override
  NetDisconnectReason? get disconnectReason =>
      state == NetConnectionState.connected
      ? null
      : NetDisconnectReason.sessionClosed;

  /// Zero, and honestly so: the bytes are already there.
  @override
  int get roundTripMicros => 0;

  @override
  double get packetLoss => 0;

  @override
  void send(
    NetChannel channel,
    Uint8List bytes, [
    int offset = 0,
    int? length,
  ]) {
    if (state != NetConnectionState.connected) {
      assert(
        false,
        'sending to peer ${_to.peer.slot}, which is no longer in the session',
      );
      return;
    }
    _to.transport._deliverMessage(
      _from.peer,
      channel,
      bytes,
      offset,
      length ?? bytes.length - offset,
    );
  }

  @override
  void disconnect() {
    if (_from.peer.isHost) {
      _room.remove(_to, NetDisconnectReason.localClose);
      return;
    }
    _room.remove(_from, NetDisconnectReason.remoteClose);
  }
}
