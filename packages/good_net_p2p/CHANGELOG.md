## Unreleased

### Fixed

* **`simulatedLoss` applies to the handshake.** It was applied when sending a
  datagram, and the connect request, accept, reject and disconnect each called
  the socket directly — so a transport at `simulatedLoss: 1` still completed
  every join, and `handshakeTimeout` could not be made to elapse by the one
  knob that exists to break it. A handshake now survives losing half of itself,
  because the request is retried on an interval.

## 0.1.1

Documentation only. No code changes.

README links now resolve on pub.dev.

## 0.1.0

First published release. A serverless UDP backend for `good_net` — **working
on a LAN**:

* A real protocol: acks, retransmission, ordering, batching, fragmentation and
  keepalives.
* **Join codes that carry the host's address** — ten characters, read aloud,
  no broker and nothing to deploy.
* **LAN discovery** — a host announces once a second and `network.discover()`
  lists what is out there.
* Passes the `good_net` conformance suite over real sockets, including
  in-order delivery of 30 messages across a link dropping 30% of everything.

**This does not cross the internet yet.** A join code carries the address the
host sees, which is enough on one machine or one LAN and not enough through a
home router; that needs STUN and a rendezvous, and a relay for the symmetric-NAT
case where hole punching cannot work. Requires `dart:io` sockets, so no web.

## 0.0.1

* Package scaffolded. Never published.
