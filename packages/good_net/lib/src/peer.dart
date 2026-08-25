/// One participant in a [NetSession], packed into a single 32-bit int:
///
/// ```text
///   31          16 15            0
///  +--------------+---------------+
///  |  generation  |     slot      |
///  +--------------+---------------+
/// ```
///
/// An extension type over `int`, following `Entity`'s precedent: a peer id
/// is passed to every message callback, stored in component rows once
/// replication lands, and written into packet headers, so it must cost
/// nothing to hold (the no-allocation rule).
///
/// # The slot is a dense index
///
/// The slot is a small dense index (`0 <= slot < maxPeers`), which is the
/// property replication needs later: per-peer state - last acked tick, interest
/// sets, input buffers - is a flat array indexed by slot, not a `Map<String,
/// ...>` searched per packet (the typed-handle rule). It is also the whole of
/// what goes on the wire: one byte, not a UUID.
///
/// # The generation catches a recycled slot
///
/// Slots are reused. A peer that times out frees slot 3, someone else joins
/// and gets slot 3, and packets still in flight from the first one arrive
/// addressed to "slot 3" - delivered to the wrong player, silently. The
/// generation counter is bumped every time a slot is handed out, so a stale
/// id compares unequal to the live one and is dropped. Same reasoning as an
/// ECS entity generation; the failure it prevents is identical.
///
/// The host is always [NetPeerId.host] - slot 0, generation 0 - because the
/// host's slot is never vacated while the session exists: the session ends
/// with it.
extension type const NetPeerId(int value) implements int {
  static const int _generationShift = 16;
  static const int _slotMask = 0xFFFF;

  /// The host of any session. Slot 0 is reserved for it and never reused,
  /// so its generation is fixed at 0.
  static const NetPeerId host = NetPeerId(0);

  /// "No peer" - what a lookup that found nothing returns, and what a
  /// connection to a peer that has already gone away reports.
  ///
  /// `Entity` has no such value; a peer id needs one, because peers come and
  /// go during a session and "the peer that sent this" still has to be
  /// answerable after that peer has left.
  static const NetPeerId none = NetPeerId(-1);

  const NetPeerId.pack(int slot, int generation)
    : value = (generation << _generationShift) | slot;

  int get slot => value & _slotMask;

  int get generation => (value >> _generationShift) & _slotMask;

  bool get isHost => value == host.value;

  bool get isNone => value == none.value;

  /// The same slot, one generation on - what the session hands out when it
  /// reuses this slot for a new peer.
  NetPeerId get nextGeneration =>
      NetPeerId.pack(slot, (generation + 1) & _slotMask);
}
