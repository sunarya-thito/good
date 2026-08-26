import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_net/good_net.dart';
import 'package:good_net_p2p/good_net_p2p.dart';
// The link and its wire format are the package's own, not its API - and this
// is a test about a bound inside the transport, which is the one place that
// distinction should not stop a test from looking.
import 'package:good_net_p2p/src/link.dart';
import 'package:good_net_p2p/src/wire.dart';

/// Records what a transport reports, so a test can say what arrived.
class _Ear implements NetListener {
  final List<Uint8List> received = <Uint8List>[];
  final List<NetPeerId> joined = <NetPeerId>[];
  final List<(NetPeerId, NetDisconnectReason)> left =
      <(NetPeerId, NetDisconnectReason)>[];
  NetDisconnectReason? closed;

  @override
  void onPeerJoined(NetPeerId peer) => joined.add(peer);

  @override
  void onPeerLeft(NetPeerId peer, NetDisconnectReason reason) =>
      left.add((peer, reason));

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
      Duration handshakeTimeout = const Duration(seconds: 2),
    }) {
      final made = P2PNetTransport(
        bindAddress: InternetAddress.loopbackIPv4,
        simulatedLoss: loss,
        handshakeTimeout: handshakeTimeout,
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

    /// [run], but stopping as soon as [done] holds.
    ///
    /// For anything waiting on the loss sweep. `P2PLink._sweepLost` only counts
    /// a packet once `_lossDeadlineMicros` - 500ms at the shortest - has passed
    /// since that packet was sent, so a fixed wait is a race: a drop late in
    /// the window is still pending when the window closes, and the link
    /// correctly reports no loss yet. Waiting for the event instead of for a
    /// duration takes the clock out of it.
    Future<void> runUntil(
      bool Function() done, {
      Duration limit = const Duration(seconds: 8),
    }) async {
      final until = DateTime.now().add(limit);
      while (DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        for (var i = 0; i < transports.length; i++) {
          transports[i].flush();
        }
        if (done()) return;
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
        // Waiting for the thirtieth rather than for two seconds. `poll` is
        // what moves a message into the ear, so it belongs in the condition,
        // and the wait is capped, so a message that never arrives fails the
        // `expect` below instead of hanging the runner.
        await runUntil(() {
          host.poll(hostEar);
          return hostEar.received.length >= 30;
        });
        // The count is two claims in one, and only the first can be waited
        // for: that all thirty arrived is a condition, and that no
        // thirty-first did is the absence of an event. So the second half
        // gets a fixed window - a dozen or so retransmission rounds at the
        // 30ms floor the clamp puts on a loopback round trip - for a message
        // whose ack was lost to be said again and refused as a duplicate.
        await run(const Duration(milliseconds: 400));
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
      // An ack rides on the peer's next packet, so a measurement takes a
      // keepalive or two even before a third of them are thrown away - and
      // then the sweep has to reach the dropped one. Waiting for the report
      // rather than for a fixed 1500ms, which used to fail about one run in
      // six on exactly the value it asserts.
      // Both things this test asserts, not just the first: the host can notice
      // its own loss before the client has had an ack back to measure a round
      // trip from, and those are two different links.
      //
      // Capped at 3s so the sweep is what satisfies it. The ack window takes
      // 6.4s to recycle at ten keepalives a second, so a longer cap would let
      // this pass on the recycle path alone and stop noticing if the sweep
      // stopped working.
      await runUntil(
        () =>
            (hosted.connectionTo(joined.localPeer)?.packetLoss ?? 0) > 0 &&
            (joined.connectionTo(NetPeerId.host)?.roundTripMicros ?? -1) >= 0,
        limit: const Duration(seconds: 3),
      );

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

    test('a handshake survives losing half of itself', () async {
      final host = transport();
      // The connect request is retried on an interval until the timeout, so
      // half of them going missing costs time and not the join. Reaching this
      // at all needs the loss knob to cover the handshake, which it did not
      // until `_send` became the one place a packet leaves.
      final client = transport(loss: 0.5);
      final hosted = await host.host();

      final joined = await client.join(hosted.id);
      expect(joined.connectionTo(NetPeerId.host), isNotNull);
    });

    test('a handshake that never lands gives up and says so', () async {
      final host = transport();
      final client = transport(
        loss: 1,
        handshakeTimeout: const Duration(milliseconds: 300),
      );
      final hosted = await host.host();

      // Nothing leaves at all, so no retry can help and the timeout is the
      // only way out. The message names the address, because the usual cause
      // is nobody listening there rather than loss.
      await expectLater(
        client.join(hosted.id),
        throwsA(isA<NetException>()),
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
      // Waiting for the two messages rather than for 400ms. `poll` is what
      // moves them into the ear, so it is part of the condition - and the
      // wait is capped, so a pair that never arrives fails the `expect`
      // below instead of hanging the runner.
      await runUntil(() {
        host.poll(hostEar);
        return hostEar.received.length >= 2;
      });

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

    // #177. `RawDatagramSocket.send` answering 0 means "would block, ask
    // again", not "sent", and the transport read it as sent. A reliable
    // message hid that completely - a retransmission covers a packet the
    // socket refused exactly as well as one a router ate - so the whole cost
    // landed on the two things sent exactly once: an unreliable message, and
    // the goodbye a leaving peer says. About one send in a hundred on Windows
    // loopback, which is a rerun rather than a bug report, which is why it
    // sat here.
    //
    // Every test below needs `simulatedBackpressure`, and that is the point
    // rather than an inconvenience: a refusal is too rare to catch and too
    // common to ignore, so the branch that handles it was code nothing had
    // ever run. None of this can be written on the reliable channel - it
    // passes against the broken transport.
    group('a socket that will not take a datagram', () {
      test('holds an unreliable message rather than dropping it', () async {
        final host = transport();
        final client = transport();
        final hostEar = _Ear();
        final hosted = await host.host();
        final joined = await client.join(hosted.id);
        await run(const Duration(milliseconds: 200));

        final connection = joined.connectionTo(NetPeerId.host)!;
        client.simulatedBackpressure = 1;
        connection.send(NetChannel.unreliable, Uint8List.fromList(<int>[9]));
        await run(const Duration(milliseconds: 150));
        host.poll(hostEar);
        expect(
          hostEar.received,
          isEmpty,
          reason:
              'the socket has been handed nothing, so nothing can have '
              'arrived. If this is not empty the knob is doing nothing and '
              'the half below cannot fail',
        );

        client.simulatedBackpressure = 0;
        await runUntil(() {
          host.poll(hostEar);
          return hostEar.received.isNotEmpty;
        }, limit: const Duration(seconds: 2));

        expect(
          hostEar.received.map((bytes) => bytes.single),
          contains(9),
          reason:
              'kept while the socket was busy and sent once it was not. An '
              'unreliable message has no second copy to fall back on, so a '
              'transport that drops it here looks downstream exactly like '
              'the wire losing it - which is why nobody found this',
        );
      });

      test('says a goodbye it could not say at the time', () async {
        final host = transport();
        final client = transport();
        final hostEar = _Ear();
        final hosted = await host.host();
        final joined = await client.join(hosted.id);
        await run(const Duration(milliseconds: 200));

        // The other exactly-once packet, and the more expensive one to lose:
        // there is no link left to retransmit a disconnect on, so a host that
        // misses it waits out the whole link timeout before it notices, and
        // holds the slot for the duration.
        client.simulatedBackpressure = 1;
        await joined.leave();
        await run(const Duration(milliseconds: 100));
        host.poll(hostEar);
        expect(
          hostEar.left,
          isEmpty,
          reason: 'the goodbye is still in hand, so the host cannot know yet',
        );

        client.simulatedBackpressure = 0;
        await runUntil(() {
          host.poll(hostEar);
          return hostEar.left.isNotEmpty;
        }, limit: const Duration(seconds: 2));

        expect(
          hostEar.left.map((departure) => departure.$2),
          contains(NetDisconnectReason.remoteClose),
          reason:
              'said late is the whole difference between a peer that left '
              'and a peer the host has to wait out a link timeout to give up '
              'on, holding the slot the while',
        );
      });

      test('sends what it held in the order it held it', () async {
        final host = transport();
        final client = transport();
        final hostEar = _Ear();
        final hosted = await host.host();
        final joined = await client.join(hosted.id);
        await run(const Duration(milliseconds: 200));

        final connection = joined.connectionTo(NetPeerId.host)!;
        client.simulatedBackpressure = 1;
        // A flush per message, so these are eight datagrams rather than one
        // packet carrying eight frames - there is nothing to reorder inside a
        // single datagram. The loop is synchronous, so no keepalive gets in
        // among them either.
        for (var i = 0; i < 8; i++) {
          connection.send(NetChannel.unreliable, Uint8List.fromList(<int>[i]));
          client.flush();
        }

        client.simulatedBackpressure = 0;
        await runUntil(() {
          host.poll(hostEar);
          return hostEar.received.length >= 8;
        });

        expect(
          hostEar.received.map((bytes) => bytes.single),
          orderedEquals(<int>[0, 1, 2, 3, 4, 5, 6, 7]),
          reason:
              'a sequence number is written when a packet is built, so a '
              'fresh datagram overtaking the held ones puts the link out of '
              'step with its own numbering. Loopback is what makes that '
              'visible here: the channel promises no ordering, but nothing '
              'between these two sockets can reorder them except this queue',
        );
      });

      test('gives up the oldest when there is no room for another', () async {
        final host = transport();
        final client = transport();
        final hostEar = _Ear();
        final hosted = await host.host();
        final joined = await client.join(hosted.id);
        await run(const Duration(milliseconds: 200));

        final connection = joined.connectionTo(NetPeerId.host)!;
        const int over = 6;
        const int count = P2PNetTransport.maxHeldDatagrams + over;
        client.simulatedBackpressure = 1;
        for (var i = 0; i < count; i++) {
          connection.send(NetChannel.unreliable, Uint8List.fromList(<int>[i]));
          client.flush();
        }

        client.simulatedBackpressure = 0;
        await runUntil(() {
          host.poll(hostEar);
          return hostEar.received.length >= P2PNetTransport.maxHeldDatagrams;
        });

        final arrived = hostEar.received
            .map((bytes) => bytes.single)
            .toList(growable: false);
        expect(
          arrived.length,
          lessThanOrEqualTo(P2PNetTransport.maxHeldDatagrams),
          reason:
              'a queue with no ceiling would have kept all $count of them, '
              'which is what the bound is for: a socket that has stopped '
              'draining is not a reason to grow a buffer until the game runs '
              'out of memory',
        );
        expect(
          arrived.first,
          over,
          reason:
              'and it is the oldest that goes, because its moment passed '
              'first - the newest datagram is the one still worth sending. '
              'Asserted on the value rather than on the count, so that a '
              'stray loopback drop mid-burst cannot decide this',
        );
        expect(
          arrived.last,
          count - 1,
          reason:
              'the newest survived, which is the other half of the same '
              'decision',
        );
      });

      test('closing over one that never drains gives up, not hangs', () async {
        final host = transport();
        final client = transport();
        final hosted = await host.host();
        await client.join(hosted.id);
        await run(const Duration(milliseconds: 200));

        // A goodbye gets a bounded wait on the way out, because closing is
        // the last chance it will ever get. *Bounded* is the word under test:
        // a socket that has stopped draining altogether must not be able to
        // hold a game's shutdown open, and the only way to know it cannot is
        // to close over one that never will.
        client.simulatedBackpressure = 1;
        await expectLater(
          client.close().timeout(const Duration(seconds: 2)),
          completes,
          reason:
              'the timeout is the assertion. With no cap on the wait this '
              'never completes, and a bare await there would hang the runner '
              'with nothing to read rather than fail with something to fix',
        );
      });
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

        // Waiting for the client to give up rather than for twice the link
        // timeout. `poll` is what reports the closure, so it is part of the
        // condition, and the wait is capped, so a link that never gives up
        // fails the `expect` below rather than hanging the runner.
        await runUntil(() {
          client.poll(clientEar);
          return clientEar.closed != null;
        });

        expect(clientEar.closed, NetDisconnectReason.timeout);
        expect(client.session, isNull);
      },
    );

    test('a link that stops hearing back reports the loss', () async {
      final host = transport();
      // The sibling test above is about the teardown; this one is about the
      // number, so the link has to outlive the measurement rather than race
      // it. Nothing here waits anywhere near 30s.
      final client = transport(linkTimeout: const Duration(seconds: 30));
      final hosted = await host.host();
      final joined = await client.join(hosted.id);
      await run(const Duration(milliseconds: 200));

      final toHost = joined.connectionTo(NetPeerId.host)!;
      expect(
        toHost.packetLoss,
        0,
        reason: 'nothing has been dropped, and the link is younger than the '
            'deadline an unanswered packet gets anyway',
      );

      // The host stops answering without saying so. What makes this the case
      // the sweep exists for: the client hears nothing at all from here, so
      // there is no ack with a gap in it to read loss out of, and no traffic
      // of its own to retransmit. Keepalives leave and nothing comes back.
      host.simulatedLoss = 1;

      // Ten keepalives a second take 6.4s to wrap the 64-packet ack window,
      // which is the other place a packet is written off. Stopping well short
      // of that leaves the sweep as the only thing that can move the figure.
      await runUntil(
        () => toHost.packetLoss > 0,
        limit: const Duration(seconds: 3),
      );

      expect(
        toHost.packetLoss,
        greaterThan(0),
        reason: 'the keepalives it is still sending are going unanswered, and '
            'unanswered past the deadline is what lost means',
      );
    });

    // #163. The transport's own lane, which #158 left out. A game's send is
    // bounded by `maxMessageBytes` and refused where it was written;
    // `sendSystem` built its bytes and went straight to the queue, so the
    // only thing between it and a message cut into more pieces than the
    // format can index was an `assert` - and an `assert` is not there in the
    // build where a silently deleted roster update cannot be recovered from.
    //
    // Both of these send a body no caller sends today. That is the point: the
    // callers carry a slot and a generation, so nothing can reach the ceiling
    // now, and the whole risk is a later system message that carries
    // something variable and inherits an unbounded path.
    group('a system message has a ceiling of its own', () {
      // A `peerJoined` body is a slot and a generation and then whatever
      // padding a test wants: `_onSystemMessage` reads the first four bytes
      // and ignores the rest, so one of these is a real roster update that
      // happens to be as long as it is allowed to be.
      Uint8List announce(int slot, int length) =>
          Uint8List(length)
            ..[0] = slot & 0xFF
            ..[1] = slot >> 8;

      const int newcomer = 7;

      test('one byte over it is refused, and nothing goes out', () async {
        final host = transport();
        final client = transport();
        final clientEar = _Ear();
        final hosted = await host.host();
        final joined = await client.join(hosted.id);
        await run(const Duration(milliseconds: 200));

        final link = hosted.connectionTo(joined.localPeer)! as P2PLink;
        const limit = P2PLink.maxSystemMessageBytes;

        // A block body, not an arrow, and matched on the text rather than on
        // `StateError` alone: more than one guard on this path throws one, so
        // a type-only assertion would be satisfied by the fragment count or
        // by a link that had already ended and would stop meaning anything.
        expect(
          () {
            // The message id is the first byte of the payload, so a body of
            // exactly the limit is one byte over it.
            link.sendSystem(
              SystemMessage.peerJoined,
              announce(newcomer, limit),
            );
          },
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('system message ${SystemMessage.peerJoined}'),
                contains('${limit + 1} bytes'),
                contains('carries at most $limit'),
              ),
            ),
          ),
          reason:
              'the same answer a game gets for an oversized send, and for the '
              'same reason: it can never arrive however long it is left, so '
              'it is a different failure from a link that is momentarily busy '
              'and the caller can do something about exactly one of them',
        );

        await run(const Duration(milliseconds: 200));
        client.poll(clientEar);

        expect(
          clientEar.joined.map((peer) => peer.slot),
          isNot(contains(newcomer)),
          reason:
              'and the refusal is where it stops. Without a bound here this '
              'is cut into two fragments and delivered, which is the thing '
              'that makes the ceiling worth stating rather than assuming',
        );
      });

      test('a body of exactly the ceiling arrives whole', () async {
        final host = transport();
        final client = transport();
        final clientEar = _Ear();
        final hosted = await host.host();
        final joined = await client.join(hosted.id);
        await run(const Duration(milliseconds: 200));

        final link = hosted.connectionTo(joined.localPeer)! as P2PLink;
        link.sendSystem(
          SystemMessage.peerJoined,
          announce(newcomer, P2PLink.maxSystemMessageBytes - 1),
        );

        // Waiting for the roster update rather than for 400ms, and on the
        // slot the `expect` names rather than on the list being non-empty,
        // so the condition and the assertion are the same claim. Capped, so
        // a body that never crosses fails the `expect` below.
        await runUntil(() {
          client.poll(clientEar);
          return clientEar.joined.any((peer) => peer.slot == newcomer);
        });

        expect(
          clientEar.joined.map((peer) => peer.slot),
          contains(newcomer),
          reason:
              'a ceiling the sender cannot reach is a bound on paper only. '
              'Exactly the stated size is one frame and crosses intact, which '
              'is what the number was chosen to mean',
        );
      });
    });
  });

  group('an unreliable message that arrives out of order', () {
    /// One payload packet carrying one whole unreliable frame, whose body is
    /// the single byte [mark].
    ///
    /// Built here and handed straight to the link, because the reordering
    /// this is about is one a loopback socket never performs: two datagrams
    /// sent in order over 127.0.0.1 arrive in order, so a test that sends
    /// them and hopes would assert nothing.
    Uint8List packet(int sequence, int mark) {
      final bytes = Uint8List(prologueBytes + payloadHeaderBytes + 4);
      final view = ByteData.sublistView(bytes);
      bytes[0] = magic0;
      bytes[1] = magic1;
      bytes[2] = protocolVersion;
      bytes[3] = PacketType.payload;
      view.setUint16(4, sequence, Endian.little);
      // This side has heard nothing back, which is what the zero says - an
      // ack of packet 0 from a peer that has received nothing is the bug the
      // flag byte exists for.
      bytes[12] = 0;
      var at = prologueBytes + payloadHeaderBytes;
      // No message id: an unreliable frame carries none, which is the whole
      // reason the link has nothing to compare a late one against.
      bytes[at++] = FrameKind.unreliable;
      view.setUint16(at, 1, Endian.little);
      at += 2;
      bytes[at] = mark;
      return bytes;
    }

    test('is handed up behind the newer one, not dropped as stale', () {
      final delivered = <int>[];
      final link = P2PLink(
        address: InternetAddress.loopbackIPv4,
        port: 51999,
        peer: NetPeerId.host,
        nowMicros: 0,
        timeoutMicros: const Duration(seconds: 5).inMicroseconds,
        send: (link, datagram, length) {},
        deliver: (link, channel, bytes, offset, length) {
          expect(channel, NetChannel.unreliable);
          delivered.add(bytes[offset]);
        },
        deliverSystem: (link, message, bytes) {},
        lost: (link, reason) {},
      );

      link.onPayload(packet(41, 41), prologueBytes + payloadHeaderBytes + 4, 0);
      link.onPayload(packet(40, 40), prologueBytes + payloadHeaderBytes + 4, 0);

      expect(
        delivered,
        <int>[41, 40],
        reason:
            'the transport hands up what arrives, in the order it arrives. '
            'Newest-wins belongs to the handler: an unreliable frame carries '
            'no message id, so the only number the link could compare is '
            'the packet sequence, which every message type on the link '
            'shares - dropping on it would make two unrelated messages '
            'suppress each other. docs/packages/networking.md says so, and '
            'shows the tick comparison a game writes instead',
      );
    });
  });
}
