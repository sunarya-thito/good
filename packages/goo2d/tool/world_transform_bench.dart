// How does the fixed step scale with entity count, and *which system* is the
// one that stops scaling linearly?
//
//   cd packages/goo2d && flutter test tool/world_transform_bench.dart
//
// Deliberately **not** in `test/`: this is a measurement, not an assertion,
// and a bench that fails the suite on a slow machine is worse than no bench.
// It lives under `tool/` with the stress harnesses for the same reason. It
// does need the Flutter test runner rather than `dart run`, because `good`
// reaches `package:flutter` for `Game.buildView` - so unlike the pure-memory
// `field_access_bench.dart`, plain `dart run` cannot load it.
//
// # What it exists to answer
//
// An on-device recording of `perf.dart` showed the two fixed-tick systems
// behaving completely differently as the entity count doubled from 10k to
// 20k:
//
//   * the movement loop stayed flat per entity (193 -> 200 ns)
//   * `WorldTransformSystem` did not (562 -> 3437 ns)
//
// Same entities, same rows, same iteration mechanism. This reproduces both
// loops headlessly so the curve can be bisected without a device in the loop.
//
// # The two axes
//
// **Entity count** is the obvious one. **Row stride** is the one worth
// testing: a component row is an *array of structs*, so a system that reads 22
// fields out of a 300-byte row still drags every byte of that row through the
// cache. The demo's `Mote` carries a `Sprite` (18 fields) that
// `WorldTransformSystem` never looks at, and [_padFields] models exactly that
// - fields declared into the row, never read, present only to push the stride
// out. If per-entity cost is flat down a column and climbs across a row, the
// layout is the cost and no amount of tightening the loop will fix it.
//
// `flutter test` is JIT with optimisation on, which is close enough for a
// *shape* (does per-entity cost stay flat?) even though absolute numbers will
// not match a profile-mode build.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

/// Ticks run before the clock starts, so the JIT has optimised the loops and
/// every entity has been through the change-detection path at least once.
const int _warmTicks = 40;
const int _timedTicks = 100;

/// Doubling, so a straight line in "ns per entity" means linear and anything
/// else is visible without arithmetic.
const List<int> _counts = <int>[5000, 10000, 20000, 40000, 80000];

/// Extra `float64`s declared into the row and never touched - see the header.
/// 0 is the bench's own lean row; 18 is what `Renderable2D`'s `Sprite` adds in
/// the demo this is chasing; 40 is well past it, to see whether the trend
/// continues or there is a step.
const List<int> _strides = <int>[0, 18, 40];

const Duration _step = Duration(milliseconds: 10);

/// Read by [_Mote.describeStruct] at declare time. A global rather than a
/// constructor argument because the prefab is built inside `describeScene`,
/// and the whole point is to vary it *between* runs, each of which resets the
/// archetype registry anyway.
int _padFields = 0;

/// Mirrors `perf.dart`'s `Mote` - same mixins in the same order, so the fields
/// `WorldTransformSystem` walks sit at the same offsets. `Renderable2D` itself
/// is left out (it would drag `dart:ui` and the renderer in) and stood in for
/// by [_padFields], which is the only thing about it this measures: stride.
class _Mote extends EntityStruct with Transform2D, WorldTransform2D, Child {
  late final DataPointer<double> phase;

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    phase = data.hasFloat64();
    for (var i = 0; i < _padFields; i++) {
      data.hasFloat64();
    }
  }
}

class _Field extends SceneStruct {
  late final _Mote mote;
  late Scene handle;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    mote = descriptor.has(_Mote());
  }

  @override
  void onSceneMounted(Scene scene) => handle = scene;
}

/// `perf.dart`'s `DriftSystem`, minus the reporting: the same five field
/// accesses and two trig calls per entity, group-iterated. It is the control -
/// a loop over the same rows whose per-entity cost is known to stay flat.
class _DriftSystem extends GameSystem with FixedTickable {
  late final Query motes;

  final Stopwatch _clock = Stopwatch();

  /// Microseconds this system spent on the tick that just ran.
  int lastMicros = 0;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    motes = descriptor.query().withAll(Transform2D, WorldTransform2D).build();
  }

  @override
  void onFixedUpdate() {
    _clock
      ..reset()
      ..start();
    for (final group in motes.groups()) {
      final transform = group.get<Transform2D>();
      final mote = group.get<_Mote>();
      for (final entity in group) {
        final t = mote.phase[entity] + 0.05;
        mote.phase[entity] = t;
        transform.transformOffsetX[entity] =
            transform.transformOffsetX[entity] + math.sin(t) * 0.9;
        transform.transformOffsetY[entity] =
            transform.transformOffsetY[entity] + math.cos(t) * 0.9;
      }
    }
    _clock.stop();
    lastMicros = _clock.elapsedMicroseconds;
  }
}

