import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/system.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

// Several scenes resident at once, each individually unloadable. The property
// that makes it work is that two loaded instances of one `SceneStruct` never
// share a page, so unloading one is "free the pages tagged with its slot" -
// no row-by-row reclamation, which `Entity` has no spare bits to make safe.

mixin _Marked on Component {
  final mark = Field.uint16(3);

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Marked>();
  }
}

class _Unit extends EntityStruct with _Marked {}

class _Level extends SceneStruct {
  late final _Unit unit;

  /// How many times this declaration has been mounted - one per loaded scene,
  /// which is the point: a `SceneStruct` is a declaration, not an instance.
  int mounts = 0;
  int unmounts = 0;

  /// The hazard #104 is about, written down where it cannot go stale the way
  /// the guide did: an `Entity` cached on the declaration. `onSceneMounted`
  /// runs once per loaded copy against this one object, so the second load
  /// overwrites what the first stored and nothing is raised.
  Entity? cachedEntity;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    unit = descriptor.has(_Unit.new);
  }

  @override
  void onSceneMounted(Scene scene) {
    mounts++;
    cachedEntity = scene.addEntity(unit);
  }

  @override
  void onSceneUnmounted(Scene scene) => unmounts++;
}

class _Census extends GameSystem with FixedTickable {
  final query = Query.all(_Marked);
  int seen = 0;

  @override
  void onFixedUpdate() {
    var count = 0;
    for (final _ in query.run()) {
      count++;
    }
    seen = count;
  }
}

class _MultiState extends GameState<_MultiGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_Census.new);
  }
}

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
    super.describeScenes(descriptor);
    level = descriptor.has(_Level());
  }
}

