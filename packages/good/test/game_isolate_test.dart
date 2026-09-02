import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:good/src/scene_handle.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/command/command.dart';
import 'package:good/src/command/param.dart';
import 'package:good/src/asset.dart';
import 'package:good/src/data.dart';
import 'package:good/src/debug/world_census.dart';
import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/event/tick_loop.dart';
import 'package:good/src/event/lifecycle.dart';
import 'package:good/src/event/state.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/input.dart';
import 'package:good/src/input/input_binding.dart';
import 'package:good/src/input/input_key.dart';
import 'package:good/src/random.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

/// The live run under test. A `GameHandle`, not an `InlineGameHandle`: every
/// test in this file spawns a real isolate, so the world is on the other side
/// and unreachable from here by design.
/// The running game under test. `Game.start` hands the instance straight
/// back now, so there is one binding rather than a game and a handle - see
/// `Game.start`'s doc on why the two collapsed.
late Game run;

// The real two-isolate bring-up: `Game.start()` hands the Game subclass
// itself to Isolate.spawn, and the copy on the other side builds its GameState
// and runs the fixed-tick loop.
//
// Every assertion about the world therefore comes through a StateChannel,
// because that is the only way a number gets here: this isolate registers no
// archetypes and holds no pages, so it cannot read a column even in principle.
// That is not a testing workaround - it is the split these tests exist to
// pin, and a system publishing what it saw is what a real game does too.
//
// Pacing is deliberate. `tool/ring_buffer_stress.dart` documents a real VM
// crash from driving a tight cross-isolate FFI loop inside the test runner's
// own isolate runner, and `triple_buffer_test.dart` documents why an
// unthrottled writer isn't a representative test anyway. Nothing here is a
// tight loop: the game isolate is paced by a Timer at a real (if fast) tick
// rate, and this isolate waits on tick notifications rather than spinning.
// That is the engine's actual usage, and it runs clean.

mixin _Moving on Component {
  final x = Field.float64();

  /// The number of live entities the mover saw this tick, written into the
  /// *first* entity's row. This is how the main isolate learns that a
  /// command-spawned entity actually exists without needing a second
  /// message channel: it just reads the count out of shared memory.
  final census = Field.uint16();

  /// Set only by [_Mover.onMounted] - proves the prefab's creation hook ran
  /// on the game isolate, for both mount-time and command-time spawns.
  final marker = Field.uint8();

  final movingType = Component.type<_Moving>();
}

class _Mover extends EntityStruct with _Moving, EntityLifecycleListener {
  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    marker[entity] = 7;
  }
}

class _MoverScene extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _MoverScene();

  late final _Mover mover;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    mover = descriptor.has(_Mover.new);
  }

  @override
  void onSceneMounted(Scene scene) {
    scene.addEntity(mover);
  }
}

class _MoverSystem extends GameSystem with FixedTickable {
  final query = Query.all(_Moving);

  /// What this system tells the main isolate.
  ///
  /// Main cannot read a component row any more - it registers no archetypes
  /// and holds no pages - so anything a test over there wants to assert has to
  /// come through the presentation lane. That is not a testing workaround; it
  /// is the architecture the split exists to enforce, and asserting through it
  /// is asserting the real thing.
  _IsolateGame get _own => game as _IsolateGame;
  StateChannel<double> get firstX => _own.firstX;
  StateChannel<int> get population => _own.population;
  StateChannel<int> get firstMarker => _own.firstMarker;

  @override
  void onFixedUpdate() {
    var count = 0;
    Entity? first;
    for (final entity in query.run()) {
      first ??= entity;
      final moving = entity<_Moving>().component;
      // Reads see last tick's published value (see data_layout.dart), so
      // this is exactly +1 per tick regardless of system ordering.
      moving.x[entity] = moving.x[entity] + 1;
      count++;
    }
    population.value = count;
    if (first != null) {
      final moving = first<_Moving>().component;
      moving.census[first] = count;
      firstX.value = moving.x[first];
      firstMarker.value = moving.marker[first];
    }
  }
}

/// "Spawn a mover" - a game-declared command, replacing the framework's
/// deleted `spawnEntity(archetypeId)`.
///
/// Main names the intent; the handler, over on the game isolate, is what turns
/// that into a prefab. Nothing about an archetype id crosses the boundary.
class _SpawnMover extends SupplierCommand<Entity> {
  final spawned = Param.entity();

  @override
  void bufferFromResult(ParamBuffer call, Entity result) =>
      spawned[call] = result;

  @override
  Entity resultFromBuffer(ParamBuffer call) => spawned[call];
}

/// "Pause the mover" - the prescribed route for a main-triggered system
/// toggle, replacing the deleted `Game.disableSystem<T>()`.
///
/// Main cannot name a system by declaration index any more, because it holds
/// no declarations to index into. It says what it *means* and the handler,
/// over where the systems are, resolves that to a type.

/// Two signals that do exactly the same thing and differ only in how they are
/// delivered, so a test can tell the two carriers apart (#142).
class _ResumeByControl extends SignalCommand {}

class _ResumeByTick extends SignalCommand {}

/// Tries the one thing #245 measured as reporting nothing at all - a spawn
/// from a receipt-delivered handler - and publishes what came back, because a
/// receipt handler has no reply leg to throw through.
class _ControlProbe extends SignalCommand {}

class _PauseMover extends SinkCommand<bool> {
  final paused = Param.uint1();

  @override
  void bufferFromParams(ParamBuffer call, bool params) =>
      paused[call] = params ? 1 : 0;

  @override
  bool paramsFromBuffer(ParamBuffer call) => paused[call] != 0;
}

class _IsolateState extends GameState<_IsolateGame> {
  final _MoverScene level = _MoverScene();

  @override
  void onMounted() {
    loadScene(level);
  }

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    descriptor
      ..hasSupplier(game.spawnMover, _onSpawnMover)
      ..hasSink(game.pauseMover, _onPauseMover)
      ..hasControlSignal(game.resumeByControl, () => paused = false)
      ..hasControlSignal(game.controlProbe, _onControlProbe)
      ..hasSignal(game.resumeByTick, () => paused = false);
  }

  Entity _onSpawnMover() => loadedScenes.single.addEntity(level.mover);

  void _onControlProbe() {
    try {
      loadedScenes.single.addEntity(level.mover);
      // Publishing on a channel from a receipt handler is deliberately still
      // allowed - it is the answer leg this lane has - so this line reaching
      // main at all is half of what the test reads.
      game.probeRefused.value = 2;
    } on StateError {
      game.probeRefused.value = 1;
    }
  }

  void _onPauseMover(bool paused) {
    if (paused) {
      disableSystem<_MoverSystem>();
    } else {
      enableSystem<_MoverSystem>();
    }
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_MoverSystem.new);
  }
}

/// A system that throws on its third tick, on the game isolate, with a real
/// timer driving it - the shape #126 was filed about.
class _DyingSystem extends GameSystem with FixedTickable {
  int ran = 0;

  @override
  void onFixedUpdate() {
    ran++;
    if (ran == 3) throw StateError('system boom on the game isolate');
  }
}

class _DyingState extends GameState<_DyingGame> {
  @override
  void onMounted() {}

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_DyingSystem.new);
  }
}

class _DyingGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  @override
  GameState createState() => _DyingState();
}

/// Draws on the game isolate and publishes what it got, so main can see that
/// the simulating copy really is the one advancing the stream (#125).
class _RandomReporter extends GameSystem with FixedTickable {
  @override
  void onFixedUpdate() {
    final game = state.game as _RandomIsolateGame;
    game.drawn.value = game.rolls.nextInt(1000000);
  }
}

class _RandomIsolateState extends GameState<_RandomIsolateGame> {
  @override
  void onMounted() {}

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_RandomReporter.new);
  }
}

class _RandomIsolateGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  @override
  int get randomSeed => 777;

  final rolls = RandomStream.of();
  final drawn = Channel.int32(-1);

  @override
  GameState createState() => _RandomIsolateState();
}

class _IsolateGame extends Game {
  @override
  int get pageSize => 4096;

  // Fast enough to keep the test short, slow enough to be a real timer-paced
  // loop rather than the tight loop ring_buffer_stress.dart warns about.
  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  late final _SpawnMover spawnMover;
  late final _PauseMover pauseMover;
  late final _ResumeByControl resumeByControl;
  late final _ResumeByTick resumeByTick;
  late final _ControlProbe controlProbe;

  /// What `_MoverSystem` publishes. Declared here because main is the copy
  /// that allocates the storage - and main is also the only reader, which is
  /// what a state channel is for.
  final firstX = Channel.float64();
  final population = Channel.int32();
  final firstMarker = Channel.int32();

  /// 1 when the spawn in `_onControlProbe` was refused, 2 when it went
  /// through. Starts at 0, so a handler that never ran is distinguishable
  /// from one that ran and was refused.
  final probeRefused = Channel.int32();

