import 'package:good/good.dart';
import 'package:meta/meta.dart';

import 'channel.dart';
import 'message.dart';
import 'peer.dart';
import 'transport.dart';

/// Declares a game's network messages, its backend, and what runs when a
/// message arrives.
///
/// ```dart
/// class MyState extends GameState<MyGame> with MultiplayerState<MyGame> {
///   late final Fire fire;
///   late final Ready ready;
///
///   @override
///   void describeNetwork(NetDescriptor descriptor) {
///     descriptor.transport(P2PNetTransport());
///
///     fire = descriptor.has(
///       Fire.new,
///       id: 'fire',
///       to: NetTarget.host,
///       channel: NetChannel.unreliable,
///     );
///     descriptor.hasHandler(fire, _onFire);
///
///     ready = descriptor.has(Ready.new, id: 'ready');
///     descriptor.hasSignal(ready, _onReady);
///   }
/// }
/// ```
///
/// **Messages are declared on the `GameState`, not the `Game`** - the
/// opposite of `describeCommands`, and for the same reason it holds there.
/// A command's index has to mean the same thing on two *isolates*, so it is
/// declared on the one object both isolates run. A message's index has to
/// mean the same thing on two *machines*, which run their own copy of the
/// whole program - so it belongs where the simulation and the socket are,
/// which is here (the isolate-affinity rule). What could go wrong across machines is
/// not registration order but *build* skew, and that is what
/// [NetTransport.schemaHash] is for.
abstract class NetDescriptor {
  /// Declares the backend this game networks over, and returns it for the
  /// `late final` field to keep.
  ///
  /// Exactly one per game. A game that wants a loopback backend in tests and
  /// a real one in a build passes a different instance here; nothing else in
  /// the game changes, because messages are declared against the game and
  /// never against a backend.
  T transport<T extends NetTransport>(T transport);

  /// Builds one message with [create], declares it, and returns it for the
  /// field to keep.
  ///
  /// A tear-off - `descriptor.has(Fire.new, id: 'fire')` - and not an
  /// instance, for `CommandDescriptor.has`'s reason: a `Param.*` field
  /// initialiser runs at construction and the record layout has to be open
  /// before it does. [id], [to] and [channel] stay here rather than moving
  /// to a field, because they are facts about the *declaration* and not
  /// about a field in the record.
  ///
  /// [to] fixes who handles it and therefore who may send it; [channel] fixes
  /// how hard the transport tries to deliver it. Both are declaration-time
  /// facts, not arguments at the send site, so that reading the
  /// declaration tells you the whole contract - and so a message cannot be
  /// sent reliably in one place and unreliably in another, which is a
  /// desync waiting to be debugged.
  T has<T extends NetMessageBase>(
    T Function() create, {
    required String id,
    NetTarget to = NetTarget.host,
    NetChannel channel = NetChannel.reliable,
  });

  /// Registers what runs when [message] arrives: **the function the message
  /// claims to be**, plus who sent it.
  ///
  /// ```dart
  /// descriptor.hasHandler(fire, (p, from) => _spawnBullet(from, p.angle));
  /// ```
  void hasHandler<P>(
    NetMessage<P> message,
    void Function(P params, NetPeerId from) handler,
  );

  /// Registers a [NetSignal]'s handler: it takes only the sender, because
  /// that is all a signal carries.
  void hasSignal(NetSignal signal, void Function(NetPeerId from) handler);
}

/// The registry behind [NetDescriptor]. A field on `NetworkSystem`, built with
/// it: `MultiplayerState.networkSystem` declares the system and the system's
/// constructor runs `describeNetwork` into this.
///
/// Implements [ParamLayouts] so `ParamBatch` can walk a batch of records that
/// arrived as bytes - the same interface `CommandRegistry` implements for the
/// isolate transport, over the same record layer.
@internal
final class NetRegistry implements ParamLayouts {
  final List<NetMessageBase> _messages = <NetMessageBase>[];

  NetTransport? _transport;

  /// The declared backend. Null only if `describeNetwork` never declared one,
  /// which `NetworkSystem` reports at boot and not at first send.
  NetTransport? get transport => _transport;

  int get length => _messages.length;

  NetMessageBase operator [](int index) => _messages[index];

  NetMessageBase? tryAt(int index) =>
      index >= 0 && index < _messages.length ? _messages[index] : null;

  @override
  ParamLayout layoutOf(int index) => requireAt(index).layout;

  NetMessageBase requireAt(int index) {
    final message = tryAt(index);
    if (message != null) return message;
    throw NetException(
      'a message record names index $index, and this build declared only '
      '$length messages. The peer that sent it is not running this build - '
      'which the schema hash in the handshake is supposed to have caught, so '
      'either the peers connected before that check or the check is wrong.',
    );
  }

  bool _sealed = false;

  /// FNV-1a over the declaration list, computed once at [seal].
  int get schemaHash => _schemaHash;
  int _schemaHash = 0;

