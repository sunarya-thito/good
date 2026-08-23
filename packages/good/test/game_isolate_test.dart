import 'dart:async';
import 'dart:typed_data';

import 'package:good/src/scene_handle.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/command/command.dart';
import 'package:good/src/command/param.dart';
import 'package:good/src/asset.dart';
import 'package:good/src/data.dart';
import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/event/lifecycle.dart';
import 'package:good/src/event/state.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/input.dart';
import 'package:good/src/input/input_binding.dart';
import 'package:good/src/input/input_key.dart';
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
  final x = Field.float64();

  /// The number of live entities the mover saw this tick, written into the
  /// *first* entity's row. This is how the main isolate learns that a
  /// command-spawned entity actually exists without needing a second
  /// message channel: it just reads the count out of shared memory.
  final census = Field.uint16();

  /// Set only by [_Mover.onMounted] - proves the prefab's creation hook ran
  /// on the game isolate, for both mount-time and command-time spawns.
  final marker = Field.uint8();

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Moving>();
  }
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
  late final Query query;

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
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
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
    population.value = count;
    if (first != null) {
      final moving = first.get<_Moving>();
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
  late final ParamPointer<Entity> spawned;

  @override
  void describeParams(ParamDescriptor descriptor) {
    spawned = descriptor.hasEntity();
  }

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

class _PauseMover extends SinkCommand<bool> {
  late final ParamPointer<int> paused;

  @override
  void describeParams(ParamDescriptor descriptor) {
    paused = descriptor.hasUint1();
  }

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
      ..hasSignal(game.resumeByTick, () => paused = false);
  }

  Entity _onSpawnMover() => loadedScenes.single.addEntity(level.mover);

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
    descriptor.has(_MoverSystem());
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
    descriptor.has(_DyingSystem());
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

  /// What `_MoverSystem` publishes. Declared here because main is the copy
  /// that allocates the storage - and main is also the only reader, which is
  /// what a state channel is for.
  late final StateChannel<double> firstX;
  late final StateChannel<int> population;
  late final StateChannel<int> firstMarker;

  @override
  void describeState(StateDescriptor descriptor) {
    super.describeState(descriptor);
    firstX = descriptor.hasFloat64();
    population = descriptor.hasInt32();
    firstMarker = descriptor.hasInt32();
  }

  @override
  GameState createState() => _IsolateState();

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    spawnMover = descriptor.has(_SpawnMover());
    pauseMover = descriptor.has(_PauseMover());
    resumeByControl = descriptor.has(_ResumeByControl());
    resumeByTick = descriptor.has(_ResumeByTick());
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
    descriptor.has(_PingSystem());
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

/// Bumps a channel every tick on the game isolate. The main isolate never
/// sees this object's twin do anything - it only ever reads the channel.
class _CounterSystem extends GameSystem with FixedTickable {
  /// Declared on the `Game` and written here. The channel is the only thing
  /// main can see of this system at all - it holds no twin of it.
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
    descriptor.has(_CounterSystem());
  }
}

class _ChannelGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  late final StateChannel<int> ticks;
  late final StateChannel<bool> alive;

  @override
  void describeState(StateDescriptor descriptor) {
    super.describeState(descriptor);
    ticks = descriptor.hasInt32();
    alive = descriptor.hasBool();
  }

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
    descriptor.has(_InputProbeSystem());
  }
}

class _InputProbeGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  late final StateChannel<bool> fireHeld;
  late final StateChannel<int> presses;
  late final StateChannel<int> releases;
  late final StateChannel<double> moveX;

  @override
  void describeState(StateDescriptor descriptor) {
    super.describeState(descriptor);
    fireHeld = descriptor.hasBool();
    presses = descriptor.hasInt32();
    releases = descriptor.hasInt32();
    moveX = descriptor.hasFloat64();
  }

  @override
  GameState createState() => _InputProbeState();
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
  late final Asset<_IsolateTexture> texture;

  // Both seeded to a value the writer can never legitimately produce, so a row
  // that was never written fails the test instead of accidentally matching
  // address 0.

  /// What the *game isolate's* copy thinks this asset's address is.
  final seenAddress = Field.int32(-1);

  /// And whether that copy has a decoded payload - `0` there, always.
  final seenLoaded = Field.int32(-1);

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    texture = descriptor.has(_isolateTexture);
  }
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
  late final Query query;

  _TexturedGame get _own => game as _TexturedGame;
  StateChannel<int> get reportedAddress => _own.reportedAddress;
  StateChannel<int> get reportedLoaded => _own.reportedLoaded;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    query = descriptor.query().withAll(_Textured).build();
  }

  @override
  void onFixedUpdate() {
    for (final entity in query.run()) {
      final prefab = entity.get<_Textured>();
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
    descriptor.has(_TexturedSystem());
  }
}

