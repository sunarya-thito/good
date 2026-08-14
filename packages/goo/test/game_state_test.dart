import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_test/flutter_test.dart';

import 'package:goo/src/scene_handle.dart';
import 'package:goo/src/archetype.dart';
import 'package:goo/src/data.dart';
import 'package:goo/src/event/fixed_loop.dart';
import 'package:goo/src/event/state.dart';
import 'package:goo/src/game.dart';
import 'package:goo/src/game_state.dart';
import 'package:goo/src/pool.dart';
import 'package:goo/src/scene.dart';
import 'package:goo/src/struct.dart';
import 'package:goo/src/system.dart';
import 'package:goo/src/handle.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late InlineGameHandle run;


// Single-copy coverage for describeState/StateChannel, driven through
// Game.startInline(...) exactly as game_test.dart does:
// one copy doing both jobs, no timer, runFixedStep() by hand. The two-isolate
// half - where the read and the write genuinely happen on different heaps,
// and where a write through the non-owning copy is even reachable - lives in
// game_isolate_test.dart.

/// Everything every listener in this file appends to. A plain top-level list
/// rather than closure-captured test state, so the same fixture code works
/// unchanged on a spawned isolate copy.
final List<String> changes = <String>[];

// --- the two declaration sources ----------------------------------------
//
// A state channel is declared by the Game or by one of its declared systems,
// and by nothing else. A GameState, a SceneStruct and a Component all
// deliberately cannot: a channel's storage is allocated on main before the
// spawn and its index in that one pass is its identity on the wire, so the
// declarer has to be something main itself runs. The GameState is built on
// the game isolate; a scene is loaded (and re-loaded) after boot via
// GameState.loadScene. See Game.describeState.

/// A plain prefab. It has no state channel of its own - a Component cannot
/// declare one (see the note above); the system publishes on its behalf.
class _Probe extends EntityStruct {
  late final DataPointer<int> hits;

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    hits = data.hasUint16();
  }

}

/// A plain scene - like a Component, it cannot declare state channels.
class _StateScene extends SceneStruct {
  _StateScene();

  late final _Probe probe;

  @override
  void describeScene(SceneDescriptor descriptor) {
    probe = descriptor.has(_Probe());
  }

}

/// A `GameSystem` - and the only thing in this fixture that runs per tick,
/// so it is what drives every write.
class _StateSystem extends GameSystem with FixedTickable {
  /// Declared by the `Game` and read back through it. A system cannot declare
  /// a channel: the storage is allocated on main before the spawn and a system
  /// only exists on the copy that ticks. The system is still the *writer*,
  /// which is the half that was always game-side.
  _StateGame get _own => game as _StateGame;
  StateChannel<int> get health => _own.health;
  StateChannel<int> get probeCount => _own.probeCount;
  StateChannel<double> get mana => _own.mana;
  StateChannel<bool> get alive => _own.alive;

  /// Set by a test to make the next tick write something; null means "tick
  /// without writing anything", which is how the "listeners do not fire on a
  /// quiet tick" case is exercised.
  int? nextHealth;
  int? nextGameCount;
  int? nextStateCount;
  int? nextProbeCount;

  @override
  void onFixedUpdate() {
    final h = nextHealth;
    if (h != null) health.value = h;
    final g = nextGameCount;
    if (g != null) (game as _StateGame).gameCount.value = g;
    final t = nextStateCount;
    // Declared on the Game and written from the game isolate - the pattern
    // that replaced `GameState.describeState`, which cannot exist now that
    // the state is built after main has already allocated the channels.
    if (t != null) (game as _StateGame).stateCount.value = t;
    final p = nextProbeCount;
    // A prefab cannot own a channel, so a per-prefab value is published
    // through a channel this system owns - the intended pattern now.
    if (p != null) probeCount.value = p;
  }
}

class _StateGameState extends GameState<_StateGame> {
  @override
  void onMounted() {
    loadScene(_StateScene());
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    descriptor.has(_StateSystem());
  }
}

