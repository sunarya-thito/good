import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:good_net/good_net.dart';

import 'code.dart';
import 'link.dart';
import 'wire.dart';

/// Peer-to-peer networking over plain UDP, with nothing in the middle.
///
/// ```dart
/// descriptor.transport(P2PNetTransport());
/// ```
///
/// # What "no server" means here, exactly
///
/// Hosting binds a UDP socket and hands back a ten-character code that **is**
/// the host's address (see [EndpointCode]). Joining decodes it and starts
/// talking. There is no broker, no relay, no account, nothing to deploy and
/// nothing that can go down. On a LAN there is not even a code to type:
/// [discover] lists the sessions announcing themselves.
///
/// And the honest other half: a code carries the address it was minted from,
/// so it reaches as far as that address does. Same machine and same LAN work
/// now, today, with no setup. **Across the internet does not**, because a home
/// router hands out a private address and drops unsolicited inbound packets -
/// getting through that needs a peer's public address (STUN) and a moment of
/// coordination to punch a hole (a rendezvous), which is a separate landing
/// and is called out in the package README rather than implied by "P2P".
///
/// # Threading and the tick
///
/// The socket lives on the game isolate, beside the simulation. That sounds
/// wrong and is not: `Game`'s loop is a `Timer`, so the isolate has an
/// ordinary event loop, and datagrams arrive on it between ticks. What
/// arrives is parsed immediately - acknowledgements have to be timely - and
/// what it *means* is queued, so the game sees a burst of packets at one
/// point in its tick rather than spread across the middle of one
/// ([NetTransport.poll]).
///
/// This is also why there is no third isolate: a network isolate would need
/// its own copy of the message registry and a second producer on the command
/// ring, to save a socket read that costs microseconds.
class P2PNetTransport extends NetTransport {
  P2PNetTransport({
    InternetAddress? bindAddress,
    this.port = 0,
    this.discoveryPort = defaultDiscoveryPort,
    this.handshakeTimeout = const Duration(seconds: 5),
    this.linkTimeout = const Duration(seconds: 5),
    this.simulatedLoss = 0,
    this.simulatedBackpressure = 0,
    Random? random,
  }) : bindAddress = bindAddress ?? InternetAddress.anyIPv4,
       _random = random ?? Random();

  /// Which interface to bind. The default listens on all of them; a test
  /// passes loopback so that nothing it does leaves the machine.
  final InternetAddress bindAddress;

  /// Which UDP port to bind, or 0 for "whatever the OS has spare".
  ///
  /// Zero is the right default precisely because the join code carries the
  /// port: there is no well-known port to agree on when the address itself
  /// travels with it. Pin it only when a router is forwarding a fixed port.
  final int port;

  /// Where LAN announcements go. Any game may use the default - a beacon
  /// carries the session code, and a code from another game simply fails to
  /// connect - but a game that wants its own quiet corner picks its own.
  final int discoveryPort;

  static const int defaultDiscoveryPort = 43770;

  /// How long [join] tries before giving up.
  ///
  /// A knob because it is a product decision, not a protocol one: a game with
  /// a "connecting..." spinner can afford five seconds, and a quick-match
  /// screen trying three codes in turn cannot.
  final Duration handshakeTimeout;

  /// How long a link may go completely silent before it is declared gone.
  ///
  /// Five seconds by default: long enough to ride out a wifi hiccup or a
  /// laptop waking up, short enough that a player whose router died does not
  /// hold a slot for a minute while everyone waits for them.
  final Duration linkTimeout;

  /// Fraction of **outgoing** datagrams to throw away, 0 to 1.
  ///
  /// A development tool, and it earns its place in the shipped class rather
  /// than in a test helper: netcode that has only ever run over loopback has
  /// never had a packet lost, so every retransmission path in it is untested
  /// code that first runs on a player's patchy hotel wifi. Turning this up is
  /// how you find out - the reliable channel should still deliver everything
  /// in order at 30%, and if it does not, that is a bug found on a desk
  /// rather than in a review.
  ///
  /// Loss is applied when sending, so setting it on one peer models a bad
  /// uplink, and setting it on both models a bad link. It is settable while
  /// running, which is the only way to model the case that matters most:
  /// a link that was fine and then was not.
  double simulatedLoss;

  /// Fraction of sends the socket is told to refuse, 0 to 1.
  ///
  /// The other half of [simulatedLoss], and a different thing: loss is the
  /// wire eating a datagram that did leave, and backpressure is the socket
  /// declining to take it in the first place, which means it never left and
  /// this transport still has it. `RawDatagramSocket.send` says so by
  /// returning 0, and its own documentation calls that a "try again".
  ///
  /// It is here for the same reason [simulatedLoss] is: a real 0 is rare
  /// enough to look like nothing on a desk and frequent enough to be a bug
  /// report, so the path that handles it is untested code unless something
  /// can force it. Measured on Windows loopback while #177 was being read,
  /// three of three hundred idle-link payload sends came back 0.
  double simulatedBackpressure;

