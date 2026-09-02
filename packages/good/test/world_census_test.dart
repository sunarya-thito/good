import 'dart:async';
import 'dart:typed_data';

import 'package:good/src/archetype.dart';
import 'package:good/src/command/command.dart';
import 'package:good/src/command/param.dart';
import 'package:good/src/data.dart';
import 'package:good/src/debug/world_census.dart';
import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/system.dart';
import 'package:flutter_test/flutter_test.dart';

/// The live run under test. One inline run per isolate, so a file-level
/// binding is enough - the same shape game_test.dart uses.
late Game run;

// #122 slice B1: a world census. Everything it reports is already known on the
// game isolate; what is new is a caller that can ask, and a blob that carries
// the answer back. Inline here, with `advance` driven by hand, so "the tick
// did not move" is exact rather than raced. The cross-isolate half is in
// game_isolate_test.dart, where the blob has a real ring to cross.

mixin _Grounded on Component {
  final weight = Field.uint16(3);

  final groundedType = Component.type<_Grounded>();
}

mixin _Winged on Component {
  final span = Field.uint8(1);

  final wingedType = Component.type<_Winged>();
}

class _Rock extends EntityStruct with _Grounded {}

class _Bird extends EntityStruct with _Winged {}

/// Two prefabs, so a census has two archetypes to tell apart and two
/// signatures that must not come back equal.
class _Habitat extends SceneStruct {
  late final _Rock rock;
  late final _Bird bird;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    rock = descriptor.has(_Rock.new);
    bird = descriptor.has(_Bird.new);
  }
}

class _AlphaSystem extends GameSystem with FixedTickable {
  @override
  void onFixedUpdate() {}
}

class _BetaSystem extends GameSystem with FixedTickable {
  @override
  void onFixedUpdate() {}
}

/// Carries a census back as the one `hasBytes` blob B1 is scoped to.
///
/// [resultFromBuffer] copies. A `hasBytes` read is a **view** onto the batch's
/// own buffer, which the transport reuses - so a command that handed the view
/// straight to whoever awaited it would hand them bytes that change underneath
/// them.
class _TakeCensus extends SupplierCommand<Uint8List> {
  final blob = Param.bytes();

  @override
  void bufferFromResult(ParamBuffer call, Uint8List result) =>
      blob[call] = result;

  @override
  Uint8List resultFromBuffer(ParamBuffer call) =>
      Uint8List.fromList(blob[call]);
}

/// Tick-delivered: the discriminator for the paused test. It genuinely needs a
/// fixed step, so while the tick is stopped it must stay pending.
class _NeedsTick extends SignalCommand {}

class _CensusState extends GameState<_CensusGame> {
  int tickBoundRuns = 0;

  @override
  void onMounted() {
    // Nothing loaded here on purpose: every test composes the world it is
    // about to count, so the census is checked against a composition the test
    // wrote rather than one the fixture happened to boot with.
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_AlphaSystem.new);
    descriptor.has(_BetaSystem.new);
  }

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    descriptor
      ..hasReadOnlySupplier(game.census, () => WorldCensus.of(this).encode())
      ..hasSignal(game.needsTick, () => tickBoundRuns++);
  }
}

class _CensusGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  late final _Habitat habitat;
  final census = Command.of(_TakeCensus.new);
  final needsTick = Command.of(_NeedsTick.new);

  @override
  GameState createState() => _CensusState();

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    habitat = descriptor.has(_Habitat.new);
  }
}

/// No scenes, no systems, no commands - a game that has come up and holds
/// nothing. What a census of it must not do is fail.
class _BareState extends GameState<_BareGame> {
  @override
  void onMounted() {}
}

class _BareGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _BareState();
}

