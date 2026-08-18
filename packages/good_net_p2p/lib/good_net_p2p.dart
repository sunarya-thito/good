/// Peer-to-peer networking for `good_net`, with no server to run.
///
/// One line of declaration and a game is networked:
///
/// ```dart
/// class MyState extends GameState<MyGame> with MultiplayerState<MyGame> {
///   @override
///   void describeNetwork(NetDescriptor descriptor) {
///     descriptor.transport(P2PNetTransport());
///     ...
///   }
/// }
/// ```
///
/// Hosting hands back a ten-character code that *is* the host's address, so
/// joining needs nothing in between - no broker, no relay, no account, no
/// deployment. On a LAN, `network.discover()` lists the sessions announcing
/// themselves and nobody types anything at all.
///
/// What this does **not** yet do is cross the internet: a home router hands
/// out a private address and drops unsolicited inbound packets, so getting
/// through one needs a peer's public address (STUN) and a moment of
/// coordination to punch a hole through it (a rendezvous). That is the next
/// landing, and it is called out here rather than left for a player to
/// discover.
library;

export 'src/code.dart' show EndpointCode;
export 'src/transport.dart' show P2PNetTransport;
