# goo_net_p2p

Serverless P2P backend for [`goo_net`](../goo_net) - "plug and play, nothing
to host, free": ICE-lite-style UDP hole punching against free public STUN
servers, a default goo-hosted free rendezvous relay for discovery/signaling
(the game developer runs nothing), and a custom lightweight
reliable/unreliable UDP data channel (plain `dart:io` sockets, no native
WebRTC dependency).

**Known trade-off:** pure hole punching does not connect 100% of real-world
NAT pairs (symmetric NAT on both ends is the known failure case). This is
scoped to hole-punching only for the MVP; a paid relay fallback is a
separate, explicitly-called-out future add-on - see the project root plan,
Phase 3.

Status: **placeholder.** Nothing here is implemented yet.