  final Random _random;

  static const Duration _beaconInterval = Duration(seconds: 1);
  static const Duration _tickInterval = Duration(milliseconds: 25);
  static const Duration _handshakeInterval = Duration(milliseconds: 200);

  @override
  String get name => P2PLink.backendName;

  @override
  int maxMessageBytes(NetChannel channel) => P2PLink.maxMessageBytes(channel);

  @override
  NetSession? get session => _session;
  _P2PSession? _session;

  RawDatagramSocket? _socket;
  Timer? _ticker;
  Timer? _beacon;

  /// Monotonic, unlike a wall clock: a link that measured its round trip
  /// against `DateTime.now()` would report a negative RTT the moment the
  /// machine synchronised its time.
  final Stopwatch _clock = Stopwatch()..start();

  int get _now => _clock.elapsedMicroseconds;

  /// Every link this peer has: one per client on the host, one to the host on
  /// a client.
  final List<P2PLink> _links = <P2PLink>[];

  /// One datagram under construction. One buffer for the life of the
  /// transport - a packet is built and handed to the socket synchronously, so
  /// there is never a second one in flight to collide with it.
  final Uint8List _scratch = Uint8List(maxDatagramPayload);
  late final ByteData _scratchView = ByteData.sublistView(_scratch);

  /// What has arrived and is waiting for [poll].
  final List<_Delivery> _queue = <_Delivery>[];
  final List<_Delivery> _spare = <_Delivery>[];

  /// Datagrams the socket would not take, oldest first.
  ///
  /// `RawDatagramSocket.send` returns 0 to mean "this would have blocked, ask
  /// again"; it is not a short write and there is no partial datagram. Taking
  /// it for a send discards the packet *inside* this transport, which is a
  /// worse thing than losing it on the wire because nothing downstream can
  /// tell the difference and nothing upstream was asked.
  ///
  /// Reliable traffic hid it: a retransmission covers a packet the socket
  /// refused just as well as one a router dropped. What it does not cover is
  /// the two things sent exactly once - an unreliable message, and the
  /// goodbye a leaving peer sends - and both of those were being thrown away
  /// here at a rate of about one in a hundred (#177).
  final List<_Blocked> _blocked = <_Blocked>[];

  /// Drained [_Blocked]s with their buffers intact, to be filled again. The
  /// no-allocation rule reaches here: backpressure arrives in bursts, and a
  /// burst is the moment to not be making garbage.
  final List<_Blocked> _blockedSpare = <_Blocked>[];

  /// How many datagrams are held before the oldest is given up on.
  ///
  /// A block clears as soon as the socket drains, which is microseconds, so
  /// reaching this at all means it has stopped draining rather than paused.
  /// Holding more at that point does not get them sent, it just spends
  /// memory on packets whose moment has passed - and the oldest is the one
  /// whose moment passed first, which is why that is the end that goes.
  ///
  /// Public because a bound nothing can name is a bound nothing can check:
  /// a test that hard-codes the number instead is a second copy of it that
  /// only breaks once someone has already changed the first.
  static const int maxHeldDatagrams = 64;

  /// The join in progress, if any.
  _Handshake? _handshake;

  /// Generation counter per slot, so a recycled slot is a different peer.
  final Map<int, int> _generations = <int, int>{};

  /// The address this host put in its join code. Also decides whether
  /// announcing on the LAN means anything - see [_startBeacon].
  InternetAddress? _advertised;

  bool _closed = false;

  // --- opening and joining ------------------------------------------------

  @override
  Future<NetSession> host([
    SessionOptions options = const SessionOptions(),
  ]) async {
    _requireOpen();
    _requireNoSession();
    await _bind();
    final socket = _socket!;
    final advertised = _advertised = await _advertisedAddress();
    final id = EndpointCode.encode(advertised, socket.port);
    if (options.id != null && options.id!.value != id.value) {
      throw NetException(
        'this backend cannot open session code ${options.id} - a p2p code is '
        'derived from the address the host is reachable at, and this host is '
        'at $id. Codes you choose yourself need a backend with a directory to '
        'look them up in.',
        transport: name,
      );
    }
    _session = _P2PSession(
      transport: this,
      id: id,
      name: options.name,
      maxPeers: options.maxPeers,
      localPeer: NetPeerId.host,
    );
    _startTicker();
    if (options.advertise) _startBeacon();
    return _session!;
  }

  @override
  Future<NetSession> join(SessionId id) async {
    _requireOpen();
    _requireNoSession();
    final endpoint = EndpointCode.decode(id);
    if (endpoint == null) {
      throw NetException(
        'that is not a code this backend can read. A p2p code is '
        '${EndpointCode.length} characters and carries the host address; '
        'check for a typo.',
        transport: name,
      );
    }
    await _bind();
    _startTicker();

    final link = _link(endpoint.address, endpoint.port, NetPeerId.host);
    final handshake = _handshake = _Handshake(id, link, _now);
    _sendConnectRequest(handshake);
    try {
      return await handshake.completer.future;
    } finally {
      _handshake = null;
    }
  }

