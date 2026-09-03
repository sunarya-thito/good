import 'dart:typed_data';

import 'package:good/good.dart';
import 'package:meta/meta.dart';

import 'channel.dart';
import 'connection.dart';
import 'listener.dart';
import 'message.dart';
import 'peer.dart';
import 'registry.dart';
import 'session.dart';
import 'transport.dart';

/// Hears about peers arriving and leaving. Mixed into anything that already
/// lives on the game isolate - a system, a scene, an entity struct, the state
/// itself - exactly like `EntitySpawnListener`.
///
/// ```dart
/// class Lobby extends SceneStruct with NetPeerListener {
///   @override
///   void onPeerJoined(NetPeerId peer) => spawnPlayerFor(peer);
/// }
/// ```
mixin NetPeerListener on GameListener {
  /// [peer] is now in the session. Fired on every machine, including for
  /// peers that were already there when this one joined - so a listener that
  /// only implements this method still ends up with the whole roster.
  void onPeerJoined(NetPeerId peer) {}

  /// [peer] has gone, for [reason]. Its slot may be handed to someone else on
  /// any later tick with a bumped `NetPeerId.generation`, so anything holding
  /// per-peer state keyed by slot clears it here.
  void onPeerLeft(NetPeerId peer, NetDisconnectReason reason) {}
}

/// Hears about the session itself starting and ending.
mixin NetSessionListener on GameListener {
  /// A session is live - this peer hosted one or finished joining one.
  void onSessionOpened(NetSession session) {}

  /// The session has ended: this peer left, the host closed it, or the host
  /// went away.
  void onSessionClosed(NetDisconnectReason reason) {}
}

/// The simulation half of multiplayer: declares the network messages, the
/// backend, and the [NetworkSystem] that carries them.
///
/// ```dart
/// class MyState extends GameState<MyGame> with MultiplayerState<MyGame> {
///   late final Fire fire;
///
///   @override
///   void describeNetwork(NetDescriptor descriptor) {
///     descriptor.transport(P2PNetTransport());
///     fire = descriptor.has(Fire.new, id: 'fire', channel: NetChannel.unreliable);
///     descriptor.hasHandler(fire, _onFire);
///   }
///
///   Future<void> startHosting() async {
///     final session = await network.host(const SessionOptions(name: 'mine'));
///     print('tell your friends: ${session.id}');
///   }
/// }
/// ```
///
/// # All of it lives on the game isolate
///
/// `Game2D` is a superclass because rendering has a main-isolate half - a
/// widget to build, native buffers to allocate before the spawn. Networking has
/// none: the socket, the messages and the handlers all live where the
/// simulation lives, and `GameState` is the type that says "game isolate" (the
/// isolate-affinity rule). Nothing here needs the Flutter side to have heard of
/// it, so nothing here is declared over there.
///
/// [describeNetwork] is abstract, with no empty default. A state that mixes
/// this in and declares nothing has a transport it never uses and a system
/// that polls nothing, and that is worth a compile error instead of a silent
/// no-op.
mixin MultiplayerState<G extends Game> on GameState<G> {
  /// Declares this game's messages and its backend - see [NetDescriptor].
  ///
  /// Runs once, at boot, from [describeSystems] - and so on the simulating
  /// copy only, because that is the one place `describeSystems` is invoked.
  /// The main-isolate copy of the state never runs it and never builds a
  /// transport, so there is no second socket to keep shut.
  void describeNetwork(NetDescriptor descriptor);

  /// The system carrying this game's traffic - `network.host(...)`,
  /// `network.join(code)`, `network.session`.
  late final NetworkSystem network;

  /// A peer joined the session. See [NetPeerListener].
  late final EventDispatcher<NetPeerListener, NetPeerId> peerJoinedEvent;

  /// A peer left. See [NetPeerListener].
  ///
  /// The payload is a record because the event genuinely carries two facts,
  /// and a peer leaving happens at human rate - a handful of times a session
  /// - so the one allocation is not on any path the no-allocation rule is about.
  late final EventDispatcher<
    NetPeerListener,
    ({NetPeerId peer, NetDisconnectReason reason})
  >
  peerLeftEvent;

  /// A session opened - hosted or joined. See [NetSessionListener].
  late final EventDispatcher<NetSessionListener, NetSession> sessionOpenedEvent;

  /// The session ended. See [NetSessionListener].
  late final EventDispatcher<NetSessionListener, NetDisconnectReason>
  sessionClosedEvent;

  @override
  @mustCallSuper
  void describeEvents(EventDescriptor descriptor) {
    super.describeEvents(descriptor);
    peerJoinedEvent = descriptor.has(
      (listener, peer) => listener.onPeerJoined(peer),
    );
    // Reverse, matching every other teardown event in the engine: a listener
    // told late can still read what the earlier ones have been warned about.
    peerLeftEvent = descriptor.has(
      (listener, left) => listener.onPeerLeft(left.peer, left.reason),
      reverse: true,
    );
    sessionOpenedEvent = descriptor.has(
      (listener, session) => listener.onSessionOpened(session),
    );
    sessionClosedEvent = descriptor.has(
      (listener, reason) => listener.onSessionClosed(reason),
      reverse: true,
    );
  }

  /// Declares the system, runs [describeNetwork] into it, and seals what that
  /// declared.
  ///
  /// The order matters and is the reason this is not two passes: a message
  /// binds to the thing that will send it at declare time, so the system has
  /// to exist before the pass runs - and the pass has to have run before the
  /// registry can be sealed and hashed.
  ///
  /// The declaration is what builds it, which is why it comes first here and
  /// did not used to. `SystemDescriptor.has` opens the event binder and the
  /// input registry around the constructor call, and a `NetworkSystem` built
  /// beside it and handed over afterwards would have had neither - so its
  /// four dispatchers could not move onto their fields. Everything after this
  /// line reads `network` back off the handle rather than off a local.
  ///
  /// Declared **before** `super.describeSystems`, so that in the absence of
  /// any `compareTo` opinion it is also first in declaration order.
  @override
  @mustCallSuper
  void describeSystems(SystemDescriptor descriptor) {
    network = descriptor.has(NetworkSystem.new);
    describeNetwork(NetBinder(network.registry, network));
    network.registry.seal();
    super.describeSystems(descriptor);
  }
}