class _TexturedGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  late final StateChannel<int> reportedAddress;
  late final StateChannel<int> reportedLoaded;

  @override
  void describeState(StateDescriptor descriptor) {
    super.describeState(descriptor);
    reportedAddress = descriptor.hasInt32(-1);
    reportedLoaded = descriptor.hasInt32(-1);
  }

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
  late final Asset<_IsolateTexture> texture;

  @override
  void describeAssets(AssetDescriptor descriptor) {
    super.describeAssets(descriptor);
    texture = descriptor.has(_lateTexture);
  }
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
  late final StateChannel<double> progress;

  /// The address the *game isolate* assigned this scene's texture, published
  /// so main can name it. Main cannot look the asset up by key: the key it
  /// holds is a different object from the one that was declared (see
  /// `Assets.adoptAt`), so an address is the only shared name.
  late final StateChannel<int> lateAddress;

  @override
  GameState createState() => _LateState();

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    super.describeScenes(descriptor);
    lateScene = descriptor.has(_LateScene());
  }

  @override
  void describeState(StateDescriptor descriptor) {
    super.describeState(descriptor);
    progress = descriptor.hasFloat64(-1);
    lateAddress = descriptor.hasInt32(-1);
  }

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    loadLate = descriptor.has(_LoadLate());
    unloadLate = descriptor.has(_UnloadLate());
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
    descriptor.has(_MoverSystem());
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
    dropScene = descriptor.has(_DropScene());
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
/// deliberately not API, so a test that wants to *wait for a tick* reaches for
/// the internal spelling on purpose. A game waiting on the simulation
/// publishes a value with `describeState` and listens to that instead.
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
    descriptor.has(_RegistrarSystem());
  }
}

class _RegistrarGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 5);

  late final StateChannel<int> registeredHere;

  @override
  void describeState(StateDescriptor descriptor) {
    super.describeState(descriptor);
    registeredHere = descriptor.hasInt32(-1);
  }

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
          game = await Game.start(_DyingGame());
          // Well past the third tick at a 5ms step.
          await Future<void>.delayed(const Duration(milliseconds: 200));
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
  test('a control command reaches a game whose tick is stopped', () async {
    final game = _IsolateGame();
    run = await Game.start(game);
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
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(
      run.tick,
      greaterThan(stopped),
      reason:
          'the handler set paused = false, so the tick came back. Sent as a '
          'tick-delivered command this could never arrive - the message that '
          'restarts the tick would be waiting on the tick it stopped.',
    );
  });

  test('a tick command does not reach a game whose tick is stopped', () async {
    final game = _IsolateGame();
    run = await Game.start(game);
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
  test(
    'a Game subclass survives Isolate.spawn and ticks on the other side',
    () async {
      final game = _IsolateGame();
      run = await Game.start(game);
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
      await _waitTicks(run, 3);

      // Everything below reads a `StateChannel` - shared memory the game
      // isolate published this tick. No copy, no message carrying the value,
      // and no component row, which this copy could not resolve anyway.
      expect(
        mover.firstMarker.value,
        7,
        reason:
            'the scene mounted an entity on the game isolate and its '
            'onEntityMounted ran there',
      );
      final firstRead = mover.firstX.value;
      expect(
        firstRead,
        greaterThan(0),
        reason: 'the mover system is running on the other isolate',
      );

      await _waitTicks(run, 5);
      expect(
        mover.firstX.value,
        greaterThan(firstRead),
        reason: 'entity state must keep changing across ticks',
      );
      expect(mover.population.value, 1);

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

      await _waitTicks(run, 3);
      expect(
        mover.population.value,
        2,
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
      await _waitTicks(run, 3);
      expect(mover.population.value, 3);

      // And the entity that came back is deliberately **not** readable here.
      // It is a valid handle on the isolate that made it and meaningless on
      // this one; the diagnostic says so rather than indexing an empty table.
      expect(
        () => spawned.get<_Moving>(),
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
      final game = _IsolateGame();
      run = await Game.start(game);
      addTearDown(() async {
        if (run.isRunning) await run.stop();
      });

      await _waitTicks(run, 3);
      expect(game.firstX.value, greaterThan(0));

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
      await _waitTicks(run, 5);
      expect(game.firstX.value, greaterThan(frozen));

      await run.stop();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'an auxiliary buffer is announced across the isolate boundary before the '
    'first tick writes to it',
    () async {
      final game = _PingGame();
      run = await Game.start(game);
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
      final game = _ChannelGame();
      run = await Game.start(game);
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
      void listener() => seen.add(counter.ticks.value);
      counter.ticks.addListener(listener);
      addTearDown(() => counter.ticks.removeListener(listener));

      await _waitTicks(run, 4);
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
      for (var i = 1; i < seen.length; i++) {
        expect(
          seen[i],
          greaterThan(seen[i - 1]),
          reason: 'each notification carries a value that actually moved',
        );
      }

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
      final game = _InputProbeGame();
      run = await Game.start(game);
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
      await _waitTicks(run, 4);

      expect(
        probe.fireHeld.value,
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
      await _waitTicks(run, 4);
      expect(probe.fireHeld.value, isFalse);
      expect(probe.releases.value, 1);
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
      final game = _LateGame();
      run = await Game.start(game);
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
      final game = _TexturedGame();
      run = await Game.start(game);
      addTearDown(() async {
        if (run.isRunning) await run.stop();
      });

      final reporter = game;
      expect(
        await _waitUntil(run, () => reporter.reportedAddress.value >= 0),
        isTrue,
      );

      // Resolved by address, not by key: main never ran a `describeAssets`
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
            'it never ran a describeAssets pass of its own',
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
    final game = _RegistrarGame();
    run = await Game.start(game);
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
  // `_msgPagesDropped`, a deferred-free set, and `MemoryPool.adoptPage`.
  //
  // Main holds no archetypes now and resolves no `Entity`, so it never had a
  // view to drop and the whole handshake is gone. The property that replaced
  // it is asserted in the first test in this file: a component read on main
  // throws, naming the presentation-only rule. There is nothing left here to
  // race with.
}
