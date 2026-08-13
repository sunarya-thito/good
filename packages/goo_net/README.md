# goo_net

Transport-agnostic networking interfaces: `NetTransport`, `NetPeer`,
`NetConnection` (reliable-ordered + unreliable-unordered channels), and
`NetSession`/`Lobby`. Dimension-agnostic - not under `goo2d` because a future
`goo3d` game needs the same lobby/P2P plumbing.

Two backends implement this contract so game code never branches on which is
active: [`goo_net_steam`](../goo_net_steam) (Steamworks lobbies + relay P2P)
and [`goo_net_p2p`](../goo_net_p2p) (serverless UDP hole-punching, no server
to run).

Status: **placeholder.** This is Phase 3 of the project root plan; nothing
here is implemented yet.