/// Source 1: the `Game` itself, declaring two channels.
class _StateGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  late final StateChannel<int> gameCount;

  /// A second channel on the same source, at a different width, written by the
  /// system on the game isolate.
  late final StateChannel<int> stateCount;

  /// Declared here on behalf of `_StateSystem`, which writes them. One source
  /// declares; the game isolate writes.
  late final StateChannel<int> health;
  late final StateChannel<int> probeCount;
  late final StateChannel<double> mana;
  late final StateChannel<bool> alive;

  /// The live descriptor, captured mid-boot so a test can try to declare
  /// against it *after* boot - see 'declaring after boot is refused'.
  StateDescriptor? capturedDescriptor;

  @override
  GameState createState() => _StateGameState();



  @override
  void describeState(StateDescriptor descriptor) {
    capturedDescriptor = descriptor;
    gameCount = descriptor.hasInt32(7);
    stateCount = descriptor.hasInt64(-5);
    health = descriptor.hasInt32(100);
    probeCount = descriptor.hasUint16(300);
    mana = descriptor.hasFloat32(0.5);
    alive = descriptor.hasBool(true);
  }
}

// --- fixtures for the failure/validation cases ---------------------------

class GameSceneStub extends SceneStruct {
  GameSceneStub();
}

/// A prefab that declares state, registered into a scene brought up by hand
/// (no `Game`) - the one legitimate way to reach `_SceneDescriptor.has`
/// without a boot pass to declare into.
class _OrphanScene extends SceneStruct {
  _OrphanScene();

  @override
  void describeScene(SceneDescriptor descriptor) {
    descriptor.has(_Probe());
  }
}

