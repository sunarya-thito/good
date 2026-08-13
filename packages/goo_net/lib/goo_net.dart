/// Transport-agnostic networking: `NetTransport`, `NetPeer`, `NetConnection`
/// (reliable-ordered + unreliable-unordered channels), `NetSession`/`Lobby`.
///
/// Placeholder - real interfaces land in Phase 3 of the project root plan.
/// Two backends will implement this package's contract:
/// `goo_net_steam` (Steamworks) and `goo_net_p2p` (serverless UDP
/// hole-punching), so game code never branches on which one is active.
library;