  @override
  GameState createState() => _IsolateState();

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    spawnMover = descriptor.has(_SpawnMover.new);
    pauseMover = descriptor.has(_PauseMover.new);
    resumeByControl = descriptor.has(_ResumeByControl.new);
    resumeByTick = descriptor.has(_ResumeByTick.new);
    controlProbe = descriptor.has(_ControlProbe.new);
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

  /// Declared by the `Game`, on main, before the spawn - which is the only
  /// copy that can allocate. This system, on the game isolate, reads the
  /// handle back off it and writes through the same native memory.
  BufferHandle get pings => (game as _PingGame).pings;

  @override
  void onFixedUpdate() {
    ByteData.sublistView(_payload).setInt64(0, state.tick + 1, Endian.little);
    pings.ring.tryWrite(_pingRecordType, _payload);
  }
}

class _PingState extends GameState<_PingGame> {
  @override
  void onMounted() {
    loadScene(_MoverScene());
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_PingSystem.new);
  }
}

class _PingGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  /// Declared here on behalf of `_PingSystem`. Buffers are allocated on this
  /// copy before the spawn; the system that fills it exists only on the other.
  late final BufferHandle pings;

  @override
  GameState createState() => _PingState();

  @override
  void describeBuffers(BufferDescriptor descriptor) {
    super.describeBuffers(descriptor);
    pings = descriptor.has(capacityBytes: 4096);
  }
}

// --- state channel fixtures ----------------------------------------------

/// Bumps a channel every tick on the game isolate. This object does not exist
/// on the main isolate at all - main only ever reads the channel.
class _CounterSystem extends GameSystem with FixedTickable {
  /// Declared on the `Game` and written here. The channel is the only thing
  /// main can see of this system at all - it holds no copy of it.
  StateChannel<int> get ticks => (game as _ChannelGame).ticks;
  StateChannel<bool> get alive => (game as _ChannelGame).alive;

  @override
  void onFixedUpdate() {
    ticks.value = ticks.value + 1;
    alive.value = true;
  }
}

class _ChannelState extends GameState<_ChannelGame> {
  @override
  void onMounted() {
    loadScene(_MoverScene());
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_CounterSystem.new);
  }
}

class _ChannelGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  final ticks = Channel.int32();
  final alive = Channel.boolean();

  @override
  GameState createState() => _ChannelState();
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

  /// Declared on the `Game`; written here. `describeInputs` below *stays* on
  /// the system, and the contrast is the point: an action allocates nothing -
  /// the raw block is a fixed size whatever a game declares, and only this
  /// copy ever resolves against it - while a channel is native memory main
  /// reserves before the spawn.
  _InputProbeGame get _own => game as _InputProbeGame;
  StateChannel<bool> get fireHeld => _own.fireHeld;
  StateChannel<int> get presses => _own.presses;
  StateChannel<int> get releases => _own.releases;
  StateChannel<double> get moveX => _own.moveX;

  @override
  void describeInputs(InputDescriptor input) {
    super.describeInputs(input);
    fire = input.has<bool>(const TriggerBinding(.spacebar));
    move = input.has<Vector2>(
      const Vec2Binding(up: .w, down: .s, left: .a, right: .d),
    );
  }

  @override
  void onFixedUpdate() {
    fireHeld.value = fire.value;
    moveX.value = move.value.x;
    if (fire.wasPressedThisFrame) presses.value = presses.value + 1;
    if (fire.wasReleasedThisFrame) releases.value = releases.value + 1;
  }
}

class _InputProbeState extends GameState<_InputProbeGame> {
  @override
  void onMounted() {
    loadScene(_MoverScene());
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_InputProbeSystem.new);
  }
}

class _InputProbeGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  final fireHeld = Channel.boolean();
  final presses = Channel.int32();
  final releases = Channel.int32();
  final moveX = Channel.float64();

  @override
  GameState createState() => _InputProbeState();
}

// --- asset fixtures -------------------------------------------------------
//
// The claim under test: asset declaration runs on both copies and assigns the
// same address on each, while only the copy that can decode ever pulls bytes.
// Nothing here can be checked by comparing two objects - they are on two
// heaps - so the game isolate *writes what it sees* (its own copy's address,
// and whether its own copy is loaded) into a component row, and this isolate
// reads those two integers out of shared memory and compares them against its
// own copy.

/// Top-level, so each isolate initializes its *own* instance of the key -
/// which is the realistic shape and keeps the key well away from the spawn
/// message.
///
/// Two copies of a `const` key are one asset now, by value, which is exactly
/// the property this file's cross-isolate agreement rests on: the copy that
/// arrives in a load request equals the one the game isolate declared.
const AssetKey<_IsolateTexture> _isolateTexture = AssetKey<_IsolateTexture>(
  _NullSource('isolate-fixture'),
);

class _NullSource extends AssetSource {
  const _NullSource(this.name);

  final String name;

  @override
  Future<Uint8List> load() async => Uint8List(4);

  @override
  Future<AssetAvailability> check() async => AssetAvailability.present;

  @override
  String get description => name;

  @override
  bool operator ==(Object other) => other is _NullSource && other.name == name;

  @override
  int get hashCode => Object.hash(_NullSource, name);
}

/// The decoded payload. Plain - `Asset<T>` is the addressed thing now.
class _IsolateTexture {
  _IsolateTexture(this.byteCount);

  final int byteCount;
}

class _IsolateTextureLoader extends AssetLoader<_IsolateTexture> {
  const _IsolateTextureLoader();

  @override
  Future<_IsolateTexture> load(AssetKey<_IsolateTexture> key) async =>
      _IsolateTexture((await key.source.load()).length);
}

class _Textured extends EntityStruct {
  final texture = Asset.of(_isolateTexture);

  // Both seeded to a value the writer can never legitimately produce, so a row
  // that was never written fails the test instead of accidentally matching
  // address 0.

  /// What the *game isolate's* copy thinks this asset's address is.
  final seenAddress = Field.int32(-1);

  /// And whether that copy has a decoded payload - `0` there, always.
  final seenLoaded = Field.int32(-1);
}

class _TexturedScene extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _TexturedScene();

  late final _Textured textured;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    textured = descriptor.has(_Textured.new);
  }

  @override
  void onSceneMounted(Scene scene) {
    scene.addEntity(textured);
  }
}

/// Publishes the game isolate's view of the asset - into the row, and out
/// through a channel main can actually read.
///
/// Not in `onMounted`: the whole point is to sample *after* the transition
/// finished, so "still not loaded" means "never loads", not "not yet".
class _TexturedSystem extends GameSystem with FixedTickable {
  final query = Query.all(_Textured);

  _TexturedGame get _own => game as _TexturedGame;
  StateChannel<int> get reportedAddress => _own.reportedAddress;
  StateChannel<int> get reportedLoaded => _own.reportedLoaded;

  @override
  void onFixedUpdate() {
    for (final entity in query.run()) {
      final prefab = entity<_Textured>().component;
      prefab.seenAddress[entity] = prefab.texture.pack();
      prefab.seenLoaded[entity] = prefab.texture.isLoaded ? 1 : 0;
      // The row write above still happens, and is still read back on this
      // isolate - it is what proves an address survives a round trip through
      // native storage. The channels are how the answer reaches main, which
      // cannot resolve a row at all.
      reportedAddress.value = prefab.seenAddress[entity];
      reportedLoaded.value = prefab.seenLoaded[entity];
    }
  }
}

class _TexturedState extends GameState<_TexturedGame> {
  @override
  void onMounted() {
    loadScene(_TexturedScene());
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_TexturedSystem.new);
  }
}

class _TexturedGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  final reportedAddress = Channel.int32(-1);
  final reportedLoaded = Channel.int32(-1);

  @override
  GameState createState() => _TexturedState();
}

// --- runtime loadScene, and the asset decode round-trip ------------------
//
// A scene *declared* at boot (so both copies hold its declaration and agree
// on its asset addresses) but *loaded* later, from the game isolate, at
// runtime. That is the case where the game isolate has to ask main to decode:
// it owns the declaration and cannot decode, main can decode and is never
// asked unless told.
//
// Before `Game.requestAssetLoad` existed this silently did nothing.
// `_reconcileAssets` took its claims and hit `if (!game.decodesAssets)
// return;`, so the scene came up with an addressed, permanently unloaded
// asset. It looked correct only because main happened to run `loadScene`
// itself during boot in every test that existed.

const AssetKey<_IsolateTexture> _lateTexture = AssetKey<_IsolateTexture>(
  _NullSource('late-fixture'),
);

class _LateProp extends EntityStruct {
  final texture = Asset.of(_lateTexture);
}

class _LateScene extends SceneStruct {
  late final _LateProp prop;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    prop = descriptor.has(_LateProp.new);
  }

  @override
  void onSceneMounted(Scene scene) {
    scene.addEntity(prop);
  }
}

