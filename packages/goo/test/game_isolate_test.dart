import 'dart:async';
import 'dart:typed_data';

import 'package:goo/src/scene_handle.dart';
import 'package:goo/src/archetype.dart';
import 'package:goo/src/command/command.dart';
import 'package:goo/src/asset.dart';
import 'package:goo/src/data.dart';
import 'package:goo/src/event/fixed_loop.dart';
import 'package:goo/src/event/state.dart';
import 'package:goo/src/game.dart';
import 'package:goo/src/game_state.dart';
import 'package:goo/src/input.dart';
import 'package:goo/src/input/input_binding.dart';
import 'package:goo/src/input/input_key.dart';
import 'package:goo/src/scene.dart';
import 'package:goo/src/struct.dart';
import 'package:goo/src/system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

// The real two-isolate bring-up: `Game.start()` hands the Game subclass
// itself to Isolate.spawn, the copy on the other side builds its GameState
// and runs the fixed-tick loop, and this isolate reads the resulting
// component data straight out of shared memory (lane 1 -
// MemoryPage.resolveRead from a non-writing isolate).
//
// Both copies still run every declaration pass, which is what makes this
// possible at all: the handle copy has its own GameState mirroring the same
// scene, so archetype ids agree and the pages the game isolate announces have
// a pool to be adopted into. What separates the copies is
// GameState.isSimulating - only one of them ticks.
//
// Pacing is deliberate. `tool/ring_buffer_stress.dart` documents a real VM
// crash from driving a tight cross-isolate FFI loop inside the test runner's
// own isolate runner, and `triple_buffer_test.dart` documents why an
// unthrottled writer isn't a representative test anyway. Nothing here is a
// tight loop: the game isolate is paced by a Timer at a real (if fast) tick
// rate, and this isolate waits on tick notifications rather than spinning.
// That is the engine's actual usage, and it runs clean.

mixin _Moving on Component {
  late final DataPointer<double> x;

  /// The number of live entities the mover saw this tick, written into the
  /// *first* entity's row. This is how the main isolate learns that a
  /// command-spawned entity actually exists without needing a second
  /// message channel: it just reads the count out of shared memory.
  late final DataPointer<int> census;

  /// Set only by [_Mover.onCreated] - proves the prefab's creation hook ran
  /// on the game isolate, for both mount-time and command-time spawns.
  late final DataPointer<int> marker;

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Moving>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    x = data.hasFloat64();
    census = data.hasUint16();
    marker = data.hasUint8();
  }
}

class _Mover extends EntityStruct<_Mover> with _Moving {
  @override
  void onCreated(Entity entity) {
    super.onCreated(entity);
    marker[entity] = 7;
  }
}

class _MoverScene extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct<T>>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _MoverScene();

  late final _Mover mover;

  @override
  void describeScene(SceneDescriptor descriptor) {
    mover = descriptor.has(_Mover());
  }

  @override
  void onMounted(Scene scene) {
    scene.addEntity(mover);
  }
}

class _MoverSystem extends GameSystem with FixedTickable {
  late final Query query;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    query = descriptor.query().withAll(_Moving).build();
  }

  @override
  void onFixedUpdate() {
    var count = 0;
    Entity? first;
    for (final entity in query.run()) {
      first ??= entity;
      final moving = entity.get<_Moving>();
      // Reads see last tick's published value (see data_layout.dart), so
      // this is exactly +1 per tick regardless of system ordering.
      moving.x[entity] = moving.x[entity] + 1;
      count++;
    }
    if (first != null) first.get<_Moving>().census[first] = count;
  }
}

class _IsolateState extends GameState<_IsolateGame> with LifecycleListener {
  @override
  void onMounted() {
    loadScene(_MoverScene());
  }
}

class _IsolateGame extends Game {
  @override
  int get pageSize => 4096;

  // Fast enough to keep the test short, slow enough to be a real timer-paced
  // loop rather than the tight loop ring_buffer_stress.dart warns about.
  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  @override
  GameState createState() => _IsolateState();

  @override
  void describeSystems(SystemDescriptor descriptor) {
    descriptor.has(_MoverSystem());
  }
}

// --- auxiliary buffer fixtures -------------------------------------------

