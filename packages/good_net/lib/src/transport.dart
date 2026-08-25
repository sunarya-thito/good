import 'package:meta/meta.dart';

import 'channel.dart';
import 'listener.dart';
import 'session.dart';

/// A networking backend: the thing that moves bytes between machines.
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
///  * **A message too big to carry is refused, not truncated or dropped.**
///    See [maxMessageBytes].
abstract class NetTransport {
  /// Identifies the backend in diagnostics - `'loopback'`, `'p2p'`.
  String get name;

  /// The most bytes one [NetConnection.send] on [channel] can carry, so the
  /// limit reaches a game from the backend, not from a player.
  ///
  /// # Where the bound comes from
  ///
  /// A message field declared with `hasString()` or `hasBytes()` has no
  /// capacity of its own: the size of a record is decided by the value
  /// written into it, at run time. So the only bound left is the carrier's,
  /// and the record layer cannot know what the carrier is. This is where it
  /// says so, and `NetworkSystem` carries the number back to the write that
  /// would exceed it.
  ///
  /// It is stated **per channel** because the two channels are bounded by
  /// different things:
  ///
  ///  * [NetChannel.reliable] may be split across datagrams and put back
  ///    together, so its ceiling is however many pieces the backend's
  ///    reassembly can track - 255 of them for `good_net_p2p`, which is
  ///    roughly 300 KB.
  ///  * [NetChannel.unreliable] is **one datagram** wide, and cannot be more
  ///    than one. Splitting an unreliable message means losing it whenever any
  ///    one of its pieces is lost, so an N-piece message multiplies the link's
  ///    loss rate by N while the channel's own contract - "losing one costs a
  ///    tick of smoothness" - quietly stops holding. There is also nothing to
  ///    gain by it: this channel carries state that supersedes itself, so a
  ///    value that does not fit today does not fit on the next tick either,
  ///    and the failure repeats and is never absorbed. A game with more state
  ///    than that sends it reliably, or splits it into messages that each
  ///    stand alone and each supersede on their own.
  ///
  /// A tick's worth of messages is **not** bounded by this. `NetworkSystem`
  /// packs a frame's records into one batch and cuts that batch at record
  /// boundaries, so what this bounds is one record - see
  /// `ParamBatch.maxRecordBytes`.
  ///
  /// An in-process backend has no wire and therefore no bound of its own. It
  /// states one anyway, at or below what a datagram backend manages, because
  /// a backend that silently accepts what another refuses is a backend that
  /// hides bugs - and loopback is what a game is developed against.
  int maxMessageBytes(NetChannel channel);

  /// What a backend's [NetConnection.send] throws when it is handed more than
  /// [maxMessageBytes] allows.
  ///
  /// Shared by every backend, so the refusal reads the same whichever one a
  /// game is running against - the same reason loopback states a bound at all.
  /// It throws instead of asserting and dropping, matching
  /// `CommandTransport.send`: a send over the ceiling can never succeed,
  /// however long it is left, so it is a different failure from a link that is
  /// momentarily busy, and the caller can do something about exactly one of
  /// them.
  static Never refuseOversized({
    required String transport,
    required NetChannel channel,
    required int length,
    required int limit,
  }) {
    final why = channel == NetChannel.unreliable
        ? ' The unreliable channel is one datagram wide on purpose: a message '
              'split across datagrams is lost whenever any one of them is, so '
              'its loss rate is that of the link multiplied by the number of '
              'pieces. Send it on the reliable channel if it has to arrive, '
              'or split it into messages that each stand alone.'
        : '';
    throw StateError(
      'this send is $length bytes and the $transport backend carries at most '
      '$limit on the ${channel.name} channel, so it will never arrive however '
      'long it is left.$why Send a shorter value, or split it in the game, '
      'where the meaning of the split is known.',
    );
  }

  /// A hash of the sending side's message declarations, checked during the
  /// handshake and refused on mismatch.
  ///
  /// # A message is identified by position
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
  /// with a version error, never a session where damage arrives as chat.
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
  /// A code is the only thing you need: [discover] hands back codes, and how
  /// one resolves to a machine - a cached LAN address, a rendezvous lookup -
  /// is the backend's own business (the no-specialised-variant rule, one way
  /// to do a thing).
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
/// One type carrying a [reason], covering every failure. Your realistic
/// response to any of them is the same - show the player what went wrong and
/// let them try again - and [reason] is the string you show.
class NetException implements Exception {
  const NetException(this.reason, {this.transport});

  final String reason;

  /// Which backend raised it, if it was raised inside one.
  final String? transport;

  @override
  String toString() =>
      transport == null ? 'NetException: $reason' : '$transport: $reason';
}