/// Asks the game isolate to load the declared-but-unloaded scene. A command,
/// because `loadScene` is game-isolate-only and this is how main asks.
class _LoadLate extends SignalCommand {}

/// And to unload it again, so the payload main is holding gets dropped.
class _UnloadLate extends SignalCommand {}

class _LateState extends GameState<_LateGame> {
  Scene? _loadedLate;

  @override
  void onMounted() {
    // Deliberately loads nothing: the scene is declared, not loaded, so the
    // load under test happens later and on the other isolate.
  }

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    descriptor
      ..hasSignal(game.loadLate, _load)
      ..hasSignal(game.unloadLate, _unload);
  }

  void _load() {
    // The progress callback runs on *this* isolate, driven by the per-asset
    // messages main sends back as it decodes - so publishing it to a channel
    // is the only way the test can see that lane worked at all.
    // `loadScene` declares the asset synchronously, before its first await, so
    // the address exists to publish the moment this returns.
    loadScene(
      game.lateScene,
      onProgress: (report) => game.progress.value = report.progress,
    ).then((scene) => _loadedLate = scene);
    game.lateAddress.value = game.assets.tryGet(_lateTexture)!.pack();
  }

  void _unload() {
    final scene = _loadedLate;
    if (scene != null) unloadScene(scene);
  }
}

class _LateGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  late final _LateScene lateScene;
  late final _LoadLate loadLate;
  late final _UnloadLate unloadLate;
  final progress = Channel.float64(-1);

  /// The address the *game isolate* assigned this scene's texture, published
  /// so main can name it. Main cannot look the asset up by key: the key it
  /// holds is a different object from the one that was declared (see
  /// `Assets.adoptAt`), so an address is the only shared name.
  final lateAddress = Channel.int32(-1);

  @override
  GameState createState() => _LateState();

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    lateScene = descriptor.has(_LateScene.new);
  }

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    loadLate = descriptor.has(_LoadLate.new);
    unloadLate = descriptor.has(_UnloadLate.new);
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

class _UnloadState extends GameState<_UnloadGame> {
  @override
  void onMounted() {
    loadScene(_MoverScene());
  }

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
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

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_MoverSystem.new);
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
    super.describeCommands(descriptor);
    dropScene = descriptor.has(_DropScene.new);
  }
}

// --- #165 slice 0: adopting a reply while the fixed tick is stopped --------
//
// The direction here is game -> main, which is the one the issue's original
// framing missed. The game isolate asks main something from its presentation
// pass; main answers on the very next ping, because `presentFrame` fires on a
// zero-step frame too. What was missing is the last hop: nothing on the game
// side read the answer back out of the ring, because the only drain lived
// inside `runFixedStep`.

/// Main-destination and tick-delivered, so its reply comes back over the ring
/// and only an adopt on the asking side completes it.
class _AskMain extends SupplierCommand<int> {
  final answer = Param.int32();

  @override
  void bufferFromResult(ParamBuffer call, int result) => answer[call] = result;

  @override
  int resultFromBuffer(ParamBuffer call) => answer[call];
}

/// Game-destination and tick-delivered, sent from the same presentation pass.
/// The control for the test: this one genuinely needs a fixed step, so it
/// stays pending for as long as the tick is stopped and discriminates against
/// a "fix" that quietly runs one.
class _AskGame extends SignalCommand {}

/// Tells the game isolate to start asking. Control-delivered, so it lands
/// while the tick is stopped.
class _StartAsking extends SignalCommand {}

/// Does the asking from the presentation pass, which is the one game-isolate
/// hook a paused game still runs.
class _AskingSystem extends GameSystem with Tickable {
  @override
  void onTick(Duration delta) {
    final asking = state as _AskingState;
    if (!asking.shouldAsk) return;
    asking.shouldAsk = false;
    asking.ask();
  }
}

class _AskingState extends GameState<_AskingGame> {
  /// Set by the control signal, read by the next presentation pass.
  bool shouldAsk = false;

  @override
  void onMounted() {
    // No scene: the question is about the command lanes, and a world would
    // only add pages to this test.
  }

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    descriptor
      ..hasControlSignal(game.startAsking, () => shouldAsk = true)
      ..hasSignal(game.askGame, () => game.gameAnswered.value = 1);
  }

  /// Fires both commands in one presentation pass, so they are queued at the
  /// same moment and differ only in where their handler lives.
  void ask() {
    game.askedTick.value = game.tick;
    game.asked.value = 1;
    unawaited(
      game.askMain().then((value) {
        game.mainAnswer.value = value;
        game.answeredTick.value = game.tick;
        game.answeredStopped.value = paused || timeScale == 0 ? 1 : 0;
        game.mainAnswered.value = 1;
      }),
    );
    // Dropped rather than awaited: while the tick is stopped this one is
    // supposed to stay pending, and stopping the game errors it.
    unawaited(game.askGame().catchError((Object _) {}));
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_AskingSystem.new);
  }
}

class _AskingGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  late final _AskMain askMain;
  late final _AskGame askGame;
  late final _StartAsking startAsking;

  /// Counted on this copy, because this is where the handler runs - the game
  /// isolate holds the same closure and never dispatches it.
  int mainHandlerRuns = 0;

  final asked = Channel.int32();
  final mainAnswered = Channel.int32();
  final gameAnswered = Channel.int32();
  final mainAnswer = Channel.int32(-1);
  final askedTick = Channel.int32(-1);
  final answeredTick = Channel.int32(-1);
  final answeredStopped = Channel.int32(-1);

  @override
  GameState createState() => _AskingState();

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    askMain = descriptor.has(_AskMain.new);
    askGame = descriptor.has(_AskGame.new);
    startAsking = descriptor.has(_StartAsking.new);
    descriptor.hasSupplier(askMain, () {
      mainHandlerRuns++;
      return 41 + mainHandlerRuns;
    });
  }
}

/// One way of stopping the fixed tick, with its undo - so the two routes
/// that were measured to behave identically are tested identically.
typedef _StopRoute = (
  String label,
  void Function(Game) stop,
  void Function(Game) start,
);

/// Polls [ready] on the wall clock rather than on ticks, because everything
/// this waits for happens while the tick is stopped.
Future<bool> _waitStopped(bool Function() ready) async {
  for (var i = 0; i < 150; i++) {
    if (ready()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return ready();
}

// --- #165 slice 1: main asking a paused game, over the ring ----------------
//
// The other direction from slice 0, and the one it left open. Answering here
// means running a handler on the game isolate, and the only thing that ran a
// handler was the pump inside `runFixedStep` - so a paused game could be asked
// nothing at all. The read-only lane is a second inbox drained from `advance`,
// which runs on a frame that afforded no step.

/// Read-only and handled on the **game** isolate: reports the tick it ran on
/// and whether the simulation was stopped while it ran. That second field is
/// the only way this side learns a fact the other copy holds - main cannot
/// read `paused` (#246).
class _ReadPaused extends SupplierCommand<({int tick, bool stopped})> {
  final atTick = Param.int32();
  final wasStopped = Param.uint1();

  @override
  void bufferFromResult(ParamBuffer call, ({int tick, bool stopped}) result) {
    atTick[call] = result.tick;
    wasStopped[call] = result.stopped ? 1 : 0;
  }

  @override
  ({int tick, bool stopped}) resultFromBuffer(ParamBuffer call) =>
      (tick: atTick[call], stopped: wasStopped[call] == 1);
}

/// Read-only, answering with the ordinal of its own arrival - so this side can
/// see the order the lane ran things in after they have crossed a ring.
class _ReadOrder extends SupplierCommand<int> {
  final ordinal = Param.int32();

  @override
  void bufferFromResult(ParamBuffer call, int result) => ordinal[call] = result;

  @override
  int resultFromBuffer(ParamBuffer call) => ordinal[call];
}

/// Tick-delivered, handled on the game isolate. The discriminator: it needs a
/// fixed step, so while the tick is stopped it must stay pending.
class _NeedsTick extends SignalCommand {}

class _PausedAskState extends GameState<_PausedAskGame> {
  int arrivals = 0;

  @override
  void onMounted() {
    // No scene: the question is about the command lanes.
  }

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    descriptor
      ..hasReadOnlySupplier(
        game.readPaused,
        () => (tick: game.tick, stopped: paused || timeScale == 0),
      )
      ..hasReadOnlySupplier(game.readOrder, () => ++arrivals)
      ..hasSignal(game.needsTick, () => game.tickRan.value += 1);
  }
}

class _PausedAskGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  late final _ReadPaused readPaused;
  late final _ReadOrder readOrder;
  late final _NeedsTick needsTick;

  /// Written by the tick-delivered handler on the game isolate, so this side
  /// can see whether it has run without waiting on its future.
  final tickRan = Channel.int32();

  @override
  GameState createState() => _PausedAskState();

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    readPaused = descriptor.has(_ReadPaused.new);
    readOrder = descriptor.has(_ReadOrder.new);
    needsTick = descriptor.has(_NeedsTick.new);
  }
}

