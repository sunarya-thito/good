/// Serverless P2P backend implementing goo_net's NetTransport/NetPeer/
/// NetConnection contract: ICE-lite-style UDP hole punching against free
/// public STUN servers, a default goo-hosted free rendezvous relay for
/// discovery/signaling (nothing for the game developer to host), and a
/// custom lightweight reliable-ordered/unreliable-unordered UDP data
/// channel (dart:io sockets, no native binding needed).
///
/// Known limitation, by design for the MVP: pure hole punching does not
/// connect 100% of real-world NAT pairs (symmetric NAT on both ends is the
/// known failure case) - a paid TURN-style relay fallback is an explicit,
/// separate future add-on, not implied by "free, no server to run".
///
/// Placeholder - lands in Phase 3 of the project root plan.
library;
