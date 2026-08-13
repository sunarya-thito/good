import 'package:flutter_test/flutter_test.dart';

import 'package:goo/src/archetype.dart';
import 'package:goo/src/data.dart';
import 'package:goo/src/event/state.dart';
import 'package:goo/src/game.dart';
import 'package:goo/src/game_state.dart';
import 'package:goo/src/scene.dart';
import 'package:goo/src/scene_handle.dart';
import 'package:goo/src/struct.dart';

// `Scene` is to `SceneStruct` what `Entity` is to `EntityStruct`: the struct is
// the declaration, the handle is one loaded instance of it. These cover the
// half of that which is real in Landing 1 - packing, resolution, generations,
// and the fact that a struct holds no instance identity of its own.

mixin _Marked on Component {
  late final DataPointer<int> mark;

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Marked>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    mark = data.hasUint8(3);
  }
}

class _Unit extends EntityStruct<_Unit> with _Marked {}

class _Level extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct<T>>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _Level();

  late final _Unit unit;

  @override
  void describeScene(SceneDescriptor descriptor) {
    unit = descriptor.has(_Unit());
  }
}

class _LevelState extends GameState<_LevelGame> with LifecycleListener {
  @override
  void onMounted() {
    loadScene(_Level());
  }
}

class _LevelGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _LevelState();
}

Future<_LevelGame> _boot() async {
  final game = _LevelGame();
  await game.start(inline: true, autoTick: false);
  addTearDown(() async {
    if (game.isRunning) await game.stop();
  });
  return game;
}

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('packing', () {
    test('generation and slot survive the extremes without bleeding', () {
      const zero = Scene.pack(0, 0);
      expect([zero.generation, zero.slot], [0, 0]);

      const max = Scene.pack(0xFFFFFFFF, 0xFFFFFFFF);
      expect(max.generation, 0xFFFFFFFF);
      expect(max.slot, 0xFFFFFFFF,
          reason: 'the top bit lands in the sign position; unpacking masks');

      const onlySlot = Scene.pack(0, 0xFFFFFFFF);
      expect(onlySlot.generation, 0);
      const onlyGeneration = Scene.pack(0xFFFFFFFF, 0);
      expect(onlyGeneration.slot, 0);
    });
  });

  group('resolution', () {
    test('a loaded scene resolves to the struct that was loaded', () async {
      final game = await _boot();
      final handle = game.state!.sceneHandle!;

      expect(handle.isLoaded, isTrue);
      expect(handle.get<_Level>(), same(game.state!.scene));
      expect(handle.tryGet<_Level>(), same(game.state!.scene));
    });

    test('the struct is a declaration and holds no handle of its own', () async {
      final game = await _boot();
      final scene = game.state!.scene!;

      // The identity lives on the state, not the struct: one SceneStruct backs
      // however many Scenes are loaded from it, exactly as one EntityStruct
      // backs many Entities, so "which handle am I" is not a question the
      // struct can answer.
      expect(game.state!.sceneHandle, isNotNull);
      expect(scene, isA<_Level>());
    });

    test('a handle to an unloaded scene stops resolving', () async {
      final game = await _boot();
      final handle = game.state!.sceneHandle!;
      expect(handle.isLoaded, isTrue);

      await game.stop();

      expect(handle.isLoaded, isFalse);
      expect(handle.tryGet<_Level>(), isNull);
      expect(() => handle.get<_Level>(), throwsStateError,
          reason: 'a stale handle is a diagnostic, not a null every caller has '
              'to remember to check');
    });

    test('a reused slot does not answer for the handle that held it before',
        () {
      final first = SceneRegistry.register(_Level());
      final firstScene = first.get<_Level>();

      SceneRegistry.unregister(first);
      final second = SceneRegistry.register(_Level());

      expect(second.slot, first.slot, reason: 'the free slot is reused');
      expect(second.value, isNot(first.value),
          reason: 'but the generation makes it a different handle - which is '
              'the whole reason Scene spends 32 bits on one and Entity, with '
              'no spare bits at all, cannot');
      expect(first.isLoaded, isFalse);
      expect(second.isLoaded, isTrue);
      expect(second.get<_Level>(), isNot(same(firstScene)));
    });

    test('get<T> reports the wrong type rather than returning null', () async {
      final game = await _boot();
      expect(() => game.state!.sceneHandle!.get<_OtherLevel>(), throwsStateError);
      expect(game.state!.sceneHandle!.tryGet<_OtherLevel>(), isNull);
    });
  });

  group('addEntity through the handle', () {
    test('is the only spelling, and stamps the declared defaults', () async {
      final game = await _boot();
      final state = game.state!;
      final scene = state.getScene<_Level>();
      final handle = state.sceneHandle!;

      state.pool.beginTick();
      final first = handle.addEntity(scene.unit);
      final second = handle.addEntity(scene.unit);
      state.pool.commitTick();

      // Creation lives on the handle rather than the struct because one
      // SceneStruct backs however many loaded Scenes - "which scene does this
      // row belong to" is a question only the receiver can answer, and the
      // handle answers it by being the receiver.
      expect(first.get<_Marked>().mark[first], 3,
          reason: 'onCreated and the declared defaults run through the handle');
      expect(second, isNot(first));
      expect(second.archetypeId, first.archetypeId);
    });
  });

  group('isActive', () {
    test('the loaded scene is the active one while it is the only one',
        () async {
      final game = await _boot();
      final handle = game.state!.sceneHandle!;
      expect(handle.isActive, isTrue);
      expect(SceneRegistry.active, handle);
    });

    test('an unloaded scene is not active, and clears the active slot',
        () async {
      final game = await _boot();
      final handle = game.state!.sceneHandle!;

      await game.stop();

      expect(handle.isActive, isFalse);
      expect(SceneRegistry.active, isNull,
          reason: 'a stopped game must not leave SceneRegistry answering for a '
              'game that no longer exists - the registry is process-global');
    });

    test('switching to an unloaded scene is refused', () {
      const stale = Scene.pack(0, 999);
      expect(() => SceneRegistry.setActive(stale), throwsStateError);
    });
  });
}

class _OtherLevel extends SceneStruct {}
