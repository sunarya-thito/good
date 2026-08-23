import 'package:flutter_test/flutter_test.dart';
import 'package:good/good.dart';
import 'package:good_net/good_net.dart';

/// A client's request: "I fired, at this angle, with this weapon".
class _Fire extends NetMessage<({double angle, int weapon})> {
  late final ParamPointer<double> angle;
  late final ParamPointer<int> weapon;

  @override
  void describeParams(ParamDescriptor descriptor) {
    angle = descriptor.hasFloat32();
    weapon = descriptor.hasUint4();
  }

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

/// The host's decision, sent to the clients and not run on the host.
class _Score extends NetMessage<({int score})> {
  late final ParamPointer<int> score;

  @override
  void describeParams(ParamDescriptor descriptor) {
    score = descriptor.hasUint16();
  }

  @override
  void bufferFromParams(ParamBuffer message, ({int score}) params) =>
      score[message] = params.score;

  @override
  ({int score}) paramsFromBuffer(ParamBuffer message) =>
      (score: score[message]);
}

/// A client's request on the reliable channel, so that ordering is actually
/// promised for it.
class _Chat extends NetMessage<({String text})> {
  late final ParamPointer<String> text;

  @override
  void describeParams(ParamDescriptor descriptor) {
    text = descriptor.hasString(32);
  }

  @override
  void bufferFromParams(ParamBuffer message, ({String text}) params) =>
      text[message] = params.text;

  @override
  ({String text}) paramsFromBuffer(ParamBuffer message) =>
      (text: text[message]);
}

/// The host's decision, run everywhere including on the host.
class _RoundOver extends NetSignal {}

/// A client's request carrying nothing.
class _Ready extends NetSignal {}

class _NetGame extends Game {
  @override
  GameState createState() => _NetState();
}

class _NetState extends GameState<_NetGame> with MultiplayerState<_NetGame> {
  /// What every handler on this machine has seen, in order.
  final List<String> log = <String>[];

  late final _Fire fire;
  late final _Chat chat;
  late final _Score score;
  late final _RoundOver roundOver;
  late final _Ready ready;

  @override
  void describeNetwork(NetDescriptor descriptor) {
    descriptor.transport(LoopbackNetTransport());

    fire = descriptor.has(_Fire(), id: 'fire', channel: NetChannel.unreliable);
    descriptor.hasHandler(
      fire,
      (params, from) =>
          log.add('fire ${params.angle} w${params.weapon} <- ${from.slot}'),
    );

    chat = descriptor.has(_Chat(), id: 'chat');
    descriptor.hasHandler(
      chat,
      (params, from) => log.add('say ${params.text}'),
    );

    score = descriptor.has(_Score(), id: 'score', to: NetTarget.clients);
    descriptor.hasHandler(
      score,
      (params, from) => log.add('score ${params.score}'),
    );

    roundOver = descriptor.has(
      _RoundOver(),
      id: 'roundOver',
      to: NetTarget.everyone,
    );
    descriptor.hasSignal(roundOver, (from) => log.add('over <- ${from.slot}'));

    ready = descriptor.has(_Ready(), id: 'ready');
    descriptor.hasSignal(ready, (from) => log.add('ready <- ${from.slot}'));
  }
}

/// Hears the roster events, to prove they reach an ordinary listener rather
/// than only the system that fires them.
class _Watcher extends GameSystem with NetPeerListener, NetSessionListener {
  final List<String> log = <String>[];

  @override
  void onPeerJoined(NetPeerId peer) => log.add('joined ${peer.slot}');

  @override
  void onPeerLeft(NetPeerId peer, NetDisconnectReason reason) =>
      log.add('left ${peer.slot} ${reason.name}');

  @override
  void onSessionOpened(NetSession session) => log.add('open ${session.id}');

  @override
  void onSessionClosed(NetDisconnectReason reason) =>
      log.add('closed ${reason.name}');
}

/// Byte-for-byte identical to [_Fire] apart from the class name - the rename
/// this issue is about (#141).
class _FireRenamed extends NetMessage<({double angle, int weapon})> {
  late final ParamPointer<double> angle;
  late final ParamPointer<int> weapon;

