import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../channel.dart';
import '../connection.dart';
import '../listener.dart';
import '../peer.dart';
import '../session.dart';
import '../transport.dart';

/// Every rule [NetTransport] states, as tests, so that a backend proves it
/// rather than intending it.
///
/// ```dart
/// void main() {
///   runNetTransportConformance('loopback', create: LoopbackNetTransport.new);
/// }
/// ```
///
/// # Why this lives in `lib/` and not in `test/`
///
/// A conformance suite that only the package defining the interface can run
/// is a suite that tests one implementation. Backends live in their own
/// packages (`goo_net_p2p`, and whatever comes after it), and a test
/// directory is not importable across packages - so the suite ships as
/// library code and each backend's test file is three lines calling it. The
/// cost is a `flutter_test` dependency on this package, which is deliberate
/// and is the whole reason it is here.
///
/// [create] must return a **fresh** transport each call; the suite builds
/// several and expects them not to share state beyond the backend's
/// switchboard.
///
/// [settle] is awaited whenever the suite has done something and wants the
/// backend to have finished reacting - a handshake to complete, a datagram to
/// cross a socket. In-process backends leave it null; a real one waits long
/// enough for a round trip on the local machine.
void runNetTransportConformance(
  String backend, {
  required NetTransport Function() create,
  Future<void> Function()? settle,
  void Function()? tearDownAll,
}) {
  Future<void> pump(List<_Peer> peers, {int times = 4}) async {
    for (var i = 0; i < times; i++) {
      if (settle != null) await settle();
      for (var p = 0; p < peers.length; p++) {
        peers[p].transport.flush();
      }
      if (settle != null) await settle();
      for (var p = 0; p < peers.length; p++) {
        peers[p].pump();
      }
    }
  }

  group('$backend: NetTransport conformance', () {
    final peers = <_Peer>[];

    _Peer peer() {
      final made = _Peer(create());
      peers.add(made);
      return made;
    }

    tearDown(() async {
      for (var i = 0; i < peers.length; i++) {
        await peers[i].transport.close();
      }
      peers.clear();
      if (tearDownAll != null) tearDownAll();
    });

    test('a hosted session names this peer as the host', () async {
      final host = peer();
      final session = await host.transport.host(
        const SessionOptions(name: 'kitchen'),
      );

      expect(session.isHost, isTrue);
      expect(session.localPeer, NetPeerId.host);
      expect(session.name, 'kitchen');
      expect(session.peerCount, 0, reason: 'nobody else has joined yet');
      expect(
        SessionId(session.id).isWellFormed,
        isTrue,
        reason: 'a generated code is one a player can retype',
      );
    });

    test('joining puts both peers on each other roster', () async {
      final host = peer();
      final client = peer();
      final hosted = await host.transport.host();
      final joined = await client.transport.join(hosted.id);
      await pump(peers);

      expect(joined.isHost, isFalse);
      expect(joined.localPeer.isHost, isFalse);
      expect(joined.id, hosted.id);
      expect(joined.peerCount, 1);
      expect(joined.peerAt(0), NetPeerId.host);
      expect(joined.connectionTo(NetPeerId.host), isNotNull);

      expect(hosted.peerCount, 1);
      expect(hosted.peerAt(0), joined.localPeer);
      expect(hosted.connectionTo(joined.localPeer), isNotNull);
      expect(host.joined, <NetPeerId>[
        joined.localPeer,
      ], reason: 'the host is told who arrived, once');
    });

    test('a message crosses in both directions, unchanged', () async {
      final host = peer();
      final client = peer();
      final hosted = await host.transport.host();
      final joined = await client.transport.join(hosted.id);
      await pump(peers);

      final up = Uint8List.fromList(<int>[1, 2, 3, 250]);
      joined.connectionTo(NetPeerId.host)!.send(NetChannel.reliable, up);
      await pump(peers);

      expect(host.received.length, 1);
      expect(host.received.single.bytes, up);
      expect(host.received.single.from, joined.localPeer);
      expect(host.received.single.channel, NetChannel.reliable);

      final down = Uint8List.fromList(<int>[9, 8, 7]);
      host.transport.session!
          .connectionTo(joined.localPeer)!
          .send(NetChannel.reliable, down);
      await pump(peers);

      expect(client.received.length, 1);
      expect(client.received.single.bytes, down);
      expect(
        client.received.single.from,
        NetPeerId.host,
        reason: 'a client hears from the host under the host id',
      );
    });

    test('a slice of a bigger buffer sends only that slice', () async {
      final host = peer();
      final client = peer();
      final hosted = await host.transport.host();
      final joined = await client.transport.join(hosted.id);
      await pump(peers);

      final scratch = Uint8List.fromList(<int>[0, 0, 42, 43, 0]);
      joined
          .connectionTo(NetPeerId.host)!
          .send(NetChannel.reliable, scratch, 2, 2);
      await pump(peers);

      expect(
        host.received.single.bytes,
        Uint8List.fromList(<int>[42, 43]),
        reason:
            'offset and length are how a caller sends out of a buffer it '
            'reuses, so a backend that ignores them corrupts every batch',
      );
    });

    test('reliable messages arrive in the order they were sent', () async {
      final host = peer();
      final client = peer();
      final hosted = await host.transport.host();
      final joined = await client.transport.join(hosted.id);
      await pump(peers);

      final connection = joined.connectionTo(NetPeerId.host)!;
      for (var i = 0; i < 20; i++) {
        connection.send(NetChannel.reliable, Uint8List.fromList(<int>[i]));
      }
      await pump(peers, times: 8);

      expect(host.received.length, 20);
      for (var i = 0; i < 20; i++) {
        expect(host.received[i].bytes.single, i);
      }
    });

    test(
      'an unreliable message arrives over a link that is not lossy',
      () async {
        final host = peer();
        final client = peer();
        final hosted = await host.transport.host();
        final joined = await client.transport.join(hosted.id);
        await pump(peers);

        joined
            .connectionTo(NetPeerId.host)!
            .send(NetChannel.unreliable, Uint8List.fromList(<int>[77]));
        await pump(peers, times: 8);

        expect(host.received.length, 1);
        expect(host.received.single.channel, NetChannel.unreliable);
        expect(host.received.single.bytes.single, 77);
      },
    );

    test('a payload far larger than one datagram round-trips', () async {
      final host = peer();
      final client = peer();
      final hosted = await host.transport.host();
      final joined = await client.transport.join(hosted.id);
      await pump(peers);

      final big = Uint8List(8000);
      for (var i = 0; i < big.length; i++) {
        big[i] = i & 0xFF;
      }
      joined.connectionTo(NetPeerId.host)!.send(NetChannel.reliable, big);
      await pump(peers, times: 16);

      expect(host.received.length, 1);
      expect(host.received.single.bytes, big);
    });

    test('sendToAll reaches every client and not the sender', () async {
      final host = peer();
      final one = peer();
      final two = peer();
      final hosted = await host.transport.host();
      await one.transport.join(hosted.id);
      await two.transport.join(hosted.id);
      await pump(peers);

      hosted.sendToAll(NetChannel.reliable, Uint8List.fromList(<int>[5]));
      await pump(peers);

      expect(one.received.length, 1);
      expect(two.received.length, 1);
      expect(host.received, isEmpty);
    });

    test('nothing is delivered outside poll', () async {
      final host = peer();
      final client = peer();
      final hosted = await host.transport.host();
      final joined = await client.transport.join(hosted.id);
      await pump(peers);
      host.received.clear();

      joined
          .connectionTo(NetPeerId.host)!
          .send(NetChannel.reliable, Uint8List.fromList(<int>[1]));
      client.transport.flush();
      if (settle != null) await settle();

      expect(
        host.received,
        isEmpty,
        reason:
            'a simulation consumes input at one point in its tick; a backend '
            'that delivers from its socket callback lands half a burst inside '
            'the tick and half outside it',
      );

      host.pump();
      expect(host.received.length, 1);
    });

    test('a client leaving is reported to the host', () async {
      final host = peer();
      final client = peer();
      final hosted = await host.transport.host();
      final joined = await client.transport.join(hosted.id);
      await pump(peers);
      final id = joined.localPeer;

      await joined.leave();
      await pump(peers, times: 8);

      expect(host.left.length, 1);
      expect(host.left.single.peer, id);
      expect(host.transport.session!.peerCount, 0);
      expect(host.transport.session!.hasPeer(id), isFalse);
      expect(
        client.closed,
        isNotNull,
        reason: 'the peer that left is told its session ended',
      );
      expect(client.transport.session, isNull);
    });

    test('the host closing ends the session for the clients', () async {
      final host = peer();
      final client = peer();
      final hosted = await host.transport.host();
      await client.transport.join(hosted.id);
      await pump(peers);

      await hosted.leave();
      await pump(peers, times: 8);

      expect(client.closed, isNotNull);
      expect(client.transport.session, isNull);
      expect(host.transport.session, isNull);
    });

    test('a reused slot is a different peer id', () async {
      final host = peer();
      final first = peer();
      final hosted = await host.transport.host();
      final firstSession = await first.transport.join(hosted.id);
      await pump(peers);
      final firstId = firstSession.localPeer;

      await firstSession.leave();
      await pump(peers, times: 8);

      final second = peer();
      final secondSession = await second.transport.join(hosted.id);
      await pump(peers);
      final secondId = secondSession.localPeer;

      expect(
        secondId.slot,
        firstId.slot,
        reason: 'slots are dense and get reused - that is what they are for',
      );
      expect(
        secondId,
        isNot(firstId),
        reason:
            'a packet still in flight from the peer that left must not be '
            'delivered as if the new one had sent it',
      );
      expect(secondId.generation, firstId.generation + 1);
    });

    test('joining a code nobody is hosting fails', () async {
      final client = peer();
      await expectLater(
        client.transport.join(SessionId.random(length: 10)),
        throwsA(isA<NetException>()),
      );
      expect(client.transport.session, isNull);
    });

    test('a full session refuses the next joiner', () async {
      final host = peer();
      final client = peer();
      final hosted = await host.transport.host(
        const SessionOptions(maxPeers: 2),
      );
      await client.transport.join(hosted.id);
      await pump(peers);

      final late = peer();
      await expectLater(
        late.transport.join(hosted.id),
        throwsA(isA<NetException>()),
      );
    });

    test('a peer running a different build is refused', () async {
      final host = peer();
      final client = peer();
      host.transport.bindSchema(0xABCDEF);
      client.transport.bindSchema(0x123456);
      final hosted = await host.transport.host();

      await expectLater(
        client.transport.join(hosted.id),
        throwsA(isA<NetException>()),
        reason:
            'index-on-the-wire means build skew reads one message as another; '
            'refusing the join is the only honest answer',
      );
    });
  });
}

