# goo_net_p2p

The serverless backend for [`goo_net`](../goo_net): peer-to-peer UDP with
nothing in the middle. Add the dependency, declare it, and a game is
networked.

```dart
descriptor.transport(P2PNetTransport());
```

Hosting binds a UDP socket and hands back a **ten-character code that is the
host's address**. Joining decodes it and starts talking. There is no broker,
no relay, no account, nothing to deploy and nothing that can go down.

```dart
final session = await network.host(SessionOptions(name: 'Kitchen table'));
print(session.id);          // 4KM2QX9P7T - read this out to a friend

await network.join(SessionId('4KM2QX9P7T'));
```

On a LAN nobody types anything: a host announces itself once a second, and
`network.discover()` lists what is out there.

## How far a code reaches

Stated plainly, because "P2P" is often left to imply more than it delivers:

| Where | Works | Why |
|---|---|---|
| One machine | **Yes** | Nothing in the way |
| One LAN | **Yes** | The code carries a LAN address, and discovery means nobody has to type it |
| Across the internet | **Not yet** | A home router hands out a private address and drops unsolicited inbound packets |

Crossing a router needs a peer's *public* address (STUN) and a moment of
coordination so both sides punch at once (a rendezvous). That is the next
landing. And the limit past it, worth signing off on before it is built: pure
hole punching fails when **both** peers are behind symmetric NAT, so "free, no
server" and "always connects" are not the same claim. A TURN-style relay
fallback is a separate, clearly-scoped addition.

## The protocol

A lightweight UDP protocol implementing `goo_net`'s two channels directly,
rather than emulating them over a TCP-shaped stream — and rather than pulling
a DTLS and SCTP stack into a native game by binding WebRTC.

| Mechanism | How |
|---|---|
| Acknowledgement | Every packet carries `seq`, `ack` and 32 `ackBits`, so one packet acknowledges 33 — losing an ack costs nothing |
| Reliability | A reliable message is kept until a packet carrying it is acknowledged, then resent on a timer derived from the measured round trip |
| Ordering | Reliable messages carry an id; the receiver delivers in order and buffers what arrives early |
| Batching | A tick's worth of messages become one datagram, up to 1200 bytes |
| Fragmentation | Anything larger is split and reassembled on the far side |
| Liveness | A keepalive every 100 ms; a link silent for `linkTimeout` (5 s) is declared gone |

Not here, and named rather than approximated: **congestion control**. A link
sends what the game asks it to and reports `packetLoss` so the game can decide
to send less.

## Testing netcode that has only ever seen loopback

`simulatedLoss` throws away a fraction of outgoing datagrams. It is a field on
the shipped class rather than a test helper on purpose: netcode that has only
run over loopback has never had a packet lost, so every retransmission path in
it is untested code that first runs on a player's hotel wifi.

```dart
final transport = P2PNetTransport(simulatedLoss: 0.3);
transport.simulatedLoss = 1;   // settable: the link that was fine, and then was not
```

At 30% loss the reliable channel still delivers everything in order — this
package's tests assert exactly that, alongside `goo_net`'s conformance suite
run over real sockets.