  @override
  Future<List<SessionInfo>> discover({
    Duration timeout = const Duration(seconds: 1),
  }) async {
    final found = <String, SessionInfo>{};
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    final done = Completer<void>();
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      final info = _readBeacon(datagram.data);
      if (info != null) found[info.id.value] = info;
    });
    Timer(timeout, () {
      socket.close();
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    return found.values.toList(growable: false);
  }

  Future<void> _bind() async {
    if (_socket != null) return;
    final socket = await RawDatagramSocket.bind(
      bindAddress,
      port,
      reuseAddress: true,
    );
    socket.broadcastEnabled = true;
    socket.listen(_onSocketEvent, onError: _onSocketError);
    _socket = socket;
  }

  /// The address to put in the join code and the beacon.
  ///
  /// Bound to one interface, that one. Bound to all of them, the first
  /// non-loopback IPv4 the machine has - which is the LAN address a peer in
  /// the same room can reach, and the best answer available without asking
  /// something on the internet what our public address is (which is STUN, and
  /// is the next landing).
  Future<InternetAddress> _advertisedAddress() async {
    if (bindAddress.type == InternetAddressType.IPv4 &&
        bindAddress != InternetAddress.anyIPv4) {
      return bindAddress;
    }
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (var i = 0; i < interfaces.length; i++) {
      final addresses = interfaces[i].addresses;
      if (addresses.isNotEmpty) return addresses.first;
    }
    // No non-loopback interface at all: an offline laptop, or a container
    // with only `lo`. Hosting still works, and the code it mints reaches
    // exactly as far as the machine itself - which is the truth.
    return InternetAddress.loopbackIPv4;
  }

  // --- the tick -----------------------------------------------------------

  void _startTicker() {
    _ticker ??= Timer.periodic(_tickInterval, (_) => _onTick());
  }

  /// Keepalives, retransmissions, timeouts and handshake retries.
  ///
  /// On a timer rather than only in [flush], because all four have to keep
  /// happening when the game has nothing to say - a link that only retried
  /// when the game sent something would stall forever the moment it went
  /// quiet, which is exactly when a lost packet is least likely to be noticed.
  void _onTick() {
    final now = _now;
    final handshake = _handshake;
    if (handshake != null) {
      if (now - handshake.startedMicros > handshakeTimeout.inMicroseconds) {
        _failHandshake(
          NetException(
            'no answer from ${handshake.link.address.address}:'
            '${handshake.link.port} after '
            '${handshakeTimeout.inMilliseconds}ms. Nobody is hosting there, or '
            'a firewall is dropping it.',
            transport: name,
          ),
        );
      } else if (now - handshake.lastSentMicros >=
          _handshakeInterval.inMicroseconds) {
        _sendConnectRequest(handshake);
      }
    }
    flush();
  }

  @override
  void flush() {
    if (_blocked.isNotEmpty) _drainBlocked();
    final now = _now;
    // Backwards: a link that times out removes itself from this list.
    for (var i = _links.length - 1; i >= 0; i--) {
      if (i >= _links.length) continue;
      _links[i].pump(_scratch, _scratchView, now);
    }
  }

  @override
  void poll(NetListener listener) {
    final due = _queue.length;
    if (due == 0) return;
    for (var i = 0; i < due; i++) {
      final delivery = _queue[i];
      switch (delivery.kind) {
        case _DeliveryKind.peerJoined:
          listener.onPeerJoined(delivery.peer);
        case _DeliveryKind.peerLeft:
          listener.onPeerLeft(delivery.peer, delivery.reason);
        case _DeliveryKind.message:
          listener.onMessage(
            delivery.peer,
            delivery.channel,
            delivery.bytes,
            delivery.offset,
            delivery.length,
          );
        case _DeliveryKind.sessionClosed:
          _session = null;
          listener.onSessionClosed(delivery.reason);
      }
      delivery.bytes = _empty;
      _spare.add(delivery);
    }
    _queue.removeRange(0, due);
  }

  static final Uint8List _empty = Uint8List(0);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _session?.leave();
    // The goodbye is sent once and this is the last chance it will get, so a
    // socket that refused it a moment ago is worth waiting on rather than
    // closing over the top of. Bounded, because a socket that never drains
    // must not be able to hold up a game's shutdown - and skipped entirely
    // when nothing is held, which is almost always.
    for (var attempt = 0; attempt < 10 && _blocked.isNotEmpty; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      _drainBlocked();
    }
    _ticker?.cancel();
    _beacon?.cancel();
    _ticker = null;
    _beacon = null;
    _socket?.close();
    _socket = null;
    _links.clear();
    _queue.clear();
    _blocked.clear();
    _blockedSpare.clear();
  }

  // --- receiving ----------------------------------------------------------

  /// Swallows what a UDP socket reports and a game cannot act on.
  ///
  /// The one that matters is Windows': sending a datagram to a port nobody is
  /// listening on gets an ICMP "port unreachable" back, and Windows surfaces
  /// that as an error on the *sending* socket rather than discarding it. So
  /// one peer quitting would raise an error on the host's socket, which -
  /// with no handler here - becomes an unhandled asynchronous error and takes
  /// the game isolate down. A peer that went away is exactly what the
  /// timeout and the disconnect packet are for; the socket error adds
  /// nothing, and the link that stopped answering is noticed either way.
  void _onSocketError(Object error, StackTrace stackTrace) {}

  void _onSocketEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.write) {
      _drainBlocked();
      return;
    }
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    // **Drained, not read once.** A read event says "there is at least one
    // datagram", not "there is exactly one", and a burst - the seven packets
    // one fragmented message becomes - can arrive under a single event.
    // Reading one per event left the rest sitting in the socket until the
    // next packet happened to wake it, which showed up as a large message
    // that arrived on a good day and timed out on a bad one.
    while (true) {
      // One `Datagram` and one `Uint8List` per packet, both allocated by
      // `dart:io` - the only per-packet garbage in the receive path, and not
      // something this layer can avoid without its own native socket
      // binding. The list is *kept*, not copied: it is ours the moment we are
      // handed it, which is what lets a queued message be a view rather than
      // a copy.
      final datagram = socket.receive();
      if (datagram == null) return;
      final data = datagram.data;
      if (data.length < prologueBytes) continue;
      if (data[0] != magic0 || data[1] != magic1) continue;
      if (data[2] != protocolVersion) continue;
      _onPacket(datagram.address, datagram.port, data[3], data);
    }
  }

  void _onPacket(InternetAddress address, int port, int type, Uint8List data) {
    final now = _now;
    switch (type) {
      case PacketType.connectRequest:
        _onConnectRequest(address, port, data);
      case PacketType.connectAccept:
        _onConnectAccept(address, port, data);
      case PacketType.connectReject:
        _onConnectReject(address, port, data);
      case PacketType.disconnect:
        _onDisconnect(address, port, data);
      case PacketType.payload:
        _linkFrom(address, port)?.onPayload(data, data.length, now);
      case PacketType.beacon:
      case PacketType.discover:
        // Answered by `discover`'s own socket, not this one.
        break;
    }
  }

  P2PLink? _linkFrom(InternetAddress address, int port) {
    final raw = address.rawAddress;
    for (var i = 0; i < _links.length; i++) {
      if (_links[i].isFrom(raw, port)) return _links[i];
    }
    return null;
  }

  P2PLink? _linkTo(NetPeerId peer) {
    for (var i = 0; i < _links.length; i++) {
      if (_links[i].peer == peer) return _links[i];
    }
    return null;
  }

  P2PLink _link(InternetAddress address, int port, NetPeerId peer) {
    final link = P2PLink(
      address: address,
      port: port,
      peer: peer,
      nowMicros: _now,
      timeoutMicros: linkTimeout.inMicroseconds,
      send: _sendDatagram,
      deliver: _queueMessage,
      deliverSystem: _onSystemMessage,
      lost: _onLinkLost,
    );
    _links.add(link);
    return link;
  }

  void _sendDatagram(P2PLink link, Uint8List datagram, int length) {
    _send(datagram, length, link.address, link.port);
  }

  /// The one place a packet leaves this transport, so that [simulatedLoss]
  /// covers the whole protocol.
  ///
  /// It used to sit in [_sendDatagram] alone, which meant the handshake and
  /// the goodbye - the two exchanges with no game logic on top to notice
  /// something went missing - were the only ones a loss knob could not break.
  /// A join at `simulatedLoss: 1` still succeeded.
  void _send(
    Uint8List datagram,
    int length,
    InternetAddress address,
    int port,
  ) {
    if (simulatedLoss > 0 && _random.nextDouble() < simulatedLoss) return;
    // Anything already waiting goes first. A fresh datagram that jumped the
    // queue would reorder the link's stream against itself, which is the one
    // thing the sequence numbers assume the socket does not do.
    if (_blocked.isNotEmpty) {
      _drainBlocked();
      if (_blocked.isNotEmpty) {
        _hold(datagram, length, address, port);
        return;
      }
    }
    if (!_write(datagram, length, address, port)) {
      _hold(datagram, length, address, port);
    }
  }

  /// One attempt at the socket. False means it would have blocked and the
  /// datagram is still ours to send.
  ///
  /// A closed transport reports true: there is no socket to be blocked on and
  /// nothing to keep the packet for, which is the same nothing the old
  /// `_socket?.send` did.
  bool _write(
    Uint8List datagram,
    int length,
    InternetAddress address,
    int port,
  ) {
    final socket = _socket;
    if (socket == null) return true;
    if (simulatedBackpressure > 0 &&
        _random.nextDouble() < simulatedBackpressure) {
      return false;
    }
    // Either `length` or zero - `send` never writes part of a datagram.
    return socket.send(
          Uint8List.sublistView(datagram, 0, length),
          address,
          port,
        ) !=
        0;
  }

  /// Keeps a datagram the socket refused, and asks to be told when it drains.
  void _hold(
    Uint8List datagram,
    int length,
    InternetAddress address,
    int port,
  ) {
    final socket = _socket;
    if (socket == null) return;
    if (_blocked.length >= maxHeldDatagrams) {
      _blockedSpare.add(_blocked.removeAt(0));
    }
    final held = _blockedSpare.isEmpty
        ? _Blocked()
        : _blockedSpare.removeLast();
    // Copied: every caller here hands over `_scratch`, which is the next
    // packet's buffer as soon as this one returns.
    if (held.bytes.length < length) held.bytes = Uint8List(length);
    held.bytes.setRange(0, length, datagram);
    held.length = length;
    held.address = address;
    held.port = port;
    _blocked.add(held);
    // One-shot, so it is re-armed on every hold rather than once at bind.
    socket.writeEventsEnabled = true;
  }

  /// Sends as much of [_blocked] as the socket will now take, oldest first.
  ///
  /// Called from the write event, and from [flush] as well because the event
  /// is the socket's to deliver and this transport already has a 25ms tick of
  /// its own. Waiting only on the event would make a missed one permanent.
  ///
  /// **It does not re-arm the write event.** Only [_hold] does, and only
  /// where a send has just been refused. Re-arming from here on a queue that
  /// is still not empty spins: the socket answers a write event immediately
  /// whenever it is writable, so anything that refuses a datagram for a
  /// reason the socket does not share - [simulatedBackpressure] is one, and a
  /// peer whose address the OS rejects would be another - gets an unbroken
  /// storm of events and the isolate never runs anything else. Draining short
  /// costs at most one tick, which is the backstop that exists anyway.
  void _drainBlocked() {
    var sent = 0;
    while (sent < _blocked.length) {
      final held = _blocked[sent];
      if (!_write(held.bytes, held.length, held.address, held.port)) break;
      sent++;
    }
    for (var i = 0; i < sent; i++) {
      _blockedSpare.add(_blocked[i]);
    }
    if (sent > 0) _blocked.removeRange(0, sent);
  }

  void _queueMessage(
    P2PLink link,
    NetChannel channel,
    Uint8List bytes,
    int offset,
    int length,
  ) {
    final delivery = _delivery(_DeliveryKind.message, link.peer)
      ..channel = channel
      ..bytes = bytes
      ..offset = offset
      ..length = length;
    _queue.add(delivery);
  }

  _Delivery _delivery(_DeliveryKind kind, NetPeerId peer) {
    final delivery = _spare.isEmpty ? _Delivery() : _spare.removeLast();
    delivery.kind = kind;
    delivery.peer = peer;
    delivery.offset = 0;
    delivery.length = 0;
    return delivery;
  }

  // --- the handshake ------------------------------------------------------

  void _sendConnectRequest(_Handshake handshake) {
    final code = handshake.id.value;
    var at = prologueBytes;
    _prologue(PacketType.connectRequest);
    _scratchView.setUint32(at, schemaHash, Endian.little);
    at += 4;
    at = _writeString(at, code);
    _send(_scratch, at, handshake.link.address, handshake.link.port);
    handshake.lastSentMicros = _now;
  }

  void _onConnectRequest(InternetAddress address, int port, Uint8List data) {
    final session = _session;
    if (session == null || !session.isHost) {
      _sendReject(address, port, RejectReason.notHosting);
      return;
    }
    final view = ByteData.sublistView(data);
    if (data.length < prologueBytes + 5) return;
    final theirSchema = view.getUint32(prologueBytes, Endian.little);
    final code = _readString(data, prologueBytes + 4);
    if (code == null) return;
    if (code != session.id.value) {
      _sendReject(address, port, RejectReason.wrongSession);
      return;
    }
    if (theirSchema != schemaHash) {
      _sendReject(address, port, RejectReason.schemaMismatch);
      return;
    }
    // A repeat because our accept was lost: answer again rather than admit
    // them twice.
    final existing = _linkFrom(address, port);
    if (existing != null) {
      _sendAccept(existing, session);
      return;
    }
    if (session.roster.length + 1 >= session.maxPeers) {
      _sendReject(address, port, RejectReason.sessionFull);
      return;
    }
    final slot = session.freeSlot();
    final generation = _generations.update(
      slot,
      (previous) => (previous + 1) & 0xFFFF,
      ifAbsent: () => 0,
    );
    final peer = NetPeerId.pack(slot, generation);
    final link = _link(address, port, peer)..promote();
    _sendAccept(link, session);
    // Everyone already here hears about the arrival, reliably.
    for (var i = 0; i < _links.length; i++) {
      if (identical(_links[i], link)) continue;
      _links[i].sendSystem(SystemMessage.peerJoined, <int>[
        slot & 0xFF,
        slot >> 8,
        generation & 0xFF,
        generation >> 8,
      ]);
    }
    session.roster.add(peer);
    _queue.add(_delivery(_DeliveryKind.peerJoined, peer));
  }

  void _sendAccept(P2PLink link, _P2PSession session) {
    _prologue(PacketType.connectAccept);
    var at = prologueBytes;
    _scratchView.setUint16(at, link.peer.slot, Endian.little);
    at += 2;
    _scratchView.setUint16(at, link.peer.generation, Endian.little);
    at += 2;
    _scratchView.setUint16(at, session.maxPeers, Endian.little);
    at += 2;
    at = _writeString(at, session.name);
    // The roster this joiner is walking into - everyone except itself. Sent
    // once here rather than as a burst of peerJoined frames, so that a client
    // is never briefly in a session it thinks is empty.
    final others = <NetPeerId>[
      for (var i = 0; i < session.roster.length; i++)
        if (session.roster[i] != link.peer) session.roster[i],
    ];
    _scratch[at++] = others.length;
    for (var i = 0; i < others.length; i++) {
      _scratchView.setUint16(at, others[i].slot, Endian.little);
      at += 2;
      _scratchView.setUint16(at, others[i].generation, Endian.little);
      at += 2;
    }
    _send(_scratch, at, link.address, link.port);
  }

  void _onConnectAccept(InternetAddress address, int port, Uint8List data) {
    final handshake = _handshake;
    if (handshake == null) return;
    if (!handshake.link.isFrom(address.rawAddress, port)) return;
    final view = ByteData.sublistView(data);
    if (data.length < prologueBytes + 7) return;
    var at = prologueBytes;
    final slot = view.getUint16(at, Endian.little);
    at += 2;
    final generation = view.getUint16(at, Endian.little);
    at += 2;
    final maxPeers = view.getUint16(at, Endian.little);
    at += 2;
    final name = _readString(data, at);
    if (name == null) return;
    at += 1 + name.length;
    final session = _P2PSession(
      transport: this,
      id: handshake.id,
      name: name,
      maxPeers: maxPeers,
      localPeer: NetPeerId.pack(slot, generation),
    )..roster.add(NetPeerId.host);
    final others = data[at++];
    for (var i = 0; i < others; i++) {
      final peerSlot = view.getUint16(at, Endian.little);
      at += 2;
      final peerGeneration = view.getUint16(at, Endian.little);
      at += 2;
      session.roster.add(NetPeerId.pack(peerSlot, peerGeneration));
    }
    handshake.link.promote();
    _session = session;
    handshake.completer.complete(session);
  }

  void _sendReject(InternetAddress address, int port, int reason) {
    _prologue(PacketType.connectReject);
    _scratch[prologueBytes] = reason;
    _send(_scratch, prologueBytes + 1, address, port);
  }

  void _onConnectReject(InternetAddress address, int port, Uint8List data) {
    final handshake = _handshake;
    if (handshake == null) return;
    if (!handshake.link.isFrom(address.rawAddress, port)) return;
    if (data.length < prologueBytes + 1) return;
    _failHandshake(
      NetException(RejectReason.describe(data[prologueBytes]), transport: name),
    );
  }

  void _failHandshake(NetException failure) {
    final handshake = _handshake;
    if (handshake == null) return;
    _handshake = null;
    _links.remove(handshake.link);
    if (!handshake.completer.isCompleted) {
      handshake.completer.completeError(failure);
    }
  }

  // --- leaving ------------------------------------------------------------

  void _sendDisconnect(P2PLink link, NetDisconnectReason reason) {
    _prologue(PacketType.disconnect);
    _scratch[prologueBytes] = reason.index;
    _send(_scratch, prologueBytes + 1, link.address, link.port);
  }

  void _onDisconnect(InternetAddress address, int port, Uint8List data) {
    final link = _linkFrom(address, port);
    if (link == null) return;
    final reason = data.length > prologueBytes
        ? NetDisconnectReason.values[data[prologueBytes] %
              NetDisconnectReason.values.length]
        : NetDisconnectReason.remoteClose;
    _onLinkLost(link, reason, tell: false);
  }

  /// A link ended, for whatever reason: it timed out, the peer said goodbye,
  /// or this side did.
  void _onLinkLost(
    P2PLink link,
    NetDisconnectReason reason, {
    bool tell = true,
  }) {
    if (link.state == NetConnectionState.disconnected) return;
    if (tell) _sendDisconnect(link, reason);
    link.end(reason);
    _links.remove(link);
    final session = _session;
    if (session == null) return;
    if (!session.isHost) {
      // The only link a client has is to the host, so losing it is losing the
      // session - there is nothing left to be a member of.
      _closeSession(
        reason == NetDisconnectReason.localClose
            ? NetDisconnectReason.localClose
            : reason == NetDisconnectReason.timeout
            ? NetDisconnectReason.timeout
            : NetDisconnectReason.sessionClosed,
      );
      return;
    }
    if (!session.roster.remove(link.peer)) return;
    final slot = link.peer.slot;
    final generation = link.peer.generation;
    for (var i = 0; i < _links.length; i++) {
      _links[i].sendSystem(SystemMessage.peerLeft, <int>[
        slot & 0xFF,
        slot >> 8,
        generation & 0xFF,
        generation >> 8,
        reason.index,
      ]);
    }
    _queue.add(_delivery(_DeliveryKind.peerLeft, link.peer)..reason = reason);
  }

  /// A roster update from the host, on a client.
  void _onSystemMessage(P2PLink link, int message, Uint8List body) {
    final session = _session;
    if (session == null || session.isHost) return;
    if (!link.peer.isHost) return;
    if (body.length < 4) return;
    final peer = NetPeerId.pack(
      body[0] | (body[1] << 8),
      body[2] | (body[3] << 8),
    );
    switch (message) {
      case SystemMessage.peerJoined:
        if (session.roster.contains(peer)) return;
        session.roster.add(peer);
        _queue.add(_delivery(_DeliveryKind.peerJoined, peer));
      case SystemMessage.peerLeft:
        if (!session.roster.remove(peer)) return;
        final reason = body.length > 4
            ? NetDisconnectReason.values[body[4] %
                  NetDisconnectReason.values.length]
            : NetDisconnectReason.remoteClose;
        _queue.add(_delivery(_DeliveryKind.peerLeft, peer)..reason = reason);
    }
  }

  /// This peer is leaving: as a client, say goodbye to the host; as the host,
  /// end it for everyone.
  Future<void> leaveSession() async {
    final session = _session;
    if (session == null) return;
    final reason = session.isHost
        ? NetDisconnectReason.sessionClosed
        : NetDisconnectReason.remoteClose;
    // Copied, because ending a link removes it from the list.
    final links = _links.toList(growable: false);
    for (var i = 0; i < links.length; i++) {
      _sendDisconnect(links[i], reason);
      links[i].end(NetDisconnectReason.localClose);
    }
    _links.clear();
    _beacon?.cancel();
    _beacon = null;
    _closeSession(NetDisconnectReason.localClose);
  }

  void _closeSession(NetDisconnectReason reason) {
    if (_session == null) return;
    // The session object stays reachable until `poll` reports the closure, so
    // that a game asking "what happened" between the two still gets an
    // answer. `poll` is what clears it.
    _queue.add(
      _delivery(_DeliveryKind.sessionClosed, NetPeerId.none)..reason = reason,
    );
  }

  // --- beacons ------------------------------------------------------------

  void _startBeacon() {
    // A session whose code says 127.0.0.1 is reachable from this machine and
    // nowhere else, so announcing it to the LAN would list an entry that
    // cannot be joined from any machine that can see the announcement. It
    // also means sending a broadcast out of a loopback-bound socket, which
    // Windows reports asynchronously as ERROR_NETWORK_UNREACHABLE - an error
    // arriving on a socket nobody expected to fail.
    if (_advertised?.isLoopback ?? true) return;
    _sendBeacon();
    _beacon ??= Timer.periodic(_beaconInterval, (_) => _sendBeacon());
  }

  /// Announces this session to the LAN.
  ///
  /// Hosts announce and clients listen, rather than clients asking and hosts
  /// answering. Only one of those needs a well-known port to be *bound*, and
  /// making it the listener's means several hosts can run on one machine -
  /// which is a normal thing to do while developing and impossible if every
  /// host has to own the same port.
  void _sendBeacon() {
    final session = _session;
    final socket = _socket;
    if (session == null || socket == null) return;
    _prologue(PacketType.beacon);
    var at = prologueBytes;
    _scratchView.setUint32(at, schemaHash, Endian.little);
    at += 4;
    at = _writeString(at, session.id.value);
    at = _writeString(at, session.name);
    _scratch[at++] = session.roster.length + 1;
    _scratchView.setUint16(at, session.maxPeers, Endian.little);
    at += 2;
    try {
      socket.send(
        Uint8List.sublistView(_scratch, 0, at),
        InternetAddress('255.255.255.255'),
        discoveryPort,
      );
    } on SocketException {
      // A machine with no route for broadcast - a container, a locked-down
      // corporate laptop - simply has no LAN discovery. The session is still
      // reachable by its code, so this is a missing convenience rather than a
      // failure worth propagating into the game.
    }
  }

  SessionInfo? _readBeacon(Uint8List data) {
    if (data.length < prologueBytes + 5) return null;
    if (data[0] != magic0 || data[1] != magic1) return null;
    if (data[2] != protocolVersion) return null;
    if (data[3] != PacketType.beacon) return null;
    final view = ByteData.sublistView(data);
    var at = prologueBytes;
    final theirSchema = view.getUint32(at, Endian.little);
    at += 4;
    // A session from a different build is not one this peer could join, so it
    // is not one to list - the alternative is a lobby full of entries that
    // all fail the same way when tapped.
    if (theirSchema != schemaHash) return null;
    final code = _readString(data, at);
    if (code == null) return null;
    at += 1 + code.length;
    final name = _readString(data, at);
    if (name == null) return null;
    at += 1 + name.length;
    if (at + 3 > data.length) return null;
    final peerCount = data[at++];
    final maxPeers = view.getUint16(at, Endian.little);
    return SessionInfo(
      id: SessionId(code),
      name: name,
      peerCount: peerCount,
      maxPeers: maxPeers,
    );
  }

  // --- small shared bits --------------------------------------------------

  void _prologue(int type) {
    _scratch[0] = magic0;
    _scratch[1] = magic1;
    _scratch[2] = protocolVersion;
    _scratch[3] = type;
  }

  /// A length-prefixed UTF-8 string, at most 255 bytes.
  int _writeString(int at, String value) {
    final bytes = utf8.encode(value);
    final length = bytes.length > 255 ? 255 : bytes.length;
    _scratch[at] = length;
    _scratch.setRange(at + 1, at + 1 + length, bytes);
    return at + 1 + length;
  }

  String? _readString(Uint8List data, int at) {
    if (at >= data.length) return null;
    final length = data[at];
    if (at + 1 + length > data.length) return null;
    return utf8.decode(
      Uint8List.sublistView(data, at + 1, at + 1 + length),
      allowMalformed: true,
    );
  }

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