/// Carries a game's network messages: drains what arrived at the top of each
/// fixed tick, and puts what was queued on the wire once per frame.
///
/// Declared by [MultiplayerState], never by hand - it has to be handed the
/// registry that `describeNetwork` filled, and that pass is the mixin's.
///
/// # Where it sits in the tick
///
/// Inbound is drained in [onFixedUpdate], and this system asks to run
/// **first**, on the same argument that puts `pumpCommands` before every
/// system: what a message handler does is write component data, and every
/// system on this tick should see it, not pick it up next tick.
///
/// `Box2DPhysicsSystem` also asks to run first, for its own good reason, so
/// two libraries claim the same slot and one of them loses. No priority
/// number papers over that, because the outcome is *correct either way*:
/// whichever runs second sees the other's writes on the next
/// tick instead of this one, which for traffic that already crossed the
/// internet is a rounding error. Declaration order breaks the tie
/// (`GameState.sortSystems` is deterministic about that), and
/// [MultiplayerState] declares this one first.
///
/// Outbound is flushed in [onTick] - the presentation pass, which runs once
/// per *frame*, after however many fixed steps that frame afforded. So three
/// catch-up steps produce one batch of datagrams instead of three, and a
/// message queued by the first step does not wait for the next frame.
class NetworkSystem extends GameSystem
    with FixedTickable, Tickable, GameSystemLifecycleListener
    implements NetSender, NetListener {
  /// Built by [MultiplayerState.describeSystems].
  @internal
  NetworkSystem();

  /// The messages and backend `describeNetwork` declared.
  @internal
  final NetRegistry registry = NetRegistry();

  /// The declared backend.
  ///
  /// Throws if `describeNetwork` declared none - at boot, naming the pass,
  /// and not at the first send with a null error.
  NetTransport get transport {
    final transport = registry.transport;
    if (transport == null) {
      throw StateError(
        'this game declared network messages but no backend to carry them. '
        'Add one in describeNetwork - `descriptor.transport(P2PNetTransport())` '
        '- or `LoopbackNetTransport()` for a test.',
      );
    }
    return transport;
  }

  /// The live session, or null when this peer is in none.
  @override
  NetSession? get session => registry.transport?.session;

  /// This peer's id.
  ///
  /// [NetPeerId.host] when there is no session, for the same reason [isHost]
  /// is true then: a game with nobody connected is a session of one, and this
  /// is the peer at the middle of it. This value is what a handler is handed
  /// as the sender, so [NetPeerId.none] here would make an offline game see
  /// every one of its own messages arrive from slot 65535, and anything
  /// keying per-peer state by slot would write it somewhere no player reads.
  @override
  NetPeerId get localPeer => session?.localPeer ?? NetPeerId.host;

  /// Whether this peer is the authority.
  ///
  /// **True when there is no session at all**, and that is what makes single
  /// player, hosting and joining one code path: a game with nobody connected
  /// is a session of one whose host is you, so `fire(...)` runs its handler
  /// locally and the same gameplay code works before anyone joins.
  @override
  bool get isHost => session?.isHost ?? true;

  /// Whether this peer is in a session with at least one other machine in it.
  bool get isNetworked {
    final session = this.session;
    return session != null && session.peerCount > 0;
  }

  /// Messages dropped because the peer that sent them was not allowed to -
  /// see the note on authority in [onMessage].
  int get rejectedMessages => _rejectedMessages;
  int _rejectedMessages = 0;

  /// One outbound batch per channel per peer slot, filled during the tick and
  /// emptied by [onTick]. Grown to fit a slot the first time one is used;
  /// null for a slot nothing has been sent to.
  final List<List<ParamBatch>?> _perPeer = <List<ParamBatch>?>[];

  /// One outbound batch per channel for messages going to every client -
  /// written once, copied per connection when it is flushed.
  late final List<ParamBatch> _broadcast = _channelBatches();

  /// The batch a received datagram is read through. One instance for the life
  /// of the system: `adoptIncoming` re-points it at the transport's buffer
  /// without copying, so parsing a message allocates nothing.
  final ParamBatch _inbound = ParamBatch();

  /// Where a message sent to nobody gets written so that it can still be read
  /// back and handled locally. See [dispatchLocally].
  ///
  /// One per channel, even though none of it goes anywhere, so that a record
  /// written here meets the ceiling it would have met on the wire. That is
  /// what makes an oversized message a mistake a game finds while it is still
  /// a game of one. Without it, a `hasBytes()` field works perfectly until
  /// the day somebody joins.
  late final List<ParamBatch> _local = _channelBatches();

  /// A batch per channel, each capped at what the declared backend carries on
  /// that channel.
  ///
  /// The cap is read once, here, and not again: a transport is declared in
  /// `describeNetwork` and never swapped, and these are built lazily on first
  /// use, which is after that pass has run.
  List<ParamBatch> _channelBatches() => <ParamBatch>[
    for (var i = 0; i < NetChannel.count; i++)
      ParamBatch(maxRecordBytes: _carries(NetChannel.values[i])),
  ];

  /// What the declared backend can carry in one message on [channel], or
  /// [ParamBatch.unbounded] when no backend has been declared - which is a
  /// mistake the [transport] getter reports properly, and not one to fail a
  /// local dispatch over.
  int _carries(NetChannel channel) =>
      registry.transport?.maxMessageBytes(channel) ?? ParamBatch.unbounded;

  @override
  int compareTo(GameSystem other) => other is NetworkSystem ? 0 : -1;

  // --- session lifecycle -------------------------------------------------

  /// Opens a session and returns it. This peer becomes [NetPeerId.host].
  ///
  /// ```dart
  /// final session = await network.host(const SessionOptions(name: 'Kitchen'));
  /// print('join code: ${session.id}');
  /// ```
  Future<NetSession> host([
    SessionOptions options = const SessionOptions(),
  ]) async {
    final transport = this.transport..bindSchema(registry.schemaHash);
    final session = await transport.host(options);
    _onSessionOpened(session);
    return session;
  }

  /// Joins the session with code [id]. Throws [NetException] if it cannot -
  /// unknown code, session full, or the two builds disagree (see
  /// [NetTransport.schemaHash]).
  Future<NetSession> join(SessionId id) async {
    final transport = this.transport..bindSchema(registry.schemaHash);
    final session = await transport.join(id);
    _onSessionOpened(session);
    return session;
  }

  /// Sessions this backend can see right now - for a join screen.
  Future<List<SessionInfo>> discover({
    Duration timeout = const Duration(seconds: 1),
  }) => transport.discover(timeout: timeout);

  /// Leaves the session, or closes it for everyone if this peer is the host.
  Future<void> leave() async {
    final session = this.session;
    if (session == null) return;
    await session.leave();
  }

  void _onSessionOpened(NetSession session) {
    _resetOutbound();
    getState<MultiplayerState>().sessionOpenedEvent.call(session);
    // Peers already present when this one joined are reported as joins, so a
    // listener that only handles onPeerJoined still sees the whole roster.
    for (var i = 0; i < session.peerCount; i++) {
      getState<MultiplayerState>().peerJoinedEvent.call(session.peerAt(i));
    }
  }

  void _resetOutbound() {
    for (var i = 0; i < _broadcast.length; i++) {
      _broadcast[i].reset();
    }
    for (var slot = 0; slot < _perPeer.length; slot++) {
      final batches = _perPeer[slot];
      if (batches == null) continue;
      for (var i = 0; i < batches.length; i++) {
        batches[i].reset();
      }
    }
  }

  // --- the tick ----------------------------------------------------------

  @override
  void onFixedUpdate() => registry.transport?.poll(this);

  @override
  void onTick(Duration delta) {
    final transport = registry.transport;
    if (transport == null) return;
    final session = transport.session;
    if (session != null) _flush(session);
    transport.flush();
  }

  void _flush(NetSession session) {
    for (var c = 0; c < NetChannel.count; c++) {
      final channel = NetChannel.values[c];
      final limit = _carries(channel);
      final broadcast = _broadcast[c];
      if (broadcast.length > 0) {
        _sendInPieces(session, null, channel, broadcast, limit);
        broadcast.reset();
      }
      for (var slot = 0; slot < _perPeer.length; slot++) {
        final batches = _perPeer[slot];
        if (batches == null) continue;
        final batch = batches[c];
        if (batch.length == 0) continue;
        // The generation is not carried here: a batch is filled and flushed
        // inside one frame, and a peer that left during that frame took its
        // connection with it, so the lookup simply finds nothing.
        final connection = session.connectionTo(_peerInSlot(session, slot));
        if (connection != null) {
          _sendInPieces(session, connection, channel, batch, limit);
        }
        batch.reset();
      }
    }
  }

  /// Hands [batch] to [connection], or to every peer when it is null, in as
  /// few sends as [limit] allows.
  ///
  /// A tick's traffic is one batch, and a busy tick's batch can be longer
  /// than any one message the backend carries. That is not a refusal: a batch
  /// is a run of records that each begin with the declaration index giving
  /// their length, so it can be cut at a record boundary and the receiving
  /// side walks each piece exactly as it would have walked the whole. Only a
  /// **single record** over the limit has no answer of this shape, and that
  /// one is refused at the write that made it - see
  /// [ParamBatch.maxRecordBytes], which every batch here is built with.
  ///
  /// Cutting at record boundaries is also what lets the unreliable channel
  /// stay one datagram wide: a lost piece costs the records in it and not the
  /// tick's whole traffic.
  void _sendInPieces(
    NetSession session,
    NetConnection? connection,
    NetChannel channel,
    ParamBatch batch,
    int limit,
  ) {
    final end = batch.start + batch.length;
    var from = batch.start;
    var record = 0;
    while (record < batch.callCount) {
      var to = from;
      while (record < batch.callCount) {
        final next = record + 1 < batch.callCount
            ? batch.startAt(record + 1)
            : end;
        // `to > from` keeps a piece from being empty: one record that will
        // not fit alone still goes, and the backend refuses it by name.
        if (limit >= 0 && next - from > limit && to > from) break;
        to = next;
        record++;
      }
      if (connection == null) {
        session.sendToAll(channel, batch.bytes, from, to - from);
      } else {
        connection.send(channel, batch.bytes, from, to - from);
      }
      from = to;
    }
  }

  /// The live peer id occupying [slot], or [NetPeerId.none].
  ///
  /// A linear walk of the roster, not a slot-indexed array, because
  /// the roster is the session's to own and it is at most a handful of
  /// entries - this runs once per slot per frame, not per message.
  NetPeerId _peerInSlot(NetSession session, int slot) {
    if (slot == NetPeerId.host.slot) return NetPeerId.host;
    for (var i = 0; i < session.peerCount; i++) {
      final peer = session.peerAt(i);
      if (peer.slot == slot) return peer;
    }
    return NetPeerId.none;
  }

  // --- NetSender ---------------------------------------------------------

  @override
  bool runsLocally(NetTarget target) {
    switch (target) {
      case NetTarget.host:
        return isHost;
      case NetTarget.clients:
        return false;
      case NetTarget.everyone:
        return true;
    }
  }

  @override
  ParamBuffer? reserve(NetMessageBase message) {
    final session = this.session;
    if (session == null) return null;
    switch (message.target) {
      case NetTarget.host:
        // The host does not send itself messages; the local dispatch in
        // `NetMessage.call` is what runs them there.
        if (session.isHost) return null;
        return _append(
          _batchFor(NetPeerId.host.slot, message.channel),
          message,
        );
      case NetTarget.clients:
      case NetTarget.everyone:
        if (session.peerCount == 0) return null;
        return _append(_broadcast[message.channel.index], message);
    }
  }

  @override
  ParamBuffer? reserveTo(NetMessageBase message, NetPeerId peer) {
    final session = this.session;
    if (session == null) return null;
    if (session.connectionTo(peer) == null) {
      assert(
        false,
        'there is no link to peer ${peer.slot} to send ${message.runtimeType} '
        'over. On the star topology a client can only reach the host; the '
        'host can reach every client. See NetSession.',
      );
      return null;
    }
    return _append(_batchFor(peer.slot, message.channel), message);
  }

  @override
  ParamBuffer scratch(NetMessageBase message) {
    final local = _local[message.channel.index]..reset();
    return _append(local, message);
  }

  @override
  void dispatchLocally(NetMessageBase message, ParamBuffer record) =>
      message.invoke(record, localPeer);

  ParamBuffer _append(ParamBatch batch, NetMessageBase message) =>
      batch.append(message.index, message.layout);

  ParamBatch _batchFor(int slot, NetChannel channel) {
    while (_perPeer.length <= slot) {
      _perPeer.add(null);
    }
    var batches = _perPeer[slot];
    if (batches == null) {
      batches = _channelBatches();
      _perPeer[slot] = batches;
    }
    return batches[channel.index];
  }

  // --- NetListener -------------------------------------------------------

  @override
  void onPeerJoined(NetPeerId peer) =>
      getState<MultiplayerState>().peerJoinedEvent.call(peer);

  @override
  void onPeerLeft(NetPeerId peer, NetDisconnectReason reason) {
    final batches = peer.slot < _perPeer.length ? _perPeer[peer.slot] : null;
    if (batches != null) {
      // Whatever was queued for them this frame has nowhere to go now.
      for (var i = 0; i < batches.length; i++) {
        batches[i].reset();
      }
    }
    getState<MultiplayerState>().peerLeftEvent.call((
      peer: peer,
      reason: reason,
    ));
  }

  @override
  void onSessionClosed(NetDisconnectReason reason) {
    _resetOutbound();
    getState<MultiplayerState>().sessionClosedEvent.call(reason);
  }

  /// Reads the records in one received datagram and runs their handlers.
  ///
  /// # Who is allowed to send what
  ///
  /// A message's [NetTarget] says who handles it, which says who may send it:
  /// a `NetTarget.host` message is a client's request and only the host may
  /// receive one; a `clients`/`everyone` message is the host's decision and
  /// only the host may send one. A record that arrives the wrong way round is
  /// **dropped and counted** ([rejectedMessages]), never asserted on,
  /// because the sender is another machine: a modified client is a thing that
  /// exists, and taking a host down in debug because someone sent it a
  /// malformed packet would be a denial of service with extra steps.
  ///
  /// Note this is the only check the transport layer makes. Whether *this*
  /// client is allowed to open that door is the game's own decision, made in
  /// the handler, where the game state that answers it lives.
  @override
  void onMessage(
    NetPeerId from,
    NetChannel channel,
    Uint8List bytes,
    int offset,
    int length,
  ) {
    _inbound.adoptIncoming(bytes, registry, offset, length);
    for (var i = 0; i < _inbound.callCount; i++) {
      final record = _inbound.callAt(i);
      final message = registry.requireAt(_inbound.indexAt(i));
      if (!_mayReceive(message, from)) {
        _rejectedMessages++;
        continue;
      }
      message.invoke(record, from);
    }
  }

  bool _mayReceive(NetMessageBase message, NetPeerId from) {
    switch (message.target) {
      case NetTarget.host:
        return isHost;
      case NetTarget.clients:
      case NetTarget.everyone:
        return from.isHost;
    }
  }

  // --- shutdown ----------------------------------------------------------

  @override
  void onUnmounted() {
    // Not awaited: unmount is synchronous, and a socket that outlives the
    // game by a few milliseconds is closed either way.
    registry.transport?.close();
  }
}
