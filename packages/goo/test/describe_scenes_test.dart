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

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

// `Game.describeScenes` declares which scenes exist and registers their
// archetypes at boot, so that loading one later costs no registration. That is
// what makes a scene loadable more than once - archetype ids are process-global
// and never recycled, so registering afresh per load would leak them.

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

class _Unit extends EntityStruct with _Marked {}

class _Level extends SceneStruct {
  late final _Unit unit;

  @override
  void describeScene(SceneDescriptor descriptor) {
    unit = descriptor.has(_Unit());
  }
}

class _Menu extends SceneStruct {}

/// Counts what a query sees, to prove a declared-but-unloaded scene's
/// archetypes are registered without any entities in them.
class _CensusSystem extends GameSystem with FixedTickable {
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

class _DeclaringState extends GameState<_DeclaringGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    descriptor.has(_CensusSystem());
  }
}

class _DeclaringGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  late final _Level level;
  late final _Menu menu;

  @override
  GameState createState() => _DeclaringState();

  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    level = descriptor.has(_Level());
    menu = descriptor.has(_Menu());
  }
}

/// Declares the same scene type twice - one instance is one declaration.
class _DoubleDeclaringGame extends _DeclaringGame {
  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    descriptor.has(_Level());
    descriptor.has(_Level());
  }
}

Future<T> _boot<T extends Game>(T game) async {
  run = await Game.startInline(game);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test(
    'a declared scene is registered at boot, before anything is loaded',
    () async {
      final game = await _boot(_DeclaringGame());

      expect(
        game.level.isInitialized,
        isTrue,
        reason:
            'declaring registers the archetypes - that is the whole point, '
            'so that loading later costs no registration',
      );
      expect(game.level.unit.archetypeId, isNotNull);
      expect(
        run.state.scene,
        isNull,
        reason: 'declared is not loaded: nothing has been loaded yet',
      );
    },
  );

  test(
    'declaring registers archetypes without creating any entities',
    () async {
      await _boot(_DeclaringGame());
      run.state.advance(const Duration(milliseconds: 10));

      expect(
        run.state.getSystem<_CensusSystem>().seen,
        0,
        reason:
            'a declared scene contributes an archetype to the registry and '
            'no rows to it',
      );
    },
  );

  test('a declared scene loads without re-registering', () async {
    final game = await _boot(_DeclaringGame());
    final before = ArchetypeRegistry.count;

    final scene = await run.state.loadScene(game.level);

    expect(
      ArchetypeRegistry.count,
      before,
      reason:
          'loading a declared scene must not register a second set of '
          'archetypes - archetype ids are process-global and never '
          'recycled, so that would leak one set per load',
    );
    expect(scene.get<_Level>(), same(game.level));
  });

  test('one declaration backs several loads', () async {
    final game = await _boot(_DeclaringGame());
    final before = ArchetypeRegistry.count;

    final first = await run.state.loadScene(game.level);
    final second = await run.state.loadScene(game.level);

    expect(ArchetypeRegistry.count, before);
    expect(
      first.get<_Level>(),
      same(second.get<_Level>()),
      reason:
          'a SceneStruct is a declaration - every load of it resolves to '
          'the same object, exactly as every Entity of a prefab resolves to '
          'the same EntityStruct',
    );
  });

  test('declaring the same scene type twice is refused', () {
    expect(Game.startInline(_DoubleDeclaringGame()), throwsStateError);
  });

  test('an undeclared scene still loads, registering lazily', () async {
    final game = await _boot(_DeclaringGame());
    final before = ArchetypeRegistry.count;

    final scene = await run.state.loadScene(_Level());

    expect(
      ArchetypeRegistry.count,
      greaterThan(before),
      reason:
          'nothing declared it, so loading is what registers it - '
          'describeScenes is additive, not a new obligation',
    );
    expect(scene.get<_Level>(), isNot(same(game.level)));
  });

  test('a declared scene shares the game\'s pool and asset table', () async {
    final game = await _boot(_DeclaringGame());

    expect(
      game.level.pool,
      same(run.state.pool),
      reason: 'one pool per Game, handed to every scene it declares',
    );
    expect(
      game.level.assets,
      same(game.assets),
      reason:
          'and one asset table, or a scene would declare into a table '
          'nothing loads from',
    );
  });

  test('scenes are declared before systems build their queries', () async {
    // _CensusSystem.describeQuery resolves against registered archetypes. If
    // describeScenes ran after describeSystems the query would be built
    // against an empty registry and match nothing forever.
    final game = await _boot(_DeclaringGame());
    await run.state.loadScene(game.level);
    run.state.loadedScenes.single.addEntity(game.level.unit);
    run.state.advance(const Duration(milliseconds: 10));

    expect(run.state.getSystem<_CensusSystem>().seen, 1);
  });
}
