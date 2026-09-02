## Unreleased

### Changed

* **`MultiplayerState.network` is a getter over the declared system** (#287).
  It was a `late final` field that `describeSystems` filled in after declaring
  the system, which named one system twice. `descriptor.has(NetworkSystem.new)`
  is the declaration; `network` looks it up. A read before the pass has run now
  reports the pass by name instead of a `LateInitializationError`.

* **`describeNetwork` documents why it is a hook.** Its descriptor is a binder
  over `NetworkSystem.registry`, so it exists only once that system does, and a
  system exists only on the copy that ticks — which is not the copy that runs a
  `GameState` field initialiser. `hasHandler` and `hasSignal` also name an
  instance member of the state, which a field initialiser cannot.

* **`MultiplayerState` declares its `NetworkSystem` before describing it.**
  `describeSystems` used to build the system, run `describeNetwork` into it
  and hand the finished object to `descriptor.has`. `SystemDescriptor.has`
  now takes a constructor and is what builds it, so the declaration comes
  first and the two passes after it read `network` back off the returned
  handle (#91). Nothing about a game's own `describeNetwork` changes.

### Breaking

* **`MultiplayerState.describeEvents` is gone. Its four dispatchers are
  fields** (#287):

  ```dart
  final peerJoinedEvent = Event.of<NetPeerListener, NetPeerId>(
    (listener, peer) => listener.onPeerJoined(peer),
  );
  ```

  `peerJoinedEvent`, `peerLeftEvent`, `sessionOpenedEvent` and
  `sessionClosedEvent` are `final` rather than `late final`, and stop being
  assigned from a hook the kernel no longer drives. `MultiplayerState` mixes
  into a `GameState`, which `Game.createState` builds inside a declaration
  window, so `Event.of` on one of its fields declares into that state's binder
  - the same binder the hook wrote to. Same listeners, same order, same
  delivery.

* **`NetMessageBase.describeParams` is gone. A message declares its fields on
  the fields that hold them** (#287):

  ```dart
  class Fire extends NetMessage<({double angle, int weapon})> {
    final angle = Param.float32();
    final weapon = Param.uint4();
  }
  ```

  | before | after |
  |---|---|
  | `void describeParams(ParamDescriptor d) { angle = d.hasFloat32(); }` | `final angle = Param.float32();` |

  `NetRegistry.declare` already opened the layout around the constructor, so
  the fields were always declared before the hook ran and the record they
  produce is unchanged - a build's schema hash is the same on both sides of
  this. Deleted together with `GameCommandBase.describeParams` in `good`,
  because the two share one record vocabulary and one `ParamLayout`.

* **`NetDescriptor.has` takes a constructor, not an instance.**
  `descriptor.has(Fire(), id: 'fire')` becomes
  `descriptor.has(Fire.new, id: 'fire')`. `id`, `to` and `channel` stay on the
  call: they are facts about the declaration, not fields in the record, and a
  field initialiser has no way to supply them (#91).

  ```dart
  // before
  fire = descriptor.has(Fire(), id: 'fire', channel: NetChannel.unreliable);

  // after
  fire = descriptor.has(Fire.new, id: 'fire', channel: NetChannel.unreliable);
  ```

  **Why.** `good`'s `Param` declares a message's fields on the fields
  themselves, and a `Param.*` initialiser runs at construction — so the record
  layout has to be open before the message exists, which means the framework
  constructs it. A message and a command are the same record on two different
  wires, so they move together or the two vocabularies drift apart.

  The wire format does not change and neither does the handshake hash. This is
  a source break only.

* **The handshake hash now covers what each field *is*, not just how wide the
  record is.** Two builds that were compatible under 0.3.0 will refuse each
  other, so peers have to be upgraded together — for any game declaring at
  least one message with at least one field. A game whose messages are all
  `NetSignal`s is unaffected, because a signal declares no fields and so
  contributes nothing new to the hash (#146).

  Nothing to change in your code. This is a wire-compatibility break, not a
  source one.

  **Why.** #141's rule is that the hash carries the wire format and nothing
  else, and the stride-plus-field-count summary it used to carry stopped being
  enough when a field's length stopped being fixed. A `hasString()` field
  keeps an offset and a length into the record's tail in the same four head
  bytes a `hasUint32()` would keep a number in — and a `hasString()` against a
  `hasFixedBytes(10)` is twelve bytes of head and one field either way, so the
  old hash could not tell them apart at all. The damage from getting that
  wrong is not one misread field: one peer reads the head and stops, the other
  reads a tail length out of those same bytes, and every record behind it in
  the batch is lost. Mixing the field kinds catches it, and closes an older
  hole of the same shape while it is there — `hasInt32` against `hasFloat32`
  has always had an identical stride and field count.

  A capacity-capped field's declared maximum is **not** mixed separately. It
  is already in the hash by way of the stride, because those bytes really are
  reserved in every record. A length-free field has no declared maximum to
  mix: the bound it does have is its carrier's ring or datagram, which is a
  local fact about one peer rather than something the two ends must agree on.

* **A backend states what one message may be, and every backend enforces it —
  loopback included.** `NetTransport.maxMessageBytes(channel)` is a new
  abstract member: a backend outside this repo has to answer it. A send over
  the ceiling throws a `StateError` naming the size, the bound and the fix,
  where `LoopbackNetTransport` used to accept anything at all (#158).

  What to change: implement `maxMessageBytes` if you have written a backend,
  and stop sending more than it reports. `LoopbackNetTransport` defaults to
  1,024 bytes on the unreliable channel and 261,120 on the reliable one, and
  takes both as constructor arguments if a test wants a smaller ceiling to aim
  at.

  **Why.** Before #146 a message's stride was fixed at its declaration, so the
  largest datagram a game could produce was visible where its messages were
  written. `hasString()` and `hasBytes()` moved that decision to run time, and
  the only bound left is the carrier's. `good_net_p2p` had one and said so;
  loopback had none and handed the bytes over — so a game developed against
  loopback, which is what tests and local play run on, could write half a
  megabyte into a field, pass everything, and fail only against a real peer.
  A backend that silently accepts what another refuses is a backend that hides
  bugs. The conformance suite now pins the refusal, so it means the same thing
  on every backend.

* **The unreliable channel is one datagram wide and does not fragment.** Its
  ceiling is a single datagram's payload — 1,178 bytes on `good_net_p2p`,
  1,024 on loopback — where it previously fragmented an unreliable message the
  same way a reliable one is fragmented. A single unreliable *record* over
  that is now refused (#158).

  What to change: nothing, unless one message of yours carries more than a
  datagram on the unreliable channel. A tick's worth of unreliable messages is
  unaffected however many there are — see the note below. If one message
  really is that big, declare it `NetChannel.reliable`, or split it into
  messages that each stand alone.

  **Why.** A message split into N pieces with no retransmission behind it is
  lost whenever any one of the N is, so its loss rate is the link's multiplied
  by N — and "losing one costs a tick of smoothness", which is the whole case
  for this channel, quietly stops being true. There is also nothing to gain:
  this channel carries state that supersedes itself, so a value that does not
  fit this tick does not fit on the next one either and the failure repeats
  instead of being absorbed. Reassembly on the receiving side is kept, because
  a peer on an older build still sends fragmented unreliable messages and
  refusing to put those back together would break an upgrade rather than
  protect anything.

### Added

* **A message field is declared on the field that holds it**, through `good`'s
  new `Param` statics (#91).

  ```dart
  // before
  class Fire extends NetMessage<({double angle, int weapon})> {
    late final ParamPointer<double> angle;
    late final ParamPointer<int> weapon;

    @override
    void describeParams(ParamDescriptor descriptor) {
      angle = descriptor.hasFloat32();
      weapon = descriptor.hasUint4();
    }
  }

  // after
  class Fire extends NetMessage<({double angle, int weapon})> {
    final angle = Param.float32();
    final weapon = Param.uint4();
  }
  ```

  `NetMessageBase.describeParams` is no longer abstract, so a message with no
  hook body needs none. Both forms coexist, and a test now pins them to one
  wire format: the same record declared each way produces the same schema
  hash.

* **A message field can hold a string or a list whose length is not declared
  up front.** `hasString()` and `hasBytes()`, with `hasFixedString(n)` and
  `hasFixedBytes(n)` beside them for the cases where a bound is real. This is
  `good`'s record layer, shared with commands — see its changelog for the
  layout and for the two rules that come with a variable-length field (#146).

* **A tick's traffic is cut at record boundaries when it outgrows one
  message.** `NetworkSystem` packs a frame's messages into one batch per
  channel per destination, and a busy frame's batch can be longer than
  anything the backend carries. It is now sent in pieces of whole records
  rather than as one send the backend would refuse — every record begins with
  the declaration index that gives its length, so a receiver walks a piece
  exactly as it would have walked the whole (#158).

  This is what keeps the unreliable ceiling affordable: a hundred position
  updates in one tick still go, and a lost piece costs the records in it
  instead of the tick's whole traffic. Only a **single record** over the
  ceiling has no answer of this shape, and that one is refused at the write
  that made it — including in a game with nobody connected, so that a message
  which only fails once somebody joins is not a thing that can be written.

### Fixed

* **The unreliable channel never discarded a stale message, and its
  documentation said it did.** `NetChannel.unreliable` promised that an older
  message arriving after a newer one was dropped before delivery. Nothing
  dropped it. An unreliable frame carries no message id, so the only number a
  link has to compare is the packet sequence, which every message type on the
  link shares — dropping on that would make two unrelated messages suppress
  each other, which is worse than the missing feature. The channel now
  documents what it does, and `docs/packages/networking.md` shows the tick
  comparison a game writes in its handler (#159).

  No behaviour changed. A game that read the old sentence and left newest-wins
  to the transport has been applying stale positions over fresh ones all
  along.

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
