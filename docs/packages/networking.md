# Networking

!!! abstract "Layer: kernel-side (`good_net`) — dimension-agnostic"
    A 3D game needs the same session and messaging plumbing a 2D one does, so
    networking sits beside the kernel rather than under a renderer.

**Networking is the command API, over a socket.** A network message and a
`GameCommand` are the same idea twice — a typed record, declared once,
identified on the wire by its position in that declaration, handed to a handler
registered where it runs. So they are not two implementations: `NetMessage` and
`NetSignal` are spelled exactly like `SinkCommand` and `SignalCommand`, and the
record layer underneath is the kernel's own, reused rather than reimplemented.

```dart
class MyState extends GameState2D<MyGame> with MultiplayerState<MyGame> {
  late final Fire fire;

  @override
  void describeNetwork(NetDescriptor descriptor) {
    descriptor.transport(LoopbackNetTransport());
    fire = descriptor.has(Fire(), channel: NetChannel.unreliable);
    descriptor.hasHandler(fire, _onFire);
  }

  void _onFire(({double angle}) params, NetPeerId from) {
    spawnBullet(from, params.angle);
  }
}
```

Send it by calling it:

```dart
fire((angle: 1.2));
```

## What networking adds over commands

Two facts an isolate boundary does not have, and **both are declared rather than
passed at the send site** — so a message's whole contract is readable in one
place, and it cannot be sent reliably in one file and unreliably in another.

### `NetTarget` — which machine handles it

| Target | Handled by | Sent by | For |
|---|---|---|---|
| `host` | The host | Anyone | A client's *intent*: "I pressed fire", "I want to buy this" |
| `clients` | Every client | Host only | The host's *decisions*: "you died", "the door opened" |
| `everyone` | Every client **and** the host | Host only | A decision the host must react to through the same path |

`NetTarget.host` is the workhorse of an authoritative game, and it has one
property worth spelling out: **calling one on the host runs it locally** rather
than failing. That is what makes single-player, host and client one code
path — the firing code says `fire((angle: a))` and does not care which machine
it is on.

`clients` deliberately does *not* run on the host: the host already knows, it is
the one that decided. Use `everyone` when the host must react through the same
code path, so host and client visibly agree rather than agreeing by two
implementations that drift.

### `NetChannel` — how hard to try

```dart
descriptor.has(PlayerMoved(), channel: NetChannel.unreliable);
descriptor.has(RoundEnded(), channel: NetChannel.reliable);
```

| Channel | Guarantee | For |
|---|---|---|
| `reliable` | Arrives exactly once, in order, however many retransmissions it takes | Anything a game cannot resolve by waiting: "player joined", "you took 12 damage", chat, the initial snapshot |
| `unreliable` | Sent once, may be dropped or reordered; an *older* one arriving after a newer one is **discarded** | State that supersedes itself: transforms, input samples — anything sent every tick where only the newest value matters |

!!! danger "Do not send transforms reliably"
    Head-of-line blocking is reliable delivery's price: one lost packet stalls
    everything queued behind it until it is resent. For a position snapshot that
    means waiting for data which was already obsolete when it was lost. Losing
    an unreliable packet costs a tick of smoothness; waiting for its
    retransmission costs far more.

Two channels rather than a per-message tunable policy, because these are the two
that game netcode actually needs and every extra one costs a receiver-side
reassembly structure that must be paid for whether or not a game uses it. It is
the same split ENet, Steam Sockets and QUIC's stream/datagram divide use.

## Declaring messages

```dart
class Fire extends NetMessage<({double angle})> {
  late final ParamPointer<double> angle;

  @override
  void describeParams(ParamDescriptor descriptor) {
    angle = descriptor.hasFloat32();
  }

  @override
  void bufferFromParams(ParamBuffer message, ({double angle}) params) {
    angle[message] = params.angle;
  }

  @override
  ({double angle}) paramsFromBuffer(ParamBuffer message) {
    return (angle: angle[message]);
  }
}
```

