import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_net/good_net.dart';
import 'package:good_net_p2p/good_net_p2p.dart';
// The prologue and the reject body are the package's own bytes, and a peer on
// another version is a thing only a raw socket can be: the version this build
// speaks is a compile-time constant, so one process cannot hold two of them.
import 'package:good_net_p2p/src/wire.dart';

/// The version a peer that is not this build speaks.
const int otherVersion = protocolVersion + 1;

void main() {
  group('a peer on another protocol version', () {
    final transports = <P2PNetTransport>[];
    final sockets = <RawDatagramSocket>[];

    P2PNetTransport transport({
      Duration handshakeTimeout = const Duration(seconds: 5),
    }) {
      final made = P2PNetTransport(
        bindAddress: InternetAddress.loopbackIPv4,
        handshakeTimeout: handshakeTimeout,
      );
      transports.add(made);
      return made;
    }

    Future<RawDatagramSocket> socket() async {
      final made = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      sockets.add(made);
      return made;
    }

    tearDown(() async {
      for (var i = 0; i < transports.length; i++) {
        await transports[i].close();
      }
      transports.clear();
      for (var i = 0; i < sockets.length; i++) {
        sockets[i].close();
      }
      sockets.clear();
    });

    /// A join request that is correct in every field except [version].
    ///
    /// The schema and the code are the host's own, so a reject can only be
    /// about the version: a request built wrong would be refused by
    /// `schemaMismatch` or `wrongSession` and the test would pass without the
    /// version ever being looked at.
    Uint8List connectRequest({
      required int version,
      required String code,
      required int schema,
    }) {
      final codeBytes = utf8.encode(code);
      final bytes = Uint8List(prologueBytes + 5 + codeBytes.length);
      final view = ByteData.sublistView(bytes);
      bytes[0] = magic0;
      bytes[1] = magic1;
      bytes[2] = version;
      bytes[3] = PacketType.connectRequest;
      var at = prologueBytes;
      view.setUint32(at, schema, Endian.little);
      at += 4;
      bytes[at++] = codeBytes.length;
      bytes.setRange(at, at + codeBytes.length, codeBytes);
      return bytes;
    }

    /// The next datagram on [from], or null if none arrives in [within].
    ///
    /// A second is far under the five a handshake would burn, so an answer
    /// that only comes after the timeout counts as no answer here.
    Future<Datagram?> reply(
      RawDatagramSocket from, {
      Duration within = const Duration(seconds: 1),
    }) {
      final answered = Completer<Datagram?>();
      final subscription = from.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = from.receive();
        if (datagram == null) return;
        if (!answered.isCompleted) answered.complete(datagram);
      });
      return answered.future
          .timeout(within, onTimeout: () => null)
          .whenComplete(subscription.cancel);
    }

    /// A packet of [type] on another version, correct in the prologue and
    /// carrying [body] where this build's layout would put one.
    Uint8List otherVersionPacket(int type, List<int> body) {
      final bytes = Uint8List(prologueBytes + body.length);
      bytes[0] = magic0;
      bytes[1] = magic1;
      bytes[2] = otherVersion;
      bytes[3] = type;
      bytes.setRange(prologueBytes, bytes.length, body);
      return bytes;
    }

    test(
      'is refused by a host, and told which version the host speaks',
      () async {
        final host = transport();
        final hosted = await host.host();
        final at = EndpointCode.decode(hosted.id)!;
        final joiner = await socket();

        joiner.send(
          connectRequest(
            version: otherVersion,
            code: hosted.id.value,
            schema: host.schemaHash,
          ),
          at.address,
          at.port,
        );

        final answer = await reply(joiner);
        expect(
          answer,
          isNotNull,
          reason:
              'Nothing came back inside a second. A join request on another '
              'version that is dropped without an answer is the joiner waiting '
              'out its handshake timeout and reporting an unreachable host.',
        );
        final data = answer!.data;
        expect(data[0], magic0);
        expect(data[1], magic1);
        expect(
          data[2],
          otherVersion,
          reason:
              'The reject is stamped with the version the request carried. A '
              'reject stamped with the host version is discarded by the joiner '
              'on the byte it is about, which is the defect one layer up.',
        );
        expect(data[3], PacketType.connectReject);
        expect(
          data.length,
          prologueBytes + 2,
          reason:
              'A reject is the reason byte and, for this one reason, the '
              'version behind it. A reject one byte short says nothing about '
              'which build is behind.',
        );
        expect(data[prologueBytes], RejectReason.versionMismatch);
        expect(
          data[prologueBytes + 1],
          protocolVersion,
          reason: 'The reason byte says what is wrong; this says with what.',
        );
      },
    );

    test('is not refused when only the version matches, which is an accept', () async {
      final host = transport();
      final hosted = await host.host();
      final at = EndpointCode.decode(hosted.id)!;
      final joiner = await socket();

      joiner.send(
        connectRequest(
          version: protocolVersion,
          code: hosted.id.value,
          schema: host.schemaHash,
        ),
        at.address,
        at.port,
      );

      final answer = await reply(joiner);
      expect(answer, isNotNull, reason: 'The host answered nothing at all.');
      expect(
        answer!.data[3],
        PacketType.connectAccept,
        reason:
            'The same bytes with this build version are admitted, so the '
            'reject above is the version byte and not the schema, the code or '
            'the length.',
      );
    });

    test('gets no answer on any packet type but a join request', () async {
      final host = transport();
      final hosted = await host.host();
      final at = EndpointCode.decode(hosted.id)!;

      // A payload, an accept and a goodbye, each on a version whose layout
      // this build does not have. None of the three is a handshake waiting on
      // an answer, so none of them is answered. One socket each, because a
      // `RawDatagramSocket` takes one listener for its whole life.
      for (final type in <int>[
        PacketType.payload,
        PacketType.connectAccept,
        PacketType.disconnect,
      ]) {
        final peer = await socket();
        peer.send(
          otherVersionPacket(type, List<int>.filled(16, 0)),
          at.address,
          at.port,
        );
        expect(
          await reply(peer, within: const Duration(milliseconds: 300)),
          isNull,
          reason:
              'Packet type \$type on another version was answered. Only a join '
              'request has anything waiting to hear the refusal.',
        );
      }
    });

    test('is not what a datagram with the wrong magic bytes becomes', () async {
      final host = transport();
      final hosted = await host.host();
      final at = EndpointCode.decode(hosted.id)!;
      final stray = await socket();

      final bytes = connectRequest(
        version: otherVersion,
        code: hosted.id.value,
        schema: host.schemaHash,
      );
      // A join request in every byte except the first, which is what any
      // other program spraying this port looks like.
      bytes[0] = magic0 ^ 0xFF;
      stray.send(bytes, at.address, at.port);

      expect(
        await reply(stray, within: const Duration(milliseconds: 300)),
        isNull,
        reason:
            'A datagram that is not this protocol got a datagram back. A '
            'socket that answers those is a reflector for anything that '
            'forges a source address at it.',
      );
    });

    test('joining one is told the version, not left to time out', () async {
      final fakeHost = await socket();
      fakeHost.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = fakeHost.receive();
        if (datagram == null) return;
        final data = datagram.data;
        if (data.length < prologueBytes) return;
        if (data[3] != PacketType.connectRequest) return;
        // What a host on `otherVersion` sends back: the reject wears the
        // version the request carried, so the joiner's own filter admits it.
        final answer = Uint8List(prologueBytes + 2);
        answer[0] = magic0;
        answer[1] = magic1;
        answer[2] = data[2];
        answer[3] = PacketType.connectReject;
        answer[prologueBytes] = RejectReason.versionMismatch;
        answer[prologueBytes + 1] = otherVersion;
        fakeHost.send(answer, datagram.address, datagram.port);
      });

      final client = transport();
      final code = EndpointCode.encode(
        InternetAddress.loopbackIPv4,
        fakeHost.port,
      );
      final startedAt = DateTime.now();

      await expectLater(
        client.join(code),
        throwsA(
          isA<NetException>().having(
            (failure) => failure.reason,
            'reason',
            allOf(contains('version'), contains('$otherVersion')),
          ),
        ),
      );

      expect(
        DateTime.now().difference(startedAt),
        lessThan(const Duration(seconds: 2)),
        reason:
            'The handshake timeout is five seconds. Failing inside two says '
            'the reject arrived and was read, not that the join gave up.',
      );
    });
  });
}