/// Stamps the clock immediately before `WorldTransformSystem` runs.
///
/// The bench used to get this system's cost by subtracting [_DriftSystem]'s
/// self-timing from `GameState.lastSystemMicros`, which the engine published
/// from a `Stopwatch` of its own. That instrumentation is gone - a game
/// framework is not a profiler - so the bench brackets the one system it is
/// here to measure and reads it directly. Strictly better as well as
/// necessary: a difference of two numbers carries both their errors, and this
/// no longer depends on the control system's timing being right.
class _PhaseStart extends GameSystem with FixedTickable {
  @override
  int compareTo(GameSystem other) => other is WorldTransformSystem ? -1 : 0;

  @override
  void onFixedUpdate() {
    final state = getState<_BenchState>();
    state.worldStartedAt = state.clock.elapsedMicroseconds;
  }
}

/// And immediately after.
class _PhaseEnd extends GameSystem with FixedTickable {
  @override
  int compareTo(GameSystem other) => other is WorldTransformSystem ? 1 : 0;

  @override
  void onFixedUpdate() {
    final state = getState<_BenchState>();
    state.worldMicros = state.clock.elapsedMicroseconds - state.worldStartedAt;
  }
}

class _BenchState extends GameState<_Bench> {
  final _Field field = _Field();
  final _DriftSystem drift = _DriftSystem();

  /// Free-running, never reset - both stamps below are readings of it and only
  /// their difference is ever used.
  final Stopwatch clock = Stopwatch()..start();
  int worldStartedAt = 0;

  /// What `WorldTransformSystem` cost on the step that just ran.
  int worldMicros = 0;

  @override
  void onMounted() => loadScene(field);

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    // The probes have no opinion about `drift` and it has none about them, so
    // the ties between them break on declaration order - which is why the
    // control system is still declared first.
    descriptor.has(drift);
    descriptor.has(_PhaseStart());
    descriptor.has(WorldTransformSystem());
    descriptor.has(_PhaseEnd());
  }
}

class _Bench extends Game {
  /// The demo's own page size, so page count per entity matches too.
  @override
  int get pageSize => 1 << 20;

  @override
  Duration get fixedTimeStep => _step;

  @override
  GameState createState() => _BenchState();
}

/// Nanoseconds per entity per tick, for one `(count, stride)` cell.
class _Cell {
  _Cell(this.drift, this.world);

  final double drift;
  final double world;
}

Future<_Cell> _measure(int count) async {
  final game = await Game.startInline(_Bench());
  final state = game.state;
  final scene = state.getScene<_Field>();
  for (var i = 0; i < count; i++) {
    scene.handle.addEntity(scene.mote);
  }

  for (var i = 0; i < _warmTicks; i++) {
    state.advance(_step);
  }

  final benchState = state as _BenchState;
  var world = 0;
  var drift = 0;
  var steps = 0;
  for (var i = 0; i < _timedTicks; i++) {
    steps += state.advance(_step);
    world += benchState.worldMicros;
    drift += benchState.drift.lastMicros;
  }
  // A tick that ran zero steps contributes zero work and would deflate every
  // average below, so the sweep is only meaningful if every advance stepped
  // exactly once.
  expect(steps, _timedTicks, reason: 'one fixed step per advance');

  await game.stop();

  final perEntity = 1000.0 / (_timedTicks * count);
  return _Cell(drift * perEntity, world * perEntity);
}

/// Each cell runs its own game in the same process, so the process-global
/// registries have to go back to empty between them - and a leftover archetype
/// from the previous cell would carry the *previous* pad count.
void _resetRegistries() {
  // ignore: invalid_use_of_visible_for_testing_member
  SceneRegistry.reset();
  // ignore: invalid_use_of_visible_for_testing_member
  ArchetypeRegistry.reset();
  // ignore: invalid_use_of_visible_for_testing_member
  ComponentTypeRegistry.reset();
}

void main() {
  // One cell per `test`, rather than one test walking the whole matrix: the
  // matrix in a single test builds and tears down fifteen games back to back
  // and killed the runner outright with no output. Per-cell, a cell that dies
  // takes only itself with it and the rest of the matrix still reports.
  final results = <String, _Cell>{};

  for (final pad in _strides) {
    for (final count in _counts) {
      test('$count entities, +$pad pad fields', () async {
        _padFields = pad;
        results['$pad/$count'] = await _measure(count);
        _resetRegistries();
      }, timeout: const Timeout(Duration(minutes: 5)));
    }
  }

  tearDownAll(() {
    final report = StringBuffer()
      ..writeln('\nns per entity per tick, world / drift')
      ..writeln('($_timedTicks ticks each; pad = unread float64s in the row)\n')
      ..write('   entities');
    for (final pad in _strides) {
      report.write('+$pad pad'.padLeft(16));
    }
    report
      ..writeln()
      ..writeln('   ${'-' * (8 + 16 * _strides.length)}');
    for (final count in _counts) {
      report.write('   ${count.toString().padLeft(8)}');
      for (final pad in _strides) {
        final cell = results['$pad/$count'];
        report.write(
          cell == null
              ? '-'.padLeft(16)
              : '${cell.world.toStringAsFixed(0)}/'
                        '${cell.drift.toStringAsFixed(0)}'
                    .padLeft(16),
        );
      }
      report.writeln();
    }
    // ignore: avoid_print
    print(report);
  });
}