const int _pingRecordType = 3;

/// Writes one record per tick into an auxiliary buffer *it* declares - the
/// shape `GameRenderer2D` uses for the draw command lane, reduced to the one
/// thing this test is about: does the buffer exist, on both sides, addressing
/// the same native memory, before the first tick writes into it.
class _PingSystem extends GameSystem with FixedTickable {
  final Uint8List _payload = Uint8List(8);

  /// Declared on both copies, so the handle holds the same handle object's
  /// twin and reads through it with no name to agree on.
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

class _PingState extends GameState<_PingGame> with LifecycleListener {
  @override
  void onMounted() {
    loadScene(_MoverScene());
  }
}

class _PingGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  @override
  GameState createState() => _PingState();

  @override
  void describeSystems(SystemDescriptor descriptor) {
    descriptor.has(_PingSystem());
  }
}

// --- state channel fixtures ----------------------------------------------

/// Bumps a channel every tick on the game isolate. The main isolate never
/// sees this object's twin do anything - it only ever reads the channel.
class _CounterSystem extends GameSystem with FixedTickable {
  late final StateChannel<int> ticks;
  late final StateChannel<bool> alive;

  @override
  void describeState(StateDescriptor descriptor) {
    ticks = descriptor.hasInt32();
    alive = descriptor.hasBool();
  }

  @override
  void onFixedUpdate() {
    ticks.value = ticks.value + 1;
    alive.value = true;
  }
}

class _ChannelState extends GameState<_ChannelGame> with LifecycleListener {
  @override
  void onMounted() {
    loadScene(_MoverScene());
  }
}

class _ChannelGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  @override
  GameState createState() => _ChannelState();

  @override
  void describeSystems(SystemDescriptor descriptor) {
    descriptor.has(_CounterSystem());
  }
}

// --- input fixtures -------------------------------------------------------
//
// The claim under test: the raw device-state block genuinely travels
// main -> game. That is the opposite direction from every other TripleBuffer
// in the engine, so nothing about it can be inferred from the state-channel
// test above - this isolate *writes* the buffer the game isolate reads.
//
// Nothing here can be checked by comparing two objects across two heaps, so
// the game isolate publishes what its own resolution saw into state channels
// and this isolate reads those back out of shared memory.

class _InputProbeSystem extends GameSystem with FixedTickable {
  late final Input<bool> fire;
  late final Input<Vector2> move;

  late final StateChannel<bool> fireHeld;
  late final StateChannel<int> presses;
  late final StateChannel<int> releases;
  late final StateChannel<double> moveX;

  @override
  void describeInputs(InputDescriptor input) {
    fire = input.has<bool>(const TriggerBinding(.spacebar));
    move = input.has<Vector2>(
      const Vec2Binding(up: .w, down: .s, left: .a, right: .d),
    );
  }

  @override
  void describeState(StateDescriptor descriptor) {
    fireHeld = descriptor.hasBool();
    presses = descriptor.hasInt32();
    releases = descriptor.hasInt32();
    moveX = descriptor.hasFloat64();
  }

  @override
  void onFixedUpdate() {
    fireHeld.value = fire.value;
    moveX.value = move.value.x;
    if (fire.wasPressedThisFrame) presses.value = presses.value + 1;
    if (fire.wasReleasedThisFrame) releases.value = releases.value + 1;
  }
}

class _InputProbeState extends GameState<_InputProbeGame> with LifecycleListener {
  @override
  void onMounted() {
    loadScene(_MoverScene());
  }
}

class _InputProbeGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  @override
  GameState createState() => _InputProbeState();

  @override
  void describeSystems(SystemDescriptor descriptor) {
    descriptor.has(_InputProbeSystem());
  }
}

// --- asset fixtures -------------------------------------------------------
//
// The claim under test: `describeAssets` runs on both copies and assigns the
// same address on each, while only the copy that can decode ever pulls bytes.
// Nothing here can be checked by comparing two objects - they are on two
// heaps - so the game isolate *writes what it sees* (its own copy's address,
// and whether its own copy is loaded) into a component row, and this isolate
// reads those two integers out of shared memory and compares them against its
// own copy.

