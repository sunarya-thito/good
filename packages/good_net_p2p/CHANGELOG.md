## Unreleased

### Fixed

* **A datagram the socket refused is now kept and sent, not thrown away.**
  `RawDatagramSocket.send` returns `0` to say the send would have blocked and
  should be tried again; it is not a short write, and there is no partial
  datagram. The transport ignored that return value, so a refused packet was
  discarded inside `P2PNetTransport` — indistinguishable, from anywhere else,
  from the wire losing it. It now goes to a queue of at most
  `P2PNetTransport.maxHeldDatagrams` and leaves on the next drain, ahead of
  anything sent after it (#177).

  What to change: nothing. This only turns packets that used to vanish into
  packets that arrive, a fraction of a millisecond later.

  **Why it was invisible.** Reliable traffic covered it completely — a
  retransmission replaces a packet the socket refused just as well as one a
  router dropped. Everything landed on the two things sent exactly once: an
  unreliable message, and the goodbye a leaving peer says. Measured on Windows
  loopback, three of three hundred payload sends on an idle link came back `0`,
  which showed up as one p2p test failing about one run in a hundred and
  passing on the rerun. A lost goodbye costs the peer a whole `linkTimeout`,
  and the slot, before it notices.

  `close()` now also gives a refused goodbye a short bounded wait — at most
  20ms, and only when something is actually held — rather than closing the
  socket over the top of it.

### Added

* **`P2PNetTransport.simulatedBackpressure`**, the other half of
  `simulatedLoss`: the fraction of sends the socket is told to refuse. Loss is
  the wire eating a datagram that did leave; backpressure is the socket
  declining to take one, which means it never left and the transport still has
  it. A real refusal is too rare to hit on a desk and too common to ignore, so
  the branch handling it was untested code — this is what tests it (#177).

* **`P2PNetTransport.maxHeldDatagrams`**, how many refused datagrams are held
  before the oldest is given up on. Public so the bound can be asserted against
  rather than copied into a test as a number (#177).

### Breaking

* **One unreliable message may be one datagram, and no more.** 1,178 bytes,
  which is `P2PNetTransport.maxMessageBytes(NetChannel.unreliable)`. An
  unreliable message over that used to be cut into fragments and put back
  together at the far end; it is now refused with a `StateError` naming the
  size, the bound and the fix. The reliable ceiling is unchanged at 255
  fragments — 300,390 bytes — and is now stated by the same method rather than
  only enforced (#158).

  What to change: nothing, unless a single unreliable message of yours carries
  more than 1,178 bytes. A tick's worth of unreliable messages is unaffected
  however many there are — `good_net`'s `NetworkSystem` cuts a long batch at
  record boundaries. If one message really is that big, declare it
  `NetChannel.reliable` or split it into messages that each stand alone.

  Peers do not have to be upgraded together. The schema hash is untouched, an
  upgraded peer never sends a fragmented unreliable message, and it still
  reassembles one sent by a peer that has not upgraded.

  **Why.** A message split into N pieces with no retransmission behind it is
  lost whenever any one of the N is, so its loss rate is the link's multiplied
  by N — see `good_net`'s notes for the whole argument.

## 0.3.0

### Breaking

* **Messages need an `id`, from `good_net` 0.3.0.** Nothing in this package's
  own API changed, but every `descriptor.has` call in a game using it now takes
  a required `id` — see `good_net`'s 0.3.0 notes for what to write and why.

  The handshake hash changed with it, so 0.3.0 peers do not accept 0.2.x peers.
  Update every peer together.

## 0.2.0

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