/// A join in flight: which code, over which link, and who is waiting.
class _Handshake {
  _Handshake(this.id, this.link, this.startedMicros)
    : lastSentMicros = startedMicros;

  final SessionId id;
  final P2PLink link;
  final int startedMicros;
  int lastSentMicros;
  final Completer<NetSession> completer = Completer<NetSession>();
}

enum _DeliveryKind { peerJoined, peerLeft, message, sessionClosed }

/// One thing waiting for [P2PNetTransport.poll]. Mutable and pooled.
class _Delivery {
  _DeliveryKind kind = _DeliveryKind.message;
  NetPeerId peer = NetPeerId.none;
  NetDisconnectReason reason = NetDisconnectReason.remoteClose;
  NetChannel channel = NetChannel.reliable;
  Uint8List bytes = Uint8List(0);
  int offset = 0;
  int length = 0;
}

/// One datagram the socket would not take, held until it will.
///
/// [bytes] outlives one send and is grown rather than replaced, so a run of
/// backpressure settles on a buffer instead of allocating per packet.
class _Blocked {
  Uint8List bytes = Uint8List(0);
  int length = 0;
  InternetAddress address = InternetAddress.loopbackIPv4;
  int port = 0;
}

/// This peer's view of the session it is in.
class _P2PSession implements NetSession {
  _P2PSession({
    required this.id,
    required this.name,
    required this.maxPeers,
    required this.localPeer,
    required P2PNetTransport transport,
  }) : // The caller names it `transport`; the underscore is this class's own
       // business.
       // ignore: prefer_initializing_formals
       _transport = transport;

