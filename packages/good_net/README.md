# good_net

Networking for the good engine family: declared messages, sessions, and the
transport contract a backend implements. Dimension-agnostic — not under
`goo2d`, because a `goo3d` game needs the same session and messaging
plumbing.

**This is the command API, over a socket.** A network message and a
`GameCommand` are the same thing — a typed record, declared once,
identified on the wire by its position in that declaration, handed to a
handler registered where it runs. So they are not two implementations:
`NetMessage` and `NetSignal` are spelled exactly like `SinkCommand` and
`SignalCommand`, and the record layer underneath (`ParamDescriptor`,
`ParamPointer`, `ParamBatch`, `ParamBuffer`) is `good`'s own, reused instead of
reimplementing it here.

```dart
class MyState extends GameState2D<MyGame> with MultiplayerState<MyGame> {
  late final Fire fire;

  @override
  void describeNetwork(NetDescriptor descriptor) {
    descriptor.transport(P2PNetTransport());
    fire = descriptor.has(Fire(), channel: NetChannel.unreliable);
    descriptor.hasHandler(fire, _onFire);
  }

  void _onFire(({double angle}) params, NetPeerId from) =>
      spawnBullet(from, params.angle);
}

fire((angle: 1.2));
```

What networking adds over commands is the two facts an isolate boundary does
not have, both declared instead of passed at the send site:

- **`NetTarget`** — which machine handles it. `host` is a client's intent and
  runs locally when the host sends it, which is what makes single-player,
  hosting and joining one code path. `clients` and `everyone` are the host's
  decisions.
- **`NetChannel`** — `reliable` (arrives, in order, however many
  retransmissions it takes) or `unreliable` (sent once, for state that
  supersedes itself, like a transform every tick).

## What is here

- Message shapes, the `describeNetwork` pass, and `MultiplayerState`.
- `NetworkSystem`, which drains what arrived at the top of each fixed tick and
  flushes what was queued once per frame — so delivery is as deterministic as
  the rest of the simulation.
- `NetSession`, the roster, and `NetPeerListener`/`NetSessionListener`.
- `NetTransport`, the backend contract.
- `LoopbackNetTransport`, which is in-process and **real**, not a mock. It is
  what tests and split-screen run on, and it is why a multiplayer game can be
  developed without a second machine.
- `package:good_net/testing.dart` — a conformance suite every backend is run
  against, so "implements `NetTransport`" means the same thing for all of them.

## What is not

- **Request/reply**, deliberately. A `GameCommand<P, R>` can await a result
  because the other isolate answers on a known schedule; a remote peer may
  never answer at all, and an API that looks awaitable but can hang forever is
  worse than one that does not offer it.
- **The ECS replication layer** — a `Replicated` mixin, delta compression,
  prediction and reconciliation. That is its own topic built on these
  interfaces; the channel split is exactly the primitive it needs.

## Backends

[`good_net_p2p`](https://pub.dev/packages/good_net_p2p) is the one that reaches another machine, with
no server to host. The Steam backend was dropped instead of built; the
contract is open, so one remains possible as a separate package and nothing
here assumes it.

See the [networking guide](https://sunarya-thito.github.io/good/packages/networking/) for the full
reference.
