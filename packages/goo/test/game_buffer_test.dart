import 'dart:typed_data';

import 'package:goo/src/scene_handle.dart';
import 'package:goo/src/archetype.dart';
import 'package:goo/src/event/fixed_loop.dart';
import 'package:goo/src/game.dart';
import 'package:goo/src/game_state.dart';
import 'package:goo/src/ring_buffer.dart';
import 'package:goo/src/scene.dart';
import 'package:goo/src/struct.dart';
import 'package:goo/src/system.dart';
import 'package:flutter_test/flutter_test.dart';

// Game.describeBuffers - the generic "auxiliary RingBuffer, allocated on the
// simulating copy, announced to the handle" hook that goo2d_render's draw
// command lane is built on. Everything here runs through
// start(inline: true, autoTick: false): one copy doing both jobs, so the
// producer and consumer ends of a buffer are both reachable from the test. The
// two-isolate half of the story - the address announcement itself - is in
// game_isolate_test.dart, where a second isolate is what makes it meaningful.
//
// Note what these tests can no longer even express: there is no name to
// misspell, no undeclared name to look up, and no collision between two
// declarations of "the same" buffer. A declaration hands back a BufferHandle
// the declarer keeps in a field (RULES.md rule 6), so the whole class of
// name-based failures the old string-keyed API had is gone rather than
// tested.

const int _pingRecordType = 3;

class _Empty extends EntityStruct {}

class _EmptyScene extends SceneStruct {
  _EmptyScene();

  @override
  void describeScene(SceneDescriptor descriptor) {
    descriptor.has(_Empty());
  }
}

/// Writes one record per tick carrying the tick number - the minimal shape of
/// what GameRenderer2D does with its draw buffer.
class _PingSystem extends GameSystem with FixedTickable {
  final Uint8List _payload = Uint8List(8);

  late final BufferHandle pings;

  @override
  void describeBuffers(BufferDescriptor descriptor) {
    pings = descriptor.has(capacityBytes: 4096);
  }

  @override
  void onFixedUpdate() {
    ByteData.sublistView(_payload).setInt64(0, game.tick + 1, Endian.little);
    pings.ring.tryWrite(_pingRecordType, _payload);
  }
}

class _BufferState extends GameState<_BufferGame> {
  @override
  void onMounted() {
    loadScene(_EmptyScene());
  }
}

class _BufferGame extends Game {
  @override
  int get pageSize => 4096;

  late final BufferHandle gameBuffer;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _BufferState();

  @override
  void describeSystems(SystemDescriptor descriptor) {
    descriptor.has(_PingSystem());
  }

  @override
  void describeBuffers(BufferDescriptor descriptor) {
    gameBuffer = descriptor.has(capacityBytes: 1024);
  }
}

/// Two declarations from the same source. Under the old string-keyed API this
/// was the "name collision" case; now it is simply two independent buffers,
/// which is what two declarations always meant.
class _TwoBufferGame extends _BufferGame {
  late final BufferHandle second;

  @override
  void describeBuffers(BufferDescriptor descriptor) {
    super.describeBuffers(descriptor);
    second = descriptor.has(capacityBytes: 2048);
  }
}

class _TinyBufferGame extends _BufferGame {
  @override
  void describeBuffers(BufferDescriptor descriptor) {
    descriptor.has(capacityBytes: RingBuffer.headerBytes);
  }
}

/// No systems, no buffers - the "declared nothing" baseline.
class _BareState extends GameState<_BareGame> {
  @override
  void onMounted() {
    loadScene(_EmptyScene());
  }
}

class _BareGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _BareState();
}

Future<T> _start<T extends Game>(T game) async {
  await game.start(inline: true, autoTick: false);
  addTearDown(() async {
    if (game.isRunning) await game.stop();
  });
  return game;
}

const Duration _step = Duration(milliseconds: 10);

