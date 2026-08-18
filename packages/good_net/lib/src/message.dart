import 'package:good/good.dart';
import 'package:meta/meta.dart';

import 'channel.dart';
import 'peer.dart';
import 'session.dart';

/// Which machines a message is handled on - the network's answer to the
/// question `HandlerSide` answers for isolates.
///
/// It is declared once, where the message is declared, and it decides both
/// halves at once: where a call to that message *goes*, and who is allowed to
/// make one. That is the same trade the command layer makes - the declaration
/// site is the routing table, so there is no second thing to keep in step
/// with it.
enum NetTarget {
  /// Handled by the host. Clients send it; the host runs it.
  ///
  /// The workhorse of an authoritative game: "I pressed fire", "I want to buy
  /// this", "I picked a colour". A client's *intent*, which the host is free
  /// to refuse.
  ///
  /// Calling one **on the host** runs it locally rather than failing, and
  /// that is what makes single-player, host and client one code path: the
  /// firing code says `fire((angle: a))` and does not care which machine it
  /// is on.
  host,

  /// Handled by every client. Only the host may send it.
  ///
  /// The host's *decisions*: "you died", "the door opened", "round over".
  /// The host does not run it locally - it already knows; it is the one that
  /// decided. Use [everyone] when the host needs to run it too.
  clients,

  /// Handled by every client **and** by the host. Only the host may send it.
  ///
  /// For a decision the host must also react to through the same code path -
  /// a scoreboard update, a sound cue - so that host and client visibly agree
  /// rather than agreeing by two implementations that drift.
  everyone,
}

/// What every network message shape has in common: an identity on the wire, a
/// record layout, a channel and a target.
///
/// Not extended directly - pick the shape the message actually is:
/// [NetMessage] (it carries parameters) or [NetSignal] (it does not). Both
/// are spelled exactly like their command counterparts (`SinkCommand`,
/// `SignalCommand`) and use the same record layer underneath - `ParamBatch`
/// holds the bytes and `ParamPointer` reads them, whether the bytes are
/// crossing an isolate or a socket.
///
/// # There is no request/reply shape yet, on purpose
///
/// `GameCommand<P, R>` can await a result because the other isolate answers
/// in microseconds and cannot fail to. A machine on the other side of the
/// internet answers in tens of milliseconds, may never answer at all, and may
/// have left the session between the question and the answer - so an awaited
/// network result needs a timeout, a cancellation and a "peer left" path
/// before it is honest. That belongs in its own landing rather than smuggled
/// in as an overload here; until then, a reply is a second message going the
/// other way, which is also what shipped netcode overwhelmingly does.
abstract class NetMessageBase {
  /// Declares this message's fields. Identical in shape and vocabulary to
  /// `GameCommandBase.describeParams` - same descriptor, same packing rule.
  void describeParams(ParamDescriptor descriptor);

  /// Position in `describeNetwork`'s declaration order - the two bytes that
  /// head this message's record and route it back to this object on the
  /// receiving machine.
  ///
  /// Assigned by [NetDescriptor.has]. Both peers agree on it because both
  /// ran the same declaration pass, which holds only while both are running
  /// the same build - see `NetTransport.schemaHash` for what enforces that.
  int get index => _index;
  int _index = -1;

  /// Bytes one record of this message occupies, excluding header and mask.
  int get strideBytes => _strideBytes;
  int _strideBytes = 0;

  int get fieldCount => _fieldCount;
  int _fieldCount = 0;

  /// Where this message is handled, from its declaration.
  NetTarget get target => _target;
  NetTarget _target = NetTarget.host;

  /// Which delivery guarantee it rides on, from its declaration.
  NetChannel get channel => _channel;
  NetChannel _channel = NetChannel.reliable;

  /// Whether a handler was registered for it.
  bool get hasHandler => _handler != null;

  Function? _handler;

  NetSender? _sender;

  /// The registered handler.
  ///
  /// Stored untyped and cast by each shape at dispatch, for the same reason
  /// `GameCommandBase.handler` is: Dart will not let a type parameter appear
  /// contravariantly in a superinterface. The cast is exact by construction -
  /// the only way in is a registration method that named the concrete shape.
  @protected
  Function get handler {
    final handler = _handler;
    if (handler == null) {
      throw StateError(
        '$runtimeType arrived from the network and nothing handles it. '
        'Register a handler in describeNetwork - a declared message with no '
        'handler is bytes nobody reads, and this peer sent them because the '
        'peer on the other end does have one.',
      );
    }
    return handler;
  }