Future<T> _boot<T extends Game>(T game) async {
  run = await Game.startInline(game);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

_StateScene _scene(Game game) => run.state.getScene<_StateScene>();

void _watch(String name, StateChannel<Object?> channel) {
  channel.addListener(() => changes.add('$name -> ${channel.value}'));
}

void main() {
  setUp(changes.clear);

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('declaration', () {
    test('both sources declare into one descriptor, indices unique', () async {
      final game = await _boot(_StateGame());
      // Game(2) then system(4) - one shared numbering. Six, not "2 + 4
      // restarted at zero twice".
      expect(game.stateChannelCount, 6);
    });

    test('a channel from every source is readable before any write', () async {
      final game = await _boot(_StateGame());
      final scene = _scene(game);
      final system = run.state.getSystem<_StateSystem>();
      // The declared initial value, published the moment storage was
      // allocated - not a null, not zeroed memory, not a throw.
      expect(game.gameCount.value, 7, reason: 'declared on the Game');
      expect(run.state.getScene<_StateScene>(), same(scene));
      expect(game.stateCount.value, -5,
          reason: 'a second channel on the same Game, at a different width');
      expect(system.probeCount.value, 300,
          reason: 'a second channel on the same GameSystem');
      expect(system.health.value, 100, reason: 'declared on a GameSystem');
      expect(system.mana.value, closeTo(0.5, 1e-9));
      expect(system.alive.value, isTrue);
    });

    test('two channels from different sources get distinct storage', () async {
      final game = await _boot(_StateGame());
      final system = run.state.getSystem<_StateSystem>();

      // Same declared width (4 bytes), different sources. If they shared a
      // slot, writing one would be visible through the other.
      system.nextGameCount = 111;
      system.nextProbeCount = 222;
      run.state.runFixedStep();

      expect(game.gameCount.value, 111);
      expect(system.probeCount.value, 222);
      expect(system.mana.value, closeTo(0.5, 1e-9),
          reason: 'a third channel nobody wrote to is untouched');
    });

    test('declaring after boot is refused', () async {
      final game = await _boot(_StateGame());
      // The *real* descriptor, kept from the boot pass. It is sealed at the
      // end of _boot(); a declaration now would have storage on neither copy
      // and an index matching nothing on the other side.
      final descriptor = game.capturedDescriptor!;
      expect(() => descriptor.hasInt32(), throwsStateError);
      expect(() => descriptor.hasFloat64(), throwsStateError);
      expect(() => descriptor.hasBool(), throwsStateError);
      expect(game.stateChannelCount, 6,
          reason: 'and nothing was appended to the declared set');
    });

    test('bootStateDescriptor is unreachable outside a boot pass', () async {
      final game = await _boot(_StateGame());
      expect(() => game.bootStateDescriptor, throwsStateError);
    });
  });

  group('width vocabulary', () {
    test('every integer width round-trips its own range', () async {
      final game = await _boot(_WidthGame());
      game.u8.value = 255;
      game.i8.value = -128;
      game.u16.value = 65535;
      game.i16.value = -32768;
      game.u32.value = 4294967295;
      game.i32.value = -2147483648;
      game.u64.value = 1 << 62;
      game.i64.value = -(1 << 62);

      expect(game.u8.value, 255);
      expect(game.i8.value, -128);
      expect(game.u16.value, 65535);
      expect(game.i16.value, -32768);
      expect(game.u32.value, 4294967295);
      expect(game.i32.value, -2147483648);
      expect(game.u64.value, 1 << 62);
      expect(game.i64.value, -(1 << 62));
    });

    test('float32 is genuinely 32 bits wide, float64 is not', () async {
      final game = await _boot(_WidthGame());
      game.f32.value = 0.1;
      game.f64.value = 0.1;
      expect(game.f32.value, isNot(0.1),
          reason: 'a 4-byte channel cannot hold a double exactly - which is '
              'the point of naming the width at the declaration');
      expect(game.f32.value, closeTo(0.1, 1e-7));
      expect(game.f64.value, 0.1);
    });

    test('bool is a real bool, and its declared initial value survives',
        () async {
      final game = await _boot(_WidthGame());
      expect(game.flag.value, isTrue, reason: 'declared hasBool(true)');
      game.flag.value = false;
      expect(game.flag.value, isFalse);
      game.flag.value = true;
      expect(game.flag.value, isTrue);
    });

    test('successive writes rotate slots without losing the value', () async {
      final game = await _boot(_StateGame());
      final system = run.state.getSystem<_StateSystem>();
      // More than three, so the triple buffer's round-robin wraps and the
      // cached per-slot ByteData views are all exercised.
      for (var i = 1; i <= 7; i++) {
        system.nextGameCount = i * 10;
        run.state.runFixedStep();
        expect(game.gameCount.value, i * 10, reason: 'write #$i');
      }
    });
  });

  group('ValueListenable', () {
    test('a channel is one, so ValueListenableBuilder takes it directly',
        () async {
      final game = await _boot(_StateGame());
      expect(game.gameCount, isA<ValueListenable<int>>());
      expect(run.state.getSystem<_StateSystem>().mana, isA<ValueListenable<double>>());
      expect(run.state.getSystem<_StateSystem>().alive, isA<ValueListenable<bool>>());
    });

    test('a write on the owning copy notifies synchronously', () async {
      final game = await _boot(_StateGame());
      _watch('gameCount', game.gameCount);

      game.gameCount.value = 42;
      expect(changes, ['gameCount -> 42'],
          reason: 'the writer is on this isolate, so there is nothing to wait '
              'for - no tick, no message, no microtask');
    });

    test('fires once per actual change, not once per write', () async {
      final game = await _boot(_StateGame());
      final system = run.state.getSystem<_StateSystem>();
      _watch('gameCount', game.gameCount);

      system.nextGameCount = 50;
      run.state.runFixedStep();
      expect(changes, ['gameCount -> 50']);

      // Same value again: a write happened, but nothing changed.
      run.state.runFixedStep();
      expect(changes, ['gameCount -> 50'],
          reason: 'writing an equal value is not a change');

      system.nextGameCount = 51;
      run.state.runFixedStep();
      expect(changes, ['gameCount -> 50', 'gameCount -> 51']);
    });

    test('does not fire on a tick where nothing was written', () async {
      await _boot(_StateGame());
      final system = run.state.getSystem<_StateSystem>();
      _watch('health', system.health);

      run.state.runFixedStep();
      run.state.runFixedStep();
      expect(changes, isEmpty,
          reason: 'no write at all, and the initial value is not a change');

      system.nextHealth = 1;
      run.state.runFixedStep();
      system.nextHealth = null;
      run.state.runFixedStep();
      run.state.runFixedStep();
      expect(changes, ['health -> 1'],
          reason: 'quiet ticks after a change are still quiet');
    });

    test('a channel nobody listens to simply never notifies', () async {
      await _boot(_StateGame());
      final system = run.state.getSystem<_StateSystem>();
      system.nextProbeCount = 5;
      run.state.runFixedStep();
      expect(system.probeCount.value, 5);
      expect(changes, isEmpty);
    });

    test('a listener added late compares against the value at that moment',
        () async {
      final game = await _boot(_StateGame());
      game.gameCount.value = 3;
      _watch('gameCount', game.gameCount);
      expect(changes, isEmpty, reason: 'adding a listener is not a change');
      game.gameCount.value = 3;
      expect(changes, isEmpty, reason: 'and neither is rewriting the same 3');
      game.gameCount.value = 4;
      expect(changes, ['gameCount -> 4']);
    });

    test('removeListener stops it', () async {
      final game = await _boot(_StateGame());
      void listener() => changes.add('tick');
      game.gameCount.addListener(listener);
      game.gameCount.value = 1;
      game.gameCount.removeListener(listener);
      game.gameCount.value = 2;
      expect(changes, ['tick']);
    });
  });

  group('validation', () {
    test('a scene can be brought up without a Game at all', () {
      // Components no longer declare state, so registering a prefab needs
      // nothing from the Game - a bare scene is a legitimate test/headless
      // fixture again rather than a StateError waiting to happen.
      final scene = _OrphanScene();
      final pool = MemoryPool(pageSize: 4096);
      // The pool is handed in rather than constructed by the scene: it belongs
      // to the Game now, and a fixture with no Game supplies its own.
      expect(() => scene.initializeScene(pool), returnsNormally);
      expect(scene.pool, same(pool));
      pool.dispose();
    });

    test('reading a channel after stop() reports disconnection', () async {
      final game = _StateGame();
      run = await Game.startInline(game);
      await run.stop();
      expect(() => game.gameCount.value, throwsStateError);
    });
  });
}

/// One channel of every declared width, all on the `Game` so a test can write
/// them without going through a system.
class _WidthState extends GameState<_WidthGame> {
  @override
  void onMounted() {
    loadScene(GameSceneStub());
  }
}

class _WidthGame extends Game {
  @override
  int get pageSize => 4096;

  late final StateChannel<int> u8;
  late final StateChannel<int> i8;
  late final StateChannel<int> u16;
  late final StateChannel<int> i16;
  late final StateChannel<int> u32;
  late final StateChannel<int> i32;
  late final StateChannel<int> u64;
  late final StateChannel<int> i64;
  late final StateChannel<double> f32;
  late final StateChannel<double> f64;
  late final StateChannel<bool> flag;

  @override
  GameState createState() => _WidthState();

  @override
  void describeState(StateDescriptor descriptor) {
    u8 = descriptor.hasUint8();
    i8 = descriptor.hasInt8();
    u16 = descriptor.hasUint16();
    i16 = descriptor.hasInt16();
    u32 = descriptor.hasUint32();
    i32 = descriptor.hasInt32();
    u64 = descriptor.hasUint64();
    i64 = descriptor.hasInt64();
    f32 = descriptor.hasFloat32();
    f64 = descriptor.hasFloat64();
    flag = descriptor.hasBool(true);
  }
}