List<int> _drainTicks(RingBuffer ring) {
  final records = ring.drain();
  return [
    for (final record in records)
      if (record.recordType == _pingRecordType)
        ByteData.sublistView(record.payload).getInt64(0, Endian.little),
  ];
}

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('declaration', () {
    test('the game and its systems both contribute, in declaration order',
        () async {
      final game = await _start(_BufferGame());
      expect(game.bufferCount, 2);
      expect(game.gameBuffer.index, 0,
          reason: "the Game's own describeBuffers runs before any system's");
      expect(game.getSystem<_PingSystem>().pings.index, 1);
    });

    test('a declared buffer is a real RingBuffer at the declared capacity',
        () async {
      final game = await _start(_BufferGame());
      final pings = game.getSystem<_PingSystem>().pings;
      expect(game.gameBuffer.capacityBytes, 1024);
      expect(game.gameBuffer.ring.capacityBytes, 1024);
      expect(pings.ring.capacityBytes, 4096);
      expect(game.gameBuffer.ring, isNot(same(pings.ring)));
    });

    test('declaring nothing costs nothing', () async {
      final game = await _start(_BareGame());
      expect(game.bufferCount, 0);
    });

    test('two declarations are two buffers, not a collision', () async {
      final game = await _start(_TwoBufferGame());
      expect(game.bufferCount, 3);
      expect(game.second.index, 1,
          reason: 'indices follow declaration order across every source');
      expect(game.gameBuffer.ring, isNot(same(game.second.ring)));
      expect(game.second.ring.capacityBytes, 2048);
    });

    test('a capacity with no room for a payload is rejected', () {
      expect(_TinyBufferGame().start(inline: true, autoTick: false),
          throwsArgumentError);
    });
  });

  group('resolution', () {
    test('nothing resolves before start - describeBuffers has not run yet', () {
      final game = _BufferGame();
      expect(game.bufferCount, 0);
      // The handle field is `late final` and unwritten: reading it is a
      // LateInitializationError naming the field, which is the whole rule-6
      // payoff - there is no string to get wrong and no map to come up empty.
      expect(() => game.gameBuffer, throwsA(isA<Error>()));
    });

    test('a system holds its own handle, over the same memory the game sees',
        () async {
      final game = await _start(_BufferGame());
      final system = game.getSystem<_PingSystem>();
      expect(system.pings.isConnected, isTrue);
      expect(system.pings.ring.bufferAddress,
          isNot(game.gameBuffer.ring.bufferAddress));
    });
  });

  group('traffic', () {
    test('a system writing every tick is drained in order by the consumer',
        () async {
      final game = await _start(_BufferGame());
      final ring = game.getSystem<_PingSystem>().pings.ring;

      expect(_drainTicks(ring), isEmpty, reason: 'nothing has ticked yet');

      game.state!.advance(_step * 3);
      expect(_drainTicks(ring), [1, 2, 3]);

      game.state!.advance(_step * 2);
      expect(_drainTicks(ring), [4, 5],
          reason: 'a drain consumes - the next one only sees what came after');
    });

    test('the buffer survives a tick in which nothing else happens', () async {
      final game = await _start(_BufferGame());
      game.state!.advance(_step * 2);
      expect(game.gameBuffer.ring.drain(), isEmpty,
          reason: 'the game-declared buffer has no producer in this fixture');
    });

    test('records accumulate across ticks until someone drains', () async {
      final game = await _start(_BufferGame());
      // 100 records x 16 bytes - well short of the ring's 4096, so this is
      // testing accumulation, not the overflow policy. One advance per step
      // rather than one big one, because advance() caps itself at
      // maxFixedStepsPerAdvance.
      for (var i = 0; i < 100; i++) {
        game.state!.advance(_step);
      }
      expect(_drainTicks(game.getSystem<_PingSystem>().pings.ring).length, 100);
    });
  });

  group('shutdown', () {
    test('stop() releases the buffers this copy allocated', () async {
      final game = await _start(_BufferGame());
      final pings = game.getSystem<_PingSystem>().pings;
      game.state!.advance(_step);
      await game.stop();
      expect(pings.isConnected, isFalse,
          reason: 'the native memory is freed; a view over it must not linger');
      // The declaration outlives the allocation, which is what makes the
      // "declared but not connected" message reachable rather than an
      // indistinguishable "no such buffer".
      expect(game.bufferCount, 2);
      expect(() => pings.ring, throwsStateError);
      expect(pings.tryRing, isNull);
    });
  });
}