  @internal
  void bind(
    int index,
    ParamLayout layout,
    NetTarget target,
    NetChannel channel,
    NetSender sender,
  ) {
    _index = index;
    _target = target;
    _channel = channel;
    describeParams(layout);
    layout.seal();
    _strideBytes = layout.strideBytes;
    _fieldCount = layout.fieldCount;
    _sender = sender;
  }

  @internal
  void bindHandler(Function handler) => _handler = handler;

  /// Reads one record off the wire and runs the handler on it.
  ///
  /// Per shape, because unpacking is the one place the shapes differ - and it
  /// is what lets a handler be the plain function the message claims to be,
  /// with no buffer in its signature.
  @internal
  void invoke(ParamBuffer record, NetPeerId from);

  NetSender _requireSender() {
    final sender = _sender;
    if (sender == null) {
      throw StateError(
        '$runtimeType was never declared. Add it to describeNetwork - '
        '`myMessage = descriptor.has($runtimeType())` - and keep the handle '
        'it returns; a message built with `new` has no index, no layout and '
        'no transport to leave through.',
      );
    }
    return sender;
  }

  /// Whether this peer is allowed to send this message at all, given its
  /// target. Host-targeted messages are sendable by anyone; the other two are
  /// the host's to send.
  bool _maySend(NetSender sender) => _target == NetTarget.host || sender.isHost;

  void _refuseSend() {
    assert(
      false,
      '$runtimeType is declared `to: ${_target.name}`, so only the host sends '
      'it, and this peer is a client. A client that wants the host to act '
      'declares a `NetTarget.host` message and sends that instead - the host '
      'then decides whether to broadcast anything.',
    );
  }
}

/// A message that carries parameters: `void Function(P)`, across a network.
///
/// The workhorse, and the direct counterpart of `SinkCommand`:
///
/// ```dart
/// class Fire extends NetMessage<({double angle, int weapon})> {
///   late final ParamPointer<double> angle;
///   late final ParamPointer<int> weapon;
///
///   @override
///   void describeParams(ParamDescriptor d) {
///     angle = d.hasFloat32();
///     weapon = d.hasUint4();
///   }
///
///   @override
///   void bufferFromParams(ParamBuffer m, ({double angle, int weapon}) p) {
///     angle[m] = p.angle;
///     weapon[m] = p.weapon;
///   }
///
///   @override
///   ({double angle, int weapon}) paramsFromBuffer(ParamBuffer m) =>
///       (angle: angle[m], weapon: weapon[m]);
/// }
/// ```
///
/// Declared and handled in one pass, and sent by calling it:
///
/// ```dart
/// fire = d.has(Fire(), to: NetTarget.host, channel: NetChannel.reliable);
/// d.hasHandler(fire, _onFire);
///
/// void _onFire(({double angle, int weapon}) p, NetPeerId from) { ... }
///
/// fire((angle: 1.2, weapon: 3));   // from anywhere, on any machine
/// ```
///
/// Note the handler's second parameter. A command's handler never asks who
/// called it - there is only one other isolate. A message's handler nearly
/// always has to: "player fired" is meaningless without which player, and
/// taking [NetPeerId] as an argument is what stops every game inventing a
/// "current sender" field that is only valid inside a callback.
abstract class NetMessage<P> extends NetMessageBase {
  /// Writes [params] into the record. One line per field.
  void bufferFromParams(ParamBuffer message, P params);

  /// Reads the parameters back out - what the handler is handed.
  P paramsFromBuffer(ParamBuffer message);

  /// Sends this message wherever its [NetTarget] says it goes.
  ///
  /// Returns without doing anything when there is no session yet, or when
  /// there is nobody on the other end - a game that fires a shot while
  /// waiting for a second player has not made a mistake, and neither has a
  /// host with no clients yet.
  ///
  /// Never a `Future`, unlike a command's `call`. There is nothing to await:
  /// even on the reliable channel, "the bytes are queued" is all this side
  /// can honestly report, and a `Future` that completed on queueing would
  /// look like a delivery receipt without being one.
  void call(P params) {
    final sender = _requireSender();
    if (!_maySend(sender)) {
      _refuseSend();
      return;
    }
    final remote = sender.reserve(this);
    if (remote != null) bufferFromParams(remote, params);
    if (!sender.runsLocally(_target)) return;
    // The same bytes the peers will read, read back. When there was nobody to
    // send to, a scratch record stands in - see [NetSender.dispatchLocally]
    // for why the local path goes through the record at all.
    final local = remote ?? sender.scratch(this);
    if (local != remote) bufferFromParams(local, params);
    sender.dispatchLocally(this, local);
  }

