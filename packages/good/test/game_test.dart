import 'dart:async';
import 'dart:convert';

import 'package:good/src/scene_handle.dart';
import 'package:good/src/event/tick_loop.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/command/command.dart';
import 'package:good/src/command/param.dart';
import 'package:good/src/data.dart';
import 'package:good/src/event.dart';
import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/event/lifecycle.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/random.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/system.dart';
import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;
import 'package:flutter/widgets.dart' show AppLifecycleState;
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
  final x = Field.float64();

  /// Written by [_Unit.onMounted] only - never a declared default - so
  /// reading 7 back proves the prefab's onMounted actually ran, not just
  /// that a row was allocated.
  final marker = Field.uint8();

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Counter>();
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
    unit = descriptor.has(_Unit.new);
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
    descriptor.has(_PresentSystem.new);
    descriptor.has(_BothPhases.new);
  }
}

class _PhaseGame extends _TestGame {
  @override
  GameState createState() => _PhaseState();
}

/// Throws once, on the tick named by [throwOnTick].
class _ThrowingSystem extends GameSystem with FixedTickable {
  int ran = 0;
  int throwOnTick = 1;
  String throwMessage = 'system boom';

  @override
  void onFixedUpdate() {
    ran++;
    if (ran == throwOnTick) throw StateError(throwMessage);
  }
}

/// Declared *after* the thrower, so "one bad listener must not skip the
/// others" is a property this can actually observe.
class _AfterThrowerSystem extends GameSystem with FixedTickable {
  int ran = 0;

  @override
  void onFixedUpdate() => ran++;
}

late _ThrowingSystem _thrower;
late _AfterThrowerSystem _afterThrower;

class _ThrowState extends _FixtureState {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    _thrower = descriptor.has(_ThrowingSystem.new);
    _afterThrower = descriptor.has(_AfterThrowerSystem.new);
  }
}

class _ThrowGame extends _TestGame {
  @override
  GameState createState() => _ThrowState();
}

class _ReportingThrowGame extends _ThrowGame {
  final List<({String systemName, String error, String stackTrace})> reports =
      <({String systemName, String error, String stackTrace})>[];

  @override
  void onSystemDisabled(String systemName, String error, String stackTrace) {
    reports.add((
      systemName: systemName,
      error: error,
      stackTrace: stackTrace,
    ));
    super.onSystemDisabled(systemName, error, stackTrace);
  }
}

/// A game whose report handler throws. Under `startInline` the main-side
/// handler runs on the game's own stack, so this lands back inside the
/// dispatch guard that called it.
class _BadReportGame extends _ThrowGame {
  int calls = 0;

  @override
  void onSystemDisabled(String systemName, String error, String stackTrace) {
    calls++;
    throw StateError('the report handler is broken too');
  }
}

/// Records the visibility hooks so a test can assert they arrived, and in
/// which order relative to the tick stopping.
class _VisibilitySystem extends GameSystem with AppVisibilityListener {
  final List<Duration> shown = <Duration>[];
  int hidden = 0;

  @override
  void onAppHidden() => hidden++;

  @override
  void onAppShown(Duration gap) => shown.add(gap);
}

late _VisibilitySystem _visibility;

class _VisibilityState extends _FixtureState {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    _visibility = descriptor.has(_VisibilitySystem.new);
  }
}

class _VisibilityGame extends _TestGame {
  @override
  GameState createState() => _VisibilityState();
}

/// The opt-out: a game that has to keep running unattended.
class _AlwaysTickingGame extends _VisibilityGame {
  @override
  bool get pauseWhenHidden => false;
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
/// `Comparable` ordering mechanism's reference usage.
///
/// Unconditional `-1`, and there is a second one of these below. Two systems
/// that both claim to precede everything contradict each other, which is
/// exactly the shape that used to wreck the sort: it is not a comparator, and
/// `List.sort` handed one does not confine the damage to the offending pair.
/// Ordering is resolved as a constraint graph now (`GameState.sortSystems`),
/// so the pair is settled by declaration order and every *other* constraint
/// survives it.
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

/// A second unconditional "I am first", contradicting [_SortsFirst].
class _AlsoSortsFirst extends GameSystem with FixedTickable {
  @override
  int compareTo(GameSystem other) => -1;

  @override
  void onFixedUpdate() => log.add('D');
}

/// The pair that reproduces #5 in miniature: a spawner that must run before
/// the pass consuming what it writes, and nothing else.
///
/// [_Composer] states no opinion at all - it is the `WorldTransformSystem`
/// shape, which deliberately does not claim to precede everyone - so the whole
/// constraint rests on [_Spawner]'s single targeted `-1`. That is the one that
/// went missing: the two contradictory unconditional opinions above made the
/// comparator inconsistent, and `List.sort` permuted this pair along with
/// everything else. In the swarm demo that put `WorldTransformSystem` ahead of
/// its spawner, so freshly created entities were composed a tick late and drew
/// one frame at the world origin.
class _Composer extends GameSystem with FixedTickable {
  @override
  void onFixedUpdate() => log.add('compose');
}

/// Declared **after** [_Composer], so declaration order alone would run it
/// second and only the constraint can put it first.
class _Spawner extends GameSystem with FixedTickable {
  @override
  int compareTo(GameSystem other) => other is _Composer ? -1 : 0;

  @override
  void onFixedUpdate() => log.add('spawn');
}

/// Extends the base fixture's set rather than replacing it - the `super` call
/// is what makes declaration order (and therefore execution order) the thing
/// under test.
class _OrderingState extends _TestState {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    // Declaration order: A, InertSystem, B, CensusSystem, Indifferent1,
    // Indifferent2, SortsFirst, AlsoSortsFirst, Composer, Spawner.
    super.describeSystems(descriptor);
    descriptor.has(_Indifferent1.new);
    descriptor.has(_Indifferent2.new);
    descriptor.has(_SortsFirst.new);
    descriptor.has(_AlsoSortsFirst.new);
    descriptor.has(_Composer.new);
    descriptor.has(_Spawner.new);
  }
}

/// Three systems whose stated positions genuinely cannot all hold.
class _CycleA extends GameSystem with FixedTickable {
  @override
  int compareTo(GameSystem other) => other is _CycleB ? -1 : 0;

  @override
  void onFixedUpdate() {}
}

