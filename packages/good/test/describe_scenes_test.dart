import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/pool.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/system.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';

part 'describe_scenes_test.g.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

// `Game.describeScenes` declares which scenes exist and registers their
// archetypes at boot, so that loading one later costs no registration. That is
// what makes a scene loadable more than once - archetype ids are process-global
// and never recycled, so registering afresh per load would leak them.

mixin _Marked on Component {
  final mark = Field.uint8(3);

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Marked>();
  }
}

class _Unit extends EntityStruct with _Marked {}

mixin _Unmarked on Component {
  final tag = Field.uint8(7);

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Unmarked>();
  }
}

class _Prop extends EntityStruct with _Unmarked {}

class _Level extends SceneStruct {
  late final _Unit unit;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    unit = descriptor.has(_Unit.new);
  }
}

class _Menu extends SceneStruct {}

/// Declared by no game, so `loadScene` is what registers it. One prefab the
/// census query matches and one it must not - a scene with a single archetype
/// could not tell "matched the right one" from "matched everything".
class _Mixed extends SceneStruct {
  late final _Unit unit;
  late final _Prop prop;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    unit = descriptor.has(_Unit.new);
    prop = descriptor.has(_Prop.new);
  }
}

/// The same census through the `describeQuery` hook. `_bootGame` runs that
/// hook once, and `_HookGame` declares no scene, so it runs against an empty
/// `ArchetypeRegistry`.
class _HookCensusSystem extends GameSystem with FixedTickable {
  late final Query marked;
  int seen = 0;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    marked = descriptor.query().withAll(_Marked).build();
  }

  @override
  void onFixedUpdate() {
    var count = 0;
    for (final _ in marked.run()) {
      count++;
    }
    seen = count;
  }
}

class _HookState extends GameState<_HookGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_HookCensusSystem.new);
  }
}

class _HookGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _HookState();
}

/// A prefab with no `Field.*` initialisers, so it can be constructed
/// directly in a test - the field-declaring ones can only be built by the
/// framework, inside the descriptor pass that gives `Field.*` something to
/// declare against.
class _Bare extends EntityStruct {}

/// Counts what a query sees, to prove a declared-but-unloaded scene's
/// archetypes are registered without any entities in them.
class _CensusSystem extends GameSystem with FixedTickable {
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

class _DeclaringState extends GameState<_DeclaringGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_CensusSystem.new);
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
    super.describeScenes(descriptor);
    level = descriptor.has(_Level());
    menu = descriptor.has(_Menu());
  }
}

/// Declares the same scene type twice - one instance is one declaration.
class _DoubleDeclaringGame extends _DeclaringGame {
  @override
  void describeScenes(GameSceneDescriptor descriptor) {
    // `_DeclaringGame` already declared a `_Level`; this is the second.
    super.describeScenes(descriptor);
    descriptor.has(_Level());
  }
}

Future<T> _boot<T extends Game>(T Function() create) async {
  final game = await Game.startInline(create);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

void main() {
  _installDeclarations();

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test(
    'a declared scene is registered at boot, before anything is loaded',
    () async {
      final game = await _boot(_DeclaringGame.new);

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
      await _boot(_DeclaringGame.new);
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
    final game = await _boot(_DeclaringGame.new);
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
    expect(scene<_Level>(), same(game.level));
  });

  test('one declaration backs several loads', () async {
    final game = await _boot(_DeclaringGame.new);
    final before = ArchetypeRegistry.count;

    final first = await run.state.loadScene(game.level);
    final second = await run.state.loadScene(game.level);

    expect(ArchetypeRegistry.count, before);
    expect(
      first<_Level>(),
      same(second<_Level>()),
      reason:
          'a SceneStruct is a declaration - every load of it resolves to '
          'the same object, exactly as every Entity of a prefab resolves to '
          'the same EntityStruct',
    );
  });

  test('declaring the same scene type twice is refused', () {
    expect(Game.startInline(_DoubleDeclaringGame.new), throwsStateError);
  });

  test('an undeclared scene still loads, registering lazily', () async {
    final game = await _boot(_DeclaringGame.new);
    final before = ArchetypeRegistry.count;

    final scene = await run.state.loadScene(_Level());

    expect(
      ArchetypeRegistry.count,
      greaterThan(before),
      reason:
          'nothing declared it, so loading is what registers it - '
          'describeScenes is additive, not a new obligation',
    );
    expect(scene<_Level>(), isNot(same(game.level)));
  });

  test('a declared scene shares the game\'s pool and asset table', () async {
    final game = await _boot(_DeclaringGame.new);

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

  group('a prefab this scene cannot spawn', () {
    // These are checked in an assert now rather than on every spawn, so each
    // needs a case that fails without the check.
    //
    // Two of the three already had one: `archetype_test.dart`'s 'addEntity
    // rejects a prefab from another scene' and 'an unregistered prefab
    // explains itself instead of crashing', plus `game_test.dart`'s 'a scene
    // refuses a prefab another scene registered'. What had no case is the
    // state between those two - registered, so `archetype` answers, and not
    // yet sealed.

    test('an archetype with no layout yet refuses to allocate a row', () {
      // Registered but never sealed - the state between `reserve` and the
      // `seal()` that ends `describeScene`. A row allocated here would be
      // stamped from a prototype that does not exist.
      final pool = MemoryPool(pageSize: 4096);
      addTearDown(pool.dispose);
      final storage = ArchetypeRegistry.registerDetached(pool, _Bare());

      expect(storage.isSealed, isFalse);
      expect(() => storage.allocateRow(-1), throwsStateError);
    });
  });

  test('scenes are declared before systems build their queries', () async {
    // _CensusSystem's query is built in a field initialiser, so it exists
    // the moment describeSystems constructs the system - before any of this
    // scene's rows do. It counts them anyway: groups() resolves archetypes on
    // the first walk and rebuilds whenever the registry grows.
    final game = await _boot(_DeclaringGame.new);
    await run.state.loadScene(game.level);
    run.state.loadedScenes.single.addEntity(game.level.unit);
    run.state.advance(const Duration(milliseconds: 10));

    expect(run.state.getSystem<_CensusSystem>().seen, 1);
  });

  // What orders the boot passes is `collectListeners` reaching for a system,
  // not the query pass reaching for an archetype (#225). `describeQuery` reads
  // `ComponentTypeRegistry` for a bit per named type and resolves archetypes
  // lazily, so it carries no requirement that `describeScenes` precede it.
  test(
    'a hook-built query matches archetypes registered after the query pass',
    () async {
      await _boot(_HookGame.new);
      final system = run.state.getSystem<_HookCensusSystem>();
      expect(
        ArchetypeRegistry.count,
        0,
        reason:
            'this game declares no scene, so describeQuery ran against an '
            'empty registry',
      );

      final struct = _Mixed();
      final scene = await run.state.loadScene(struct);
      scene.addEntity(struct.unit);
      scene.addEntity(struct.prop);
      run.state.advance(const Duration(milliseconds: 10));

      expect(ArchetypeRegistry.count, 2);
      expect(
        system.seen,
        1,
        reason:
            'the _Unit row and not the _Prop row - a query that resolved to '
            'every archetype would count two, and one that never resolved '
            'would count none',
      );
    },
  );
}