  final P2PNetTransport _transport;

  @override
  final SessionId id;

  @override
  final String name;

  @override
  final int maxPeers;

  @override
  final NetPeerId localPeer;

  /// Everyone else: the clients on the host, the host plus the other clients
  /// on a client.
  final List<NetPeerId> roster = <NetPeerId>[];

  @override
  bool get isHost => localPeer.isHost;

  @override
  bool get isOpen => identical(_transport._session, this);

  @override
  int get peerCount => roster.length;

  @override
  NetPeerId peerAt(int index) => roster[index];

  @override
  bool hasPeer(NetPeerId peer) => roster.contains(peer);

  @override
  NetConnection? connectionTo(NetPeerId peer) {
    if (peer == localPeer) return null;
    // The star: a client reaches the host and nobody else, and on the host
    // every roster entry has a link of its own.
    if (!isHost && !peer.isHost) return null;
    return _transport._linkTo(peer);
  }

  @override
  void sendToAll(
    NetChannel channel,
    Uint8List bytes, [
    int offset = 0,
    int? length,
  ]) {
    final links = _transport._links;
    for (var i = 0; i < links.length; i++) {
      links[i].send(channel, bytes, offset, length);
    }
  }

  /// The lowest slot nobody holds. Linear over a handful of peers, at join
  /// time - a free-list would be more machinery than the problem has.
  int freeSlot() {
    for (var slot = 1; slot < maxPeers; slot++) {
      var taken = false;
      for (var i = 0; i < roster.length; i++) {
        if (roster[i].slot == slot) {
          taken = true;
          break;
        }
      }
      if (!taken) return slot;
    }
    throw StateError('no free slot in a session that is not full');
  }

  @override
  Future<void> leave() => _transport.leaveSession();
}