Future<T> _boot<T extends Game>(T Function() create) async {
  final game = await Game.startInline(create);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

const Duration _step = Duration(milliseconds: 10);

ArchetypeCensus _archetypeNamed(WorldCensus census, String name) =>
    census.archetypes.singleWhere((a) => a.typeName == name);

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('a census of a world the test composed', () {
    test('counts entities per archetype and per scene', () async {
      final game = await _boot(_CensusGame.new);
      final state = run.state;
      final first = await state.loadScene(game.habitat);
      final second = await state.loadScene(game.habitat);

      // Three rocks in one scene, and two rocks plus four birds in the other.
      // Deliberately lopsided: an implementation that reported the archetype
      // total for both scenes, or attributed every page to the first slot,
      // has to disagree with one of the numbers below.
      for (var i = 0; i < 3; i++) {
        first.addEntity(game.habitat.rock);
      }
      for (var i = 0; i < 2; i++) {
        second.addEntity(game.habitat.rock);
      }
      for (var i = 0; i < 4; i++) {
        second.addEntity(game.habitat.bird);
      }

      final census = WorldCensus.of(state);

      expect(census.entityCount, 9);
      expect(
        census.scenes.map((s) => (s.slot, s.typeName, s.entityCount)),
        [(0, '_Habitat', 3), (1, '_Habitat', 6)],
        reason:
            'a page records `ownerSceneSlot` and nothing else, so which scene '
            'a row belongs to is read off the page it sits in',
      );
      expect(census.scenes.map((s) => s.generation), [
        0,
        0,
      ], reason: 'first load of each slot');

      final rocks = _archetypeNamed(census, '_Rock');
      final birds = _archetypeNamed(census, '_Bird');
      expect(census.archetypes.length, 2);
      expect(
        rocks.entityCount,
        5,
        reason: 'three in one scene, two in the other',
      );
      expect(birds.entityCount, 4);
      expect(
        rocks.pageCount,
        2,
        reason:
            'two loaded scenes never share a page, which is what makes one '
            'individually unloadable',
      );
      expect(
        rocks.strideBytes,
        2,
        reason: 'one uint16 field, rounded to bytes',
      );
      expect(birds.strideBytes, 1);
      expect(
        rocks.componentSignature & birds.componentSignature,
        0,
        reason:
            'two disjoint component sets, so the signatures share no bit - a '
            'census that reported one archetype\'s signature for every '
            'archetype would fail here',
      );
      expect(rocks.componentSignature, isNot(0));
      expect(birds.componentSignature, isNot(0));
      expect(census.archetypes.map((a) => a.archetypeId), [
        0,
        1,
      ], reason: 'ids in registration order, which is what an Entity packs');
    });

    test('reports every declared system and its enabled bit', () async {
      await _boot(_CensusGame.new);
      final state = run.state;

      expect(
        WorldCensus.of(state).systems
            .map((s) => (s.index, s.typeName, s.enabled)),
        [(0, '_AlphaSystem', true), (1, '_BetaSystem', true)],
      );

      state.disableSystem<_AlphaSystem>();
      final after = WorldCensus.of(state).systems;
      expect(
        after.map((s) => s.enabled),
        [false, true],
        reason:
            'disabling a system pauses it and leaves it declared, so it stays '
            'in the list with its bit down',
      );
      expect(after.map((s) => s.typeName), [
        '_AlphaSystem',
        '_BetaSystem',
      ], reason: 'and it keeps its place in execution order');
    });

    test('an unloaded scene leaves its archetypes at zero', () async {
      final game = await _boot(_CensusGame.new);
      final state = run.state;
      final scene = await state.loadScene(game.habitat);
      scene.addEntity(game.habitat.rock);
      scene.addEntity(game.habitat.bird);

      expect(WorldCensus.of(state).entityCount, 2);

      state.unloadScene(scene);
      final census = WorldCensus.of(state);

      expect(census.scenes, isEmpty, reason: 'the slot is tombstoned');
      expect(
        census.archetypes.map((a) => (a.typeName, a.entityCount, a.pageCount)),
        [('_Rock', 0, 0), ('_Bird', 0, 0)],
        reason:
            'archetype ids are process-global and are never recycled, so an '
            'archetype whose scene is gone stays visible at zero rather than '
            'disappearing',
      );
    });

    test('a destroyed entity stops being counted', () async {
      final game = await _boot(_CensusGame.new);
      final state = run.state;
      final scene = await state.loadScene(game.habitat);
      final doomed = scene.addEntity(game.habitat.rock);
      scene.addEntity(game.habitat.rock);

      expect(_archetypeNamed(WorldCensus.of(state), '_Rock').entityCount, 2);

      doomed.destroy();

      expect(
        _archetypeNamed(WorldCensus.of(state), '_Rock').entityCount,
        1,
        reason:
            'the row count is the bump cursor over the stride minus the free '
            'set, so a recycled row is subtracted rather than counted twice',
      );
      expect(
        _archetypeNamed(WorldCensus.of(state), '_Rock').pageCount,
        1,
        reason: 'the page is still held; only the row went back',
      );
    });
  });

  group('an empty world', () {
    test('is an empty census, not a failure', () async {
      await _boot(_BareGame.new);
      final census = WorldCensus.of(run.state);

      expect(census.scenes, isEmpty);
      expect(census.archetypes, isEmpty);
      expect(census.systems, isEmpty);
      expect(census.entityCount, 0);
      expect(
        WorldCensus.decode(census.encode()).entityCount,
        0,
        reason: 'and the blob for one is readable rather than a special case',
      );
    });

    test('a game with scenes declared but none loaded still has its '
        'archetypes', () async {
      await _boot(_CensusGame.new);
      final census = WorldCensus.of(run.state);

      expect(census.scenes, isEmpty);
      expect(
        census.archetypes.map((a) => (a.typeName, a.entityCount)),
        [('_Rock', 0), ('_Bird', 0)],
        reason:
            'declaring a scene registers its archetypes; loading one is what '
            'gives them pages',
      );
    });
  });

  group('the blob', () {
    test('round-trips every field', () async {
      final game = await _boot(_CensusGame.new);
      final state = run.state;
      final scene = await state.loadScene(game.habitat);
      scene.addEntity(game.habitat.rock);
      scene.addEntity(game.habitat.bird);
      scene.addEntity(game.habitat.bird);
      state.disableSystem<_BetaSystem>();
      state.advance(_step * 2);

      final taken = WorldCensus.of(state);
      final read = WorldCensus.decode(taken.encode());

      expect(read.tick, taken.tick);
      expect(
        read.tick,
        2,
        reason: 'and the tick it names is the one it ran on',
      );
      expect(
        read.scenes.map(
          (s) => (s.slot, s.generation, s.typeName, s.entityCount),
        ),
        taken.scenes.map(
          (s) => (s.slot, s.generation, s.typeName, s.entityCount),
        ),
      );
      expect(
        read.archetypes.map(
          (a) => (
            a.archetypeId,
            a.typeName,
            a.entityCount,
            a.pageCount,
            a.strideBytes,
            a.componentSignature,
          ),
        ),
        taken.archetypes.map(
          (a) => (
            a.archetypeId,
            a.typeName,
            a.entityCount,
            a.pageCount,
            a.strideBytes,
            a.componentSignature,
          ),
        ),
      );
      expect(
        read.systems.map((s) => (s.index, s.typeName, s.enabled)),
        taken.systems.map((s) => (s.index, s.typeName, s.enabled)),
      );
    });

    test('carries a signature with its top bit set', () async {
      // Bit 63 makes `bitFor`'s mask negative, which every consumer tolerates
      // because it only ever ANDs and ORs. Two uint32 words is what carries it
      // across intact; a single signed word read back unsigned would not.
      const signature = -9223372036854775808; // 1 << 63
      final blob = WorldCensus(
        tick: 1,
        scenes: const [],
        archetypes: const [
          ArchetypeCensus(
            archetypeId: 0,
            typeName: '_Rock',
            entityCount: 1,
            pageCount: 1,
            strideBytes: 2,
            componentSignature: signature,
          ),
        ],
        systems: const [],
      ).encode();

      expect(
        WorldCensus.decode(blob).archetypes.single.componentSignature,
        signature,
      );
    });

    test('refuses bytes it did not write', () async {
      await _boot(_BareGame.new);
      final good = WorldCensus.of(run.state).encode();

      expect(
        () => WorldCensus.decode(Uint8List.fromList([...good, 0])),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('left over'),
          ),
        ),
        reason:
            'a census is diagnostic output; a wrong answer beats no answer '
            'for nobody',
      );
      expect(
        () =>
            WorldCensus.decode(Uint8List.sublistView(good, 0, good.length - 1)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('ended early'),
          ),
        ),
      );
      final wrongVersion = Uint8List.fromList(good)..[0] = 99;
      expect(
        () => WorldCensus.decode(wrongVersion),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('format version 99'),
          ),
        ),
      );
    });
  });

  group('asking for one', () {
    test('answers while the game is paused, and runs no step', () async {
      final game = await _boot(_CensusGame.new);
      final state = run.state as _CensusState;
      final scene = await state.loadScene(game.habitat);
      scene.addEntity(game.habitat.rock);
      scene.addEntity(game.habitat.bird);
      expect(state.advance(_step * 2), 2);

      game.pause();

      // Queued first, so a lane that ran things in arrival order would run
      // this one ahead of the census rather than leave it waiting.
      var tickBoundDone = false;
      final tickBound = game.needsTick();
      unawaited(tickBound.then((_) => tickBoundDone = true));

      final answer = game.census();
      expect(
        state.advance(_step * 3),
        0,
        reason: 'the point of the fixture: this frame affords no fixed step',
      );

      final census = WorldCensus.decode(
        await answer.timeout(const Duration(seconds: 5)),
      );
      expect(
        census.tick,
        2,
        reason:
            'the handler ran on a frame that ran no step, so the world it '
            'counted is the one standing still at tick 2',
      );
      expect(run.tick, 2, reason: 'and the tick did not move to serve it');
      expect(census.entityCount, 2);
      expect(census.scenes.single.entityCount, 2);
      expect(census.systems.map((s) => s.typeName), [
        '_AlphaSystem',
        '_BetaSystem',
      ]);

      // A turn of the microtask queue, so a completion that was going to
      // happen has happened before this is read.
      await Future<void>.delayed(Duration.zero);
      expect(
        tickBoundDone,
        isFalse,
        reason:
            'a tick-delivered command queued at the same moment still needs a '
            'fixed step, so it has to still be pending - without this the '
            'test passes against a census that quietly ran one',
      );
      expect(state.tickBoundRuns, 0);

      game.resume();
      expect(state.advance(_step), 1);
      await tickBound.timeout(const Duration(seconds: 5));
      expect(state.tickBoundRuns, 1);
    });

    test('and at a time scale of zero, which stops the tick the other '
        'way', () async {
      final game = await _boot(_CensusGame.new);
      final state = run.state;
      final scene = await state.loadScene(game.habitat);
      scene.addEntity(game.habitat.rock);
      expect(state.advance(_step * 2), 2);

      game.setTimeScale(0);
      final answer = game.census();
      expect(state.advance(_step * 3), 0);

      final census = WorldCensus.decode(
        await answer.timeout(const Duration(seconds: 5)),
      );
      expect(census.tick, 2);
      expect(census.entityCount, 1);
      expect(run.tick, 2);
    });

    test('a running game answers it too', () async {
      final game = await _boot(_CensusGame.new);
      final state = run.state;
      final scene = await state.loadScene(game.habitat);
      scene.addEntity(game.habitat.rock);

      final answer = game.census();
      expect(state.advance(_step), 1);

      final census = WorldCensus.decode(
        await answer.timeout(const Duration(seconds: 5)),
      );
      expect(
        census.tick,
        1,
        reason:
            'the drain is on the frame, after the step, so the census reads '
            'the world this frame ended with',
      );
      expect(census.entityCount, 1);
    });
  });
}