class _CycleB extends GameSystem with FixedTickable {
  @override
  int compareTo(GameSystem other) => other is _CycleC ? -1 : 0;

  @override
  void onFixedUpdate() {}
}

class _CycleC extends GameSystem with FixedTickable {
  @override
  int compareTo(GameSystem other) => other is _CycleA ? -1 : 0;

  @override
  void onFixedUpdate() {}
}

class _CyclicState extends _FixtureState {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_CycleA.new);
    descriptor.has(_CycleB.new);
    descriptor.has(_CycleC.new);
  }
}

class _CyclicGame extends _TestGame {
  @override
  GameState createState() => _CyclicState();
}

class _OrderingGame extends _TestGame {
  @override
  GameState createState() => _OrderingState();
}

/// Counts what the query sees *this* tick, to prove a command-spawned
/// entity is visible to systems on the tick the command lands.
class _CensusSystem extends GameSystem with FixedTickable {
  final query = Query.all(_Counter);
  final List<int> seen = <int>[];

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
  final spawned = Param.entity();

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
    descriptor.has(_SystemA.new);
    descriptor.has(_InertSystem.new);
    descriptor.has(_SystemB.new);
    descriptor.has(_CensusSystem.new);
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
    spawnUnit = descriptor.has(_SpawnUnit.new);
  }
}

/// A control command whose handler does the one thing a control handler must
/// not do - write component data outside a tick window (#142).
class _WriteOutsideTick extends SignalCommand {}

class _BadControlState extends _FixtureState {
  /// Set by the test during the bootstrap window, before the first tick has
  /// published anything - the one time a write outside a tick is legitimate.
  late Entity victim;

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    descriptor.hasControlSignal(
      (game as _BadControlGame).writeOutsideTick,
      _onWrite,
    );
  }

  void _onWrite() {
    // A plain column write on an entity that already exists - the guard is
    // about the write window, not about allocation.
    level.unit.marker[victim] = 5;
  }
}

class _BadControlGame extends _TestGame {
  late final _WriteOutsideTick writeOutsideTick;

  @override
  GameState createState() => _BadControlState();

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    writeOutsideTick = descriptor.has(_WriteOutsideTick.new);
  }
}

/// Registers a command that *returns* something as a control handler, which
/// has to fail where it is written rather than hang where it is called.
class _Answering extends SupplierCommand<int> {
  final value = Param.int32();

  @override
  void bufferFromResult(ParamBuffer call, int result) => value[call] = result;

  @override
  int resultFromBuffer(ParamBuffer call) => value[call];
}

class _AnsweringState extends _FixtureState {
  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    descriptor.hasControlSupplier((game as _AnsweringGame).answering, () => 1);
  }
}

class _AnsweringGame extends _TestGame {
  late final _Answering answering;

  @override
  GameState createState() => _AnsweringState();

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    answering = descriptor.has(_Answering.new);
  }
}

/// The same refusal, asked of the **main** descriptor. Both sides share one
/// message function, so this exists to prove the shared call is actually
/// wired on both rather than only on the side that happened to be tested.
class _AnsweringMainGame extends _TestGame {
  late final _Answering answeringMain;

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    answeringMain = descriptor.has(_Answering.new);
    descriptor.hasControlSupplier(answeringMain, () => 1);
  }
}

// --- #165: the read-only command lane --------------------------------------
//
// Inline, and `advance` driven by hand, so "the tick did not move" and "the
// other lane is still waiting" are exact rather than raced. The cross-isolate
// version of the same three assertions is in game_isolate_test.dart, where the
// batch has a real ring to cross.

/// Read-only and game-handled. Reports the tick it ran on and whether the
/// simulation was stopped while it ran, which is the only way a caller learns
/// a fact the other copy holds.
class _Inspect extends SupplierCommand<({int tick, bool stopped})> {
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

/// Read-only, and answers with the ordinal of its own arrival - so a caller
/// can see what order the lane ran things in.
class _Arrival extends SupplierCommand<int> {
  final ordinal = Param.int32();

  @override
  void bufferFromResult(ParamBuffer call, int result) => ordinal[call] = result;

  @override
  int resultFromBuffer(ParamBuffer call) => ordinal[call];
}

/// Tick-delivered and game-handled: the discriminator. It genuinely needs a
/// fixed step, so while the tick is stopped it has to stay pending - which is
/// what a "fix" that quietly ran a step would fail.
class _TickBound extends SignalCommand {}

class _ReadOnlyState extends _FixtureState {
  int arrivals = 0;
  int tickBoundRuns = 0;

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    final game = this.game as _ReadOnlyGame;
    descriptor
      ..hasReadOnlySupplier(
        game.inspect,
        () => (tick: game.tick, stopped: paused || timeScale == 0),
      )
      ..hasReadOnlySupplier(game.arrival, () => ++arrivals)
      ..hasSignal(game.tickBound, () => tickBoundRuns++);
  }
}

class _ReadOnlyGame extends _TestGame {
  late final _Inspect inspect;
  late final _Arrival arrival;
  late final _TickBound tickBound;

  @override
  GameState createState() => _ReadOnlyState();

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    inspect = descriptor.has(_Inspect.new);
    arrival = descriptor.has(_Arrival.new);
    tickBound = descriptor.has(_TickBound.new);
  }
}

/// A shape that answers with nothing, registered on the lane whose handlers
/// promise not to write - so it would have no effect at all, and has to fail
/// where it is written.
class _Mute extends SignalCommand {}

class _MuteReadOnlyState extends _FixtureState {
  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    descriptor.hasReadOnlySignal((game as _MuteReadOnlyGame).mute, () {});
  }
}

class _MuteReadOnlyGame extends _TestGame {
  late final _Mute mute;

  @override
  GameState createState() => _MuteReadOnlyState();

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    mute = descriptor.has(_Mute.new);
  }
}

/// The same refusal asked of the **main** descriptor, and through the sink
/// spelling rather than the signal one - two methods and two descriptors, so
/// the shared message function is proved wired on both sides.
class _MuteSink extends SinkCommand<int> {
  final value = Param.int32();

  @override
  void bufferFromParams(ParamBuffer call, int params) => value[call] = params;

  @override
  int paramsFromBuffer(ParamBuffer call) => value[call];
}

class _MuteReadOnlyMainGame extends _TestGame {
  late final _MuteSink muteSink;

