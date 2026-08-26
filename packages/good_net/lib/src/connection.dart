import 'dart:typed_data';

import 'channel.dart';
import 'peer.dart';

/// Why a connection ended - reported to [NetListener.onPeerLeft] for one peer
/// and [NetListener.onSessionClosed] for the whole session, and readable
/// afterwards on [NetConnection.disconnectReason].
///
/// A game shows different UI for "they quit" and "they dropped", and a
/// session decides differently too (a timeout may be worth holding the slot
/// open for a reconnect; a clean leave never is), so the transport reports
/// which it was and not a single "gone".
enum NetDisconnectReason {
  /// This side called [NetConnection.disconnect] or left the session.
  localClose,

  /// The remote peer closed cleanly and said so.
  remoteClose,

  /// No packet - not even a keepalive - arrived within the transport's
  /// timeout. The wire equivalent of "they pulled the cable"; a crashed
  /// process and a dead router look identical from here.
  timeout,

  /// The host ended the session, or the host itself went away, which ends
  /// the session for every peer in it.
  sessionClosed,

  /// The handshake never completed: unreachable, refused, full, or a
  /// protocol-version mismatch.
  connectFailed,
}

/// Where a connection is in its lifecycle.
enum NetConnectionState {
  /// Handshake in flight. Sending is legal - see [NetConnection.send] - but
  /// nothing leaves the machine until the peer accepts.
  connecting,

  /// Established. Messages flow.
  connected,

  /// Finished, for the reason in [NetConnection.disconnectReason]. A
  /// connection never returns to [connected] from here; a reconnect is a new
  /// connection with a new [NetPeerId] generation.
  disconnected,
}

/// A link to exactly one remote peer.
///
/// Obtained from a [NetSession] - never constructed. The session owns the
/// connection objects and reuses them across peers occupying the same slot,
/// so a stale reference reports [NetPeerId] mismatches instead of quietly
/// addressing whoever holds the slot now.
///
/// # Sending allocates nothing
///
/// [send] takes bytes plus an offset and a length, and not a `Uint8List`
/// sized to the message, so a caller can keep one scratch buffer for its
/// lifetime and write successive messages into it (the no-allocation rule). The
/// transport copies the bytes out before returning - it has to, since a
/// reliable message may be retransmitted long after the caller has reused
/// that scratch space - so the buffer is free the instant [send] returns.
///
/// # Receiving is not here
///
/// There is no `onMessage` on a connection, and no stream to listen to.
/// Inbound traffic arrives through [NetTransport.poll], once per tick, for
/// every peer at once. Two reasons: a per-connection `Stream` allocates a
/// subscription and an event object per message, and delivery scattered
/// across event-loop turns would land mid-tick, half in and half out of the
/// simulation step that is meant to consume it.
abstract class NetConnection {
  /// Who is on the other end. [NetPeerId.none] once the connection is
  /// finished and its slot has been recycled.
  NetPeerId get peer;

  /// Where this connection is in its lifecycle.
  NetConnectionState get state;

  /// Set exactly when [state] is [NetConnectionState.disconnected].
  NetDisconnectReason? get disconnectReason;

  /// Smoothed round-trip time in microseconds, or -1 before enough packets
  /// have crossed to measure one.
  ///
  /// Microseconds and not a `Duration`: a `Duration` is a heap object, and
  /// this is read every tick by anything doing lag compensation.
  int get roundTripMicros;

  /// Fraction of sent packets this side believes were lost, 0.0 to 1.0,
  /// smoothed over a few seconds.
  double get packetLoss;

  /// Queues [length] bytes from [bytes], starting at [offset], for delivery
  /// on [channel]. `length` defaults to "the rest of [bytes] after
  /// [offset]".
  ///
  /// Nothing is sent from inside this call - the transport batches whatever
  /// accumulated during the tick into as few datagrams as it can and flushes
  /// them from [NetTransport.poll]. Sending 1 message or 200 in one tick
  /// costs the same per message.
  ///
  /// Legal while [state] is [NetConnectionState.connecting]: messages queue and
  /// go out the moment the handshake completes, so a caller does not have to
  /// write its own "send once connected" queue. Illegal once disconnected - it
  /// asserts and drops (the assert-not-print rule), because a send that
  /// silently vanishes is how a game ends up waiting forever for a reply.
  void send(NetChannel channel, Uint8List bytes, [int offset = 0, int? length]);

  /// Closes this connection, telling the peer why if a packet can still get
  /// through. Idempotent.
  void disconnect();
}
