# Networking

<!-- snippet-scope
class PlayerMoved extends NetMessage<({double x, double y})> {
  @override
  void bufferFromParams(ParamBuffer message, ({double x, double y}) params) {}

  @override
  ({double x, double y}) paramsFromBuffer(ParamBuffer message) => (x: 0, y: 0);
}

class RoundEnded() extends NetSignal;

void spawnBullet(NetPeerId from, double angle) {}

void applyPosition(NetPeerId from, double x, double y) {}
-->

!!! abstract "Layer: kernel-side (`good_net`)"
    A 3D game needs the same session and messaging plumbing a 2D one does, so
    networking sits beside the kernel instead of under a renderer.

**Networking is the command API, over a socket.** A network message and a
`GameCommand` are the same thing — a typed record, declared once,
identified on the wire by its position in that declaration, handed to a handler
registered where it runs. So they are not two implementations: `NetMessage` and
`NetSignal` are spelled exactly like `SinkCommand` and `SignalCommand`, and the
record layer underneath is the kernel's own, reused instead of reimplemented.

```dart
class MyState extends GameState2D<MyGame> with MultiplayerState<MyGame> {
  late final Fire fire;

  @override
  void describeNetwork(NetDescriptor descriptor) {
    descriptor.transport(LoopbackNetTransport());
    fire = descriptor.has(Fire(), id: 'fire', channel: NetChannel.unreliable);
    descriptor.hasHandler(fire, _onFire);
  }

  void _onFire(({double angle}) params, NetPeerId from) {
    spawnBullet(from, params.angle);
  }
}
```


## The `id` is the protocol, not the class name

Every message declares an `id`, and it is the thing two peers actually agree
on. The handshake hashes it — along with each message's layout, target and
channel — and refuses a peer whose hash differs, which is what stops two builds
forming a session over bytes they will read differently.

It is a string you choose, and the only rule the engine enforces is that no two
messages in one game share one. Both halves of that are checked where you
declare them, not at a handshake.

**Rename the class freely.** `Fire` can become `FireCommand` without touching
the protocol, because the id did not move. That is the point: a refactor should
not be a wire change.

The alternative — hashing the Dart class name — is what this replaced, and it
failed in two ways that look like nothing from the code. A rename broke every
peer. And `--obfuscate`, which release builds use, rewrites type names outright:
measured on a Windows release build, `PlayerInputMessage` became `zl`, so an
obfuscated client computed a different hash from a plain server built from the
same source and the two refused each other.

**Change an id when the wire format changes** and you want old peers turned
away — a field added, a width widened, a meaning altered. `'fire'` becoming
`'fire.v2'` is a deliberate break, which is the only kind worth having.
Send it by calling it:

<!-- snippet-setup
final fire = given<Fire>();
-->
```dart
fire((angle: 1.2));
```

## What networking adds over commands

Two facts an isolate boundary does not have, and **both are declared instead of
passed at the send site** — so a message's whole contract is readable in one
place, and it cannot be sent reliably in one file and unreliably in another.

### `NetTarget` — which machine handles it

| Target | Handled by | Sent by | For |
|---|---|---|---|
| `host` | The host | Anyone | A client's *intent*: "I pressed fire", "I want to buy this" |
| `clients` | Every client | Host only | The host's *decisions*: "you died", "the door opened" |
| `everyone` | Every client **and** the host | Host only | A decision the host must react to through the same path |

`NetTarget.host` is the workhorse of an authoritative game, and it has one
property worth spelling out: **calling one on the host runs it locally** instead
of failing. That is what makes single-player, host and client one code path —
the firing code says `fire((angle: a))` and does not care which machine it is
on.

`clients` does *not* run on the host: the host already knows, it is
the one that decided. Use `everyone` when the host must react through the same
code path, so host and client visibly agree instead of agreeing by two
implementations that drift.

### `NetChannel` — how hard to try

<!-- snippet-setup
final descriptor = given<NetDescriptor>();
-->
```dart
descriptor.has(PlayerMoved(), id: 'playerMoved', channel: NetChannel.unreliable);
descriptor.has(RoundEnded(), id: 'roundEnded', channel: NetChannel.reliable);
```