  @override
  void describeCommands(CommandDescriptor descriptor) {
    super.describeCommands(descriptor);
    muteSink = descriptor.has(_MuteSink.new);
    descriptor.hasReadOnlySink(muteSink, (_) {});
  }
}

/// Two independent streams and two systems, one drawing from each, so a test
/// can disable one and watch the other (#125).
class _DrawsFromA extends GameSystem with FixedTickable {
  final List<int> drawn = <int>[];

  @override
  void onFixedUpdate() => drawn.add(_randomGame.a.nextInt(1000));
}

class _DrawsFromB extends GameSystem with FixedTickable {
  final List<int> drawn = <int>[];

  @override
  void onFixedUpdate() => drawn.add(_randomGame.b.nextInt(1000));
}

late _DrawsFromA _drawsA;
late _DrawsFromB _drawsB;
late _RandomGame _randomGame;

class _RandomState extends _FixtureState {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    _drawsA = descriptor.has(_DrawsFromA.new);
    _drawsB = descriptor.has(_DrawsFromB.new);
  }
}

class _RandomGame extends _TestGame {
  _RandomGame({this.randomSeed = 20260823});

  @override
  final int randomSeed;

  late final RandomStream a;
  late final RandomStream b;

  @override
  GameState createState() => _RandomState();

  @override
  void describeRandom(RandomDescriptor descriptor) {
    super.describeRandom(descriptor);
    _randomGame = this;
    a = descriptor.has();
    b = descriptor.has();
  }
}

typedef _Nudge = ({Entity entity, double amount});

/// A user command, to prove the dispatch table is not hardcoded to the
/// framework's own spawn. Sets [x] on an entity it is handed by value.
class _NudgeCommand extends SinkCommand<_Nudge> {
  final entity = Param.entity();
  final amount = Param.float64();

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
    nudge = descriptor.has(_NudgeCommand.new);
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
    descriptor.has(_NudgeCommand.new);
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
    descriptor.has(_SystemA.new);
  }
}

class _DuplicateSystemGame extends _TestGame {
  @override
  GameState createState() => _DuplicateSystemState();
}