/// One participant under test: a transport plus everything it has reported.
class _Peer implements NetListener {
  _Peer(this.transport);

  final NetTransport transport;

  final List<NetPeerId> joined = <NetPeerId>[];
  final List<({NetPeerId peer, NetDisconnectReason reason})> left =
      <({NetPeerId peer, NetDisconnectReason reason})>[];
  final List<({NetPeerId from, NetChannel channel, Uint8List bytes})> received =
      <({NetPeerId from, NetChannel channel, Uint8List bytes})>[];
  NetDisconnectReason? closed;

  void pump() => transport.poll(this);

  @override
  void onPeerJoined(NetPeerId peer) => joined.add(peer);

  @override
  void onPeerLeft(NetPeerId peer, NetDisconnectReason reason) =>
      left.add((peer: peer, reason: reason));

  @override
  void onMessage(
    NetPeerId from,
    NetChannel channel,
    Uint8List bytes,
    int offset,
    int length,
  ) => received.add((
    from: from,
    channel: channel,
    // Copied: the buffer is the transport's and is reused before the next
    // poll, which is exactly what a real listener has to cope with too.
    bytes: Uint8List.fromList(
      Uint8List.sublistView(bytes, offset, offset + length),
    ),
  ));

  @override
  void onSessionClosed(NetDisconnectReason reason) => closed = reason;
}
