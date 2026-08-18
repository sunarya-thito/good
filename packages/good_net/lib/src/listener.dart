import 'dart:typed_data';

import 'channel.dart';
import 'connection.dart';
import 'peer.dart';

/// Everything a transport reports, delivered from inside
/// [NetTransport.poll] - never from an event-loop turn of its own.
///
/// # Why an object with methods, and not streams or callbacks
///
/// A `Stream` per event kind allocates a subscription per listener and an event
/// object per message, and delivers on whatever microtask turn the socket
/// happened to fire in - i.e. mid-tick, splitting one burst of traffic across
/// two simulation steps. A record of closures has the same per-call allocation
/// problem in a different wrapper (the no-allocation and no-closure rules).
///
/// One long-lived listener object with methods on it allocates once, at
/// boot, and every dispatch is a virtual call. The engine-facing layer
/// implements this on a `GameSystem`, so a game never writes one by hand.
///
/// Every method has an empty default body: a listener overrides the two it
/// cares about without writing four stubs.
abstract class NetListener {
  /// A peer entered the session - including peers that were already in it
  /// when *this* peer joined, reported once each on the first poll after
  /// joining, so a listener that only handles this callback still ends up
  /// with the full roster.
  ///
  /// A peer joining is not the same as a direct link existing to it: on the
  /// star topology described on [NetSession], a client learns about its
  /// fellow clients but has no [NetConnection] to them. Check
  /// [NetSession.connectionTo] before assuming one.
  void onPeerJoined(NetPeerId peer) {}

  /// A peer left, for [reason]. Its slot may be handed to someone else on
  /// any later poll, with a bumped [NetPeerId.generation]; anything holding
  /// per-peer state keyed by slot must clear it here.
  void onPeerLeft(NetPeerId peer, NetDisconnectReason reason) {}

  /// [length] bytes arrived from [from] on [channel], starting at [offset]
  /// of [bytes].
  ///
  /// **The buffer is the transport's own and is reused before the next
  /// poll.** Read what is needed inside this call; a listener that wants to
  /// keep the payload copies it into storage it owns. Handing out a view
  /// rather than a freshly allocated `Uint8List` per message is the whole
  /// point - a 60 Hz snapshot stream would otherwise allocate 60 lists per
  /// peer per second, on the tick path (the hot-path rules).
  void onMessage(
    NetPeerId from,
    NetChannel channel,
    Uint8List bytes,
    int offset,
    int length,
  ) {}

  /// The session this transport was in has ended - the host closed it, the
  /// host vanished, or this peer left. [NetTransport.session] is null from
  /// here on, and [onPeerLeft] is *not* also fired for each remaining peer:
  /// one event for one thing that happened.
  void onSessionClosed(NetDisconnectReason reason) {}
}