| Channel | Guarantee | For |
|---|---|---|
| `reliable` | Arrives exactly once, in order, however many retransmissions it takes | Anything a game cannot resolve by waiting: "player joined", "you took 12 damage", chat, the initial snapshot |
| `unreliable` | Sent once, may be dropped, and may arrive after a message that was sent later | State that supersedes itself: transforms, input samples — anything sent every tick where only the newest value matters |

**A late unreliable message still reaches the handler.** Nothing on the link
compares what arrives against what it has already delivered, so a position sent
on tick 40 that overtakes one sent on tick 41 is applied second and the entity
snaps backwards for a frame. Newest-wins is the handler's to enforce, and what
it takes is a tick number travelling with the state:

```dart
class Moved extends NetMessage<({int tick, double x, double y})> {
  late final ParamPointer<int> tick;
  late final ParamPointer<double> x;
  late final ParamPointer<double> y;

  @override
  void describeParams(ParamDescriptor descriptor) {
    tick = descriptor.hasUint32();
    x = descriptor.hasFloat32();
    y = descriptor.hasFloat32();
  }

  @override
  void bufferFromParams(
    ParamBuffer message,
    ({int tick, double x, double y}) params,
  ) {
    tick[message] = params.tick;
    x[message] = params.x;
    y[message] = params.y;
  }

  @override
  ({int tick, double x, double y}) paramsFromBuffer(ParamBuffer message) =>
      (tick: tick[message], x: x[message], y: y[message]);
}
```

and a comparison against the newest one already applied:

<!-- snippet: in MyState with MultiplayerState<MyGame> -->
```dart
final _newestTick = <NetPeerId, int>{};

void _onMoved(({int tick, double x, double y}) params, NetPeerId from) {
  final newest = _newestTick[from];
  if (newest != null && params.tick <= newest) return;
  _newestTick[from] = params.tick;
  applyPosition(from, params.x, params.y);
}
```

One counter per sender: two peers number their own ticks, and a peer that
joins mid-match starts wherever its clock is.

!!! danger "Do not send transforms reliably"
    Head-of-line blocking is reliable delivery's price: one lost packet stalls
    everything queued behind it until it is resent. For a position snapshot that
    means waiting for data which was already obsolete when it was lost. Losing
    an unreliable packet costs a tick of smoothness; waiting for its
    retransmission costs far more.

Two channels, not a per-message tunable policy, because these are the two
that game netcode actually needs and every extra one costs a receiver-side
reassembly structure that must be paid for whether or not a game uses it. It is
the same split ENet, Steam Sockets and QUIC's stream/datagram divide use.

### How big one message may be

A field declared `hasString()` or `hasBytes()` has no capacity of its own — the
size of a record is decided by the value written into it — so what bounds it is
the backend, and the backend says so:

| | `good_net_p2p` | `LoopbackNetTransport` |
|---|---|---|
| `reliable` | 300,390 bytes (255 datagrams, put back together) | 261,120 |
| `unreliable` | 1,178 bytes (**one** datagram) | 1,024 |

Writing more than that into one message throws, at the call that wrote it,
naming the number. It throws in a game with nobody connected too — a message
that only fails once somebody joins is a message that fails in front of a
player.

!!! info "A tick's worth of messages is not bounded by this"
    A frame's messages are packed into one batch per channel, and a busy
    frame's batch is regularly longer than any one message. That is cut at a
    record boundary and sent in pieces, so a hundred position updates in one
    tick cost a hundred records and not a refusal. Only a **single record**
    over the ceiling has no answer of that shape.

!!! danger "The unreliable channel does not fragment, and that is deliberate"
    A message cut into N pieces with nothing retransmitting them is lost
    whenever any one of the N is, so its loss rate is the link's multiplied by
    N — and "losing one costs a tick of smoothness" stops being true. There is
    nothing to gain by it either: this channel carries state that supersedes
    itself, so a value that does not fit this tick will not fit on the next
    one, and the failure repeats rather than being absorbed. Send it
    `reliable` if it has to arrive, or split it into messages that each stand
    alone and each supersede on their own.

Loopback's ceilings are lower than any real backend's on purpose. It has no
wire and therefore no bound of its own, and a backend that silently accepts
what another refuses is a backend that hides bugs — so a message loopback takes
is one a real backend takes too. Both are constructor arguments if a test wants
a smaller one to aim at.

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

<!-- snippet-setup
final fire = given<Fire>();
-->
```dart
typedef Shot = ({double angle, double power, bool charged});

class Fire extends NetMessage<Shot> { /* ... */ }

fire((angle: 1.2, power: 0.8, charged: true));
```