/// Polls [ready] once per reported tick, up to [within] ticks.
///
/// Ticks rather than wall-clock: the thing being waited on is driven by the
/// game isolate's loop, so counting its ticks is what makes this reliable on a
/// loaded CI machine rather than a timing guess.
Future<bool> _waitUntil(
  Game run,
  bool Function() ready, {
  int within = 40,
}) async {
  for (var i = 0; i < within; i++) {
    if (ready()) return true;
    await _waitTicks(run, 1);
  }
  return ready();
}

/// Waits for [count] more fixed ticks to be reported by the game isolate.
///
/// Through `runHandle.runtime` rather than a public hook: tick listening is
/// framework plumbing (the state channels' own reconciliation rides it) and
/// is not API, so a test that wants to *wait for a tick* reaches for the
/// internal spelling. A game waiting on the simulation publishes a value with
/// `Channel.*` and listens to that instead.
Future<void> _waitTicks(Game run, int count) {
  final target = run.tick + count;
  final done = Completer<void>();
  void listener(int tick) {
    if (tick >= target && !done.isCompleted) done.complete();
  }

  final runtime = run.runtimeOrNull!;
  runtime.addTickListener(listener);
  return done.future
      .timeout(const Duration(seconds: 20))
      .whenComplete(() => runtime.removeTickListener(listener));
}

// --- #122 B1: a world census, across the boundary --------------------------
//
// The inline half is in world_census_test.dart. This is the half that can
// actually fail on its own: main and the game isolate hold two copies of the
// `Game`, and only one of them registers archetypes, loads scenes or holds
// systems. A census that read the registries on this side would answer
// "empty world" about a world that is simply somewhere else, and would do it
// without an error - so the blob has to be produced over there and carried
// back, and only a spawned run proves it is.

mixin _Counted on Component {
  final weight = Field.uint16(2);

  final countedType = Component.type<_Counted>();
}

class _Pebble extends EntityStruct with _Counted {}

class _CensusScene extends SceneStruct {
  late final _Pebble pebble;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    pebble = descriptor.has(_Pebble.new);
  }

  @override
  void onSceneMounted(Scene scene) {
    for (var i = 0; i < 5; i++) {
      scene.addEntity(pebble);
    }
  }
}

class _IdleSystem extends GameSystem with FixedTickable {
  @override
  void onFixedUpdate() {}
}

class _SleepySystem extends GameSystem with FixedTickable {
  @override
  void onFixedUpdate() {}
}

/// The census blob, as the one `hasBytes` parameter B1 is scoped to.
///
/// [resultFromBuffer] copies, because a `hasBytes` read hands back a view onto
/// the batch's own buffer and the transport reuses those bytes.
class _TakeWorldCensus extends SupplierCommand<Uint8List> {
  final blob = Param.bytes();

  @override
  void bufferFromResult(ParamBuffer call, Uint8List result) =>
      blob[call] = result;

  @override
  Uint8List resultFromBuffer(ParamBuffer call) => Uint8List.fromList(blob[call]);
}

/// Disables one system on the game isolate, so the enabled bits this side
/// reads are ones this side asked for rather than ones the fixture was born
/// with.
class _SleepASystem extends SignalCommand {}

class _CensusIsolateState extends GameState<_CensusIsolateGame> {
  final _CensusScene level = _CensusScene();

  @override
  void onMounted() {
    loadScene(level);
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_IdleSystem.new);
    descriptor.has(_SleepySystem.new);
  }

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    descriptor
      ..hasReadOnlySupplier(
        game.censusBlob,
        () => WorldCensus.of(this).encode(),
      )
      ..hasControlSignal(game.sleepASystem, disableSystem<_SleepySystem>);
  }
}

class _CensusIsolateGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  late final _TakeWorldCensus censusBlob;
  late final _SleepASystem sleepASystem;

  @override
  GameState createState() => _CensusIsolateState();

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    censusBlob = descriptor.has(_TakeWorldCensus.new);
    sleepASystem = descriptor.has(_SleepASystem.new);
  }
}

// --- #123: which isolate registers an asset decoder ------------------------
//
// `AssetLoaders` is a per-isolate static map, so the question "who registers"
// is really "on which copy". `describeAssetLoaders` is called from
// `Game._bootMain`, which main runs before the spawn and the game isolate
// never runs at all - so the decoder exists exactly where decoding happens and
// nowhere else. That is asserted from both sides below, because a hook wired
// into the declaration passes *both* copies run would still look right from
// main.

class _LoaderProbe {}

class _ProbeInfo extends AssetInfo {
  const _ProbeInfo();
}

class _LoaderProbeLoader extends AssetLoader<_LoaderProbe> {
  const _LoaderProbeLoader();

  @override
  Future<_LoaderProbe> load(AssetKey<_LoaderProbe> key) async => _LoaderProbe();

  @override
  AssetInfo describe(_LoaderProbe value) => const _ProbeInfo();
}

/// Publishes what the *game* isolate can see of the registry.
class _RegistrarSystem extends GameSystem with FixedTickable {
  _RegistrarGame get _own => game as _RegistrarGame;

  @override
  void onFixedUpdate() {
    _own.registeredHere.value = AssetLoaders.isRegistered<_LoaderProbe>()
        ? 1
        : 0;
  }
}

class _RegistrarState extends GameState<_RegistrarGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_RegistrarSystem.new);
  }
}

class _RegistrarGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  final registeredHere = Channel.int32(-1);

  @override
  void describeAssetLoaders(AssetLoaderRegistrar loaders) {
    super.describeAssetLoaders(loaders);
    loaders.register<_LoaderProbe>(const _LoaderProbeLoader());
  }

  @override
  GameState createState() => _RegistrarState();
}

