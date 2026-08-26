/// Which delivery guarantee a message is sent with.
///
/// There are two, and every channel a transport offers costs a receiver-side
/// reassembly structure that is paid for whether or not a game uses it:
///
///  * [reliable] - arrives, exactly once, in the order it was sent, however
///    many retransmissions that takes. For anything a game cannot resolve by
///    waiting for the next update: "player joined", "door opened", "you took
///    12 damage", chat, the initial world snapshot. Head-of-line blocking is
///    the price - one lost packet stalls everything queued behind it on this
///    channel until it is resent, so transforms must not use it.
///
///  * [unreliable] - sent once, may be dropped, and may arrive after a
///    message that was sent later. A late one is handed up like any other:
///    nothing here compares it against what has already been delivered, so a
///    handler that needs the newest value carries a tick or sequence number
///    in the message and drops what is behind the one it has. For state that
///    supersedes itself: position and rotation snapshots, input samples,
///    anything sent every tick where only the newest value matters. Losing
///    one costs a tick of smoothness; waiting for its retransmission would
///    cost far more than that.
///
/// The split matches ENet, Steam Sockets and QUIC's stream/datagram divide -
/// it is the standard shape, and the backends here implement it directly on
/// UDP instead of emulating it over a TCP-shaped stream.
enum NetChannel {
  /// Reliable and ordered. See the enum doc.
  reliable,

  /// Unreliable and unordered. See the enum doc.
  unreliable;

  /// How many channels there are, for sizing per-channel arrays without
  /// walking `values` on a hot path.
  static const int count = 2;
}
