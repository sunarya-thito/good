import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:good/good.dart';
import 'package:good_net/good_net.dart';
import 'package:good_net_p2p/good_net_p2p.dart';

/// What a game actually writes: a message class, a declaration, a handler.
class Fire extends NetMessage<({double angle, int weapon})> {
  final angle = Param.float32();
  final weapon = Param.uint4();

  @override
  void bufferFromParams(
    ParamBuffer message,
    ({double angle, int weapon}) params,
  ) {
    angle[message] = params.angle;
    weapon[message] = params.weapon;
  }

  @override
  ({double angle, int weapon}) paramsFromBuffer(ParamBuffer message) =>
      (angle: angle[message], weapon: weapon[message]);
}

/// The host's answer, going the other way.
class Hit extends NetMessage<({int slot, int damage})> {
  final slot = Param.uint16();
  final damage = Param.uint8();

  @override
  void bufferFromParams(ParamBuffer message, ({int slot, int damage}) params) {
    slot[message] = params.slot;
    damage[message] = params.damage;
  }

  @override
  ({int slot, int damage}) paramsFromBuffer(ParamBuffer message) =>
      (slot: slot[message], damage: damage[message]);
}

class ShooterGame extends Game {
  @override
  GameState createState() => ShooterState();
}

class ShooterState extends GameState<ShooterGame>
    with MultiplayerState<ShooterGame> {
  final List<String> log = <String>[];

  late final Fire fire;
  late final Hit hit;

  @override
  void describeNetwork(NetDescriptor descriptor) {
    descriptor.transport(
      P2PNetTransport(
        bindAddress: InternetAddress.loopbackIPv4,
        handshakeTimeout: const Duration(seconds: 2),
      ),
    );

    fire = descriptor.has(
      fireMessage,
      id: 'fire',
      channel: NetChannel.unreliable,
    );
    descriptor.hasHandler(fire, _onFire);

    hit = descriptor.has(Hit.new, id: 'hit', to: NetTarget.everyone);
    descriptor.hasHandler(hit, _onHit);
  }

  /// Overridable so a subclass can declare a different message set - what a
  /// peer on another build looks like.
  Fire fireMessage() => Fire();

  void _onFire(({double angle, int weapon}) params, NetPeerId from) {
    log.add('fire ${params.angle} w${params.weapon} <- ${from.slot}');
    // The host decides, and tells everyone - including itself, since the
    // message is declared `to: everyone`.
    if (network.isHost) hit((slot: from.slot, damage: 25));
  }

  void _onHit(({int slot, int damage}) params, NetPeerId from) =>
      log.add('hit ${params.slot} for ${params.damage}');
}

void main() {
  final running = <Game>[];

  Future<ShooterState> boot([ShooterGame? game]) async {
    final booted = game ?? ShooterGame();
    await Game.startInline(booted);
    running.add(booted);
    return booted.state as ShooterState;
  }

  /// Advances every game repeatedly, with real time in between, because the
  /// packets are real.
  Future<void> play(List<ShooterState> states, {int frames = 40}) async {
    for (var frame = 0; frame < frames; frame++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      for (var i = 0; i < states.length; i++) {
        states[i].advance(const Duration(milliseconds: 16));
      }
    }
  }

  tearDown(() async {
    for (var i = 0; i < running.length; i++) {
      if (running[i].isRunning) await running[i].stop();
    }
    running.clear();
  });

  test('two games on real sockets play one round of the same rules', () async {
    final host = await boot();
    final client = await boot();

    final hosted = await host.network.host(
      const SessionOptions(name: 'kitchen table'),
    );
    expect(hosted.id.length, EndpointCode.length);

    final joined = await client.network.join(hosted.id);
    await play(<ShooterState>[host, client], frames: 10);

    expect(host.network.session!.peerCount, 1);
    expect(client.network.session!.peerCount, 1);

    // A client asks the host to act...
    client.fire((angle: 0.5, weapon: 2));
    await play(<ShooterState>[host, client]);

    expect(
      host.log,
      contains('fire 0.5 w2 <- ${joined.localPeer.slot}'),
      reason: 'the request runs on the host, tagged with who sent it',
    );
    expect(
      client.log.where((line) => line.startsWith('fire')),
      isEmpty,
      reason: 'and not on the client that only asked for it',
    );

    // ...and the host's answer reaches both, through the same handler.
    expect(host.log, contains('hit ${joined.localPeer.slot} for 25'));
    expect(client.log, contains('hit ${joined.localPeer.slot} for 25'));
  });

  test('a game with nobody connected still runs its own messages', () async {
    final alone = await boot();

    alone.fire((angle: 1.5, weapon: 7));

    expect(alone.log, <String>['fire 1.5 w7 <- 0', 'hit 0 for 25']);
  });

  test('leaving is seen on the other side', () async {
    final host = await boot();
    final client = await boot();
    final hosted = await host.network.host();
    final joined = await client.network.join(hosted.id);
    await play(<ShooterState>[host, client], frames: 10);

    await client.network.leave();
    await play(<ShooterState>[host, client], frames: 20);

    expect(host.network.session!.hasPeer(joined.localPeer), isFalse);
    expect(host.network.session!.peerCount, 0);
    expect(client.network.session, isNull);
  });
}
