import 'package:meta/meta.dart';

import 'listener.dart';
import 'session.dart';

/// A networking backend: what actually moves bytes between machines.
///
/// One of these is declared per game, in `describeNetwork`, and from then on
/// nothing in game code names it again - messages are declared against the
/// game, not against the backend, so switching from `LoopbackNetTransport` in
/// a test to `P2PNetTransport` in a build is a one-line change at the
/// declaration and nothing else.
///
/// # What a backend owes the layer above it
///
///  * **Nothing is delivered outside [poll].** A socket fires whenever the OS
///    feels like it; a simulation consumes input at one point in its tick.
///    A backend therefore buffers what arrives and hands it over only when
///    asked, so a burst of packets lands wholly inside one tick instead of
///    half in and half out of it.
///  * **Nothing is sent outside [flush]**, beyond what the backend's own
///    protocol needs (handshakes, acks, keepalives). [NetConnection.send]
///    queues; flush is what puts a tick's worth of traffic into as few
///    datagrams as it can.
///  * **The schema hash is checked before a session forms.** See
///    [schemaHash].
abstract class NetTransport {
  /// Identifies the backend in diagnostics - `'loopback'`, `'p2p'`.
  String get name;

  /// A hash of the sending side's message declarations, checked during the
  /// handshake and refused on mismatch.
  ///
  /// # Why this exists at all
  ///
  /// A message's identity on the wire is its **position** in `describeNetwork`
  /// (the same trick `describeCommands` uses across isolates), which is what
  /// makes a message cost two bytes of header instead of a name. Across
  /// isolates that is airtight: both copies are the same program. Across
  /// machines it is not - a player on last week's build has a different
  /// declaration order, and index 4 quietly means something else on their
  /// side. The bytes still parse; they just mean the wrong thing, which is
  /// the worst failure mode available.
  ///
  /// So the handshake carries this, and a mismatch is a refused connection
  /// with a version error rather than a session where damage arrives as chat.
  int get schemaHash => _schemaHash;
  int _schemaHash = 0;

  /// Set by `NetworkSystem` at boot, once the message registry is sealed.
  /// Not a constructor argument, because the transport is declared *before*
  /// the messages it will carry are.
  @internal
  void bindSchema(int hash) => _schemaHash = hash;

  /// The session this transport is in, or null before hosting or joining and
  /// after leaving.
  NetSession? get session;

  /// Opens a session and returns it, with this peer as [NetPeerId.host].
  ///
  /// The options are optional: hosting with the defaults is the common case
  /// and should not need an argument to say so.
  Future<NetSession> host([SessionOptions options = const SessionOptions()]);

  /// Joins the session with the code [id].
  ///
  /// One entry point rather than a second `joinDiscovered(SessionInfo)`
  /// overload: [discover] hands back codes, and how a code resolves to a
  /// machine - a cached LAN address, a rendezvous lookup - is the backend's
  /// own business (the no-specialised-variant rule, one way to do a thing).
  ///
  /// Fails with a [NetException] if the code is unknown, the session is full,
  /// or the two ends disagree about [schemaHash].
  Future<NetSession> join(SessionId id);

  /// Sessions this backend can currently see - LAN broadcast answers, a
  /// rendezvous listing. Empty for backends with no discovery of their own.
  ///
  /// Allocates: it is a menu, not a tick.
  Future<List<SessionInfo>> discover({
    Duration timeout = const Duration(seconds: 1),
  });

  /// Hands everything that arrived since the last call to [listener], and
  /// returns.
  ///
  /// Called once per fixed tick by `NetworkSystem`, before any game system
  /// runs - the same placement `pumpCommands` has, and for the same reason:
  /// what a message does is write component data, and every system on this
  /// tick should see it.
  void poll(NetListener listener);

  /// Puts everything queued by [NetConnection.send] on the wire.
  ///
  /// Called once per frame by `NetworkSystem`, after the fixed steps - so a
  /// frame that ran three simulation steps still sends one batch, and a
  /// message queued by the first step does not wait a frame for the third.
  void flush();

  /// Leaves any session and releases sockets. Idempotent.
  Future<void> close();
}

/// What a backend throws when it cannot do what was asked: no such session,
/// session full, version mismatch, no route to the host.
///
/// A single exception type with a [reason] rather than a class per failure:
/// the caller's realistic response to all of them is the same - show the
/// player what went wrong and let them try again - and the string is what
/// actually gets shown.
class NetException implements Exception {
  const NetException(this.reason, {this.transport});

  final String reason;

  /// Which backend raised it, if it was raised inside one.
  final String? transport;

  @override
  String toString() =>
      transport == null ? 'NetException: $reason' : '$transport: $reason';
}