/// Top-level, so each isolate lazily initializes its *own* instance of the
/// key - which is the realistic shape (a `static final` on the prefab) and
/// keeps the key well away from the spawn message.
final _IsolateTextureAsset _isolateTexture = _IsolateTextureAsset();

class _NullSource extends GameAssetSource {
  @override
  Future<Uint8List> load() async => Uint8List(4);

  @override
  String get description => 'isolate-fixture';
}

class _IsolateTexture extends GameAssetInstance {
  int? _byteCount;

  int get byteCount {
    requireLoaded();
    return _byteCount!;
  }
}

class _IsolateTextureAsset extends GameAsset<_IsolateTexture> {
  @override
  final GameAssetSource source = _NullSource();

  @override
  _IsolateTexture createInstance() => _IsolateTexture();

  @override
  Future<void> loadInto(_IsolateTexture instance) async {
    instance._byteCount = (await source.load()).length;
  }
}

class _Textured extends EntityStruct<_Textured> {
  late final _IsolateTexture texture;

  /// What the *game isolate's* copy thinks this asset's address is.
  late final DataPointer<int> seenAddress;

  /// And whether that copy has a decoded payload - `0` there, always.
  late final DataPointer<int> seenLoaded;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    texture = descriptor.has(_isolateTexture);
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    // Seeded to a value the writer can never legitimately produce, so a row
    // that was never written fails the test instead of accidentally matching
    // address 0.
    seenAddress = data.hasInt32(-1);
    seenLoaded = data.hasInt32(-1);
  }
}

class _TexturedScene extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct<T>>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _TexturedScene();

  late final _Textured textured;

  @override
  void describeScene(SceneDescriptor descriptor) {
    textured = descriptor.has(_Textured());
  }

  @override
  void onMounted(Scene scene) {
    scene.addEntity(textured);
  }
}

/// Publishes the game isolate's view of the asset into the row every tick.
/// Not in `onCreated`: the whole point is to sample *after* the transition
/// finished, so "still not loaded" means "never loads", not "not yet".
class _TexturedSystem extends GameSystem with FixedTickable {
  late final Query query;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    query = descriptor.query().withAll(_Textured).build();
  }

  @override
  void onFixedUpdate() {
    for (final entity in query.run()) {
      final prefab = entity.get<_Textured>();
      prefab.seenAddress[entity] = prefab.texture.address;
      prefab.seenLoaded[entity] = prefab.texture.isLoaded ? 1 : 0;
    }
  }
}

class _TexturedState extends GameState<_TexturedGame> with LifecycleListener {
  @override
  void onMounted() {
    loadScene(_TexturedScene());
  }
}

class _TexturedGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  @override
  GameState createState() => _TexturedState();

  @override
  void describeSystems(SystemDescriptor descriptor) {
    descriptor.has(_TexturedSystem());
  }
}


// --- un-adopt handshake fixtures -----------------------------------------
//
// Unloading a scene frees its pages on the game isolate while the main copy
// may still be holding adopted views of them. Freeing first is a
// use-after-free that a shared-memory design cannot report - it just returns
// wrong numbers - so the free is deferred until main confirms it has let go.
// `unloadScene` is game-isolate-only by design, so main asks for it the way
// the architecture prescribes: a command.

class _DropScene extends SignalCommand {}

class _UnloadState extends GameState<_UnloadGame> with LifecycleListener {
  @override
  void onMounted() {
    loadScene(_MoverScene());
  }

  @override
  void describeCommands(CommandDescriptor descriptor) {
    descriptor.hasSignal(game.dropScene, _drop);
  }

  // Read from `loadedScenes` rather than captured from loadScene's future:
  // `onMounted` runs on **main**, before the spawn, so a `.then` callback
  // would fire on that copy and the game isolate would inherit a null. The
  // list is appended synchronously inside loadScene, so it crosses with the
  // copy already populated.
  void _drop() {
    if (loadedScenes.isNotEmpty) unloadScene(loadedScenes.first);
  }
}

class _UnloadGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  late final _DropScene dropScene;

  @override
  GameState createState() => _UnloadState();

  @override
  void describeCommands(CommandDescriptor descriptor) {
    dropScene = descriptor.has(_DropScene());
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    descriptor.has(_MoverSystem());
  }
}