  /// Sends to exactly one peer, whatever the declared target would have done.
  ///
  /// For the host answering one client - a spawn burst for the player who just
  /// joined, a private "you may not do that". Asserts and drops if there is no
  /// link to [peer] (the assert-not-print rule): a message to an unreachable
  /// client is a bug in the caller's model of the topology, not a runtime
  /// condition to swallow.
  void sendTo(NetPeerId peer, P params) {
    final sender = _requireSender();
    if (!_maySend(sender)) {
      _refuseSend();
      return;
    }
    if (peer == sender.localPeer) {
      final local = sender.scratch(this);
      bufferFromParams(local, params);
      sender.dispatchLocally(this, local);
      return;
    }
    final record = sender.reserveTo(this, peer);
    if (record != null) bufferFromParams(record, params);
  }

  @override
  @internal
  void invoke(ParamBuffer record, NetPeerId from) =>
      (handler as void Function(P, NetPeerId))(paramsFromBuffer(record), from);
}

/// A message that carries nothing: `void Function()`, across a network.
///
/// "Ready", "I want to skip the cutscene", "round over". Two lines including
/// the class, since the default [describeParams] declares an empty record -
/// the same shape `SignalCommand` has.
///
/// ```dart
/// class Ready extends NetSignal {}
///
/// ready = d.has(Ready());
/// d.hasSignal(ready, (from) => _readyPeers.add(from));
///
/// ready();
/// ```
abstract class NetSignal extends NetMessageBase {
  /// Nothing to declare. Overridable anyway, for a signal that grows a field
  /// later and would otherwise have to change class.
  @override
  @mustCallSuper
  void describeParams(ParamDescriptor descriptor) {}

  /// Sends this signal wherever its [NetTarget] says it goes. See
  /// [NetMessage.call].
  void call() {
    final sender = _requireSender();
    if (!_maySend(sender)) {
      _refuseSend();
      return;
    }
    final remote = sender.reserve(this);
    if (!sender.runsLocally(_target)) return;
    sender.dispatchLocally(this, remote ?? sender.scratch(this));
  }

  /// Sends to exactly one peer. See [NetMessage.sendTo].
  void sendTo(NetPeerId peer) {
    final sender = _requireSender();
    if (!_maySend(sender)) {
      _refuseSend();
      return;
    }
    if (peer == sender.localPeer) {
      sender.dispatchLocally(this, sender.scratch(this));
      return;
    }
    sender.reserveTo(this, peer);
  }

  @override
  @internal
  void invoke(ParamBuffer record, NetPeerId from) =>
      (handler as void Function(NetPeerId))(from);
}

/// What a message needs from the thing that owns the transport, so that a
/// message can be *called* without naming the system that carries it.
///
/// `NetworkSystem` is the only implementation. It is an interface for the
/// same reason `CommandSender` is one: the registry lives a layer up, and a
/// message pointing back down at it would be a cycle.
@internal
abstract interface class NetSender {
  /// This peer's own id, or [NetPeerId.none] outside a session.
  NetPeerId get localPeer;

  bool get isHost;

  /// The live session, or null when not in one.
  NetSession? get session;

  /// Whether a message declared for [target] also runs on this machine.
  bool runsLocally(NetTarget target);

  /// A record in whichever outbound batch [message]'s target says it belongs
  /// in, or null when there is nobody to send it to - no session yet, a host
  /// with no clients, a host-targeted message being sent by the host itself.
  ParamBuffer? reserve(NetMessageBase message);

  /// A record in the batch bound for one specific peer.
  ParamBuffer? reserveTo(NetMessageBase message, NetPeerId peer);

  /// A record that is going nowhere, for a message that is only being
  /// handled locally.
  ParamBuffer scratch(NetMessageBase message);

  /// Runs [message]'s handler on this machine, over [record] - **not** by
  /// handing the caller's own value straight to the handler.
  ///
  /// The detour through the bytes is the point: a host that ran its own
  /// messages by passing the object through would exercise a code path no
  /// client ever runs, and every truncated string and out-of-range field
  /// would show up only at the far end, in someone else's session. Local
  /// dispatch pays one record write to be the same thing a remote dispatch
  /// is.
  void dispatchLocally(NetMessageBase message, ParamBuffer record);
}
