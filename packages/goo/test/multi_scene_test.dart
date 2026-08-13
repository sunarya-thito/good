import 'package:flutter_test/flutter_test.dart';

import 'package:goo/src/archetype.dart';
import 'package:goo/src/data.dart';
import 'package:goo/src/event/fixed_loop.dart';
import 'package:goo/src/game.dart';
import 'package:goo/src/game_state.dart';
import 'package:goo/src/scene.dart';
import 'package:goo/src/scene_handle.dart';
import 'package:goo/src/struct.dart';
import 'package:goo/src/system.dart';

// Several scenes resident at once, each individually unloadable. The property
// that makes it work is that two loaded instances of one `SceneStruct` never
// share a page, so unloading one is "free the pages tagged with its slot" -
// no row-by-row reclamation, which `Entity` has no spare bits to make safe.

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
    mark = data.hasUint16(3);
  }
}

class _Unit extends EntityStruct<_Unit> with _Marked {}

class _Level extends SceneStruct {
  late final _Unit unit;

  /// How many times this declaration has been mounted - one per loaded scene,
  /// which is the point: a `SceneStruct` is a declaration, not an instance.
  int mounts = 0;
  int unmounts = 0;

  @override
  void describeScene(SceneDescriptor descriptor) {
    unit = descriptor.has(_Unit());
  }

  @override
  void onMounted(Scene scene) {
    mounts++;
    scene.addEntity(unit);
  }

  @override
  void onUnmounted(Scene scene) => unmounts++;
}

class _Census extends GameSystem with FixedTickable {
  late final Query query;
  int seen = 0;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    query = descriptor.query().withAll(_Marked).build();
  }

  @override
  void onFixedUpdate() {
    var count = 0;
    for (final _ in query.run()) {
      count++;
    }
    seen = count;
  }
}

class _MultiState extends GameState<_MultiGame> {}

class _MultiGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  late final _Level level;

  @override
  GameState createState() => _MultiState();

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    level = descriptor.has(_Level());
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    descriptor.has(_Census());
  }
}

Future<_MultiGame> _boot() async {
  final game = _MultiGame();
  await game.start(inline: true, autoTick: false);
  addTearDown(() async {
    if (game.isRunning) await game.stop();
  });
  return game;
}