Identical in shape and vocabulary to a `GameCommand` — same `ParamDescriptor`,
same packing rules, same "keep the handle in a `late final` field", and the same
answer for **more than one parameter**: `P` is a single type, so several values
travel as a **Dart record**.

```dart
typedef Shot = ({double angle, double power, bool charged});

class Fire extends NetMessage<Shot> { /* ... */ }

fire((angle: 1.2, power: 0.8, charged: true));
```

Worth a `typedef`: the record type appears in three signatures here, so naming
it once means a new field is one edit rather than three. See
[commands](../guide/flutter-bridge.md#more-than-one-parameter-use-a-record) for
the full walk-through — it is the same mechanism.

`NetSignal` is the no-parameter shape:

```dart
class RoundEnded extends NetSignal { }

// declared
roundEnded = descriptor.has(RoundEnded(), to: NetTarget.everyone);
descriptor.hasSignal(roundEnded, _onRoundEnded);

// sent
roundEnded();
```

### Sending to one peer

```dart
fire.sendTo(peerId, (angle: 1.2));
```

### Nobody to send to is not an error

A send with no session, or with nobody on the other end, returns without doing
anything. A game that fires a shot while waiting for a second player has not
made a mistake, and neither has a host with no clients yet.

## Sessions

Mix `MultiplayerState` into your `GameState` and you get `network`:

```dart
final session = await network.host(SessionOptions(name: 'My Game', maxPeers: 4));
print(session.id);                       // the join code

await network.join(SessionId('ABCD12'));
await network.leave();
```

`NetSession` is the roster:

| Member | What it gives |
|---|---|
| `id` | The join code, stable for the session's life |
| `localPeer` | This peer's own id — `NetPeerId.host` when hosting |
| `isHost` | Whether this machine is the host |
| `peerCount` / `peerAt(i)` | The roster, by index |
| `hasPeer(id)` | Whether a peer is still on the roster |
| `connectionTo(id)` | The direct link, or null — always null between two clients |
| `sendToAll(...)` | Every peer with a direct link |

!!! info "Indexed roster access, not a list"
    `peerAt(index)` rather than a `List<NetPeerId>` getter, so walking the
    roster every tick allocates neither a list nor an iterator. Roster order is
    unspecified and shifts as peers come and go — index into it within one tick
    only.

### Events

```dart
class Lobby extends GameSystem with NetPeerListener, NetSessionListener {
  @override
  void onPeerJoined(NetPeerId peer) { }
  @override
  void onPeerLeft(NetPeerId peer, NetDisconnectReason reason) { }
  @override
  void onSessionOpened(NetSession session) { }
  @override
  void onSessionClosed(NetDisconnectReason reason) { }
}
```

Teardown events dispatch in reverse, matching every other teardown event in the
engine: a listener told late can still read what the earlier ones were warned
about.

## Version safety

A message's identity on the wire is **its position in `describeNetwork`'s
declaration order** — two bytes at the head of the record. Both peers agree on
it because both ran the same declaration pass, which holds only while both are
running the same build.

`NetTransport.schemaHash` is what enforces that: the registry is sealed and
hashed at boot, the hash is bound to the transport, and a peer running a
different build is refused at join rather than silently misrouting messages into
the wrong handlers.

## Backends

`NetTransport` is the contract a backend implements. Exactly one is declared per
game:

```dart
descriptor.transport(LoopbackNetTransport());
```

A game that wants a loopback backend in tests and a real one in a build passes a
different instance here — **nothing else in the game changes**, because messages
are declared against the game rather than against a backend.

### Loopback — in `good_net` itself

`LoopbackNetTransport` is in-process and **real**, not a mock. It is what tests
and split-screen run on, and it is why a multiplayer game can be developed
without a second machine.

`package:good_net/testing.dart` ships a conformance suite that every backend is
tested against, so "implements `NetTransport`" means the same thing for all of
them.

### good_net_p2p — the serverless backend { #p2p }

The "nothing to host, no bill" path, for a game that reaches another machine.

```dart
descriptor.transport(P2PNetTransport());
```

Hosting binds a UDP socket and hands back a **ten-character code that is the
host's address**. Joining decodes it and starts talking. There is no broker, no
relay, no account, nothing to deploy and nothing that can go down.

```dart
final session = await network.host(SessionOptions(name: 'Kitchen table'));
print(session.id);          // e.g. 4KM2QX9P7T — read this out to a friend

await network.join(SessionId('4KM2QX9P7T'));
```

On a LAN nobody has to type anything at all: a host announces itself once a
second, and `network.discover()` lists what is out there.

```dart
for (final found in await network.discover()) {
  print('${found.name} — ${found.peerCount}/${found.maxPeers}');
  await network.join(found.id);
}
```

!!! warning "How far a code reaches"
    A code carries the address it was minted from, so it reaches exactly as far
    as that address does. **Same machine and same LAN work today, with no
    setup. Across the internet does not yet.** A home router hands out a private
    address and drops unsolicited inbound packets, so crossing one needs a
    peer's *public* address (STUN) and a moment of coordination to punch a hole
    through it (a rendezvous) — a separate landing, called out here rather than
    left for a player to discover.

#### The protocol

A lightweight UDP protocol implementing both channels directly, rather than
emulating them over a TCP-shaped stream:

| Mechanism | How |
|---|---|
| Acknowledgement | Each packet carries `seq`, `ack` and 32 `ackBits`, so one packet acknowledges 33 — losing an ack costs nothing |
| Reliability | A reliable message is kept until a packet carrying it is acknowledged, then resent on a timer derived from the measured round trip |
| Ordering | Reliable messages carry an id; the receiver delivers in order and buffers what arrives early |
| Batching | A tick's worth of messages become **one datagram**, up to 1200 bytes |
| Fragmentation | Anything larger is split, and reassembled on the far side |
| Liveness | A keepalive every 100 ms; a link silent for `linkTimeout` (5 s by default) is declared gone |

!!! question "Why not WebRTC?"
    Binding full WebRTC or libdatachannel means pulling a DTLS and SCTP stack
    into a native game just to move packets. The custom protocol implements the
    same `NetTransport` contract without that weight.

#### Testing netcode that has only ever seen loopback

`simulatedLoss` throws away a fraction of **outgoing** datagrams, and it is a
field on the shipped class rather than a test helper for a reason: netcode that
has only run over loopback has never had a packet lost, so every retransmission
path in it is untested code that first runs on a player's hotel wifi.

```dart
final transport = P2PNetTransport(simulatedLoss: 0.3);
// ...and it is settable while running, which is how you model the case that
// matters most: a link that was fine and then was not.
transport.simulatedLoss = 1;
```

At 30% loss the reliable channel should still deliver everything, in order.
`good_net_p2p`'s own tests assert exactly that.

## Topology

Traffic is host-and-spokes, not a full mesh: a client has a direct link to the
host and to nobody else, which is why `connectionTo` is always null between two
clients. Client-to-client communication goes through the host, which is also
where authority belongs.

## What this layer is, and is not

`good_net` is **messaging and sessions**. It moves declared records and manages
who is in the session.

There is **no request/reply shape**, deliberately. A `GameCommand<P, R>` can
await a result because the other isolate answers on a known schedule; a remote
peer may never answer at all, and an API that looks awaitable but can hang
forever is worse than one that does not offer it.

The **ECS replication layer** — a `Replicated` mixin, delta compression,
client-side prediction and reconciliation — is its own topic rather than
something bundled into messaging. Building it on these interfaces is a game's
decision, and the channel split is exactly the primitive it needs.

## A note on isolates

`describeNetwork` runs once per copy of the state, at boot, inside
`describeSystems` — including on the main-isolate copy, exactly as every other
declaration pass re-runs there. The transport built on that copy **never opens a
socket**: nothing calls `host` or `join` on it, because a system only ticks on
the copy that simulates.

`NetworkSystem` drains what arrived at the top of each fixed tick and puts what
was queued on the wire once per frame, so message delivery is as deterministic
as the rest of the simulation.
