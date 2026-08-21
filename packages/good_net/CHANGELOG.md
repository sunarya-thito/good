## Unreleased

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