/// Waits for [count] more fixed ticks to be reported by the game isolate.
Future<void> _waitTicks(Game game, int count) {
  final target = game.tick + count;
  final done = Completer<void>();
  void listener(int tick) {
    if (tick >= target && !done.isCompleted) done.complete();
  }

  game.addTickListener(listener);
  return done.future
      .timeout(const Duration(seconds: 20))
      .whenComplete(() => game.removeTickListener(listener));
}

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test(
    'a Game subclass survives Isolate.spawn and ticks on the other side',
    () async {
      final game = _IsolateGame();
      await game.start();
      addTearDown(() async {
        if (game.isRunning) await game.stop();
      });

      // start() completed, so the spawned copy got far enough to build its
      // state and hand back its command ring - the sendability question the
      // whole design rests on, answered.
      expect(game.state, isNotNull);
      expect(game.state!.isSimulating, isFalse,
          reason: 'this copy is the handle: it mirrors declarations and reads '
              'shared memory, but the tick loop is on the other isolate');
      final scene = game.state!.getScene<_MoverScene>();
      final mounted = Entity.pack(scene.mover.archetypeId, 0, 0);

      await _waitTicks(game, 3);

      // Reading the game isolate's published snapshot directly - no copy, no
      // message carrying the value.
      expect(scene.mover.marker[mounted], 7,
          reason: 'the scene mounted an entity on the game isolate and its '
              'onCreated ran there');
      final firstRead = scene.mover.x[mounted];
      expect(firstRead, greaterThan(0),
          reason: 'the mover system is running on the other isolate');

      await _waitTicks(game, 5);
      final secondRead = scene.mover.x[mounted];
      expect(secondRead, greaterThan(firstRead),
          reason: 'entity state must keep changing across ticks');
      expect(scene.mover.census[mounted], 1);

      // --- a command sent from the main isolate lands, and answers --------
      //
      // The whole transport, end to end: this copy writes the request into
      // the main->game ring, the game isolate drains it inside a fixed tick
      // and runs the handler, writes the reply into the game->main ring, and
      // this copy picks it up on the next tick notification and completes the
      // future below with the entity that was actually created over there.
      final spawned = await game
          .spawnEntity(scene.mover.archetypeId)
          .timeout(const Duration(seconds: 20));
      expect(
        spawned,
        Entity.pack(
          scene.mover.archetypeId,
          0,
          scene.mover.archetype.strideBytes,
        ),
        reason: 'the created entity crossed back over the reply ring - the '
            'encode/apply lane this replaces had no way to return anything',
      );

      await _waitTicks(game, 3);
      expect(scene.mover.census[mounted], 2,
          reason: 'the ring-buffer spawn command created a second entity on '
              'the game isolate');
      expect(scene.mover.marker[spawned], 7,
          reason: 'onCreated runs for a command-spawned entity too');
      expect(scene.mover.x[spawned], greaterThan(0),
          reason: 'and the new entity is picked up by the running system');

      // The handle's own state must refuse to simulate: two loops over one
      // set of pages is exactly the corruption the split exists to prevent.
      expect(() => game.state!.runFixedStep(), throwsStateError);

      await game.stop();
      expect(game.isRunning, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'disableSystem from the main isolate stops the game isolate ticking it',
    () async {
      final game = _IsolateGame();
      await game.start();
      addTearDown(() async {
        if (game.isRunning) await game.stop();
      });

      final scene = game.state!.getScene<_MoverScene>();
      final mounted = Entity.pack(scene.mover.archetypeId, 0, 0);

      await _waitTicks(game, 3);
      expect(scene.mover.x[mounted], greaterThan(0));

      await game.disableSystem<_MoverSystem>();
      // Let the disable message land and a couple of ticks pass with it
      // applied, then take a baseline.
      await _waitTicks(game, 3);
      final frozen = scene.mover.x[mounted];
      await _waitTicks(game, 5);
      expect(scene.mover.x[mounted], frozen,
          reason: 'a disabled system must not be ticking on the game isolate');

      await game.enableSystem<_MoverSystem>();
      await _waitTicks(game, 5);
      expect(scene.mover.x[mounted], greaterThan(frozen));

      await game.stop();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'an auxiliary buffer is announced across the isolate boundary before the '
    'first tick writes to it',
    () async {
      final game = _PingGame();
      await game.start();
      addTearDown(() async {
        if (game.isRunning) await game.stop();
      });

      // The whole ordering claim in Game.describeBuffers, asserted directly:
      // start() has returned, so the announcement has already landed - even
      // though the buffer is declared by a *system*, whose declaration only
      // exists after describeSystems ran on the far side.
      expect(game.bufferCount, 1);
      final handle = game.getSystem<_PingSystem>().pings;
      expect(handle.isConnected, isTrue);
      expect(handle.ring.capacityBytes, 4096);
      expect(game.state!.isSimulating, isFalse, reason: 'this copy is the handle');

      // Paced by the game isolate's own 5ms timer and waited on via tick
      // notifications - no tight cross-isolate loop, per the note at the top
      // of this file.
      await _waitTicks(game, 4);

      final records = handle.ring.drain();
      expect(records, isNotEmpty,
          reason: 'the system on the game isolate wrote through addresses '
              'this isolate reconstructed - the same shared memory');
      final ticks = [
        for (final record in records)
          ByteData.sublistView(record.payload).getInt64(0, Endian.little),
      ];
      expect(records.every((r) => r.recordType == _pingRecordType), isTrue);
      expect(ticks.first, 1, reason: 'the very first tick was captured, so '
          'the buffer was live before the tick loop started');
      for (var i = 1; i < ticks.length; i++) {
        expect(ticks[i], ticks[i - 1] + 1, reason: 'no gaps, no reordering');
      }

      // Draining is what keeps the ring from filling; picking up again from
      // where the last drain stopped is the property the render lane leans on.
      final resumeFrom = ticks.last;
      await _waitTicks(game, 3);
      final more = [
        for (final record in handle.ring.drain())
          ByteData.sublistView(record.payload).getInt64(0, Endian.little),
      ];
      expect(more, isNotEmpty);
      expect(more.first, resumeFrom + 1);

      await game.stop();
      expect(handle.isConnected, isFalse,
          reason: 'the game isolate freed the memory; the view must go too');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'a state channel written on the game isolate is observed on the main one',
    () async {
      final game = _ChannelGame();
      await game.start();
      addTearDown(() async {
        if (game.isRunning) await game.stop();
      });

      final counter = game.getSystem<_CounterSystem>();
      // Declared on both copies, seeded before `ready`, so it reads as its
      // initial value the instant start() returns - never an unpublished
      // TripleBuffer.
      expect(counter.ticks.value, 0);
      expect(counter.alive.value, isFalse);

      // The main isolate's half of the two-speed notification: this copy
      // learns nothing until a tick message lands, and reconciles then.
      final seen = <int>[];
      void listener() => seen.add(counter.ticks.value);
      counter.ticks.addListener(listener);
      addTearDown(() => counter.ticks.removeListener(listener));

      await _waitTicks(game, 4);
      expect(counter.ticks.value, greaterThan(0),
          reason: 'the game isolate has been writing into shared memory this '
              'whole time');
      expect(counter.alive.value, isTrue);
      expect(seen, isNotEmpty,
          reason: 'and a ValueListenable listener on this isolate was told');
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThan(seen[i - 1]),
            reason: 'each notification carries a value that actually moved');
      }

      // Writing from the copy that does not own the memory is a programmer
      // error, not a silent no-op that "works" until someone wonders why the
      // simulation never noticed. Asserts are on under the test runner.
      expect(() => counter.ticks.value = 999, throwsAssertionError);
      expect(counter.ticks.value, isNot(999));

      await game.stop();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'raw input written on the main isolate reaches the game isolate\'s tick',
    () async {
      final game = _InputProbeGame();
      await game.start();
      addTearDown(() async {
        if (game.isRunning) await game.stop();
      });

      final probe = game.getSystem<_InputProbeSystem>();
      // The announcement ordering, asserted directly: start() has returned,
      // so the game isolate has already handed this copy the raw block's
      // address and this copy has built the write end over it. A GameView
      // built on the very next line has somewhere to put a key event.
      final device = game.inputDevice;
      expect(device, isNotNull,
          reason: 'this copy is the handle - the one Flutter runs on, and '
              'therefore the only one that can ever see a KeyEvent');
      expect(game.state!.isSimulating, isFalse);
      expect(probe.fire.value, isFalse,
          reason: 'this copy\'s twin of the system never resolves: its '
              'actions read their declared default forever, which is exactly '
              'what the doc on Input says happens on the non-simulating side');

      await _waitTicks(game, 3);
      expect(probe.fireHeld.value, isFalse);
      expect(probe.presses.value, 0);

      // The write that has to cross a heap boundary in the direction nothing
      // else in the engine goes.
      device!
        ..press(InputKey.spacebar)
        ..press(InputKey.d);
      await _waitTicks(game, 4);

      expect(probe.fireHeld.value, isTrue,
          reason: 'the game isolate resolved a binding against bits this '
              'isolate wrote - main -> game through the same TripleBuffer '
              'primitive the state channels use in the other direction');
      expect(probe.moveX.value, 1,
          reason: 'and composed four raw bits into a vector on that side, '
              'because resolution is the reader\'s job: only the reader has '
              'the bindings');
      expect(probe.presses.value, 1,
          reason: 'exactly one press edge, however many ticks the key was '
              'held for - edge detection is per resolution, and the key has '
              'now been down for several');
      expect(probe.releases.value, 0);

      device.release(InputKey.spacebar);
      await _waitTicks(game, 4);
      expect(probe.fireHeld.value, isFalse);
      expect(probe.releases.value, 1);
      expect(probe.presses.value, 1, reason: 'and no phantom second press');
      expect(probe.moveX.value, 1,
          reason: 'the other key is still held - releasing one bit must not '
              'republish the whole block as empty');

      await game.stop();
      expect(game.inputDevice, isNull,
          reason: 'the game isolate freed the memory; the write end must go '
              'with it');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'both copies declare an asset to the same address; only one decodes',
    () async {
      final game = _TexturedGame();
      await game.start();
      addTearDown(() async {
        if (game.isRunning) await game.stop();
      });

      final scene = game.state!.getScene<_TexturedScene>();
      final entity = Entity.pack(scene.textured.archetypeId, 0, 0);
      final here = scene.textured.texture;

      await _waitTicks(game, 4);

      expect(
        scene.textured.seenAddress[entity],
        here.address,
        reason: 'the two copies ran the same describeAssets pass in the same '
            'order on two heaps, so the address the game isolate writes into '
            'a row is exactly the one this copy resolves it by - which is the '
            'entire reason a row can hold a Uint32 instead of a reference',
      );
      expect(
        scene.textured.seenLoaded[entity],
        0,
        reason: 'and the game isolate never decoded it: decoding needs '
            'dart:ui, which is not on that isolate. It holds an addressed, '
            'unloaded instance forever, by design',
      );

      expect(
        here.isLoaded,
        isTrue,
        reason: 'while this copy - the one with Flutter attached - did load '
            'it, during loadScene\'s asynchronous half',
      );
      expect(here.byteCount, 4, reason: 'and its payload is readable here');

      await game.stop();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'unloading a scene drops the main copy page views before the memory goes',
    () async {
      final game = _UnloadGame();
      await game.start();
      addTearDown(() async {
        if (game.isRunning) await game.stop();
      });

      final scene = game.state!.getScene<_MoverScene>();
      final mounted = Entity.pack(scene.mover.archetypeId, 0, 0);

      await _waitTicks(game, 3);
      expect(scene.mover.x[mounted], greaterThan(0),
          reason: 'main is reading the game isolate page through an adopted '
              'view - which is exactly what has to be taken away safely');

      // Main cannot unload directly - `unloadScene` is game-isolate-only - so
      // it asks through a command, which is the prescribed route.
      await game.dropScene();
      await _waitTicks(game, 4);

      expect(
        () => scene.mover.x[mounted],
        throwsStateError,
        reason: 'main dropped its view of the freed page, so a stale Entity '
            'reports the unload instead of reading memory that has been '
            'handed back to the allocator',
      );

      await game.stop();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

}