Worth a `typedef`: the record type appears in three signatures here, so naming
it once means a new field is one edit, not three. See
[commands](../guide/flutter-bridge.md#more-than-one-parameter-use-a-record) for
the full walk-through — it is the same mechanism.

`NetSignal` is the no-parameter shape:

<!-- snippet-setup
final descriptor = given<NetDescriptor>();
late RoundEnded roundEnded;
void _onRoundEnded(NetPeerId from) {}
-->
```dart
class RoundEnded() extends NetSignal;

// declared
roundEnded = descriptor.has(RoundEnded(), id: 'roundEnded', to: NetTarget.everyone);
descriptor.hasSignal(roundEnded, _onRoundEnded);

// sent
roundEnded();
```

### Sending to one peer

<!-- snippet-setup
final fire = given<Fire>();
final peerId = given<NetPeerId>();
-->
```dart
fire.sendTo(peerId, (angle: 1.2, power: 0.8, charged: true));
```

### Nobody to send to is not an error

A send with no session, or with nobody on the other end, returns without doing
anything. A game that fires a shot while waiting for a second player has not
made a mistake, and neither has a host with no clients yet.

## Sessions

Mix `MultiplayerState` into your `GameState` and you get `network`:

<!-- snippet: body MyState with MultiplayerState<MyGame> -->
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
    `peerAt(index)`, not a `List<NetPeerId>` getter, so walking the
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
different build is refused at join instead of silently misrouting messages into
the wrong handlers.

## Backends

`NetTransport` is the contract a backend implements. Exactly one is declared per
game:

<!-- snippet-setup
final descriptor = given<NetDescriptor>();
-->
```dart
descriptor.transport(LoopbackNetTransport());
```

A game that wants a loopback backend in tests and a real one in a build passes a
different instance here — **nothing else in the game changes**, because messages
are declared against the game instead of against a backend.

### Loopback — in `good_net` itself

`LoopbackNetTransport` is in-process and **real**, not a mock. It is what tests
and split-screen run on, and it is why a multiplayer game can be developed
without a second machine.

`package:good_net/testing.dart` ships a conformance suite that every backend is
tested against, so "implements `NetTransport`" means the same thing for all of
them.

### good_net_p2p — the serverless backend { #p2p }

The "nothing to host, no bill" path, for a game that reaches another machine.

<!-- snippet-setup
final descriptor = given<NetDescriptor>();
-->
```dart
descriptor.transport(P2PNetTransport());
```

Hosting binds a UDP socket and hands back a **ten-character code that is the
host's address**. Joining decodes it and starts talking. There is no broker, no
relay, no account, nothing to deploy and nothing that can go down.

<!-- snippet: body MyState with MultiplayerState<MyGame> -->
```dart
final session = await network.host(SessionOptions(name: 'Kitchen table'));
print(session.id);          // e.g. 4KM2QX9P7T — read this out to a friend

await network.join(SessionId('4KM2QX9P7T'));
```

On a LAN nobody has to type anything at all: a host announces itself once a
second, and `network.discover()` lists what is out there.

<!-- snippet: body MyState with MultiplayerState<MyGame> -->
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

A lightweight UDP protocol implementing both channels directly, instead of
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
field on the shipped class, not a test helper for a reason: netcode that
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

There is **no request/reply shape**. A `GameCommand<P, R>` can
await a result because the other isolate answers on a known schedule; a remote
peer may never answer at all, and an API that looks awaitable but can hang
forever is worse than one that does not offer it.

The **ECS replication layer** — a `Replicated` mixin, delta compression, client-
side prediction and reconciliation — is its own topic instead of something
bundled into messaging. Building it on these interfaces is a game's decision,
and the channel split is exactly the primitive it needs.

## A note on isolates

`describeNetwork` runs once, at boot, inside `describeSystems` — and so on the
**simulating copy only**. Most declaration passes do re-run on the main-isolate
copy, because an index has to mean the same thing on both sides of the boundary;
`describeSystems` is the exception, and networking rides it. There is no
main-isolate `NetworkSystem`, no second transport, and nothing over there to call
`host` or `join` on by mistake.

`NetworkSystem` drains what arrived at the top of each fixed tick and puts what
was queued on the wire once per frame, so message delivery is as deterministic
as the rest of the simulation.
