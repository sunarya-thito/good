## 0.3.0

### Breaking

* **A network message now declares its own protocol id.** `descriptor.has`
  takes a required `id`, and the handshake hash is computed from that instead
  of the message's Dart class name (#141).

  ```dart
  fire = descriptor.has(Fire(), id: 'fire', channel: NetChannel.unreliable);
  ```

  Add an `id` to every `descriptor.has` call. Pick the string once and treat it
  as part of the protocol: peers agree because someone wrote the same id in
  both builds, not because a class is still spelled the same way.

  **Why it had to change.** The hash mixed `runtimeType.toString()`, so two
  changes a reader would rightly call behaviour-preserving broke peer
  compatibility with no wire format change at all. Renaming `PlayerInput` to
  `InputCommand` made every old peer refuse the new build. And `--obfuscate`
  rewrites type names outright — measured on a release build, where
  `PlayerInputMessage` became `zl` and the hash moved with it, so an
  obfuscated client could not talk to a plain server built from identical
  source.

  There is deliberately **no fallback to the class name** for messages that do
  not supply an id. A fallback would leave the fragile path as the default and
  make the safe one something you have to already know about, which fails
  exactly the people this protects.

  Two messages sharing an id, or an empty id, are refused where they are
  declared rather than at a handshake.

  **This changes the hash**, so 0.3.0 peers do not accept 0.2.x peers. That is
  a real break, unlike the one 0.2.0 claimed and 0.2.1 retracted — update every
  peer together.

## 0.2.1

Documentation only. No code changes.

### The 0.2.0 breaking note was wrong

**0.2.0 does not break peer compatibility. A build against 0.2.0 talks to a
build against 0.1.x exactly as before, and no coordinated update is needed.**
If you read that note and planned a fleet-wide rollout, you can drop it.

The claim was that `good` 0.2.0 declaring four commands of its own shifted the
declaration order the handshake hashes. It does shift the order commands are
declared in — but the handshake hash does not read commands. Network messages
are declared in `describeNetwork` on the `GameState`, commands in
`describeCommands` on the `Game`, and `SchemaRegistry.seal` walks only the
messages. The two passes are independent, which `NetDescriptor`'s own doc says:
a command's index has to mean the same thing on two *isolates*, a message's on
two *machines*.

Measured rather than reasoned: a game with three extra commands declared and an
otherwise identical set of messages hashes to the same value, while adding one
message changes it.

The mistake was mine, not a change in behaviour. The 0.2.0 entry is left below
rather than deleted, since it was published and may have been read.

## 0.2.0

### Breaking

> **Retracted in 0.2.1 — the entry below is wrong.** Peer compatibility with
> 0.1.x is unaffected and no coordinated update is needed. The handshake hash
> reads network messages, not commands. Kept here because 0.2.0 shipped with
> it.

* **Peers built against 0.1.x can no longer connect.** The handshake hashes the
  order commands are declared in, and `good` 0.2.0 declares four of its own
  before anything a game declares — so the same game, rebuilt against this
  version, computes a different schema hash and refuses an older peer.

  Nothing in `good_net` changed to cause it and no wire format moved. The cause
  is upstream, in `good`; the consequence is here, which is why it is written
  down here.

  There is no compatibility mode. **Update every peer together**, including
  dedicated servers and any client you cannot ship an update to at the same
  time. A staged rollout will partition your players by build.

### Fixed

* **The conformance suite waits for delivery.** `pump` ran four flush and poll
  rounds and then asserted, which is deterministic in process and a race over a
  real socket: `sendToAll` failed about one run in three, because a reliable
  message needing a retransmit had not landed yet. Each call site now states
  the condition it depends on and pumps until it holds, capped at five seconds.
  Loopback got faster — the predicate is checked after the first round, which a
  local send has already satisfied.

## 0.1.1

Documentation only. No code changes.

README links now resolve on pub.dev.

## 0.1.0

First published release. Networking as the command API over a socket:

* **Declared messages** — `NetMessage` and `NetSignal`, spelled like `good`'s
  `SinkCommand` and `SignalCommand` and built on the same record layer, so a
  message is identified on the wire by its position in the declaration.
* **Sessions and roster events**, message targets, and the reliable/unreliable
  channel split.
* **`NetTransport`** — the contract a backend implements, with
  `LoopbackNetTransport` in the box.
* **A conformance suite** every backend is run against, exported from
  `package:good_net/testing.dart`.

Not here yet: request/reply messages (deliberately absent), the ECS
replication layer, and congestion control — a link reports `packetLoss` and
lets the game decide to send less.

## 0.0.1

* Package scaffolded. Never published.
