/// The bytes on the wire: what a packet looks like, and why it looks like
/// that.
///
/// # A packet
///
/// ```text
///   0    1    2    3    4      6      8         12   13
///  +----+----+----+----+------+------+---------+----+ ...
///  | 'g'| 'n'| ver|type| seq  | ack  | ackBits | ok | frames
///  +----+----+----+----+------+------+---------+----+ ...
/// ```
///
/// The four-byte prologue is on **every** packet, handshake included. UDP has
/// no connection to filter on, so a socket bound for a game hears every
/// stray, misdirected and scanned datagram on that port; the magic and the
/// version are what let it discard them in four comparisons instead of
/// mis-parsing them as a join request.
///
/// `seq`/`ack`/`ackBits` ride only on [PacketType.payload], and they are the
/// whole reliability mechanism:
///
///  * `seq` numbers this packet, per connection, wrapping at 16 bits.
///  * `ack` is the highest `seq` heard from the other side.
///  * `ackBits` is the 32 before it, one bit each. So one packet acknowledges
///    33 - losing an ack costs nothing as long as another arrives within 32
///    packets, which is what makes acknowledgement itself unreliable and
///    therefore free.
///
/// This is the scheme Glenn Fiedler's articles describe and ENet, QUIC and
/// Steam Sockets all wear variations of. It is not novel and should not be:
/// the failure modes are known, which is the point of picking it.
///
/// # A frame
///
/// One packet carries as many frames as fit, which is what makes a tick's
/// worth of messages one datagram instead of forty:
///
/// ```text
///  +-------+------------+------------------------+--------+---------+
///  | flags | messageId? | groupId,index,count?    | length | payload |
///  +-------+------------+------------------------+--------+---------+
/// ```
///
///  * `flags` bits 0-1 are the [FrameKind]; bit 2 says the frame is one
///    fragment of a larger message.
///  * `messageId` is present on reliable and system frames, and is what the
///    receiver orders and de-duplicates by.
///  * The fragment triple is present when bit 2 is set.
///  * `length` is the payload's, in bytes.
library;

/// `g`, `n` - and then a version, so that a future format change is a refused
/// connection rather than a garbled one.
const int magic0 = 0x67;
const int magic1 = 0x6E;
const int protocolVersion = 1;

/// Bytes before any packet's own body.
const int prologueBytes = 4;

/// Bytes of `seq`/`ack`/`ackBits`/`ackValid` on a payload packet, after the
/// prologue.
///
/// The last byte is a flag, and it is there because zero is a real sequence
/// number: without it, a peer that has received nothing still writes `ack: 0`
/// and retires the other side's very first reliable message unsent.
const int payloadHeaderBytes = 9;

/// What a datagram is for.
///
/// Deliberately few. Everything that happens *during* a session is a frame
/// inside [payload] rather than a packet type of its own, because a frame
/// inherits the sequencing, acknowledgement and batching that the payload
/// packet already has - a roster update that needed its own retransmission
/// logic would be a second reliability implementation to keep correct
/// (the one-fact-one-place rule).
abstract final class PacketType {
  /// A client asking who is hosting, sent to the broadcast address.
  static const int discover = 0;

  /// A host answering [discover], or announcing itself unprompted.
  static const int beacon = 1;

  /// A client asking to join: schema hash, and the code it thinks it is
  /// joining.
  static const int connectRequest = 2;

  /// The host saying yes: the slot it assigned, the session, and the roster.
  static const int connectAccept = 3;

  /// The host saying no, with a reason a player can read.
  static const int connectReject = 4;

  /// Everything else, once a session exists.
  static const int payload = 5;

  /// A clean goodbye, from either side.
  static const int disconnect = 6;
}

/// What a frame inside a payload packet is.
abstract final class FrameKind {
  /// A game message on [NetChannel.reliable].
  static const int reliable = 0;

  /// A game message on [NetChannel.unreliable].
  static const int unreliable = 1;

  /// The transport's own traffic - roster updates. Always reliable, and
  /// never handed to the game.
  static const int system = 2;

  static const int mask = 0x3;

  /// Bit 2: this frame is one fragment of a message too big for a datagram.
  static const int fragmented = 0x4;
}

/// What a [PacketType.connectReject] carries, so that a joiner can say
/// something true to the player rather than "connection failed".
abstract final class RejectReason {
  static const int sessionFull = 0;
  static const int schemaMismatch = 1;
  static const int wrongSession = 2;
  static const int notHosting = 3;

  static String describe(int reason) {
    switch (reason) {
      case sessionFull:
        return 'the session is full';
      case schemaMismatch:
        return 'the host is running a different build of this game';
      case wrongSession:
        return 'that code is not the session this host has open';
      case notHosting:
        return 'nobody is hosting at that address any more';
      default:
        return 'the host refused the connection (reason $reason)';
    }
  }
}

/// The transport's own frames, inside [FrameKind.system].
abstract final class SystemMessage {
  /// A peer joined: slot, generation.
  static const int peerJoined = 0;

  /// A peer left: slot, generation, [NetDisconnectReason] index.
  static const int peerLeft = 1;
}

/// The most payload bytes to put in one datagram.
///
/// 1200 rather than the 1500 an Ethernet frame holds: every tunnel, VPN and
/// PPPoE link on the way subtracts its own header from that, and a datagram
/// that ends up one byte over is not shortened, it is **dropped** - silently,
/// intermittently, and only for the players behind that one link. 1200 is the
/// figure QUIC settled on for the same reason, and the cost of being
/// conservative is one extra packet per 1200 bytes.
const int maxDatagramPayload = 1200;

/// Sequence numbers wrap, so "newer" cannot be `>`.
///
/// Half the space is treated as ahead and half as behind, which is right as
/// long as the two ends are never more than 32768 packets apart - at any
/// plausible rate, that is minutes of one-way silence, by which time the
/// connection has timed out anyway.
bool sequenceGreaterThan(int a, int b) {
  const int half = 0x8000;
  return ((a > b) && (a - b <= half)) || ((a < b) && (b - a > half));
}