  /// Fixes the declaration list and computes the hash both peers compare.
  ///
  /// The hash covers, per message and in order: its declared id, its head
  /// stride, its field count, what each of those fields *is*
  /// (`ParamLayout.signature`), its target and its channel. Everything, in
  /// other words, that the two ends have to agree on for a record to mean the
  /// same thing twice - a reordered declaration, a field that grew from
  /// `hasUint8` to `hasUint16`, a channel changed from reliable to
  /// unreliable. Any of those and the peers refuse each other with a version
  /// error, instead of forming a session in which damage arrives as chat.
  ///
  /// # The field kinds are in it; a declared capacity is not
  ///
  /// #141's rule is that the hash carries the wire format and nothing else.
  /// The head stride and the field count are a *summary* of the wire format,
  /// and a summary stops being enough as soon as a field can live in the
  /// tail. A `hasString()` field keeps an offset and a length into the
  /// record's tail in the four head bytes a `hasUint32()` would hold a number
  /// in, and a peer that reads the wrong one of those does not misread one
  /// field: it computes the wrong tail length, and every record behind it in
  /// the batch is lost. The signature tells those two declarations apart, and
  /// it separates `hasInt32` from `hasFloat32`, which share a stride and a
  /// field count.
  ///
  /// What does **not** go in is the capacity `hasFixedString(n)` declares.
  /// That one is already in the hash by way of the stride, because the bytes
  /// really are reserved in every record. There is nothing further to add,
  /// and nothing about a length-free field to add either: it has no declared
  /// maximum, and the bound it does have is the carrier's - a local fact
  /// about one peer's ring or datagram, and not something the two ends have
  /// to agree on.
  ///
  /// 32-bit FNV-1a, not a cryptographic digest: this catches *accidents* -
  /// two builds that drifted - and there is nothing to gain by forging it,
  /// since a peer that wants to send nonsense can simply send nonsense.
  void seal() {
    if (_sealed) return;
    _sealed = true;
    var hash = 0x811c9dc5;
    void mix(int byte) {
      hash = (hash ^ (byte & 0xFF)) & 0xFFFFFFFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }

    for (var i = 0; i < _messages.length; i++) {
      final message = _messages[i];
      // The declared id, never the class name. A name is renameable and,
      // under `--obfuscate`, rewritten outright - measured: PlayerInputMessage
      // becomes `zl`, which moved this hash and refused a plain peer (#141).
      final id = message.protocolId;
      for (var c = 0; c < id.length; c++) {
        mix(id.codeUnitAt(c));
        mix(id.codeUnitAt(c) >> 8);
      }
      mix(message.strideBytes);
      mix(message.strideBytes >> 8);
      mix(message.fieldCount);
      final signature = message.layout.signature;
      for (var b = 0; b < signature.length; b++) {
        mix(signature[b]);
      }
      mix(message.target.index);
      mix(message.channel.index);
    }
    _schemaHash = hash;
  }

  T declare<T extends NetMessageBase>(
    T Function() create,
    String protocolId,
    NetTarget target,
    NetChannel channel,
    NetSender sender,
  ) {
    _requireOpen();
    if (protocolId.isEmpty) {
      throw ArgumentError.value(
        protocolId,
        'id',
        'a network message needs a non-empty id: it is what the handshake '
            'compares, and an empty one would make every message that forgot '
            'it look like the same message.',
      );
    }
    // Built before the duplicate checks for `CommandRegistry.declare`'s
    // reason: they read `runtimeType`, which a tear-off's static type
    // argument does not pin down.
    final layout = ParamLayout();
    final message = layout.open(create);
    for (var i = 0; i < _messages.length; i++) {
      if (_messages[i].runtimeType == message.runtimeType) {
        throw StateError(
          '${message.runtimeType} is declared twice. One instance is one '
          'message, and its position in this pass is its identity on the '
          'wire, so a second one would be a different message with the same '
          'name.',
        );
      }
      if (_messages[i].protocolId == protocolId) {
        throw StateError(
          'two messages are declared with the id "$protocolId": '
          '${_messages[i].runtimeType} and ${message.runtimeType}. An id is '
          'what the handshake compares, so two of them would make the two '
          'messages indistinguishable to a peer while being different here. '
          'Give each its own.',
        );
      }
    }
    message.bind(_messages.length, protocolId, layout, target, channel, sender);
    _messages.add(message);
    return message;
  }

  void declareHandler(NetMessageBase message, Function handler) {
    _requireOpen();
    if (message.index < 0 || tryAt(message.index) != message) {
      throw StateError(
        '${message.runtimeType} has no handler to register against because it '
        'was never declared. Declare it first: '
        '`myMessage = descriptor.has(${message.runtimeType}(), id: ...)`.',
      );
    }
    if (message.hasHandler) {
      throw StateError(
        '${message.runtimeType} already has a handler. A message has one '
        'meaning on the machine that receives it - two handlers would be two '
        'answers to what that meaning is.',
      );
    }
    message.bindHandler(handler);
  }

  void declareTransport(NetTransport transport) {
    _requireOpen();
    final current = _transport;
    if (current != null) {
      throw StateError(
        'this game already networks over ${current.name}, and '
        '${transport.name} was declared as well. One game, one backend: a '
        'peer reachable two ways is two sessions, two rosters and two '
        'answers to "am I the host".',
      );
    }
    _transport = transport;
  }

  void _requireOpen() {
    if (!_sealed) return;
    throw StateError(
      'network messages can only be declared during boot, in describeNetwork '
      '- the index a message gets is its identity on the wire, and the peers '
      'have already agreed on the list.',
    );
  }
}

/// [NetDescriptor] as the one `describeNetwork` pass sees it.
@internal
final class NetBinder implements NetDescriptor {
  NetBinder(this._registry, this._sender);

  final NetRegistry _registry;
  final NetSender _sender;

  @override
  T transport<T extends NetTransport>(T transport) {
    _registry.declareTransport(transport);
    return transport;
  }

  @override
  T has<T extends NetMessageBase>(
    T Function() create, {
    required String id,
    NetTarget to = NetTarget.host,
    NetChannel channel = NetChannel.reliable,
  }) => _registry.declare(create, id, to, channel, _sender);

  @override
  void hasHandler<P>(
    NetMessage<P> message,
    void Function(P params, NetPeerId from) handler,
  ) => _registry.declareHandler(message, handler);

  @override
  void hasSignal(NetSignal signal, void Function(NetPeerId from) handler) =>
      _registry.declareHandler(signal, handler);
}