Future<_MultiGame> _boot() async {
  final game = await Game.startInline(_MultiGame.new);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
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

  test(
    'two instances of one declaration are both resident and both tick',
    () async {
      final game = await _boot();
      final state = run.state;

      final a = await state.loadScene(game.level);
      final b = await state.loadScene(game.level);

      expect(a, isNot(b));
      expect(state.loadedScenes, [a, b]);
      expect(
        game.level.mounts,
        2,
        reason: 'one declaration, mounted once per loaded instance',
      );

      state.advance(_step);
      expect(
        run.state.getSystem<_Census>().seen,
        2,
        reason:
            'every loaded scene is live - all tick, all receive input, '
            'all render. There is no front scene to be excluded from',
      );
    },
  );

  test(
    'an Entity cached on the declaration is overwritten by the second load',
    () async {
      // The guide taught this shape - `late Entity playerEntity` on a
      // SceneStruct, read back through what is now `singleScene` - and it is
      // wrong for the same reason `mounts` counts to two above. Pinned here
      // because a doc cannot fail a build when the engine moves under it.
      final game = await _boot();
      final state = run.state;

      final a = await state.loadScene(game.level);
      final first = game.level.cachedEntity;
      expect(first, isNotNull);

      final b = await state.loadScene(game.level);
      final second = game.level.cachedEntity;

      expect(
        second,
        isNot(first),
        reason: 'the second mount wrote over the first, with nothing raised',
      );
      expect(
        first!.sceneSlot,
        a.slot,
        reason:
            'and the first entity is still alive in its own scene - the field '
            'is not stale, it is naming the wrong instance',
      );
      expect(second!.sceneSlot, b.slot);
    },
  );

  test(
    'singleScene refuses to guess once a second scene is resident',
    () async {
      final game = await _boot();
      final state = run.state;

      await state.loadScene(game.level);
      expect(
        state.singleScene<_Level>(),
        same(game.level),
        reason: 'one loaded scene is what it is for',
      );

      await state.loadScene(game.level);
      expect(
        () => state.singleScene<_Level>(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('loadedScenes'),
          ),
        ),
        reason:
            'this is the call that worked all through development and started '
            'throwing the day a HUD loaded. The name says so now',
      );
    },
  );

  test('their entities live in different pages', () async {
    final game = await _boot();
    final state = run.state;

    final a = await state.loadScene(game.level);
    final b = await state.loadScene(game.level);
    final inA = a.addEntity(game.level.unit);
    final inB = b.addEntity(game.level.unit);

    expect(inA.archetypeId, inB.archetypeId, reason: 'same prefab');
    expect(
      inA.pageIndex,
      isNot(inB.pageIndex),
      reason:
          'and that is the whole mechanism: rows of one archetype from '
          'two loaded scenes never share a page, so unloading one is a page '
          'free rather than a row-by-row reclamation',
    );
  });

  test('unloading one leaves the other intact', () async {
    final game = await _boot();
    final state = run.state;

    final a = await state.loadScene(game.level);
    final b = await state.loadScene(game.level);
    final survivor = b.addEntity(game.level.unit);
    survivor.get<_Marked>().mark[survivor] = 41;

    state.advance(_step);
    expect(
      run.state.getSystem<_Census>().seen,
      3,
      reason: 'one entity per mount, plus the one added to b',
    );

    state.unloadScene(a);

    expect(game.level.unmounts, 1);
    expect(a.isLoaded, isFalse);
    expect(b.isLoaded, isTrue);
    expect(state.loadedScenes, [b]);

    state.advance(_step);
    expect(
      run.state.getSystem<_Census>().seen,
      2,
      reason: "the unloaded scene's rows are gone from every query",
    );
    expect(
      survivor.get<_Marked>().mark[survivor],
      41,
      reason: 'and the survivor is untouched - its pages were never shared',
    );
  });

  test(
    'an Entity from an unloaded scene reports the unload, not garbage',
    () async {
      final game = await _boot();
      final state = run.state;

      final a = await state.loadScene(game.level);
      final doomed = a.addEntity(game.level.unit);
      state.advance(_step);

      state.unloadScene(a);

      // Page granularity, not per handle: `Entity` spends all 64 of its bits
      // and has none for a generation counter, so the detection is that the
      // page it names has been freed and its slot tombstoned.
      expect(() => doomed.get<_Marked>().mark[doomed], throwsStateError);
    },
  );

  test('unloadAllScene takes down every instance of one declaration', () async {
    final game = await _boot();
    final state = run.state;

    await state.loadScene(game.level);
    await state.loadScene(game.level);
    await state.loadScene(game.level);
    expect(state.loadedScenes.length, 3);

    state.unloadAllScene(game.level);

    expect(state.loadedScenes, isEmpty);
    expect(game.level.unmounts, 3);
    state.advance(_step);
    expect(run.state.getSystem<_Census>().seen, 0);
  });

  test(
    'with several scenes loaded, `scene` refuses rather than guessing',
    () async {
      final game = await _boot();
      final state = run.state;

      final a = await state.loadScene(game.level);
      final b = await state.loadScene(game.level);

      // This used to answer with the *first* loaded scene - a guess dressed as
      // an accessor, and specified by this test rather than accidental. A state
      // holding two scenes has no basis for choosing between them, so it says
      // so; the caller names the one it means.
      expect(() => state.scene, throwsStateError);
      expect(state.loadedScenes, <Scene>[a, b]);

      // Derived rather than stored, so nothing has to be updated on unload and
      // nothing can be left stale: with one left, it answers again.
      state.unloadScene(a);
      expect(state.loadedScenes.singleOrNull, b);
      expect(state.scene, isNotNull);

      state.advance(_step);
      expect(
        run.state.getSystem<_Census>().seen,
        1,
        reason:
            'and b was ticking all along - it was never in a background '
            'state to be promoted out of',
      );
    },
  );

  test('unloading everything leaves no scene', () async {
    final game = await _boot();
    final state = run.state;

    final a = await state.loadScene(game.level);
    state.unloadScene(a);

    expect(state.loadedScenes.singleOrNull, isNull);
    expect(state.scene, isNull);
    expect(state.loadedScenes, isEmpty);
  });

  test('the pages survive the unload until the reader has let go', () async {
    // Inline has no reader, so the free is immediate and this asserts the
    // *inline* half: unregistering happens first, so the scene is
    // unreachable through the API the moment unloadScene returns, whatever
    // the memory is doing. The spawned half - where the free is deferred
    // across a round trip - is covered in game_isolate_test.dart.
    final game = await _boot();
    final state = run.state;

    final a = await state.loadScene(game.level);
    final doomed = a.addEntity(game.level.unit);
    state.advance(_step);

    state.unloadScene(a);

    expect(a.isLoaded, isFalse, reason: 'unreachable through the handle');
    expect(state.loadedScenes, isEmpty);
    expect(
      () => doomed.get<_Marked>().mark[doomed],
      throwsStateError,
      reason: 'and unreachable through any Entity into it',
    );
  });

  test('a page freed by one unload is not handed to the next load', () async {
    final game = await _boot();
    final state = run.state;

    final a = await state.loadScene(game.level);
    final inA = a.addEntity(game.level.unit);
    state.unloadScene(a);

    final b = await state.loadScene(game.level);
    final inB = b.addEntity(game.level.unit);

    expect(
      inB.pageIndex,
      isNot(inA.pageIndex),
      reason:
          'page slots are tombstoned and never reused, so the stale '
          'handle above keeps reporting the unload rather than resolving '
          'into whatever the next scene put there',
    );
    expect(() => inA.get<_Marked>().mark[inA], throwsStateError);
  });

  test('a query can be scoped to one loaded scene', () async {
    final game = await _boot();
    final state = run.state;

    final a = await state.loadScene(game.level);
    final b = await state.loadScene(game.level);

    // Each scene gets 1 unit from onSceneMounted.
    // Add 2 more to a, and 3 more to b.
    for (var i = 0; i < 2; i++) {
      a.addEntity(game.level.unit);
    }
    for (var i = 0; i < 3; i++) {
      b.addEntity(game.level.unit);
    }

    final census = run.state.getSystem<_Census>();
    expect(census.query.run().length, 7, reason: 'unscoped sees all 7');
    expect(census.query.run(a).length, 3, reason: 'scene a has 3');
    expect(census.query.run(b).length, 4, reason: 'scene b has 4');

    var groupsSeenA = 0;
    for (final group in census.query.groups(a)) {
      for (final _ in group) {
        groupsSeenA++;
      }
    }
    expect(groupsSeenA, 3);

    var groupsSeenB = 0;
    for (final group in census.query.groups(b)) {
      for (final _ in group) {
        groupsSeenB++;
      }
    }
    expect(groupsSeenB, 4);
  });
}
