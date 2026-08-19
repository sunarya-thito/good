import 'package:good/src/scene_handle.dart';
import 'package:good/src/event/tick_loop.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/command/command.dart';
import 'package:good/src/command/param.dart';
import 'package:good/src/data.dart';
import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/event/lifecycle.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/system.dart';
import 'package:flutter_test/flutter_test.dart';

/// The live run under test. A file-level binding: the bring-up helper
/// returns the `Game` (the description) while tests also need the run, and
/// one inline run per isolate means one binding is enough.
late Game run;

// Everything here runs through Game.startInline(...) - one
// isolate, one copy of the Game, no timer, no wall clock. GameState.advance
// (Duration) is the whole scheduler, so driving it by hand is not a
// reduced-fidelity stand-in for the real loop; it *is* the real loop, minus
// the Timer that decides when to call it.

/// Records execution order across systems. Cleared in setUp.
final List<String> log = <String>[];

mixin _Counter on Component {
  late final DataPointer<double> x;

  /// Written by [_Unit.onMounted] only - never a declared default - so
  /// reading 7 back proves the prefab's onMounted actually ran, not just
  /// that a row was allocated.
  late final DataPointer<int> marker;

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Counter>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    x = data.hasFloat64();
    marker = data.hasUint8();
  }
}

class _Unit extends EntityStruct with _Counter, EntityLifecycleListener {
  @override
  void onEntityMounted(Entity entity) {
    super.onEntityMounted(entity);
    marker[entity] = 7;
  }
}

class _TestScene extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _TestScene();

  late final _Unit unit;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    unit = descriptor.has(_Unit());
  }
}

/// Presentation-phase system: records the delta it was handed, so the tests
/// can tell "ran once per frame" from "ran once per simulation step".
class _PresentSystem extends GameSystem with Tickable {
  final List<Duration> deltas = <Duration>[];

  @override
  void onTick(Duration delta) {
    log.add('P');
    deltas.add(delta);
  }
}

/// Mixes both phases, to prove one system can simulate *and* present and
/// that the two fire in the right order relative to each other.
class _BothPhases extends GameSystem with FixedTickable, Tickable {
  @override
  void onFixedUpdate() => log.add('sim');

  @override
  void onTick(Duration delta) => log.add('present');
}

/// Carries the two phase probes and no other system, so the listener counts
/// below are the probes' own - which is why it comes off [_FixtureState]
/// rather than [_TestState]. The *state* is what varies; the `Game` only has
/// to say which one to build.
class _PhaseState extends _FixtureState {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_PresentSystem());
    descriptor.has(_BothPhases());
  }
}

class _PhaseGame extends _TestGame {
  @override
  GameState createState() => _PhaseState();
}

class _SystemA extends GameSystem with FixedTickable {
  @override
  void onFixedUpdate() => log.add('A');
}

class _SystemB extends GameSystem with FixedTickable {
  @override
  void onFixedUpdate() => log.add('B');
}

/// Declared between A and B but not `FixedTickable` - the tick loop must
/// walk straight past it rather than tripping over it.
class _InertSystem extends GameSystem {}

/// Declared last, but sorts itself before every other system - the
/// `Comparable` ordering mechanism's reference usage. Unconditional `-1`
/// (not "before _SystemA specifically") deliberately: an opinion about only
/// *one* other system, combined with declaration-order tie-breaks for every
/// other pair, has no valid total order at all (this system would have to
/// be simultaneously "before A" and, transitively through the tie-broken
/// pairs, "after" a system A is itself tie-broken before) - that is a
/// self-contradictory scenario to test against, not a real one. An
/// unconditional opinion has no such conflict: it is consistently the
/// minimum against every other system regardless of comparison direction.
class _SortsFirst extends GameSystem with FixedTickable {
  @override
  int compareTo(GameSystem other) => -1;

  @override
  void onFixedUpdate() => log.add('C');
}

/// Two systems that both express no opinion - stability (declaration order
/// survives when nothing overrides `compareTo`) is what distinguishes a
/// correct sort from one that merely happens to look right.
class _Indifferent1 extends GameSystem with FixedTickable {
  @override
  void onFixedUpdate() => log.add('1');
}

