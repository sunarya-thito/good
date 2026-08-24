## Unreleased

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