  @override
  void describeParams(ParamDescriptor descriptor) {
    angle = descriptor.hasFloat32();
    weapon = descriptor.hasUint4();
  }

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

/// One message, declared under the id a peer agreed on.
class _OneMessageState extends GameState<_NetGame>
    with MultiplayerState<_NetGame> {
  _OneMessageState(this._make, this._id);

  final NetMessageBase Function() _make;
  final String _id;

  @override
  void onMounted() {}

  @override
  void describeNetwork(NetDescriptor descriptor) {
    descriptor.transport(LoopbackNetTransport());
    final message = descriptor.has(_make(), id: _id);
    if (message is NetMessage<({double angle, int weapon})>) {
      descriptor.hasHandler(message, (params, from) {});
    }
  }
}

class _OneMessageGame extends _NetGame {
  _OneMessageGame(this._make, this._id);

  final NetMessageBase Function() _make;
  final String _id;

  @override
  GameState createState() => _OneMessageState(_make, _id);
}

/// Two messages, same id - a copy-paste that must not reach a peer.
class _CollidingState extends GameState<_NetGame>
    with MultiplayerState<_NetGame> {
  @override
  void onMounted() {}

  @override
  void describeNetwork(NetDescriptor descriptor) {
    descriptor.transport(LoopbackNetTransport());
    descriptor.has(_Fire(), id: 'same');
    descriptor.has(_FireRenamed(), id: 'same');
  }
}

class _CollidingGame extends _NetGame {
  @override
  GameState createState() => _CollidingState();
}

class _WatchedState extends _NetState {
  final _Watcher watcher = _Watcher();

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(watcher);
  }
}

class _WatchedGame extends _NetGame {
  @override
  GameState createState() => _WatchedState();
}

/// A build that declares one message more than [_NetState] - what a player on
/// last week's version looks like from here.
class _Emote extends NetSignal {}

class _SkewedState extends _NetState {
  late final _Emote emote;