class _Indifferent2 extends GameSystem with FixedTickable {
  @override
  void onFixedUpdate() => log.add('2');
}

/// Extends the base fixture's set rather than replacing it - the `super` call
/// is what makes declaration order (and therefore execution order) the thing
/// under test.
class _OrderingState extends _TestState {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    // Declaration order: A, InertSystem, B, CensusSystem, Indifferent1,
    // Indifferent2, SortsBeforeA.
    super.describeSystems(descriptor);
    descriptor.has(_Indifferent1());
    descriptor.has(_Indifferent2());
    descriptor.has(_SortsFirst());
  }
}

class _OrderingGame extends _TestGame {
  @override
  GameState createState() => _OrderingState();
}

/// Counts what the query sees *this* tick, to prove a command-spawned
/// entity is visible to systems on the tick the command lands.
class _CensusSystem extends GameSystem with FixedTickable {
  late final Query query;
  final List<int> seen = <int>[];

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    query = descriptor.query().withAll(_Counter).build();
  }

  @override
  void onFixedUpdate() {
    var count = 0;
    for (final _ in query.run()) {
      count++;
    }
    seen.add(count);
  }
}

/// "Spawn a unit" - the shape that replaced the framework's built-in
/// `spawnEntity(archetypeId)`.
///
/// The Flutter isolate says what it *wants*; the handler, which runs on the
/// game isolate, is the only thing that knows which prefab that means. An
/// `archetypeId` crossing the boundary would have made main name an identifier
/// it has no way to see, which is why the built-in was deleted rather than
/// kept.
class _SpawnUnit extends SupplierCommand<Entity> {
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

/// The scene, the spawn handler and nothing else. Split out from [_TestState]
/// so a fixture wanting a different system set inherits the setup without
/// inheriting systems it would then have to drop - dropping them means an
/// override that skips `super.describeSystems`, which is the one thing
/// `@mustCallSuper` is here to stop.
class _FixtureState extends GameState<_TestGame> {
  /// Held rather than looked up: the handler needs the prefab, and this is the
  /// side that has it.
  final _TestScene level = _TestScene();

  @override
  void onMounted() {
    loadScene(level);
  }

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    descriptor.hasSupplier(game.spawnUnit, _onSpawnUnit);
  }

  Entity _onSpawnUnit() => loadedScenes.single.addEntity(level.unit);
}

class _TestState extends _FixtureState {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_SystemA());
    descriptor.has(_InertSystem());
    descriptor.has(_SystemB());
    descriptor.has(_CensusSystem());
  }
}

class _TestGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  late final _SpawnUnit spawnUnit;

  @override
  GameState createState() => _TestState();

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    spawnUnit = descriptor.has(_SpawnUnit());
  }
}

typedef _Nudge = ({Entity entity, double amount});

/// A user command, to prove the dispatch table is not hardcoded to the
/// framework's own spawn. Sets [x] on an entity it is handed by value.
class _NudgeCommand extends SinkCommand<_Nudge> {
  late final ParamPointer<Entity> entity;
  late final ParamPointer<double> amount;

  @override
  void describeParams(ParamDescriptor descriptor) {
    entity = descriptor.hasEntity();
    amount = descriptor.hasFloat64();
  }

  @override
  void bufferFromParams(ParamBuffer call, _Nudge params) {
    entity[call] = params.entity;
    amount[call] = params.amount;
  }

  @override
  _Nudge paramsFromBuffer(ParamBuffer call) =>
      (entity: entity[call], amount: amount[call]);
}

/// Declared on the `Game` (the only place a command may be declared) and
/// handled on the `GameState` - so it runs on the game isolate, inside the
/// tick window, which is what the test below actually checks.
class _CommandGame extends _TestGame {
  late final _NudgeCommand nudge;

  @override
  GameState createState() => _CommandState();

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    nudge = descriptor.has(_NudgeCommand());
  }
}

class _CommandState extends GameState<_CommandGame> {
  @override
  void onMounted() {
    loadScene(_TestScene());
  }

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    descriptor.hasSink(game.nudge, _onNudge);
  }

  // The handler is the plain function the command claims to be: no buffer in
  // the signature, no pointer in the body.
  void _onNudge(_Nudge p) => p.entity.get<_Counter>().x[p.entity] = p.amount;
}