void main() {
  // Registered on *this* isolate only, and that is the point rather than an
  // omission: this is the copy with Flutter attached, so it is the only one
  // that decodes. The spawned game isolate declares the same assets, hands
  // out the same addresses and writes them into rows without ever needing a
  // loader - which is what the tests below assert directly.
  setUp(
    () => AssetLoaders.register<_IsolateTexture>(const _IsolateTextureLoader()),
  );

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
    AssetLoaders.reset();
  });

  // #126. Before this, a system throwing on the game isolate killed it and
  // nothing on this side was told: the tick stopped, `isRunning` went on
  // answering true, and `stop()` waited forever for a message from an isolate
  // that no longer existed. That last part is why this test asserts on
  // `stop()` completing and not only on the error arriving - a test that
  // checked the report alone would pass with the hang still there, and a
  // thirty-second timeout is a miserable way to find that out.
  test('a dead game isolate is reported, and can still be stopped', () async {
    final errors = <Object>[];
    late Game game;

    await runZonedGuarded(() async {
          game = await Game.start(_DyingGame.new);
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          while (game.isRunning &&
              errors.isEmpty &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }, (Object error, StackTrace stack) => errors.add(error)) ??
        Future<void>.value();

    expect(
      game.isRunning,
      isFalse,
      reason:
          'the isolate is gone, so the handle must stop claiming otherwise - '
          'this is what makes shutDown return instead of waiting',
    );
    expect(
      errors,
      isNotEmpty,
      reason:
          'the death has to reach this isolate. Dart error port aside there '
          'is no channel for it: GameCommand is main -> game, a StateChannel '
          'carries only numbers and bools, describeBuffers is the bulk lane.',
    );
    expect(
      errors.first.toString(),
      contains('system boom on the game isolate'),
      reason: 'and it has to carry what actually went wrong',
    );

    // The whole point: this completes rather than hanging.
    await game.stop().timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('stop() hung on a dead isolate - the #126 bug'),
    );
  });

  // #142 Stage 1. The two tests below are a pair and have to fail
  // independently: one says a control command reaches a stopped game, the
  // other says a tick command does not. Only the first would pass on an
  // implementation that quietly made everything receipt-delivered, and that
  // would destroy the guarantee `runFixedStep` gives a tick-delivered
  // handler - that it runs inside the write window.

  // #142 Stage 2. `Game.pause` and `Game.resume` used to be string tags on
  // the control port; they are commands now. This is the test that says the
  // migration kept the property the tags had - resume reaches a game whose
  // tick is stopped - and it is the one that fails if any of the four
  // engine commands regresses to tick delivery.
  //
  // The existing #117 and #124 tests drive `GameState` directly, so they pin
  // the semantics but never touch the carrier. This one goes through the
  // main-isolate API a pause button would use.

  // #125. Randomness is simulation state, so only the simulating copy may
  // move it. Asserting that the game isolate draws correctly would pass on an
  // implementation where *both* copies draw and quietly disagree - so the
  // load-bearing half of this test is the refusal on main.
  test('only the simulating copy advances a stream', () async {
    final game = await Game.start(_RandomIsolateGame.new);
    run = game;
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });

    expect(
      await _waitUntil(run, () => game.drawn.value >= 0),
      isTrue,
      reason: 'the game isolate draws, and publishes what it got',
    );

    expect(
      () => game.rolls.nextInt(1000),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('does not own the simulation'),
        ),
      ),
      reason:
          'this copy is the handle. A draw here would advance a stream the '
          'game isolate knows nothing about, and the two would stop agreeing '
          'about a sequence that is supposed to replay.',
    );

    expect(
      () => game.rolls.intFor(const Entity(0), 10),
      throwsA(isA<StateError>()),
      reason:
          'and the per-entity form too - it needs the tick, which this copy '
          'does not have in any meaningful sense',
    );
  });
  test('pause and resume cross as commands, with the tick stopped', () async {
    final game = await Game.start(_IsolateGame.new);
    run = game;
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });
    await _waitTicks(run, 3);

    game.pause();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final stopped = run.tick;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(
      run.tick,
      stopped,
      reason: 'the tick has to be genuinely stopped for resume to be a test',
    );

    game.resume();
    await _waitTicks(run, 1);
    expect(
      run.tick,
      greaterThan(stopped),
      reason:
          'resume is receipt-delivered, so it lands in the port callback. '
          'Tick-delivered it could never arrive - the command that restarts '
          'the tick would be pumped by the tick it stopped.',
    );
  });

  // The other two public controls on the same migrated path. A scale of zero
  // stops the tick exactly as pause does, so restoring it has the same
  // problem to solve, and stepOnce only means anything while stopped.
  test('time scale and stepOnce cross as commands too', () async {
    final game = await Game.start(_IsolateGame.new);
    run = game;
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });
    await _waitTicks(run, 3);

    game.setTimeScale(0);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final stopped = run.tick;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(run.tick, stopped, reason: 'a zero scale runs no fixed ticks');

    game.stepOnce();
    await _waitTicks(run, 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      run.tick,
      stopped + 1,
      reason:
          'exactly one step, delivered while nothing was ticking - which is '
          'the only time stepping is worth anything',
    );

    game.setTimeScale(1);
    await _waitTicks(run, 1);
    expect(
      run.tick,
      greaterThan(stopped + 1),
      reason: 'and restoring the scale reaches a game that is not ticking',
    );
  });
  test('a control command reaches a game whose tick is stopped', () async {
    final game = await Game.start(_IsolateGame.new);
    run = game;
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });
    await _waitTicks(run, 3);

    game.pause();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final stopped = run.tick;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      run.tick,
      stopped,
      reason: 'the tick has to be genuinely stopped for this to mean anything',
    );

    // Carried over the control port and run in the port callback. Nothing
    // pumps a ring here, because nothing is ticking to pump it.
    await game.resumeByControl().timeout(const Duration(seconds: 5));
    await _waitTicks(run, 1);

    expect(
      run.tick,
      greaterThan(stopped),
      reason:
          'the handler set paused = false, so the tick came back. Sent as a '
          'tick-delivered command this could never arrive - the message that '
          'restarts the tick would be waiting on the tick it stopped.',
    );
  });

  test('a control handler is refused the world on the game isolate', () async {
    final game = await Game.start(_IsolateGame.new);
    run = game;
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });
    await _waitTicks(run, 3);

    game.pause();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final stopped = run.tick;

    // Runs in the port callback on the game isolate, with the tick genuinely
    // stopped. The handler catches its own refusal and publishes what it saw,
    // because a receipt-delivered handler has no reply leg to throw back
    // through - which is also what makes this the real configuration and not
    // the inline stand-in: the transport, the pool and the state all crossed
    // an `Isolate.spawn` before this ran.
    await game.controlProbe().timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(
      game.probeRefused.value,
      1,
      reason:
          'addEntity from a receipt handler was the second row of #245 and it '
          'reported nothing at all. A guard bound to the wrong pool copy '
          'across the spawn would read 2 here',
    );
    expect(
      run.tick,
      stopped,
      reason: 'and nothing restarted the tick behind the test',
    );
  });

  test('a tick command does not reach a game whose tick is stopped', () async {
    final game = await Game.start(_IsolateGame.new);
    run = game;
    addTearDown(() async {
      if (run.isRunning) await run.stop();
      // The batch never ran, so its future never completes - dropped rather
      // than awaited, which is the failure mode this test exists to pin.
    });
    await _waitTicks(run, 3);

    game.pause();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final stopped = run.tick;

    // Same handler body, same command shape, tick-delivered instead. It sits
    // in the ring with nothing to drain it.
    var completed = false;
    unawaited(
      game
          .resumeByTick()
          .then<void>((_) {
            completed = true;
          })
          .catchError((Object _) {
            // Stopping the game errors every batch it never answered, which is
            // this one and is correct. Swallowed so an expected failure does not
            // surface as an unhandled async error at teardown.
          }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(
      run.tick,
      stopped,
      reason:
          'a tick-delivered command is pumped from runFixedStep, so a stopped '
          'tick never sees it - which is the whole reason control delivery '
          'had to exist',
    );
    expect(
      completed,
      isFalse,
      reason: 'and its future is still waiting, because nothing ran it',
    );

    // Let the game go so teardown can stop it.
    await game.resumeByControl().timeout(const Duration(seconds: 5));
  });

  // #165 slice 0. Both routes into a stopped tick, because both were measured
  // to behave identically and a fix that served one and not the other would
  // be a fix aimed at the wrong thing.
  for (final route in <_StopRoute>[
    ('pause()', (game) => game.pause(), (game) => game.resume()),
    (
      'setTimeScale(0)',
      (game) => game.setTimeScale(0),
      (game) => game.setTimeScale(1),
    ),
  ]) {
    final (label, stopIt, startIt) = route;
    test('$label adopts a reply main has already written', () async {
      final game = await Game.start(_AskingGame.new);
      run = game;
      addTearDown(() async {
        if (run.isRunning) await run.stop();
      });
      await _waitTicks(run, 3);

      stopIt(game);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final stopped = run.tick;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        run.tick,
        stopped,
        reason: 'the tick has to be stopped for any of this to mean anything',
      );

      // Control-delivered, so it lands in the port callback and the next
      // presentation pass does the asking.
      await game.startAsking().timeout(const Duration(seconds: 5));
      expect(
        await _waitStopped(() => game.asked.value == 1),
        isTrue,
        reason:
            'the presentation pass runs on a zero-step frame, so a paused game '
            'can still send',
      );

      expect(
        await _waitStopped(() => game.mainAnswered.value == 1),
        isTrue,
        reason:
            'main ran the handler and wrote the reply into the ring on its '
            'per-tick ping, which keeps arriving while the tick is stopped. '
            'Before #165 nothing on the game side ever read it back out: the '
            'only drain was inside runFixedStep, so the caller waited out the '
            'pause for an answer that already existed.',
      );

      expect(
        game.answeredStopped.value,
        1,
        reason:
            'and it completed while the simulation was still stopped, not '
            'after something quietly restarted it',
      );
      expect(
        game.answeredTick.value,
        game.askedTick.value,
        reason: 'the tick did not move across the answer',
      );
      expect(
        run.tick,
        stopped,
        reason: 'seen from this side too - no step was run to serve the ask',
      );
      expect(game.mainAnswer.value, 42, reason: 'the reply carried its value');
      expect(game.mainHandlerRuns, 1, reason: 'answered by main, exactly once');

      // The discriminator. A tick-delivered command queued in the same
      // presentation pass needs a fixed step and must still be waiting, which
      // is what a fix built on stepOnce would fail.
      expect(
        game.gameAnswered.value,
        0,
        reason:
            'a game-destination command queued at the same moment is still '
            'pending, so nothing ran a fixed step to answer the other one',
      );

      startIt(game);
      expect(
        await _waitStopped(() => game.gameAnswered.value == 1),
        isTrue,
        reason:
            'and it drains on resume exactly as it always did - adopting '
            'replies early takes nothing away from the tick lane',
      );
    });
  }

  // #165 slice 1. Both stop routes again, for the same reason: they were
  // measured to behave identically, and a lane that served one and not the
  // other would be aimed at the wrong thing.
  for (final route in <_StopRoute>[
    ('pause()', (game) => game.pause(), (game) => game.resume()),
    (
      'setTimeScale(0)',
      (game) => game.setTimeScale(0),
      (game) => game.setTimeScale(1),
    ),
  ]) {
    final (label, stopIt, startIt) = route;
    test('$label answers a read-only command from main', () async {
      final game = await Game.start(_PausedAskGame.new);
      run = game;
      addTearDown(() async {
        if (run.isRunning) await run.stop();
      });
      await _waitTicks(run, 3);

      stopIt(game);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final stopped = run.tick;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        run.tick,
        stopped,
        reason: 'the tick has to be stopped for any of this to mean anything',
      );

      // Sent *first*, so a lane that ran arrivals in one order would run this
      // one ahead of the read-only ask rather than leave it waiting.
      var tickBoundDone = false;
      final tickBound = game.needsTick();
      unawaited(
        tickBound.then((_) {
          tickBoundDone = true;
        }).catchError((Object _) {}),
      );

      final answer = await game.readPaused().timeout(
        const Duration(seconds: 5),
      );

      expect(
        answer.stopped,
        isTrue,
        reason:
            'the handler ran on the game isolate and reported from there that '
            'the simulation was stopped while it ran. Before this lane '
            'existed the only thing that ran a handler was the pump inside '
            'runFixedStep, so this await never returned while paused (#165)',
      );
      expect(
        answer.tick,
        stopped,
        reason: 'and it read the same tick this side is looking at',
      );
      expect(
        run.tick,
        stopped,
        reason: 'the tick did not move to serve the ask',
      );

      // The discriminator. Give anything that was going to happen time to
      // happen: this is a real isolate, and the ping arrives every frame.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        tickBoundDone,
        isFalse,
        reason:
            'a tick-delivered command sent at the same moment still needs a '
            'fixed step, so it has to still be pending - without this the '
            'test passes against a fix that quietly runs one, which is what '
            'stepOnce already does',
      );
      expect(
        game.tickRan.value,
        0,
        reason: 'seen from the game side too - its handler has not run',
      );

      // Order within the lane, after crossing a ring rather than a list.
      final ordered = await Future.wait(<Future<int>>[
        game.readOrder(),
        game.readOrder(),
        game.readOrder(),
      ]).timeout(const Duration(seconds: 5));
      expect(
        ordered,
        <int>[1, 2, 3],
        reason:
            'one queue, fed from the ring in arrival order and drained from '
            'the front',
      );
      expect(run.tick, stopped, reason: 'still no step, three answers later');

      startIt(game);
      await tickBound.timeout(const Duration(seconds: 5));
      expect(
        await _waitStopped(() => game.tickRan.value == 1),
        isTrue,
        reason:
            'and the tick lane delivers on resume exactly as it always did - '
            'the read-only lane takes nothing away from it',
      );
    });
  }

  test('a read-only command works on a running game too', () async {
    final game = await Game.start(_PausedAskGame.new);
    run = game;
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });
    await _waitTicks(run, 3);

    final tickBound = game.needsTick();
    final answer = await game.readPaused().timeout(const Duration(seconds: 5));
    expect(
      answer.stopped,
      isFalse,
      reason: 'nothing about this lane depends on the game being stopped',
    );
    expect(
      answer.tick,
      greaterThan(0),
      reason: 'it read a tick the running simulation had actually reached',
    );

    await tickBound.timeout(const Duration(seconds: 5));
    expect(
      await _waitStopped(() => game.tickRan.value == 1),
      isTrue,
      reason:
          'and the tick-delivered command sent alongside it still arrives on '
          'its own schedule',
    );
  });

  // #122 B1. The inline half of this is in world_census_test.dart; what a
  // spawned run adds is the only thing that can distinguish a census from a
  // census that quietly read the wrong copy's registries. #165's guard-binding
  // bug was caught the same way.
  group('a world census', () {
    test('crosses the boundary while the game is paused', () async {
      final game = await Game.start(_CensusIsolateGame.new);
      run = game;
      addTearDown(() async {
        if (run.isRunning) await run.stop();
      });
      await _waitTicks(run, 3);

      game.pause();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final stopped = run.tick;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        run.tick,
        stopped,
        reason: 'the tick has to be stopped for any of this to mean anything',
      );

      expect(
        ArchetypeRegistry.count,
        0,
        reason:
            'this side registered nothing, so a census assembled here would '
            'report an empty world - which is the failure a spawned run '
            'catches and an inline one cannot',
      );
      expect(SceneRegistry.slotCount, 0);

      final census = WorldCensus.decode(
        await game.censusBlob().timeout(const Duration(seconds: 5)),
      );

      expect(census.tick, stopped, reason: 'it counted the world standing still');
      expect(run.tick, stopped, reason: 'and the tick did not move to serve it');
      expect(census.entityCount, 5);
      expect(
        census.scenes.map((s) => (s.slot, s.typeName, s.entityCount)),
        [(0, '_CensusScene', 5)],
        reason: 'one scene, mounted with five entities in onSceneMounted',
      );
      expect(
        census.archetypes.map((a) => (a.typeName, a.entityCount, a.strideBytes)),
        [('_Pebble', 5, 2)],
      );
      expect(census.archetypes.single.componentSignature, isNot(0));
      expect(
        census.systems.map((s) => (s.index, s.typeName, s.enabled)),
        [(0, '_IdleSystem', true), (1, '_SleepySystem', true)],
      );
    });

    test('reports an enabled bit this side changed', () async {
      final game = await Game.start(_CensusIsolateGame.new);
      run = game;
      addTearDown(() async {
        if (run.isRunning) await run.stop();
      });
      await _waitTicks(run, 3);
      game.pause();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await game.sleepASystem();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final census = WorldCensus.decode(
        await game.censusBlob().timeout(const Duration(seconds: 5)),
      );
      expect(
        census.systems.map((s) => (s.typeName, s.enabled)),
        [('_IdleSystem', true), ('_SleepySystem', false)],
        reason:
            'the census reads the systems the game isolate holds now, not the '
            'set it booted with - so a disable that crossed on the control '
            'lane is visible on the read-only one',
      );
    });

    test('the copy that does not simulate refuses to take one', () async {
      final game = await Game.start(_CensusIsolateGame.new);
      run = game;
      addTearDown(() async {
        if (run.isRunning) await run.stop();
      });

      // This side's `GameState` exists only to re-run the declaration passes.
      // It never ticks and its registries stay empty, so a census taken from
      // it would be empty for a reason that has nothing to do with the world.
      final here = run.runtimeOrNull!.state!;
      expect(here.isSimulating, isFalse);
      expect(
        () => WorldCensus.of(here),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('does not own the simulation'),
              contains('hasReadOnlySupplier'),
            ),
          ),
        ),
      );
    });
  });

  test(
    'a Game subclass survives Isolate.spawn and ticks on the other side',
    () async {
      final game = await Game.start(_IsolateGame.new);
      run = game;
      addTearDown(() async {
        if (run.isRunning) await run.stop();
      });

      // start() completed, so the spawned copy got far enough to build its
      // state and hand back its command ring - the sendability question the
      // whole design rests on, answered.
      expect(run.isRunning, isTrue);

      // The world is *not* here, and asserting that is no longer possible -
      // which is the point, and a stronger property than what these lines used
      // to check. There were four assertions here: that this copy's state was
      // non-null, that it was not simulating, that it had loaded no scenes,
      // and that `singleScene` threw. All of them reached the mirror through
      // `Game.state`, so all of them are gone with it: `run` is a `GameHandle`,
      // not an `InlineGameHandle`, and `run.state` does not compile.
      //
      // "Unreachable" beats "reachable but empty". The evidence that survives
      // is further down - a component read on this isolate throws, naming the
      // presentation-only rule.

      final mover =
          game; // the channels live on the Game; main holds no systems
      expect(
        await _waitUntil(
          run,
          () => mover.firstMarker.value == 7 && mover.firstX.value > 0,
        ),
        isTrue,
        reason:
            'the scene mounted an entity on the game isolate and its '
            'onEntityMounted ran there',
      );
      final firstRead = mover.firstX.value;

      expect(
        await _waitUntil(
          run,
          () => mover.firstX.value > firstRead && mover.population.value == 1,
        ),
        isTrue,
        reason: 'entity state must keep changing across ticks',
      );

      // --- a command sent from the main isolate lands, and answers --------
      //
      // The whole transport, end to end: this copy writes the request into
      // the main->game ring, the game isolate drains it inside a fixed tick
      // and runs the handler, writes the reply into the game->main ring, and
      // this copy picks it up on the next tick notification and completes the
      // future below with the entity that was actually created over there.
      final spawned = await game.spawnMover().timeout(
        const Duration(seconds: 20),
      );

      expect(
        await _waitUntil(run, () => mover.population.value == 2),
        isTrue,
        reason:
            'the ring-buffer spawn command created a second entity on '
            'the game isolate',
      );

      final second = await game.spawnMover().timeout(
        const Duration(seconds: 20),
      );
      expect(
        second,
        isNot(spawned),
        reason:
            'a real handle crossed back over the reply ring, twice, '
            'naming two different rows - the encode/apply lane this '
            'replaces could not return anything at all',
      );
      expect(
        await _waitUntil(run, () => mover.population.value == 3),
        isTrue,
      );

      // And the entity that came back is deliberately **not** readable here.
      // It is a valid handle on the isolate that made it and meaningless on
      // this one; the diagnostic says so rather than indexing an empty table.
      expect(
        () => spawned<_Moving>().component,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('presentation-only'),
          ),
        ),
        reason:
            'main holds no archetypes, so a component read is not a '
            'slow path here - it is a category error, and has to report as one',
      );

      // "The handle's own state refuses to simulate" was asserted here.
      // It cannot be any more, and does not need to be: this copy has no
      // state to call `runFixedStep` on. Two tick loops over one set of
      // pages is now unrepresentable rather than guarded.

      await run.stop();
      expect(run.isRunning, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'a command from the main isolate stops the game isolate ticking a system',
    () async {
      final game = await Game.start(_IsolateGame.new);
      run = game;
      addTearDown(() async {
        if (run.isRunning) await run.stop();
      });

      expect(await _waitUntil(run, () => game.firstX.value > 0), isTrue);

      // Main cannot call `disableSystem` any more: it holds no systems and so
      // no index to name one by. It sends a command that says what it means,
      // and the handler - on the isolate where the systems actually are -
      // resolves that to a type. The old `Game.disableSystem<T>()` and its
      // `_msgDisable` control message are gone with the system list.
      await game.pauseMover(true).timeout(const Duration(seconds: 20));
      // Let a couple of ticks pass with it applied, then take a baseline.
      await _waitTicks(run, 3);
      final frozen = game.firstX.value;
      await _waitTicks(run, 5);
      expect(
        game.firstX.value,
        frozen,
        reason:
            'a disabled system must not be ticking on the game isolate - '
            'and a frozen channel is the honest evidence, since the system '
            'that publishes it is the one that stopped',
      );

      await game.pauseMover(false).timeout(const Duration(seconds: 20));
      expect(await _waitUntil(run, () => game.firstX.value > frozen), isTrue);

      await run.stop();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'an auxiliary buffer is announced across the isolate boundary before the '
    'first tick writes to it',
    () async {
      final game = await Game.start(_PingGame.new);
      run = game;
      addTearDown(() async {
        if (run.isRunning) await run.stop();
      });

      // The whole ordering claim in Game.describeBuffers, asserted directly:
      // start() has returned, so the announcement has already landed - even
      // though the buffer is declared by a *system*, whose declaration only
      // exists after describeSystems ran on the far side.
      expect(game.bufferCount, 1);
      final handle = game.pings;
      expect(handle.isConnected, isTrue);
      expect(handle.ring.capacityBytes, 4096);
      expect(run.isRunning, isTrue, reason: 'this copy is the handle');

      // Paced by the game isolate's own 5ms timer and waited on via tick
      // notifications - no tight cross-isolate loop, per the note at the top
      // of this file.
      await _waitTicks(run, 4);

      final records = handle.ring.drain();
      expect(
        records,
        isNotEmpty,
        reason:
            'the system on the game isolate wrote through addresses '
            'this isolate reconstructed - the same shared memory',
      );
      final ticks = [
        for (final record in records)
          ByteData.sublistView(record.payload).getInt64(0, Endian.little),
      ];
      expect(records.every((r) => r.recordType == _pingRecordType), isTrue);
      expect(
        ticks.first,
        1,
        reason:
            'the very first tick was captured, so '
            'the buffer was live before the tick loop started',
      );
      for (var i = 1; i < ticks.length; i++) {
        expect(ticks[i], ticks[i - 1] + 1, reason: 'no gaps, no reordering');
      }

      // Draining is what keeps the ring from filling; picking up again from
      // where the last drain stopped is the property the render lane leans on.
      final resumeFrom = ticks.last;
      await _waitTicks(run, 3);
      final more = [
        for (final record in handle.ring.drain())
          ByteData.sublistView(record.payload).getInt64(0, Endian.little),
      ];
      expect(more, isNotEmpty);
      expect(more.first, resumeFrom + 1);

      await run.stop();
      expect(
        handle.isConnected,
        isFalse,
        reason: 'the game isolate freed the memory; the view must go too',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'a state channel written on the game isolate is observed on the main one',
    () async {
      final game = await Game.start(_ChannelGame.new);
      run = game;
      addTearDown(() async {
        if (run.isRunning) await run.stop();
      });

      final counter = game;
      // Declared on both copies, seeded before `ready`, so it reads as its
      // initial value the instant start() returns - never an unpublished
      // TripleBuffer.
      expect(counter.ticks.value, 0);
      expect(counter.alive.value, isFalse);

      // The main isolate's half of the two-speed notification: this copy
      // learns nothing until a tick message lands, and reconciles then.
      final seen = <int>[];
      final observed = Completer<void>();
      void listener() {
        seen.add(counter.ticks.value);
        if (!observed.isCompleted && seen.length >= 3) {
          observed.complete();
        }
      }
      counter.ticks.addListener(listener);
      addTearDown(() => counter.ticks.removeListener(listener));

      // `alive` is written `true` on every one of those same ticks, so it is
      // the witness for "a notification means the published value moved": it
      // moves once, false -> true, and every write after that publishes the
      // value already there. However many ticks land, at most one
      // notification may come out of it.
      final aliveSeen = <bool>[];
      void aliveListener() => aliveSeen.add(counter.alive.value);
      counter.alive.addListener(aliveListener);
      addTearDown(() => counter.alive.removeListener(aliveListener));

      await observed.future.timeout(const Duration(seconds: 20));
      expect(
        counter.ticks.value,
        greaterThan(0),
        reason:
            'the game isolate has been writing into shared memory this '
            'whole time',
      );
      expect(counter.alive.value, isTrue);
      expect(
        seen,
        isNotEmpty,
        reason: 'and a ValueListenable listener on this isolate was told',
      );
      // Non-decreasing, not strictly increasing, and the difference is the
      // whole of #182. A listener is handed no value: it reads `value`, which
      // is a live read of shared memory the game isolate is still writing. So
      // the read can land a tick or two ahead of the value that triggered the
      // notification, and the *next* notification - fired against the value
      // the poll saw, not the one this listener read - can then read back the
      // same number. Asserting a strict rise here asserted that the reader
      // never overtakes the notifier, which nothing promises; it held under a
      // quiet machine and failed about half the full-suite runs. What a live
      // read does promise is that it never goes backwards.
      for (var i = 1; i < seen.length; i++) {
        expect(
          seen[i],
          greaterThanOrEqualTo(seen[i - 1]),
          reason: 'a published counter is never seen to run backwards',
        );
      }
      // "Every notification was backed by a move", stated so that it does not
      // race: no listener can run between these two reads, and the counter
      // rises by at least one per notification, so it must have reached at
      // least the number of notifications delivered.
      expect(
        counter.ticks.value,
        greaterThanOrEqualTo(seen.length),
        reason: 'each notification carries a value that actually moved',
      );
      expect(
        aliveSeen.length,
        lessThanOrEqualTo(1),
        reason:
            'and a channel rewritten with the value it already holds, every '
            'tick, notifies nobody',
      );
      expect(aliveSeen, isNot(contains(false)));

      // Writing from the copy that does not own the memory is a programmer
      // error, not a silent no-op that "works" until someone wonders why the
      // simulation never noticed. Asserts are on under the test runner.
      expect(() => counter.ticks.value = 999, throwsAssertionError);
      expect(counter.ticks.value, isNot(999));

      await run.stop();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'raw input written on the main isolate reaches the game isolate\'s tick',
    () async {
      final game = await Game.start(_InputProbeGame.new);
      run = game;
      addTearDown(() async {
        if (run.isRunning) await run.stop();
      });

      final probe = game;
      // The announcement ordering, asserted directly: start() has returned,
      // so the game isolate has already handed this copy the raw block's
      // address and this copy has built the write end over it. A GameView
      // built on the very next line has somewhere to put a key event.
      final device = game.inputDevice;
      expect(
        device,
        isNotNull,
        reason:
            'this copy is the handle - the one Flutter runs on, and '
            'therefore the only one that can ever see a KeyEvent',
      );
      // This copy holds no twin of the system whose actions those are - it
      // declared no systems at all. It used to hold one, and the assertion
      // here was that the twin's actions read their declared default forever;
      // there is nothing left to read them off, which is the stronger version
      // of the same claim.
      // (There is nothing here to read them off: `run` is a GameHandle,
      // so `run.state` does not compile on this side at all.)

      await _waitTicks(run, 3);
      expect(probe.fireHeld.value, isFalse);
      expect(probe.presses.value, 0);

      // The write that has to cross a heap boundary in the direction nothing
      // else in the engine goes.
      device!
        ..press(InputKey.spacebar)
        ..press(InputKey.d);
      expect(
        await _waitUntil(
          run,
          () =>
              probe.fireHeld.value &&
              probe.moveX.value == 1 &&
              probe.presses.value == 1,
        ),
        isTrue,
        reason:
            'the game isolate resolved a binding against bits this '
            'isolate wrote - main -> game through the same TripleBuffer '
            'primitive the state channels use in the other direction',
      );
      expect(
        probe.moveX.value,
        1,
        reason:
            'and composed four raw bits into a vector on that side, '
            'because resolution is the reader\'s job: only the reader has '
            'the bindings',
      );
      expect(
        probe.presses.value,
        1,
        reason:
            'exactly one press edge, however many ticks the key was '
            'held for - edge detection is per resolution, and the key has '
            'now been down for several',
      );
      expect(probe.releases.value, 0);

      device.release(InputKey.spacebar);
      expect(
        await _waitUntil(
          run,
          () => !probe.fireHeld.value && probe.releases.value == 1,
        ),
        isTrue,
      );
      expect(probe.presses.value, 1, reason: 'and no phantom second press');
      expect(
        probe.moveX.value,
        1,
        reason:
            'the other key is still held - releasing one bit must not '
            'republish the whole block as empty',
      );

      await run.stop();
      expect(
        game.inputDevice,
        isNull,
        reason:
            'the game isolate freed the memory; the write end must go '
            'with it',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'a scene loaded at runtime from the game isolate gets its assets decoded',
    () async {
      final game = await Game.start(_LateGame.new);
      run = game;
      addTearDown(() async {
        if (run.isRunning) await run.stop();
      });

      expect(
        game.lateAddress.value,
        -1,
        reason:
            'nothing has loaded the scene, so no address has been '
            'assigned to report',
      );

      // Main asks; the game isolate loads the scene, which declares the asset
      // over there and then has to ask *back* for the decode it cannot do.
      await game.loadLate().timeout(const Duration(seconds: 20));
      expect(await _waitUntil(run, () => game.lateAddress.value >= 0), isTrue);
      final address = game.lateAddress.value;

      // By address, never by key. `describeScenes` runs on the game isolate
      // now, so this copy never declared anything - and the key object it
      // holds is not the one that was declared anyway, because a key crossing
      // a port arrives as a copy. The address is the shared name.
      expect(
        await _waitUntil(
          run,
          () =>
              game.assets.of<_IsolateTexture>().tryUnpack(address)?.isLoaded ==
              true,
        ),
        isTrue,
        reason:
            'the game isolate loaded the scene at runtime, so it had to '
            'ask this copy to decode. Before the round-trip existed, '
            '_reconcileAssets returned at `if (!game.decodesAssets)` and no '
            'decode was ever requested, leaving this false forever',
      );
      final declared = game.assets.of<_IsolateTexture>().tryUnpack(address)!;
      expect(
        declared.value.byteCount,
        4,
        reason: 'and the payload really landed, not just the flag',
      );

      expect(
        await _waitUntil(run, () => game.progress.value == 1.0),
        isTrue,
        reason:
            'progress crossed back the other way too: main sends one '
            'message per decode, the game isolate turns each into a '
            'SceneLoadProgress, and the terminal 1.0 still fires - the same '
            'contract the in-process path has',
      );

      // --- and the unload half ------------------------------------------
      await game.unloadLate().timeout(const Duration(seconds: 20));

      expect(
        await _waitUntil(
          run,
          () => game.assets.of<_IsolateTexture>().tryUnpack(address) == null,
        ),
        isTrue,
        reason:
            'the game isolate dropped its declaration, and told this copy '
            'to drop the payload with it. Without that message the image '
            'would stay alive on main with nothing left able to name it',
      );

      await run.stop();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'the game isolate assigns the asset address; main adopts it and decodes',
    () async {
      final game = await Game.start(_TexturedGame.new);
      run = game;
      addTearDown(() async {
        if (run.isRunning) await run.stop();
      });

      final reporter = game;
      expect(
        await _waitUntil(run, () => reporter.reportedAddress.value >= 0),
        isTrue,
      );

      // Resolved by address, not by key: main never ran an asset declaration
      // pass, and its own `_isolateTexture` object is not the one that was
      // declared - a key crossing a port arrives as a copy.
      final here = game.assets.of<_IsolateTexture>().tryUnpack(
        reporter.reportedAddress.value,
      );
      expect(
        here,
        isNotNull,
        reason:
            'main adopted the declaration when it was asked to decode - '
            'it declared no asset of its own',
      );
      expect(
        reporter.reportedAddress.value,
        here!.pack(),
        reason:
            'one copy assigns the address and the other takes it as given. '
            'It used to be two copies computing the same number from the same '
            'declaration order, which is the agreement this landing stopped '
            'needing - and which nothing re-established when a scene was '
            'loaded at runtime on one side only',
      );
      expect(
        reporter.reportedLoaded.value,
        0,
        reason:
            'and the game isolate never decoded it: decoding needs '
            'dart:ui, which is not on that isolate. It holds an addressed, '
            'unloaded instance forever, by design',
      );

      expect(
        await _waitUntil(run, () => here.isLoaded),
        isTrue,
        reason:
            'while this copy - the one with Flutter attached - did load '
            'it, on the far side of loadScene\'s decode request',
      );
      expect(
        here.value.byteCount,
        4,
        reason: 'and its payload is readable here',
      );

      await run.stop();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('the game isolate registers no asset decoder, and main does', () async {
    final game = await Game.start(_RegistrarGame.new);
    run = game;
    addTearDown(() async {
      if (run.isRunning) await run.stop();
    });

    expect(
      AssetLoaders.isRegistered<_LoaderProbe>(),
      isTrue,
      reason:
          'this copy ran _bootMain, which is the only call site of '
          'describeAssetLoaders, and this copy is the one that decodes',
    );

    expect(await _waitUntil(run, () => game.registeredHere.value >= 0), isTrue);
    expect(
      game.registeredHere.value,
      0,
      reason:
          'and the game isolate never ran that pass. AssetLoaders is a '
          'per-isolate static, so a decoder registered there would answer '
          'for nothing - that copy holds payload-free declarations and '
          'never decodes. A hook wired into one of the two passes both '
          'copies run would report 1 here and still look correct from main',
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  // DELETED, not disabled: 'unloading a scene drops the main copy page views
  // before the memory goes'.
  //
  // It asserted the capability this landing removes. Main used to adopt a
  // read-only view of every page the game isolate allocated, so unloading a
  // scene had to negotiate - free the memory while a widget was mid-repaint
  // over it and you get wrong numbers, silently, which is the one failure a
  // shared-memory design cannot report. That was `_msgPageGone` /
  // `_msgPagesDropped`, a deferred-free set, and a pool-side adoption call.
  //
  // Main holds no archetypes now and resolves no `Entity`, so it never had a
  // view to drop and the whole handshake is gone. The property that replaced
  // it is asserted in the first test in this file: a component read on main
  // throws, naming the presentation-only rule. There is nothing left here to
  // race with.

  // The assumption `_ControlMessage` rests on, pinned against a real spawn
  // rather than assumed (#142).
  //
  // The two control lanes tag every message with an enum value and route it
  // with a `switch`. A `switch` on an enum compares with `==`, which for an
  // enum is identity, so if `Isolate.spawn` copied the value instead of
  // handing back the canonical one, every arm would miss and the message
  // would vanish - `start()` hanging with nothing to point at, which is the
  // worst way for this to be wrong. `_ControlMessage` is private to game.dart,
  // so this pins the language guarantee it depends on, in both directions and
  // over a real port.
  test('an enum survives a real spawn with its identity intact', () async {
    final fromChild = ReceivePort();
    final greeted = Completer<List<Object?>>();
    final echoed = Completer<List<Object?>>();
    fromChild.listen((dynamic message) {
      final parts = (message as List).cast<Object?>();
      (greeted.isCompleted ? echoed : greeted).complete(parts);
    });
    final child = await Isolate.spawn(_echoTags, fromChild.sendPort);

    // Child -> parent: the value the child sent is the parent's own constant.
    final hello = await greeted.future;
    expect(
      identical(hello[0], _WireTag.hello),
      isTrue,
      reason:
          'an enum arrived from a spawned isolate as a copy rather than the '
          'canonical value, so a switch on it would match no arm',
    );

    // Parent -> child, and the answer says what the child's own switch did
    // with it rather than just whether it compared equal.
    (hello[1]! as SendPort).send(<Object>[_WireTag.farewell]);
    final back = await echoed.future;
    expect(
      back[0],
      'farewell',
      reason: 'the switch on the far side matched the wrong arm, or none',
    );
    expect(back[1], isTrue);

    child.kill(priority: Isolate.immediate);
    fromChild.close();
  }, timeout: const Timeout(Duration(seconds: 30)));
}

/// Two values, so a `switch` on the far side has something to get wrong.
enum _WireTag { hello, farewell }

/// The far half of 'an enum survives a real spawn with its identity intact'.
/// Top-level because a closure is not sendable.
void _echoTags(SendPort toParent) {
  final fromParent = ReceivePort();
  toParent.send(<Object>[_WireTag.hello, fromParent.sendPort]);
  fromParent.listen((dynamic message) {
    final tag = (message as List)[0] as _WireTag;
    // The routing itself, not a comparison standing in for it.
    var arm = 'no arm matched';
    switch (tag) {
      case _WireTag.hello:
        arm = 'hello';
      case _WireTag.farewell:
        arm = 'farewell';
    }
    toParent.send(<Object>[arm, identical(tag, _WireTag.farewell)]);
    fromParent.close();
  });
}
