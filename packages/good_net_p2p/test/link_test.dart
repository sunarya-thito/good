import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_net/good_net.dart';
import 'package:good_net_p2p/good_net_p2p.dart';

/// Records what a transport reports, so a test can say what arrived.
class _Ear implements NetListener {
  final List<Uint8List> received = <Uint8List>[];
  final List<NetPeerId> joined = <NetPeerId>[];
  NetDisconnectReason? closed;

  @override
  void onPeerJoined(NetPeerId peer) => joined.add(peer);

  @override
  void onPeerLeft(NetPeerId peer, NetDisconnectReason reason) {}

  @override
  void onMessage(
    NetPeerId from,
    NetChannel channel,
    Uint8List bytes,
    int offset,
    int length,
  ) => received.add(
    Uint8List.fromList(Uint8List.sublistView(bytes, offset, offset + length)),
  );

  @override
  void onSessionClosed(NetDisconnectReason reason) => closed = reason;
}

void main() {
  group('the join code', () {
    test('round-trips an address and a port', () {
      final code = EndpointCode.encode(InternetAddress('192.168.1.23'), 51234);

      expect(code.length, EndpointCode.length);
      expect(SessionId(code).isWellFormed, isTrue);

      final back = EndpointCode.decode(code)!;
      expect(back.address.address, '192.168.1.23');
      expect(back.port, 51234);
    });

    test('covers the ends of both ranges', () {
      for (final endpoint in <({String address, int port})>[
        (address: '0.0.0.0', port: 0),
        (address: '255.255.255.255', port: 65535),
        (address: '127.0.0.1', port: 1),
        (address: '10.0.0.1', port: 65534),
      ]) {
        final code = EndpointCode.encode(
          InternetAddress(endpoint.address),
          endpoint.port,
        );
        final back = EndpointCode.decode(code)!;
        expect(back.address.address, endpoint.address);
        expect(back.port, endpoint.port);
      }
    });

    test('a code from somewhere else decodes to nothing', () {
      expect(EndpointCode.decode(SessionId('AAAAAA')), isNull);
      expect(
        EndpointCode.decode(SessionId('AAAAAAAAA0')),
        isNull,
        reason: 'zero is not in the alphabet, so this is not one of ours',
      );
    });
  });

  group('the reliability layer', () {
    final transports = <P2PNetTransport>[];

    P2PNetTransport transport({
      double loss = 0,
      Duration linkTimeout = const Duration(seconds: 5),
    }) {
      final made = P2PNetTransport(
        bindAddress: InternetAddress.loopbackIPv4,
        simulatedLoss: loss,
        handshakeTimeout: const Duration(seconds: 2),
        linkTimeout: linkTimeout,
      );
      transports.add(made);
      return made;
    }

    tearDown(() async {
      for (var i = 0; i < transports.length; i++) {
        await transports[i].close();
      }
      transports.clear();
    });

    /// Lets the sockets and the retransmission timer do their work.
    Future<void> run(Duration duration) async {
      final until = DateTime.now().add(duration);
      while (DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        for (var i = 0; i < transports.length; i++) {
          transports[i].flush();
        }
      }
    }

    test(
      'every reliable message survives a link losing a third of it',
      () async {
        final host = transport(loss: 0.3);
        final client = transport(loss: 0.3);
        final hostEar = _Ear();
        final hosted = await host.host();
        final joined = await client.join(hosted.id);
        await run(const Duration(milliseconds: 200));

        final connection = joined.connectionTo(NetPeerId.host)!;
        for (var i = 0; i < 30; i++) {
          connection.send(
            NetChannel.reliable,
            Uint8List.fromList(<int>[i, 0xAB]),
          );
        }
        await run(const Duration(seconds: 2));
        host.poll(hostEar);

        expect(
          hostEar.received.length,
          30,
          reason:
              'reliable means every one of them arrives, however many times '
              'the transport has to say it',
        );
        for (var i = 0; i < 30; i++) {
          expect(
            hostEar.received[i][0],
            i,
            reason: 'and ordered means in the order they were sent',
          );
        }
      },
    );

    test('a lossy link reports loss and a round trip', () async {
      final host = transport(loss: 0.3);
      final client = transport();
      final hosted = await host.host();
      final joined = await client.join(hosted.id);
      // Long enough for several keepalives to survive the loss - an ack rides
      // on the peer's next packet, so a measurement takes a keepalive or two
      // even before a third of them are thrown away.
      await run(const Duration(milliseconds: 1500));

      final toHost = joined.connectionTo(NetPeerId.host)!;
      expect(
        toHost.roundTripMicros,
        greaterThanOrEqualTo(0),
        reason: 'packets have crossed, so there is a measurement by now',
      );
      expect(
        hosted.connectionTo(joined.localPeer)!.packetLoss,
        greaterThan(0),
        reason:
            'the host is dropping a third of what it sends; it should '
            'notice that its packets are not being acknowledged',
      );
    });

    test('an unreliable message is not resent, and does not block', () async {
      final host = transport();
      final client = transport();
      final hostEar = _Ear();
      final hosted = await host.host();
      final joined = await client.join(hosted.id);
      await run(const Duration(milliseconds: 200));

      final connection = joined.connectionTo(NetPeerId.host)!;
      connection.send(NetChannel.unreliable, Uint8List.fromList(<int>[1]));
      connection.send(NetChannel.reliable, Uint8List.fromList(<int>[2]));
      await run(const Duration(milliseconds: 400));
      host.poll(hostEar);

      expect(hostEar.received.length, 2);
      expect(hostEar.received.map((bytes) => bytes.single).toSet(), <int>{
        1,
        2,
      });

      // Long enough for several retransmission windows: an unreliable message
      // that was being kept and resent would show up again here.
      hostEar.received.clear();
      await run(const Duration(milliseconds: 600));
      host.poll(hostEar);
      expect(hostEar.received, isEmpty);
    });

    test(
      'a host that goes silent is given up on, not waited for forever',
      () async {
        final host = transport();
        final client = transport(
          linkTimeout: const Duration(milliseconds: 400),
        );
        final clientEar = _Ear();
        final hosted = await host.host();
        await client.join(hosted.id);
        await run(const Duration(milliseconds: 200));
        expect(client.session, isNotNull);

        // Not `leave()`, which says goodbye politely - this is the router
        // unplugged, the laptop lid closed, the process killed. Nothing arrives
        // and nothing explains why, which is the case a timeout exists for.
        host.simulatedLoss = 1;

        await run(const Duration(milliseconds: 800));
        client.poll(clientEar);

        expect(clientEar.closed, NetDisconnectReason.timeout);
        expect(client.session, isNull);
      },
    );
  });
}