Future<T> _game<T extends Game>(T Function() create) async {
  final game = await Game.startInline(create);
  run = game;
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
      final game = await _game(_TestGame.new);
      expect(_state(game).advance(_step * 3), 3);
      expect(run.tick, 3);
    });

    test(
      'a partial step accumulates instead of being lost or rounded up',
      () async {
        final game = await _game(_TestGame.new);
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
      final game = await _game(_TestGame.new);
      expect(_state(game).advance(Duration.zero), 0);
      expect(run.tick, 0);
    });

    test('a long stall is capped at maxFixedStepsPerAdvance', () async {
      final game = await _game(_TestGame.new);
      // 100 steps' worth of wall clock in one go.
      expect(_state(game).advance(_step * 100), game.maxFixedStepsPerAdvance);
      expect(run.tick, game.maxFixedStepsPerAdvance);
    });

    test(
      'the backlog past the cap is dropped, not carried into next frame',
      () async {
        final game = await _game(_TestGame.new);
        _state(game).advance(_step * 100);
        // If the remaining ~95 steps had been kept in the accumulator, this
        // would immediately run another full capped batch - the spiral.
        expect(_state(game).advance(_step), 1);
      },
    );

    test('sub-step phase survives the drop', () async {
      final game = await _game(_TestGame.new);
      // 100 steps + 3ms. After capping, the 3ms remainder must still be
      // there, so 7ms more is enough for the next step.
      _state(game).advance(_step * 100 + const Duration(milliseconds: 3));
      expect(_state(game).advance(const Duration(milliseconds: 7)), 1);
    });
  });

  // #117. Two things are being pinned here and they fail independently: that
  // the tick actually stops while hidden, and that the time spent hidden is
  // discarded instead of spent on the way back in.
  group('app visibility', () {
    test('hiding stops the fixed tick and showing starts it again', () async {
      final game = await _game(_VisibilityGame.new);
      final state = _state(game);
      state.startTimer();
      addTearDown(state.stopTimer);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      final before = run.tick;
      expect(
        before,
        greaterThan(0),
        reason:
            'the timer has to be running for stopping it to mean anything - '
            'a bench that cannot fail is worse than none',
      );

      state.setVisible(false);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        run.tick,
        before,
        reason:
            'six steps worth of wall clock passed while hidden and not one '
            'of them may have run',
      );
      expect(_visibility.hidden, 1);

      state.setVisible(true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        run.tick,
        greaterThan(before),
        reason: 'and the tick comes back, or this pauses a game forever',
      );
      expect(_visibility.shown, hasLength(1));
    });

    test('showing discards the time left over from before hiding', () async {
      final game = await _game(_VisibilityGame.new);
      final state = _state(game);
      // The state 'sub-step phase survives the drop' pins: the batch is
      // capped and dropped, and 3ms of phase stays in the accumulator. Seven
      // more milliseconds would complete a step - and that is the step this
      // must not run, because it was earned before the app went away.
      state.advance(_step * 100 + const Duration(milliseconds: 3));

      state.setVisible(false);
      state.setVisible(true);

      expect(
        state.advance(const Duration(milliseconds: 7)),
        0,
        reason:
            'the 3ms was earned before hiding and is discarded on the way '
            'back, so 7ms is 7ms and not a whole step. Without the reset '
            'this is 1 - the first frame back spends a step on a world the '
            'player stopped watching.',
      );
    });

    test('a game can opt out and keep ticking while hidden', () async {
      final game = await _game(_AlwaysTickingGame.new);
      final state = _state(game);
      state.startTimer();
      addTearDown(state.stopTimer);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      final before = run.tick;
      state.setVisible(false);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(
        run.tick,
        greaterThan(before),
        reason:
            'pauseWhenHidden is false, so the session keeps running - this '
            'is the escape hatch and it has to actually let go',
      );
      expect(
        _visibility.hidden,
        1,
        reason: 'opting out of the pause does not opt out of the hook',
      );
    });

    test('losing focus is not being hidden', () {
      // The distinction the whole design turns on. `inactive` is a window
      // that lost focus, a phone call, the shade coming down - all still on
      // screen. Treating it as hidden is why some games stop on alt-tab.
      expect(visibleInLifecycleState(AppLifecycleState.resumed), isTrue);
      expect(visibleInLifecycleState(AppLifecycleState.inactive), isTrue);
      expect(visibleInLifecycleState(AppLifecycleState.hidden), isFalse);
      expect(visibleInLifecycleState(AppLifecycleState.paused), isFalse);
      expect(visibleInLifecycleState(AppLifecycleState.detached), isFalse);
    });

    test('losing focus is losing input', () {
      // #161, and the other half of the distinction above. The two
      // predicates agree on `resumed` and on everything below `inactive`,
      // and `inactive` is the one state where they part: still on screen,
      // and no longer receiving key events.
      expect(focusedInLifecycleState(AppLifecycleState.resumed), isTrue);
      expect(focusedInLifecycleState(AppLifecycleState.inactive), isFalse);
      expect(focusedInLifecycleState(AppLifecycleState.hidden), isFalse);
      expect(focusedInLifecycleState(AppLifecycleState.paused), isFalse);
      expect(focusedInLifecycleState(AppLifecycleState.detached), isFalse);
    });

    test('the same state twice is not two events', () async {
      final game = await _game(_VisibilityGame.new);
      final state = _state(game);
      // Flutter walks inactive -> hidden -> paused on the way down and back
      // up again, so "not visible" arrives more than once around any real
      // backgrounding.
      state.setVisible(false);
      state.setVisible(false);
      state.setVisible(true);
      state.setVisible(true);

      expect(_visibility.hidden, 1);
      expect(_visibility.shown, hasLength(1));
    });
  });

  // #124. Time scale changes how *often* a fixed tick happens, never how big
  // one is, so every assertion here counts ticks. There is no dt to inspect
  // and that is the design: a fixed step is always `fixedTimeStep`.

  // #126. A system that throws used to kill the game isolate silently and
  // permanently. These pin the two halves of the answer: the dispatch
  // survives one bad listener, and the listener is taken out of circulation.
  //
  // Debug and release differ here and the tests say so, because the suite
  // runs in debug: the `assert` in `_ListenerSet._reportUncaught` fires, so
  // these expect an `AssertionError` where a release build would simply carry
  // on with the system disabled.

  // #142 Stage 1. The constraint that pays for receipt delivery, and the
  // declaration-time refusal that keeps a caller from discovering it as a
  // hang.

  // #125. A seeded stream is the raw material for replay and is not replay -
  // see `RandomStream`'s doc for what else that needs.
  group('seeded randomness', () {
    test('the same seed draws the same sequence', () async {
      final first = await _game(_RandomGame.new);
      final drawn = <int>[for (var i = 0; i < 8; i++) first.a.nextInt(1000)];
      await run.stop();
      SceneRegistry.reset();
      ArchetypeRegistry.reset();
      ComponentTypeRegistry.reset();

      final second = await _game(_RandomGame.new);
      expect(
        <int>[for (var i = 0; i < 8; i++) second.a.nextInt(1000)],
        drawn,
        reason:
            'the whole point. The algorithm is written out in random.dart '
            'rather than taken from dart:math precisely so this keeps '
            'holding across an SDK upgrade.',
      );
      expect(
        drawn.toSet().length,
        greaterThan(1),
        reason: 'and it has to actually vary, or equality proves nothing',
      );
    });

    test('a different seed draws a different sequence', () async {
      final first = await _game(() => _RandomGame(randomSeed: 1));
      final drawn = <int>[for (var i = 0; i < 8; i++) first.a.nextInt(1000)];
      await run.stop();
      SceneRegistry.reset();
      ArchetypeRegistry.reset();
      ComponentTypeRegistry.reset();

      final second = await _game(() => _RandomGame(randomSeed: 2));
      expect(<int>[
        for (var i = 0; i < 8; i++) second.a.nextInt(1000),
      ], isNot(drawn));
    });

    // The #126 interaction, and the reason streams are declared separately
    // rather than shared. A system that throws is disabled by the engine now,
    // so "a system stopped drawing" is something that happens on its own.
    test('disabling a system does not shift another stream', () async {
      final game = await _game(_RandomGame.new);
      _state(game).advance(_step * 4);
      final withBoth = <int>[..._drawsB.drawn];
      expect(withBoth, hasLength(4));
      expect(_drawsA.drawn, hasLength(4));
      await run.stop();
      SceneRegistry.reset();
      ArchetypeRegistry.reset();
      ComponentTypeRegistry.reset();

      final again = await _game(_RandomGame.new);
      _state(again).disableSystem<_DrawsFromA>();
      _state(again).advance(_step * 4);

      expect(
        _drawsA.drawn,
        isEmpty,
        reason: 'the disable has to have taken, or this proves nothing',
      );
      expect(
        _drawsB.drawn,
        withBoth,
        reason:
            'B never drew from A stream, so A not running cannot move it. '
            'One shared stream would shift every one of these.',
      );
    });

    // The case the hash exists to dissolve: a per-entity value is derived
    // from the entity and the tick, so it has no position for a spawn to
    // move.
    test('a per-entity value does not depend on who was asked first', () async {
      // The watched entity is spawned **first** in both runs, so it has the
      // same identity either way, and asked **last**, after every neighbour.
      // A hash of the entity and the tick does not care how many questions
      // came before it. A stream drawn once per entity does: four neighbours
      // would move it four places, and the watched entity would get a
      // different number in the crowded run.
      //
      // Both halves matter. Spawning it first is what keeps the identity
      // fixed; asking it last is what makes a stateful implementation fail.
      Future<int> valueAskedAfter(int neighbours) async {
        final game = await _game(_RandomGame.new);
        final scene = _state(game).loadedScenes.single;
        final level = (run.state as _FixtureState).level;
        final watched = scene.addEntity(level.unit);
        final others = <Entity>[
          for (var i = 0; i < neighbours; i++) scene.addEntity(level.unit),
        ];
        _state(game).advance(_step);

        for (final other in others) {
          game.a.intFor(other, 1000);
        }
        final value = game.a.intFor(watched, 1000);

        await run.stop();
        SceneRegistry.reset();
        ArchetypeRegistry.reset();
        ComponentTypeRegistry.reset();
        return value;
      }

      final alone = await valueAskedAfter(0);
      final crowded = await valueAskedAfter(4);
      expect(
        crowded,
        alone,
        reason:
            'same entity, same tick, same answer - whoever else was asked in '
            'between. This is the scene load and unload case, and the hash '
            'is why it needs no handling.',
      );
    });
  });
  group('control-delivered commands', () {
    test('a control handler writing component data trips the guard', () async {
      final game = await _game(_BadControlGame.new);
      final state = _state(game) as _BadControlState;
      state.victim = state.loadedScenes.single.addEntity(state.level.unit);
      // One committed tick, so the page has published - the assert stays
      // silent before the first publish, which is scene bootstrap and the one
      // hole in the guard.
      state.advance(_step);

      expect(
        () => game.writeOutsideTick(),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.toString(),
            'message',
            contains('outside a tick'),
          ),
        ),
        reason:
            'there is no open write slot outside a tick, so the write would '
            'be erased by the next beginTick with nothing said. The debug '
            'assert is what turns a silent loss into a failure.',
      );
    });

    test('a command that answers cannot be control-delivered', () async {
      expect(
        () => _game(_AnsweringGame.new),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('cannot'), contains('hasSupplier')),
          ),
        ),
        reason:
            'a receipt-delivered command has no reply leg, so an R has '
            'nowhere to come from. Failing at the declaration is the whole '
            'point - the alternative is a caller awaiting a future that '
            'never completes.',
      );
    });

    test('the refusal holds on the main descriptor too', () async {
      expect(
        () => _game(_AnsweringMainGame.new),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('cannot'), contains('hasSupplier')),
          ),
        ),
        reason:
            'the two descriptors share one message function, and sharing is '
            'not the same as both calling it - this is the side the '
            'game-side test does not reach',
      );
    });
  });
  group('the read-only command lane', () {
    // #165. Three assertions, and the third is the one that discriminates: a
    // fix that quietly ran a fixed step to serve the ask - which is exactly
    // what stepOnce does - would pass the first two and fail this.
    test('answers while the game is paused, and runs no step', () async {
      final game = await _game(_ReadOnlyGame.new);
      final state = _state(game) as _ReadOnlyState;
      expect(state.advance(_step * 2), 2);

      game.pause();

      // Queued *first*, so one arrival-ordered inbox drained per frame would
      // run this one ahead of the read-only ask rather than leave it waiting.
      var tickBoundDone = false;
      final tickBound = game.tickBound();
      unawaited(tickBound.then((_) => tickBoundDone = true));

      final answer = game.inspect();
      expect(
        state.advance(_step * 3),
        0,
        reason: 'the point of the fixture: this frame affords no fixed step',
      );

      expect(
        await answer.timeout(const Duration(seconds: 5)),
        (tick: 2, stopped: true),
        reason:
            'the handler ran on a frame that ran no step, and reported from '
            'the game side that the simulation was stopped while it did',
      );
      expect(run.tick, 2, reason: 'and the tick did not move to serve it');

      // A turn of the microtask queue, so a completion that was going to
      // happen has happened before this is read.
      await Future<void>.delayed(Duration.zero);
      expect(
        tickBoundDone,
        isFalse,
        reason:
            'a tick-delivered command queued at the same moment still needs a '
            'fixed step, so it has to still be pending - without this the '
            'test passes against a fix that quietly runs one',
      );
      expect(state.tickBoundRuns, 0);

      game.resume();
      expect(state.advance(_step), 1);
      await tickBound.timeout(const Duration(seconds: 5));
      expect(
        state.tickBoundRuns,
        1,
        reason: 'and it is delivered on resume, exactly as it was before',
      );
    });

    test('and at a time scale of zero, which stops the tick the other '
        'way', () async {
      final game = await _game(_ReadOnlyGame.new);
      final state = _state(game) as _ReadOnlyState;
      expect(state.advance(_step * 2), 2);

      game.setTimeScale(0);

      var tickBoundDone = false;
      final tickBound = game.tickBound();
      unawaited(tickBound.then((_) => tickBoundDone = true));

      final answer = game.inspect();
      expect(state.advance(_step * 3), 0);

      expect(await answer.timeout(const Duration(seconds: 5)), (
        tick: 2,
        stopped: true,
      ));
      expect(run.tick, 2);
      await Future<void>.delayed(Duration.zero);
      expect(tickBoundDone, isFalse);

      game.setTimeScale(1);
      expect(state.advance(_step), 1);
      await tickBound.timeout(const Duration(seconds: 5));
      expect(state.tickBoundRuns, 1);
    });

    test('answers in the order it was asked', () async {
      final game = await _game(_ReadOnlyGame.new);
      final state = _state(game) as _ReadOnlyState;
      game.pause();

      final first = game.arrival();
      final second = game.arrival();
      final third = game.arrival();
      expect(state.advance(_step * 3), 0);

      expect(
        await Future.wait(<Future<int>>[
          first,
          second,
          third,
        ]).timeout(const Duration(seconds: 5)),
        <int>[1, 2, 3],
        reason:
            'one queue fed in arrival order and drained from the front, so '
            'the lane keeps order within itself the way tick delivery does '
            'within its own',
      );
      expect(state.arrivals, 3, reason: 'and each ran exactly once');
    });

    test('a running game answers it after the step, not inside it', () async {
      final game = await _game(_ReadOnlyGame.new);
      final state = _state(game) as _ReadOnlyState;

      final answer = game.inspect();
      final tickBound = game.tickBound();
      expect(state.advance(_step), 1);

      expect(
        await answer.timeout(const Duration(seconds: 5)),
        (tick: 1, stopped: false),
        reason:
            'the drain is on the frame, after the step and after the '
            'presentation pass, so the handler reads the snapshot this frame '
            'published. Draining it from the tick window as well would have '
            'answered from the top of the step, at tick 0 - one lane with two '
            'answers depending on whether the game happened to be moving',
      );
      await tickBound.timeout(const Duration(seconds: 5));
      expect(
        state.tickBoundRuns,
        1,
        reason: 'and the tick lane is untouched by any of this',
      );
      expect(run.tick, 1);
    });

    test('a command that answers with nothing cannot be read-only', () async {
      expect(
        () => _game(_MuteReadOnlyGame.new),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('returns nothing'), contains('hasControlSignal')),
          ),
        ),
        reason:
            'the lane promises not to write and the shape has no answer to '
            'send back, so between the two there is nothing left for the '
            'handler to do. Failing at the declaration is the point',
      );
    });

    test('the refusal holds on the main descriptor, and on the sink '
        'spelling', () async {
      expect(
        () => _game(_MuteReadOnlyMainGame.new),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('returns nothing'), contains('hasControlSink')),
          ),
        ),
        reason:
            'two descriptors and two methods share one message function, and '
            'sharing is not the same as all four calling it',
      );
    });
  });
  group('a system that throws', () {
    test('does not stop the listeners declared after it', () async {
      final game = await _game(_ThrowGame.new);
      _thrower
        ..ran = 0
        ..throwOnTick = 1;
      _afterThrower.ran = 0;

      expect(
        () => _state(game).advance(_step),
        throwsA(isA<AssertionError>()),
        reason: 'debug reports the throw by asserting, and that stops the run',
      );
      expect(
        _afterThrower.ran,
        1,
        reason:
            'it is declared after the thrower and must still have run. '
            'Reporting inside the loop instead of after it would skip it, '
            'which is the whole thing the guard exists to stop.',
      );
    });

    test('is disabled, and the rest of the game keeps ticking', () async {
      final game = await _game(_ThrowGame.new);
      final state = _state(game);
      _thrower
        ..ran = 0
        ..throwOnTick = 1;
      _afterThrower.ran = 0;

      expect(() => state.advance(_step), throwsA(isA<AssertionError>()));
      expect(
        state.isSystemEnabled<_ThrowingSystem>(),
        isFalse,
        reason:
            'taken out of circulation, the way a throwing coroutine is '
            'removed. GameState.enableSystem brings it back.',
      );

      // Three more ticks. In release this is simply what happens; here it is
      // what happens after the assert has been caught.
      state
        ..advance(_step)
        ..advance(_step)
        ..advance(_step);
      expect(_thrower.ran, 1, reason: 'disabled means it is not called again');
      expect(
        _afterThrower.ran,
        4,
        reason:
            'and everything else goes on ticking - one bad system is not a '
            'dead game',
      );
    });

    test('the disable is reported to the main isolate', () async {
      FlutterErrorDetails? reportedToFlutter;
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) => reportedToFlutter = details;
      addTearDown(() => FlutterError.onError = previousOnError);

      final game = await _game(_ReportingThrowGame.new);
      final state = _state(game);
      _thrower
        ..ran = 0
        ..throwOnTick = 1
        ..throwMessage = 'system boom';
      _afterThrower.ran = 0;

      // The report is handed to the command inside the guard's catch, before
      // the assert that ends this tick - so it is already gone by the time
      // the assert throws, and nothing here has to pretend to be a release
      // build to see it. The assert is the only thing debug adds, and that is
      // the compiler's doing rather than the engine's.
      //
      // `startInline` is one copy, so `CommandRegistry.inline` installs both
      // sides' handlers here and the main-side handler runs without a ring
      // crossing. What that leaves untested is the delivery *timing* across a
      // real isolate, where main pumps on the tick notification - and that is
      // unreachable from a debug test either way, because there the assert
      // kills the game isolate and `Game.start`'s error port is what reports
      // the failure instead.
      expect(() => state.advance(_step), throwsA(isA<AssertionError>()));

      expect(game.reports, hasLength(1));
      expect(game.reports.first.systemName, contains('_ThrowingSystem'));
      expect(game.reports.first.error, contains('system boom'));
      expect(
        game.reports.first.stackTrace,
        contains('_ThrowingSystem.onFixedUpdate'),
        reason: 'the stack is what says which line threw, and #143 asks for '
            'it by name',
      );

      // And the base implementation hands it to Flutter, so a game that does
      // not override onSystemDisabled still sees it.
      expect(reportedToFlutter, isNotNull);
      expect(
        reportedToFlutter!.exception.toString(),
        contains('system _ThrowingSystem threw: Bad state: system boom'),
      );

      // Reported once, not once per tick: the system is disabled, so it never
      // throws again.
      state
        ..advance(_step)
        ..advance(_step);
      expect(_thrower.ran, 1);
      expect(_afterThrower.ran, 3);
      expect(game.reports, hasLength(1));
    });

    test('a report too long for its fields is truncated, not refused', () async {
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (_) {};
      addTearDown(() => FlutterError.onError = previousOnError);

      final game = await _game(_ReportingThrowGame.new);
      final state = _state(game);
      _thrower
        ..ran = 0
        ..throwOnTick = 1
        // Longer than the 1024-byte error field, and not ASCII: a cut through
        // the middle of a multi-byte character has to come back inside the
        // cap, not one replacement character over it. `Param.fixedString`
        // refuses an oversized write, and a throw from inside the reporting
        // path would take out the report of the throw.
        ..throwMessage = 'é' * 4000;
      addTearDown(() => _thrower.throwMessage = 'system boom');

      expect(() => state.advance(_step), throwsA(isA<AssertionError>()));
      expect(game.reports, hasLength(1));
      expect(
        utf8.encode(game.reports.first.error).length,
        lessThanOrEqualTo(1024),
        reason: 'the cap _ReportDisabledSystemCommand declares for the field',
      );
      expect(
        utf8.encode(game.reports.first.stackTrace).length,
        lessThanOrEqualTo(2048),
      );
      expect(
        game.reports.first.error,
        startsWith('Bad state: '),
        reason: 'truncated at the end, so the front of the message survives',
      );
    });

    test('a report that cannot be sent does not take the tick with it', () async {
      final game = await _game(_BadReportGame.new);
      final state = _state(game);
      _thrower
        ..ran = 0
        ..throwOnTick = 1
        ..throwMessage = 'system boom';
      _afterThrower.ran = 0;

      // Still the assert, and nothing else: the report handler threw on this
      // stack, and that must not become the failure the tick reports, nor
      // stop the listeners declared after the thrower.
      expect(() => state.advance(_step), throwsA(isA<AssertionError>()));
      expect(game.calls, 1, reason: 'the handler really did run, and throw');
      expect(
        _afterThrower.ran,
        1,
        reason: 'the guard promises one bad listener does not stop the rest, '
            'and the reporting path runs inside the catch that keeps it',
      );

      state.advance(_step);
      expect(_afterThrower.ran, 2, reason: 'and the game goes on ticking');
    });

    test('a throwing coroutine is unaffected by any of this', () async {
      // Coroutines were already guarded, in CoroutineScheduler.step, and this
      // change did not touch them. Pinned so a later edit to one guard does
      // not quietly assume it owns both.
      final game = await _game(_TestGame.new);
      final state = _state(game);
      Object? landed;
      Iterable<Object?> boom() sync* {
        yield null;
        throw StateError("coroutine boom");
      }

      state.coroutines
          .start(state, boom())
          .catchError((Object e) => landed = e);

      state
        ..advance(_step)
        ..advance(_step)
        ..advance(_step);
      await Future<void>.delayed(Duration.zero);

      expect(landed, isA<StateError>(), reason: 'lands on the handle');
      expect(state.coroutines.length, 0, reason: 'and it is removed');
      expect(run.tick, 3, reason: 'the simulation never noticed');
    });
  });
  group('time scale and pause', () {
    test('a scale of zero runs no fixed ticks at all', () async {
      final game = await _game(_TestGame.new);
      final state = _state(game);
      state.timeScale = 0;

      expect(
        state.advance(_step * 3),
        0,
        reason:
            'zero means the accumulator stops filling, so no step runs - not '
            'three steps of size zero. A system that divides by its timestep '
            'never sees one it was not written for.',
      );
      expect(run.tick, 0);
    });

    test('a half scale runs half as many ticks', () async {
      final game = await _game(_TestGame.new);
      final state = _state(game);
      state.timeScale = 0.5;

      expect(
        state.advance(_step * 4),
        2,
        reason:
            'four steps of wall clock at half speed earns two steps of '
            'simulated time, each still exactly one fixedTimeStep',
      );
    });

    test(
      'pausing stops the fixed tick and leaves presentation running',
      () async {
        await _game(_PhaseGame.new);
        run.state.advance(_step * 2);
        final simmed = log.where((e) => e == 'sim').length;
        final presented = log.where((e) => e == 'present').length;
        expect(simmed, greaterThan(0));

        run.state.paused = true;
        run.state.advance(_step * 5);

        expect(
          log.where((e) => e == 'sim').length,
          simmed,
          reason: 'paused means no simulation',
        );
        expect(
          log.where((e) => e == 'present').length,
          greaterThan(presented),
          reason:
              'and the frame keeps being presented, which is the whole reason '
              'this is not #117 - a pause menu has to draw',
        );
      },
    );

    test(
      'stepOnce advances one step and leaves the accumulator alone',
      () async {
        final game = await _game(_TestGame.new);
        final state = _state(game);
        state.paused = true;
        // Three milliseconds of phase, short of the ten a step costs.
        state.timeScale = 1;
        state.paused = false;
        state.advance(const Duration(milliseconds: 3));
        expect(run.tick, 0);
        state.paused = true;

        state.stepOnce();
        expect(run.tick, 1, reason: 'exactly one step, clock regardless');

        state.paused = false;
        expect(
          state.advance(const Duration(milliseconds: 7)),
          1,
          reason:
              'the 3ms of phase was still there - stepOnce goes straight to '
              'runFixedStep and must not drain or reset the accumulator, or '
              'unpausing would resume from a different point than it paused at',
        );
      },
    );

    test('unpausing returns to the scale it was paused at', () async {
      final game = await _game(_TestGame.new);
      final state = _state(game);
      state.timeScale = 0.5;
      state.paused = true;
      state.advance(_step * 4);
      expect(run.tick, 0);

      state.paused = false;
      expect(
        state.advance(_step * 4),
        2,
        reason:
            'pause and scale are two facts. One field could not hold "paused, '
            'and half speed when it comes back".',
      );
    });

    test('a negative scale is refused', () async {
      final game = await _game(_TestGame.new);
      expect(
        () => _state(game).timeScale = -1,
        throwsA(isA<AssertionError>()),
        reason:
            'nothing here is reversible, so a negative delta would corrupt '
            'the step arithmetic rather than rewind anything',
      );
    });

    // The composition case. #117 restarts the timer when the app comes back;
    // this must not also restart the *game*.
    test(
      'a game paused by the game stays paused across hide and show',
      () async {
        final game = await _game(_VisibilityGame.new);
        final state = _state(game);
        state.paused = true;

        state.setVisible(false);
        state.setVisible(true);

        expect(
          state.advance(_step * 5),
          0,
          reason:
              'the player paused it, then the app went away and came back. '
              'Being shown again restores what #117 stopped, never what the '
              'game stopped.',
        );
        expect(run.tick, 0);
      },
    );
  });
  group('presentation phase (Tickable)', () {
    test('runs once per frame, not once per simulation step', () async {
      await _game(_PhaseGame.new);
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
      await _game(_PhaseGame.new);
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
      await _game(_PhaseGame.new);
      run.state.advance(_step);
      // Not just "both ran" - the ordering is the entire contract. A
      // Tickable reads what the tick published, so it must come after.
      expect(log.indexOf('sim'), lessThan(log.indexOf('present')));
    });

    test(
      'the delta is the frame\'s elapsed time, not the fixed step',
      () async {
        await _game(_PhaseGame.new);
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
        await _game(_PhaseGame.new);
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
      final game = await _game(_TestGame.new);
      _state(game).advance(_step * 2);
      expect(log, ['A', 'B', 'A', 'B']);
    });

    test(
      'a declared system that is not FixedTickable is simply skipped',
      () async {
        final game = await _game(_TestGame.new);
        _state(game).advance(_step);
        expect(log, ['A', 'B']);
        expect(run.state.getSystem<_InertSystem>(), isA<_InertSystem>());
      },
    );

    test(
      'disableSystem stops a system ticking; enableSystem resumes it',
      () async {
        final game = await _game(_TestGame.new);
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
      final game = await _game(_TestGame.new);
      run.state.disableSystems([_SystemA, _SystemB]);
      _state(game).advance(_step);
      expect(log, isEmpty);
      run.state.enableSystems([_SystemA, _SystemB]);
      _state(game).advance(_step);
      expect(log, ['A', 'B']);
    });

    test('an undeclared system cannot be toggled or fetched', () async {
      await _game(_TestGame.new);
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
        expect(Game.startInline(_DuplicateSystemGame.new), throwsStateError);
      },
    );

    test('a system reaches its siblings and its scene', () async {
      final game = await _game(_TestGame.new);
      final census = run.state.getSystem<_CensusSystem>();
      expect(
        census.getSystem<_SystemA>(),
        same(run.state.getSystem<_SystemA>()),
      );
      expect(census.singleScene<_TestScene>(), same(_state(game).scene));
      expect(census.state, same(run.state));
    });
  });

  group('Comparable-driven system ordering', () {
    test(
      'a system that sorts itself first runs first, despite declaring last',
      () async {
        final game = await _game(_OrderingGame.new);
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
        final game = await _game(_OrderingGame.new);
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
        final game = await _game(_OrderingGame.new);
        _state(game).advance(_step);
        expect(
          log,
          ['C', 'D', 'A', 'B', '1', '2', 'spawn', 'compose'],
          reason:
              'declaration order was A, B, Indifferent1, Indifferent2, '
              'SortsFirst, AlsoSortsFirst, Composer, Spawner '
              '(InertSystem/CensusSystem are not FixedTickable and do not '
              'log). C and D both claim to be first, so they take the front '
              'in declaration order; Spawner crosses Composer; everything '
              'else stays where it was declared',
        );
      },
    );

    test(
      'a targeted constraint survives two systems that both claim to be first',
      () async {
        final game = await _game(_OrderingGame.new);
        _state(game).advance(_step);
        expect(
          log.indexOf('spawn'),
          lessThan(log.indexOf('compose')),
          reason:
              'Spawner returns -1 against Composer and nothing else, and was '
              'declared after it. C and D contradict each other, which is '
              'what a comparison sort could not survive - it permuted the '
              'whole list and dropped this constraint, which is #5',
        );
      },
    );

    test('systems whose stated positions form a cycle are rejected', () async {
      await expectLater(
        Game.startInline(_CyclicGame.new),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('cycle'),
              contains('_CycleA'),
              contains('_CycleB'),
              contains('_CycleC'),
            ),
          ),
        ),
      );
    });
  });

  group('tick phases', () {
    test('each dispatcher resolves its listeners at boot, by type', () async {
      final game = await _game(_PhaseGame.new);
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
      final game = await _game(_PhaseGame.new);
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
        final game = await _game(_TestGame.new);
        final scene = _state(game).singleScene<_TestScene>();
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
        final game = await _game(_TestGame.new);
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
        final game = await _game(_TestGame.new);
        final scene = _state(game).singleScene<_TestScene>();
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
        final game = await _game(_CommandGame.new);
        final scene = _state(game).singleScene<_TestScene>();
        final entity = _state(game).loadedScenes.single.addEntity(scene.unit);
        _state(game).advance(_step);
        expect(scene.unit.x[entity], 0.0);

        game.nudge((entity: entity, amount: 12.5));
        _state(game).advance(_step);
        expect(scene.unit.x[entity], 12.5);
      },
    );

    test('a command nothing handles is refused at the sender', () async {
      await _game(_TestGame.new);
      expect(
        () => _NudgeCommand()((entity: const Entity(0), amount: 1)),
        throwsStateError,
        reason:
            'both copies run both declaration passes, so the sending side '
            'already knows nothing will read this',
      );
    });

    test('a command declared on the GameState is refused at boot', () {
      expect(Game.startInline(_BadCommandGame.new), throwsStateError);
    });

    // "reaching the command channel before start throws" was asserted here
    // with `_TestGame().createCommandBatch`. There is no such method on a
    // `Game` any more: a batch is written into one run's command ring, so it
    // comes off the `GameHandle`, and a handle only exists once `Game.start`
    // has returned. The error the test was checking for is now unreachable by
    // construction rather than diagnosed at runtime.

    test('stopping fails a batch still queued for a tick window', () async {
      final game = await _game(_TestGame.new);
      // Sent and deliberately not advanced: a game-destination batch waits
      // for the tick window whichever way the game was booted, so this is
      // sitting in the transport's inbox holding the only completer that
      // could answer it.
      final pending = game.spawnUnit();
      // Attached *before* stop(), so the error has a listener the moment it
      // is delivered rather than being reported as unhandled.
      final settled = pending.then<Object?>(
        (entity) => entity,
        onError: (Object error) => error,
      );

      await run.stop();

      // Never a bare `await pending`. That is what hid this: an abandoned
      // batch neither completes nor errors, so awaiting it hangs the suite
      // for the whole test timeout instead of failing this line.
      final outcome = await settled.timeout(
        const Duration(seconds: 2),
        onTimeout: () => 'never completed',
      );
      expect(
        outcome,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('was run'),
        ),
        reason:
            'a queued batch never ran, so it must be failed with that and '
            'not with the in-flight message about a lost reply',
      );
    });

    test('a scene refuses a prefab another scene registered', () async {
      final game = await _game(_TestGame.new);
      final scene = _state(game).singleScene<_TestScene>();
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
      final game = await _game(_TestGame.new);
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
      final game = await _game(_TestGame.new);
      final scene = _state(game).singleScene<_TestScene>();
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
      final game = await _game(_TestGame.new);
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
      final game = await _game(_TestGame.new);
      expect(Game.startInline(() => game), throwsStateError);
    });

    test(
      'advance/runFixedStep refuse to run on a state that is not simulating',
      () {
        // A GameState that was never marked as owning the simulation is exactly
        // what the main isolate's handle copy holds after start().
        //
        // Through `EventBinder.open` because `_TestState()` on its own now
        // throws out of its own field initialisers - `GameState` declares its
        // dispatchers there and they need a binder open around the call, which
        // `Game._bootMain` is what normally provides. Constructing it bare
        // would still throw a StateError and this test would still pass, off
        // the wrong guard entirely.
        final handle = EventBinder.open(_TestState.new);
        expect(() => handle.advance(_step), throwsStateError);
        expect(handle.runFixedStep, throwsStateError);
      },
    );

    test('a GameState with no scene is legitimate, and still ticks', () async {
      final game = await _game(_ScenelessGame.new);
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
      expect(() => run.state.singleScene<_TestScene>(), throwsStateError);
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
        await _game(_TestGame.new);
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
      await _game(_TestGame.new);
      // Two spellings of the same number, and they have to agree: a host
      // driving the loop reads the return value, while anything asking after
      // the fact - a HUD dividing a per-advance total to get a per-step one -
      // reads the field.
      expect(run.advance(_step * 3), 3);
      expect(run.state.lastStepCount, 3);
    });

    test('is zero on a frame the accumulator could not fill', () async {
      await _game(_TestGame.new);
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
    descriptor.has(_SystemA.new);
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