const _step = Duration(milliseconds: 10);

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test('two instances of one declaration are both resident and both tick',
      () async {
    final game = await _boot();
    final state = game.state!;

    final a = await state.loadScene(game.level);
    final b = await state.loadScene(game.level);

    expect(a, isNot(b));
    expect(state.loadedScenes, [a, b]);
    expect(game.level.mounts, 2,
        reason: 'one declaration, mounted once per loaded instance');

    state.advance(_step);
    expect(game.getSystem<_Census>().seen, 2,
        reason: 'every loaded scene ticks - that is the decided semantics, and '
            'it is why switchScene is informational rather than a gate');
  });

  test('their entities live in different pages', () async {
    final game = await _boot();
    final state = game.state!;

    final a = await state.loadScene(game.level);
    final b = await state.loadScene(game.level);
    final inA = a.addEntity(game.level.unit);
    final inB = b.addEntity(game.level.unit);

    expect(inA.archetypeId, inB.archetypeId, reason: 'same prefab');
    expect(inA.pageIndex, isNot(inB.pageIndex),
        reason: 'and that is the whole mechanism: rows of one archetype from '
            'two loaded scenes never share a page, so unloading one is a page '
            'free rather than a row-by-row reclamation');
  });

  test('unloading one leaves the other intact', () async {
    final game = await _boot();
    final state = game.state!;

    final a = await state.loadScene(game.level);
    final b = await state.loadScene(game.level);
    final survivor = b.addEntity(game.level.unit);
    survivor.get<_Marked>().mark[survivor] = 41;

    state.advance(_step);
    expect(game.getSystem<_Census>().seen, 3,
        reason: 'one entity per mount, plus the one added to b');

    state.unloadScene(a);

    expect(game.level.unmounts, 1);
    expect(a.isLoaded, isFalse);
    expect(b.isLoaded, isTrue);
    expect(state.loadedScenes, [b]);

    state.advance(_step);
    expect(game.getSystem<_Census>().seen, 2,
        reason: "the unloaded scene's rows are gone from every query");
    expect(survivor.get<_Marked>().mark[survivor], 41,
        reason: 'and the survivor is untouched - its pages were never shared');
  });

  test('an Entity from an unloaded scene reports the unload, not garbage',
      () async {
    final game = await _boot();
    final state = game.state!;

    final a = await state.loadScene(game.level);
    final doomed = a.addEntity(game.level.unit);
    state.advance(_step);

    state.unloadScene(a);

    // Page granularity, not per handle: `Entity` spends all 64 of its bits
    // and has none for a generation counter, so the detection is that the
    // page it names has been freed and its slot tombstoned.
    expect(() => doomed.get<_Marked>().mark[doomed], throwsStateError);
  });

  test('unloadAllScene takes down every instance of one declaration',
      () async {
    final game = await _boot();
    final state = game.state!;

    await state.loadScene(game.level);
    await state.loadScene(game.level);
    await state.loadScene(game.level);
    expect(state.loadedScenes.length, 3);

    state.unloadAllScene(game.level);

    expect(state.loadedScenes, isEmpty);
    expect(game.level.unmounts, 3);
    state.advance(_step);
    expect(game.getSystem<_Census>().seen, 0);
  });

  test('switchScene records the front scene without gating simulation',
      () async {
    final game = await _boot();
    final state = game.state!;

    final a = await state.loadScene(game.level);
    final b = await state.loadScene(game.level);

    expect(a.isActive, isTrue,
        reason: 'the first load becomes active so a one-scene game need not '
            'call switchScene at all');
    expect(b.isActive, isFalse, reason: 'a later load does not steal the front');

    state.switchScene(b);
    expect(a.isActive, isFalse);
    expect(b.isActive, isTrue);
    expect(state.sceneHandle, b);

    state.advance(_step);
    expect(game.getSystem<_Census>().seen, 2,
        reason: 'switching is informational - the background scene keeps '
            'ticking, which is the decided semantics');
  });

  test('unloading the front scene clears the front', () async {
    final game = await _boot();
    final state = game.state!;

    final a = await state.loadScene(game.level);
    state.unloadScene(a);

    expect(SceneRegistry.active, isNull);
    expect(state.sceneHandle, isNull);
    expect(state.scene, isNull);
  });

  test('the pages survive the unload until the reader has let go', () async {
    // Inline has no reader, so the free is immediate and this asserts the
    // *inline* half: unregistering happens first, so the scene is
    // unreachable through the API the moment unloadScene returns, whatever
    // the memory is doing. The spawned half - where the free is deferred
    // across a round trip - is covered in game_isolate_test.dart.
    final game = await _boot();
    final state = game.state!;

    final a = await state.loadScene(game.level);
    final doomed = a.addEntity(game.level.unit);
    state.advance(_step);

    state.unloadScene(a);

    expect(a.isLoaded, isFalse, reason: 'unreachable through the handle');
    expect(state.loadedScenes, isEmpty);
    expect(() => doomed.get<_Marked>().mark[doomed], throwsStateError,
        reason: 'and unreachable through any Entity into it');
  });

  test('a page freed by one unload is not handed to the next load', () async {
    final game = await _boot();
    final state = game.state!;

    final a = await state.loadScene(game.level);
    final inA = a.addEntity(game.level.unit);
    state.unloadScene(a);

    final b = await state.loadScene(game.level);
    final inB = b.addEntity(game.level.unit);

    expect(inB.pageIndex, isNot(inA.pageIndex),
        reason: 'page slots are tombstoned and never reused, so the stale '
            'handle above keeps reporting the unload rather than resolving '
            'into whatever the next scene put there');
    expect(() => inA.get<_Marked>().mark[inA], throwsStateError);
  });
}