  @override
  void describeNetwork(NetDescriptor descriptor) {
    emote = descriptor.has(_Emote(), id: 'emote');
    descriptor.hasSignal(emote, (from) => log.add('emote <- ${from.slot}'));
    super.describeNetwork(descriptor);
  }
}

class _SkewedGame extends _NetGame {
  @override
  GameState createState() => _SkewedState();
}

const Duration _step = Duration(milliseconds: 16);

void main() {
  final running = <Game>[];

  Future<T> boot<T extends Game>(T game) async {
    await Game.startInline(game);
    running.add(game);
    return game;
  }

  _NetState stateOf(Game game) => game.state as _NetState;

  /// One round of "everyone sends what they queued, then everyone reads what
  /// arrived". Two passes, because a reply to what lands in the first is only
  /// sent in the second.
  void exchange(List<Game> games, {int rounds = 2}) {
    for (var round = 0; round < rounds; round++) {
      for (var i = 0; i < games.length; i++) {
        games[i].state.advance(_step);
      }
    }
  }

  // #141. The handshake used to mix each message's Dart class name, so two
  // things a reader would call behaviour-preserving broke peer compatibility:
  // renaming a class, and building with --obfuscate. Measured before the fix:
  // --obfuscate rewrote `PlayerInputMessage` to `zl` and moved the hash.
  group('schema identity', () {
    int hashOf(Game game) => (game.state as MultiplayerState)
        .getSystem<NetworkSystem>()
        .registry
        .schemaHash;

    test('renaming a message class does not change the hash', () async {
      final original = await boot(_OneMessageGame(_Fire.new, 'fire'));
      final renamed = await boot(_OneMessageGame(_FireRenamed.new, 'fire'));

      expect(
        hashOf(renamed),
        hashOf(original),
        reason:
            'same id, same layout, same target and channel - only the Dart '
            'class name differs, and a rename is a refactor rather than a '
            'protocol change. This is the whole of #141.',
      );
    });

    test('a different id does change the hash', () async {
      final fire = await boot(_OneMessageGame(_Fire.new, 'fire'));
      final renamedId = await boot(_OneMessageGame(_Fire.new, 'fire.v2'));

      expect(
        hashOf(renamedId),
        isNot(hashOf(fire)),
        reason:
            'the control. If the id were not in the hash the test above '
            'would pass on a hash that had simply stopped noticing anything, '
            'and two peers would form a session over incompatible bytes.',
      );
    });

    test('two messages cannot share an id', () async {
      await expectLater(
        boot(_CollidingGame()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('"same"'), contains('_Fire')),
          ),
        ),
        reason:
            'an id is what the handshake compares, so two of them would be '
            'indistinguishable to a peer while being different here - and it '
            'is a copy-paste away',
      );
    });

    test('an id cannot be empty', () async {
      await expectLater(
        boot(_OneMessageGame(_Fire.new, '')),
        throwsA(isA<ArgumentError>()),
        reason:
            'an empty id is a forgotten id, and every message that forgot '
            'one would look like the same message',
      );
    });
  });
  tearDown(() async {
    for (var i = 0; i < running.length; i++) {
      if (running[i].isRunning) await running[i].stop();
    }
    running.clear();
    LoopbackNetTransport.reset();
  });

  test(
    'offline, a host-targeted message runs on the machine that sent it',
    () async {
      final game = await boot(_NetGame());
      final state = stateOf(game);

      state.fire((angle: 0.5, weapon: 3));

      expect(
        state.log,
        <String>['fire 0.5 w3 <- 0'],
        reason:
            'a game with nobody connected is a session of one whose host is '
            'you - which is what makes single player and hosting one code path',
      );
    },
  );

  test('a client request runs on the host and nowhere else', () async {
    final host = await boot(_NetGame());
    final client = await boot(_NetGame());
    await stateOf(host).network.host(SessionOptions(id: SessionId('AAAAAA')));
    await stateOf(client).network.join(SessionId('AAAAAA'));
    exchange(<Game>[host, client]);

    final joined = stateOf(client).network.session!.localPeer;
    stateOf(client).fire((angle: 0.25, weapon: 1));
    exchange(<Game>[client, host]);

    expect(stateOf(host).log, <String>['fire 0.25 w1 <- ${joined.slot}']);
    expect(
      stateOf(client).log,
      isEmpty,
      reason: 'the client asked the host to act; it did not act itself',
    );
  });

  test('a host decision runs on the clients and not on the host', () async {
    final host = await boot(_NetGame());
    final client = await boot(_NetGame());
    await stateOf(host).network.host(SessionOptions(id: SessionId('BBBBBB')));
    await stateOf(client).network.join(SessionId('BBBBBB'));
    exchange(<Game>[host, client]);

    stateOf(host).score((score: 4200));
    exchange(<Game>[host, client]);

    expect(stateOf(client).log, <String>['score 4200']);
    expect(stateOf(host).log, isEmpty);
  });

  test(
    'an everyone message runs on the host too, through the same bytes',
    () async {
      final host = await boot(_NetGame());
      final client = await boot(_NetGame());
      await stateOf(host).network.host(SessionOptions(id: SessionId('CCCCCC')));
      await stateOf(client).network.join(SessionId('CCCCCC'));
      exchange(<Game>[host, client]);

      stateOf(host).roundOver();
      exchange(<Game>[host, client]);

      expect(stateOf(host).log, <String>['over <- 0']);
      expect(stateOf(client).log, <String>['over <- 0']);
    },
  );

  test('a client may not send what only the host may send', () async {
    final host = await boot(_NetGame());
    final client = await boot(_NetGame());
    await stateOf(host).network.host(SessionOptions(id: SessionId('DDDDDD')));
    await stateOf(client).network.join(SessionId('DDDDDD'));
    exchange(<Game>[host, client]);

    expect(
      () => stateOf(client).score((score: 1)),
      throwsA(isA<AssertionError>()),
      reason:
          'the declaration says the host decides scores, so a client trying '
          'to is a bug in the game, caught where it is written',
    );
  });

  test('messages sent in one tick keep their order on their channel', () async {
    final host = await boot(_NetGame());
    final client = await boot(_NetGame());
    await stateOf(host).network.host(SessionOptions(id: SessionId('EEEEEE')));
    await stateOf(client).network.join(SessionId('EEEEEE'));
    exchange(<Game>[host, client]);

    stateOf(client).chat((text: 'one'));
    stateOf(client).chat((text: 'two'));
    stateOf(client).chat((text: 'three'));
    exchange(<Game>[client, host]);

    expect(stateOf(host).log, <String>['say one', 'say two', 'say three']);
  });

  test(
    'a channel orders against itself and not against the other one',
    () async {
      final host = await boot(_NetGame());
      final client = await boot(_NetGame());
      await stateOf(host).network.host(SessionOptions(id: SessionId('PPPPPP')));
      await stateOf(client).network.join(SessionId('PPPPPP'));
      exchange(<Game>[host, client]);

      final joined = stateOf(client).network.session!.localPeer;
      stateOf(client).fire((angle: 1, weapon: 2));
      stateOf(client).chat((text: 'hi'));
      stateOf(client).fire((angle: 2, weapon: 4));
      exchange(<Game>[client, host]);

      // The reliable message is not asserted to land between the two unreliable
      // ones, and must not be: the two channels are two independent streams -
      // reliable traffic waits for retransmissions that unreliable traffic
      // never waits for, so an ordering across them is one no backend can keep.
      // What *is* promised is that each channel keeps its own order.
      expect(
        stateOf(host).log.where((line) => line.startsWith('fire')),
        <String>[
          'fire 1.0 w2 <- ${joined.slot}',
          'fire 2.0 w4 <- ${joined.slot}',
        ],
      );
      expect(stateOf(host).log, contains('say hi'));
    },
  );

  test('sendTo reaches one client and not the others', () async {
    final host = await boot(_NetGame());
    final one = await boot(_NetGame());
    final two = await boot(_NetGame());
    await stateOf(host).network.host(SessionOptions(id: SessionId('FFFFFF')));
    await stateOf(one).network.join(SessionId('FFFFFF'));
    await stateOf(two).network.join(SessionId('FFFFFF'));
    exchange(<Game>[host, one, two]);

    final onlyOne = stateOf(one).network.session!.localPeer;
    stateOf(host).score.sendTo(onlyOne, (score: 7));
    exchange(<Game>[host, one, two]);

    expect(stateOf(one).log, <String>['score 7']);
    expect(stateOf(two).log, isEmpty);
  });

  test('the roster reaches an ordinary listener on both machines', () async {
    final host = await boot(_WatchedGame());
    final client = await boot(_WatchedGame());
    await stateOf(host).network.host(SessionOptions(id: SessionId('GGGGGG')));
    exchange(<Game>[host]);
    await stateOf(client).network.join(SessionId('GGGGGG'));
    exchange(<Game>[host, client]);

    final hostWatcher = (host.state as _WatchedState).watcher;
    final clientWatcher = (client.state as _WatchedState).watcher;
    final joined = stateOf(client).network.session!.localPeer;

    expect(hostWatcher.log, <String>['open GGGGGG', 'joined ${joined.slot}']);
    expect(
      clientWatcher.log,
      <String>['open GGGGGG', 'joined 0'],
      reason:
          'a peer that joins late is told about who was already there, so a '
          'listener that only handles onPeerJoined still sees everyone',
    );

    await stateOf(client).network.leave();
    exchange(<Game>[client, host]);

    expect(hostWatcher.log.last, 'left ${joined.slot} remoteClose');
    expect(clientWatcher.log.last, 'closed localClose');
  });

  test('the schema hash tracks the message declarations and nothing else', () async {
    final plain = await boot(_NetGame());
    final watched = await boot(_WatchedGame());
    final skewed = await boot(_SkewedGame());

    expect(
      stateOf(watched).network.registry.schemaHash,
      stateOf(plain).network.registry.schemaHash,
      reason:
          'the watcher adds a system, not a message - two builds that declare '
          'the same messages can talk to each other whatever else differs',
    );
    expect(
      stateOf(skewed).network.registry.schemaHash,
      isNot(stateOf(plain).network.registry.schemaHash),
      reason:
          'one extra message shifts every index after it, so the peers would '
          'read each other records as the wrong message entirely',
    );
  });
}