/// Declares a command from the `GameState`, which is refused: its index would
/// exist on the game isolate and not on the Flutter one.
class _BadCommandState extends _TestState {
  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    descriptor.has(_NudgeCommand());
  }
}

class _BadCommandGame extends _TestGame {
  @override
  GameState createState() => _BadCommandState();
}

class _DuplicateSystemState extends _TestState {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    // `_TestState` already declared a `_SystemA`; this is the second.
    super.describeSystems(descriptor);
    descriptor.has(_SystemA());
  }
}

class _DuplicateSystemGame extends _TestGame {
  @override
  GameState createState() => _DuplicateSystemState();
}

Future<T> _game<T extends Game>(T game) async {
  run = await Game.startInline(game);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

/// The simulation half. Every scheduler call lives here now, not on `Game`.
GameState _state(Game game) => run.state;

const Duration _step = Duration(milliseconds: 10);

void main() {
  setUp(log.clear);

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('accumulator', () {
    test('runs one step per whole fixedTimeStep of elapsed time', () async {
      final game = await _game(_TestGame());
      expect(_state(game).advance(_step * 3), 3);
      expect(run.tick, 3);
    });

    test(
      'a partial step accumulates instead of being lost or rounded up',
      () async {
        final game = await _game(_TestGame());
        final state = _state(game);
        expect(state.advance(const Duration(milliseconds: 6)), 0);
        expect(
          state.advance(const Duration(milliseconds: 6)),
          1,
          reason: '6ms + 6ms is one whole 10ms step',
        );
        expect(
          state.advance(const Duration(milliseconds: 6)),
          0,
          reason: '2ms carried + 6ms is still short of a step',
        );
        expect(state.advance(const Duration(milliseconds: 2)), 1);
        expect(run.tick, 2);
      },
    );

    test('zero elapsed time runs nothing', () async {
      final game = await _game(_TestGame());
      expect(_state(game).advance(Duration.zero), 0);
      expect(run.tick, 0);
    });

    test('a long stall is capped at maxFixedStepsPerAdvance', () async {
      final game = await _game(_TestGame());
      // 100 steps' worth of wall clock in one go.
      expect(_state(game).advance(_step * 100), game.maxFixedStepsPerAdvance);
      expect(run.tick, game.maxFixedStepsPerAdvance);
    });

    test(
      'the backlog past the cap is dropped, not carried into next frame',
      () async {
        final game = await _game(_TestGame());
        _state(game).advance(_step * 100);
        // If the remaining ~95 steps had been kept in the accumulator, this
        // would immediately run another full capped batch - the spiral.
        expect(_state(game).advance(_step), 1);
      },
    );

    test('sub-step phase survives the drop', () async {
      final game = await _game(_TestGame());
      // 100 steps + 3ms. After capping, the 3ms remainder must still be
      // there, so 7ms more is enough for the next step.
      _state(game).advance(_step * 100 + const Duration(milliseconds: 3));
      expect(_state(game).advance(const Duration(milliseconds: 7)), 1);
    });
  });

  group('presentation phase (Tickable)', () {
    test('runs once per frame, not once per simulation step', () async {
      await _game(_PhaseGame());
      // One advance worth three whole fixed steps.
      expect(run.state.advance(_step * 3), 3);
      expect(
        log.where((e) => e == 'sim').length,
        3,
        reason: 'simulation runs per step',
      );
      expect(
        log.where((e) => e == 'present').length,
        1,
        reason:
            'presentation runs per frame - three catch-up steps still '
            'produce one presented frame, which is the whole reason the '
            'two phases are separate',
      );
    });

    test('runs even on a frame that afforded no simulation step', () async {
      await _game(_PhaseGame());
      expect(
        run.state.advance(const Duration(milliseconds: 4)),
        0,
        reason: 'less than one fixed step',
      );
      expect(
        log,
        contains('present'),
        reason:
            'a frame where the simulation did not advance is still a '
            'frame - an interpolating renderer has work to do on it',
      );
      expect(log, isNot(contains('sim')));
    });

    test('presentation runs after simulation within one frame', () async {
      await _game(_PhaseGame());
      run.state.advance(_step);
      // Not just "both ran" - the ordering is the entire contract. A
      // Tickable reads what the tick published, so it must come after.
      expect(log.indexOf('sim'), lessThan(log.indexOf('present')));
    });

    test(
      'the delta is the frame\'s elapsed time, not the fixed step',
      () async {
        await _game(_PhaseGame());
        const frame = Duration(milliseconds: 35); // 3 steps + 5ms remainder
        run.state.advance(frame);
        expect(
          run.state.getSystem<_PresentSystem>().deltas,
          [frame],
          reason:
              'onTick receives real elapsed wall clock, unlike '
              'onFixedUpdate which always represents exactly fixedTimeStep',
        );
      },
    );

    test(
      'a Tickable-only system never receives a fixed tick, and vice versa',
      () async {
        await _game(_PhaseGame());
        run.state.advance(_step);
        // _PresentSystem is Tickable and not FixedTickable: it logs 'P' once
        // (presentation) and never participates in the simulation pass.
        expect(log.where((e) => e == 'P').length, 1);
        expect(run.state.getSystem<_PresentSystem>().deltas, hasLength(1));
      },
    );
  });

  group('system execution', () {
    test('systems tick in declaration order, every step', () async {
      final game = await _game(_TestGame());
      _state(game).advance(_step * 2);
      expect(log, ['A', 'B', 'A', 'B']);
    });

    test(
      'a declared system that is not FixedTickable is simply skipped',
      () async {
        final game = await _game(_TestGame());
        _state(game).advance(_step);
        expect(log, ['A', 'B']);
        expect(run.state.getSystem<_InertSystem>(), isA<_InertSystem>());
      },
    );

    test(
      'disableSystem stops a system ticking; enableSystem resumes it',
      () async {
        final game = await _game(_TestGame());
        _state(game).advance(_step);
        expect(log, ['A', 'B']);

        run.state.disableSystem<_SystemA>();
        expect(run.state.isSystemEnabled<_SystemA>(), isFalse);
        log.clear();
        _state(game).advance(_step);
        expect(log, ['B'], reason: 'A is paused but B keeps running');

        run.state.enableSystem<_SystemA>();
        log.clear();
        _state(game).advance(_step);
        expect(log, ['A', 'B']);
      },
    );

    test('disableSystems/enableSystems take a set of types', () async {
      final game = await _game(_TestGame());
      run.state.disableSystems([_SystemA, _SystemB]);
      _state(game).advance(_step);
      expect(log, isEmpty);
      run.state.enableSystems([_SystemA, _SystemB]);
      _state(game).advance(_step);
      expect(log, ['A', 'B']);
    });

    test('an undeclared system cannot be toggled or fetched', () async {
      await _game(_TestGame());
      expect(() => run.state.getSystem<_CensusSystem>(), returnsNormally);
      expect(
        () => run.state.disableSystem<_UndeclaredSystem>(),
        throwsArgumentError,
      );
      expect(
        () => run.state.getSystem<_UndeclaredSystem>(),
        throwsArgumentError,
      );
      expect(
        run.state.tryGetSystem<_UndeclaredSystem>(),
        isNull,
        reason: 'tryGetSystem is the "I work either way" form',
      );
      expect(run.state.tryGetSystem<_CensusSystem>(), isNotNull);
    });

    test(
      'declaring the same system twice is an error, not a silent duplicate',
      () {
        expect(Game.startInline(_DuplicateSystemGame()), throwsStateError);
      },
    );

    test('a system reaches its siblings and its scene', () async {
      final game = await _game(_TestGame());
      final census = run.state.getSystem<_CensusSystem>();
      expect(
        census.getSystem<_SystemA>(),
        same(run.state.getSystem<_SystemA>()),
      );
      expect(census.getScene<_TestScene>(), same(_state(game).scene));
      expect(census.state, same(run.state));
    });
  });

  group('Comparable-driven system ordering', () {
    test(
      'a system that sorts itself first runs first, despite declaring last',
      () async {
        final game = await _game(_OrderingGame());
        _state(game).advance(_step);
        expect(
          log.first,
          'C',
          reason:
              '_SortsFirst.compareTo returns -1 unconditionally, so it '
              'must run before every other system in this game even though '
              'it was declared after all of them',
        );
      },
    );

    test(
      'systems with no opinion keep declaration order (sort stability)',
      () async {
        final game = await _game(_OrderingGame());
        _state(game).advance(_step);
        final i1 = log.indexOf('1');
        final i2 = log.indexOf('2');
        expect(
          i1,
          lessThan(i2),
          reason:
              'Indifferent1 was declared before Indifferent2 and neither '
              'overrides compareTo, so a correct stable sort must not '
              'reorder them relative to each other',
        );
      },
    );

    test(
      'full order matches declaration order with only C moved to the front',
      () async {
        final game = await _game(_OrderingGame());
        _state(game).advance(_step);
        expect(
          log,
          ['C', 'A', 'B', '1', '2'],
          reason:
              'declaration order was A, B, Indifferent1, Indifferent2, '
              'SortsFirst (InertSystem/CensusSystem are not FixedTickable '
              'and do not log) - only C moving to the front should change',
        );
      },
    );
  });

  group('tick phases', () {
    test('each dispatcher resolves its listeners at boot, by type', () async {
      final game = await _game(_PhaseGame());
      final state = _state(game);

      // The point of the whole event design: by the time anything is
      // dispatched, the receiver list is already settled. It was resolved by
      // one composition walk at boot instead of by testing every candidate on
      // every dispatch, which is what the old fireEvent walk did.
      expect(
        state.fixedTickEvent.listenerCount,
        1,
        reason: 'only _BothPhases simulates',
      );
      expect(
        state.tickEvent.listenerCount,
        2,
        reason: '_PresentSystem and _BothPhases both present',
      );
    });

    test('a disabled system stays collected and declines', () async {
      final game = await _game(_PhaseGame());
      final state = _state(game);
      state.advance(_step);
      expect(log, ['sim', 'P', 'present']);

      log.clear();
      run.state.disableSystem<_BothPhases>();

      expect(
        state.fixedTickEvent.listenerCount,
        1,
        reason: 'membership is baked - disabling does not re-collect',
      );
      state.advance(_step);
      expect(
        log,
        ['P'],
        reason:
            'it declines through listensToEvents instead, which is the '
            'one thing a pre-resolved list cannot bake because it is '
            'genuinely runtime state',
      );
    });
  });

  group('command dispatch and processing', () {
    test(
      'a spawn command round-trips to a real entity with onMounted run',
      () async {
        final game = await _game(_TestGame());
        final scene = _state(game).getScene<_TestScene>();
        final archetypeId = scene.unit.archetypeId;

        final pending = game.spawnUnit();
        // Nothing happens until the tick that runs the inbox - not even inline,
        // where the batch never leaves this isolate. A game-handled command
        // waits for the tick window whichever way the game was booted.
        expect(scene.unit.archetype.pageCount, 0);

        _state(game).advance(_step);

        expect(scene.unit.archetype.pageCount, 1);
        expect(
          await pending,
          Entity.pack(archetypeId, 0, 0),
          reason:
              'the entity travels back as the command\'s result - the old '
              'encode/apply lane could only leave it in a field on the '
              'isolate that made it',
        );
        expect(
          scene.unit.marker[await pending],
          7,
          reason: 'onMounted must run for a command-spawned entity too',
        );
      },
    );

    test(
      'a command lands before systems run, on the very tick it arrives',
      () async {
        final game = await _game(_TestGame());
        final census = run.state.getSystem<_CensusSystem>();

        _state(game).advance(_step); // tick 1: nothing exists
        game.spawnUnit();
        _state(game)
            .advance(_step); // tick 2: command applies, then systems run
        _state(game).advance(_step); // tick 3

        expect(census.seen, [
          0,
          1,
          1,
        ], reason: 'the spawn must be visible to the census on tick 2, not 3');
      },
    );

    test(
      'a burst of commands travels as one batch and lands on one tick',
      () async {
        final game = await _game(_TestGame());
        final scene = _state(game).getScene<_TestScene>();
        final id = scene.unit.archetypeId;

        // One batch, fifty calls: one message, one wake-up, one reply. The
        // round trip is what costs, not the bytes.
        final batch = run.createCommandBatch();
        final keys = <CommandKey<Entity>>[
          for (var i = 0; i < 50; i++) batch.supply(game.spawnUnit),
        ];
        final pending = batch.send();
        _state(game).advance(_step);
        final results = await pending;

        expect(run.state.getSystem<_CensusSystem>().seen, [50]);
        expect(keys[0][results], Entity.pack(id, 0, 0));
        expect(
          keys[49][results],
          isNot(keys[0][results]),
          reason:
              'each call in the batch gets its own record, so each result '
              'is its own entity rather than the last one written',
        );
      },
    );

    test(
      'a user-declared command runs its handler on the game isolate',
      () async {
        final game = await _game(_CommandGame());
        final scene = _state(game).getScene<_TestScene>();
        final entity = _state(game).loadedScenes.single.addEntity(scene.unit);
        _state(game).advance(_step);
        expect(scene.unit.x[entity], 0.0);

        game.nudge((entity: entity, amount: 12.5));
        _state(game).advance(_step);
        expect(scene.unit.x[entity], 12.5);
      },
    );

    test('a command nothing handles is refused at the sender', () async {
      await _game(_TestGame());
      expect(
        () => _NudgeCommand()((entity: const Entity(0), amount: 1)),
        throwsStateError,
        reason:
            'both copies run both declaration passes, so the sending side '
            'already knows nothing will read this',
      );
    });

    test('a command declared on the GameState is refused at boot', () {
      expect(Game.startInline(_BadCommandGame()), throwsStateError);
    });

    // "reaching the command channel before start throws" was asserted here
    // with `_TestGame().createCommandBatch`. There is no such method on a
    // `Game` any more: a batch is written into one run's command ring, so it
    // comes off the `GameHandle`, and a handle only exists once `Game.start`
    // has returned. The error the test was checking for is now unreachable by
    // construction rather than diagnosed at runtime.

    test('a scene refuses a prefab another scene registered', () async {
      final game = await _game(_TestGame());
      final scene = _state(game).getScene<_TestScene>();
      // Deliberately brought up on the *same* pool the loaded scene uses.
      // That is the case a pool-identity check could not see: ownership used
      // to be inferred from pool identity, which was only ever true because a
      // scene owned its own pool. The pool belongs to the Game now and every
      // scene shares it, so two scenes are pool-identical and only the
      // prefab's own recorded scene tells them apart.
      final other = _TestScene()..initializeScene(_state(game).pool);
      other.handle = SceneRegistry.register(other);
      expect(
        identical(other.pool, scene.pool),
        isTrue,
        reason: 'same pool, different scene - the whole point of the case',
      );
      expect(
        () => _state(game).loadedScenes.single.addEntity(other.unit),
        throwsStateError,
        reason:
            'the prefab belongs to `other`, so spawning it into the '
            'loaded scene would put its rows in the wrong page group',
      );
    });
  });

  group('tick notification', () {
    test('fires once per presented frame, with the tick it depicts', () async {
      final game = await _game(_TestGame());
      final ticks = <int>[];
      void listener(int tick) => ticks.add(tick);

      run.runtimeOrNull!.addTickListener(listener);
      // One frame that afforded three simulation steps. The notification is
      // "a frame is ready to consume", and the frame is written by the
      // presentation pass, which runs once - so one ping, naming the tick it
      // depicts. Pinging per step would tell a renderer three times that a
      // frame it only wrote once was ready. See GameRuntime.presentFrame.
      _state(game).advance(_step * 3);
      expect(ticks, [3]);

      _state(game).advance(_step);
      expect(ticks, [3, 4], reason: 'the next frame pings once more');

      run.runtimeOrNull!.removeTickListener(listener);
      _state(game).advance(_step * 2);
      expect(ticks, [3, 4], reason: 'a removed listener stops being called');
      expect(run.tick, 6, reason: 'but the loop kept ticking');
    });

    test('the pool has committed by the time a listener runs', () async {
      final game = await _game(_TestGame());
      final scene = _state(game).getScene<_TestScene>();
      final entity = _state(game).loadedScenes.single.addEntity(scene.unit);
      run.runtimeOrNull!.addTickListener((_) {
        expect(scene.pool.isTickOpen, isFalse);
        expect(scene.unit.marker[entity], 7);
      });
      _state(game).advance(_step);
    });
  });

  group('handle vs simulation', () {
    // 'a Game that never started has no state at all' lived here. A Game
    // has no `state` at any point now - started or not - so the property
    // is carried by the type rather than by a test.

    test('the inline copy is the one that simulates', () async {
      final game = await _game(_TestGame());
      expect(
        run.state.isSimulating,
        isTrue,
        reason: 'inline means one copy doing both jobs',
      );
      expect(run.state.scene, isA<_TestScene>());
      expect(
        run.state.game,
        same(game),
        reason: 'the back-reference is typed and points at this copy',
      );
    });

    test('starting twice is an error', () async {
      final game = await _game(_TestGame());
      expect(Game.startInline(game), throwsStateError);
    });

    test(
      'advance/runFixedStep refuse to run on a state that is not simulating',
      () {
        // A GameState that was never marked as owning the simulation is exactly
        // what the main isolate's handle copy holds after start().
        final handle = _TestState();
        expect(() => handle.advance(_step), throwsStateError);
        expect(handle.runFixedStep, throwsStateError);
      },
    );

    test('a GameState with no scene is legitimate, and still ticks', () async {
      final game = await _game(_ScenelessGame());
      expect(
        run.state.scene,
        isNull,
        reason:
            'a game that never calls loadScene has no world - '
            'world loaded at all',
      );
      expect(
        run.state.pool.pageCount,
        0,
        reason:
            'the pool belongs to the Game now, not the scene, so a game '
            'with no world has an empty pool rather than no pool - which is '
            'why the tick loop no longer asks whether there is storage',
      );
      expect(
        _state(game).advance(_step * 2),
        2,
        reason: 'systems still run without a world to run over',
      );
      expect(log, ['A', 'A']);
      expect(() => run.state.getScene<_TestScene>(), throwsStateError);
    });

    // DELETED: 'loadScene is explicitly unimplemented, not silently broken'.
    // `Game.loadScene` was a stub that only ever threw, kept while scene
    // transitions were being designed. It is gone rather than implemented:
    // loading registers archetypes, spawns entities and claims assets, all of
    // which are simulation acts the presentation copy has no world to perform.
    // `GameState.loadScene` is the only spelling, and a main-triggered
    // transition goes through a command whose handler runs over there.
    test(
      'loadScene is a GameState method, and refuses a mirror copy',
      () async {
        await _game(_TestGame());
        // Inline, so this copy does simulate and the call is legal - the point
        // is that the method is reached through the state at all.
        expect(run.state.isSimulating, isTrue);
        expect(run.state.loadScene(_TestScene()), isA<Future<Scene>>());
      },
    );
  });

  // DELETED: the two 'where the frame went' timing assertions. `advance` used
  // to carry a Stopwatch and publish lastSimulationMicros /
  // lastPresentationMicros / lastAdvanceMicros / lastAdvanceIntervalMicros;
  // those were benchmarking instrumentation and are gone, so an assertion that
  // one of them returned a non-negative int went with them. What the two tests
  // were *also* checking survives here, split from the timings it was mixed
  // with: presentation running once per frame regardless of step count is
  // covered by 'presentation phase (Tickable)' above, and the step count
  // itself is below.
  group('lastStepCount', () {
    test('reports the steps the last advance ran', () async {
      await _game(_TestGame());
      // Two spellings of the same number, and they have to agree: a host
      // driving the loop reads the return value, while anything asking after
      // the fact - a HUD dividing a per-advance total to get a per-step one -
      // reads the field.
      expect(run.advance(_step * 3), 3);
      expect(run.state.lastStepCount, 3);
    });

    test('is zero on a frame the accumulator could not fill', () async {
      await _game(_TestGame());
      expect(run.advance(const Duration(milliseconds: 1)), 0);
      expect(
        run.state.lastStepCount,
        0,
        reason: 'the accumulator had not filled',
      );
    });
  });
}

class _UndeclaredSystem extends GameSystem {}

/// The "no world yet" configuration: a GameState that declares no scene.
class _ScenelessState extends GameState<_ScenelessGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_SystemA());
  }
}

class _ScenelessGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _ScenelessState();
}
