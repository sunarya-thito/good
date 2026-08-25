import 'dart:math';
import 'dart:typed_data';

import 'channel.dart';
import 'connection.dart';
import 'peer.dart';

/// The code that identifies a session - what one player reads out and the
/// others type in.
///
/// An extension type over `String`, so it costs nothing beyond the string
/// itself while still refusing to be passed where a player name is expected.
///
/// # Six characters, drawn from a 31-symbol alphabet
///
/// This is the thing a human retypes. PeerJS hands out 36-character UUIDs
/// because a browser pastes them through a link; a game hands them out at a
/// couch or over voice chat. [SessionId.random] therefore produces six
/// characters from a 31-symbol alphabet with `0`/`O` and `1`/`I`/`L` removed
/// - about 30 bits, which is ample against accidental collision among
/// concurrently live sessions and is **not** a security boundary. A session
/// id is a capability to attempt a join and nothing more: anything that must
/// not be guessed needs its own check on top.
extension type const SessionId(String value) implements String {
  /// Chosen so a code read aloud or copied off a screen survives the trip:
  /// no `0`/`O`, no `1`/`I`/`L`.
  static const String alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

  static const int defaultLength = 6;

  /// A fresh random code. Pass [random] to make a test deterministic; the
  /// default draws from [Random.secure], so two hosts starting in the same
  /// millisecond do not produce the same code.
  factory SessionId.random({Random? random, int length = defaultLength}) {
    final rng = random ?? Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(alphabet[rng.nextInt(alphabet.length)]);
    }
    return SessionId(buffer.toString());
  }

  /// Whether this could be a code [SessionId.random] produced - the shape
  /// check a join screen runs before spending a network round trip on a typo.
  bool get isWellFormed {
    if (value.isEmpty) return false;
    for (var i = 0; i < value.length; i++) {
      if (!alphabet.contains(value[i])) return false;
    }
    return true;
  }
}

/// What a host asks for when it opens a session.
class SessionOptions {
  const SessionOptions({
    this.name = '',
    this.maxPeers = 8,
    this.advertise = true,
    this.id,
  }) : assert(maxPeers >= 2, 'a session with room for one is not a session'),
       assert(maxPeers <= 0xFFFF, 'peer slots are a 16-bit field in NetPeerId');

  /// Shown in discovery listings. Free-form; not an identifier.
  final String name;

  /// Total participants **including the host**, so `maxPeers: 4` is the host
  /// plus three others. This fixes the width of every per-peer array a
  /// backend allocates when the session opens, so it cannot be changed once
  /// the session is up.
  final int maxPeers;

  /// Whether the session answers discovery queries. A private match whose
  /// code is shared out of band sets this false and is then reachable only
  /// through [NetTransport.join].
  final bool advertise;

  /// A specific code to open under instead of a fresh random one - for tests,
  /// and for a game that mints its own. Opening fails if the backend finds
  /// the code already taken.
  final SessionId? id;
}

/// One session as seen from outside it: what discovery returns and a join
/// screen lists.
///
/// A plain value object allocated only on the discovery path - a menu, not a
/// tick - so it holds strings and is immutable, never pooled. It carries
/// no address: how a code resolves to a machine is the backend's business,
/// and a LAN address in this class would mean nothing to a backend that
/// resolves through a rendezvous instead.
class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.name,
    required this.peerCount,
    required this.maxPeers,
  });

  final SessionId id;
  final String name;

  /// Participants currently in it, host included.
  final int peerCount;

  final int maxPeers;

  bool get isFull => peerCount >= maxPeers;

  @override
  String toString() => 'SessionInfo($id, "$name", $peerCount/$maxPeers)';
}

/// A session this peer is currently in.
///
/// # Topology: a star, with the host at the centre
///
/// Clients connect to the host and to nobody else. That is not a limitation
/// of the backends - it is the shape almost every shipped game netcode uses
/// (Mirror, Unity Netcode, Photon), for two reasons that both apply here:
///
///  * **Authority.** Something has to decide who actually got hit. With a
///    host that sees every input, that decision has one place to live. In a
///    mesh either every peer simulates everything and they disagree, or you
///    invent an election to pick the one that does - which is a host again,
///    with extra steps.
///  * **Traversal.** NAT hole punching succeeds per *pair*. A star needs
///    `n - 1` successful punches; a mesh needs `n * (n - 1) / 2`, so a
///    five-player mesh has ten chances to hit the symmetric-NAT case instead
///    of four.
///
/// So on a client, "who is in this session" and "who can I reach" are
/// different questions: it *knows about* every peer, because the host tells
/// it who is there, and it can *reach* only the host. [connectionTo] returns
/// null for the rest, and traffic between two clients is the host's game code
/// choosing to forward something. Forwarding is a line you write: a transport
/// that relayed on its own would double the host's bandwidth bill without ever
/// saying so.
abstract class NetSession {
  /// The join code. Stable for the life of the session.
  SessionId get id;

  /// What the host called it, from [SessionOptions.name].
  String get name;

  int get maxPeers;

  /// This peer's own id - [NetPeerId.host] when hosting, a slot the host
  /// assigned when not.
  NetPeerId get localPeer;

  bool get isHost => localPeer.isHost;

  /// Everyone else in the session: the connected clients on the host, and the
  /// host plus the other clients on a client. Excludes [localPeer].
  int get peerCount;

  /// The peer at [index] of the roster, `0 <= index < peerCount`.
  ///
  /// Indexed access, not a `List<NetPeerId>` getter, so that walking the
  /// roster every tick allocates neither a list nor an iterator (the no-closure
  /// rule). Roster order is unspecified and shifts as peers come and go; index
  /// into it within one tick only.
  NetPeerId peerAt(int index);

  /// The direct link to [peer], or null when there is none - always null
  /// between two clients, see the class doc.
  NetConnection? connectionTo(NetPeerId peer);

  /// Whether [peer] is currently on this session's roster.
  bool hasPeer(NetPeerId peer);

  /// Sends to every peer this one has a direct link to: every client if this
  /// is the host, the host alone if it is not.
  ///
  /// The bytes are copied once per connection, so this costs exactly what the
  /// same number of [NetConnection.send] calls would - it exists to spare the
  /// caller the roster walk, not to save copies.
  void sendToAll(
    NetChannel channel,
    Uint8List bytes, [
    int offset = 0,
    int? length,
  ]);

  /// False once this session has ended, whichever side ended it.
  bool get isOpen;

  /// Leaves (as a client) or closes it for everyone (as the host).
  ///
  /// The future completes once the goodbye is actually on the wire, so a game
  /// can await this before tearing its process down and have peers see a
  /// clean [NetDisconnectReason.remoteClose] instead of waiting out a
  /// timeout.
  Future<void> leave();
}
