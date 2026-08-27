// Where does the physics demo's frame actually go?
//
// AOT ONLY. Run it in profile mode, from `packages/goo2d/example`:
//
//   flutter run -t lib/bench_physics.dart --profile -d windows
//
// It drives the Physics case up through a series of populations on its own,
// waits for each to fill and settle, samples the engine's own channels, prints
// a table to stdout and exits. No clicking, and no reading numbers off a
// screenshot.
//
// **Debug mode would make every row a lie.** Debug-mode Dart is 10-50x slower
// for the tight numeric loops this engine is made of, and this project has
// twice drawn a wrong conclusion from a JIT measurement - once by a factor of
// about 100. If `kProfileMode` is false this refuses to run rather than print
// numbers that look plausible.
//
// # What it is trying to settle
//
// "Physics is slow" is not actionable. `advance` splits into `present` and
// `step`, `step` into systems, and systems into `physics` and everything the
// case itself does. The point of the table is to say which of those is the
// frame, at a population where the frame is already too long - and then, for
// physics specifically, to say whether the cost is the *population* or the
// contact graph, which is what `awake` and `bppairs` are for.
//
// `physics` used to be four columns, because `Box2DPhysicsSystem` timed its
// own phases. It no longer does - a shipped package is not a profiler - and
// what the case can measure from outside is the system as a whole.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Texture;
import 'package:goo2d/goo2d.dart';

import 'package:goo2d_example/demo/physics.dart';

/// Populations to walk, smallest first.
///
/// 0 is not padding: it prices the engine with a world that has a floor, two
/// walls and nothing else, so every later row can be read as a *difference*
/// from an empty frame rather than as an absolute that quietly includes the
/// harness.
const List<int> populations = <int>[0, 250, 1000, 4000, 8000, 20000];

/// Fixed steps to let a freshly filled pile stop moving before sampling.
///
/// **Counted in steps, not seconds, and that correction changed the answer.**
/// The case spawns bodies mid-air, and a collapsing pile is a different and
/// far more expensive world than the resting one a game spends its time in. A
/// two-*second* settle is 120 steps at 60 fps but only about 50 at the 5 fps
/// the heavy rows actually run at - so the rows that most needed settling got
/// the least of it, and every one of them was timing an avalanche.
const int settleSteps = 300;

/// Fixed steps to sample over, for the same reason.
const int sampleSteps = 180;

/// Wall-clock ceilings, so a row that never converges ends the bench instead
/// of hanging it.
const Duration settleCap = Duration(seconds: 60);
const Duration sampleCap = Duration(seconds: 30);

/// Sampling period. The channels are republished once per `advance`, so
/// anything faster than a frame just re-reads the same value.
const Duration samplePeriod = Duration(milliseconds: 50);

void main() {
  if (!kProfileMode) {
    stderr.writeln(
      'bench_physics measures nothing useful outside profile mode.\n'
      'Run: flutter run -t lib/bench_physics.dart --profile -d windows',
    );
    exit(2);
  }
  runApp(const _BenchApp());
}

/// Solver threads, from `--dart-define=workers=N`. 1 - no threads at all - is
/// the default, so an unqualified run measures what it always did.
/// **0 means "leave the case's own default alone"**, which is what an
/// unqualified run should measure: what a person actually gets when they open
/// the demo. Pass `workers=1` to force the single-threaded baseline.
///
/// It defaulted to 1, which quietly made every run measure a configuration
/// the demo does not ship.
const int _workers = int.fromEnvironment('workers', defaultValue: 0);

class _BenchApp extends StatefulWidget {
  const _BenchApp();

  @override
  State<_BenchApp> createState() => _BenchAppState();
}

class _BenchAppState extends State<_BenchApp> {
  PhysicsGame? _game;

  /// Fixed steps the simulation has run since the bench started.
  ///
  /// Accumulated from a channel listener rather than polled: the channels are
  /// republished once per `advance`, so a listener fires exactly once per
  /// advance and `stepsPerAdvance` can be added without double counting.
  /// Polling at a fixed period would count the same advance many times at low
  /// frame rates - which is precisely the regime this number exists for.
  int _steps = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    // **Inside the constructor call, and on the Game rather than a
    // top-level.** `Game.start` deep-copies this object to the game isolate,
    // so a field set here arrives; a top-level does not, and the first
    // version of this used one - the world was built with 1 worker however
    // many were asked for, and the bench reported that threading did nothing.
    //
    // Left untouched at 0, so an unqualified run measures the case as it
    // ships rather than a configuration only the bench ever produces.
    final game = await Game.start(() {
      final game = PhysicsGame();
      if (_workers > 0) {
        game.solverWorkerCount = _workers;
      }
      return game;
    });
    if (!mounted) {
      await game.stop();
      return;
    }
    // `systemMicros` moves every advance, so it is the tick source; the
    // recorder in the harness uses it for the same reason.
    game.systemMicros.addListener(() {
      _steps += game.stepsPerAdvance.value;
    });
    setState(() => _game = game);

    // One frame, so `GameView` is mounted and actually driving `advance`
    // before the first population is asked for. Sampling a game nothing is
    // pumping reports a frame time of zero.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final rows = <_Row>[];
    for (final target in populations) {
      rows.add(await _measure(game, target));
    }

    _report(rows);
    await game.stop();
    exit(0);
  }

  Future<_Row> _measure(PhysicsGame game, int target) async {
    await game.setPopulation(target);

    // The case spawns at a capped rate per tick on purpose, so reaching the
    // target takes time proportional to it. Waiting on the *reported*
    // population rather than on a fixed sleep is what keeps this honest when
    // the frame rate collapses and the fill therefore takes longer.
    final deadline = DateTime.now().add(const Duration(seconds: 180));
    while (game.spawnedCount.value < target &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    await _runSteps(settleSteps, settleCap, null);

    final row = _Row(target);
    await _runSteps(sampleSteps, sampleCap, () => row.add(game));
    return row;
  }

  /// Waits for [steps] fixed steps to elapse, calling [onSample] as they go.
  Future<void> _runSteps(int steps, Duration cap, void Function()? onSample) async {
    final target = _steps + steps;
    final deadline = DateTime.now().add(cap);
    while (_steps < target && DateTime.now().isBefore(deadline)) {
      onSample?.call();
      await Future<void>.delayed(samplePeriod);
    }
  }

  void _report(List<_Row> rows) {
    final out = StringBuffer()
      ..writeln('')
      ..writeln('=== physics frame breakdown (profile, minimum of samples) ===')
      // **Asked for, and actually got.** The first is a compile-time const
      // read on the main isolate and proves nothing about the world; the
      // second is what Box2D reports for the live world on the game isolate.
      // They can differ, because top-level state does not cross
      // Isolate.spawn.
      ..writeln('solver threads: '
          '${_workers > 0 ? "asked $_workers" : "case default"}'
          ', world reports ${rows.isEmpty ? "?" : rows.last.threads}')
      ..writeln('')
      ..writeln(
        '  target  actual  advance     step  systems  present |'
        '  physics |'
        '   b2bod  escaped    awake  touching  bppairs | st/adv   simfps',
      )
      ..writeln(
        '  ---------------------------------------------'
        '-------------------------------------------------'
        '--------------------------------',
      );
    for (final row in rows) {
      out.writeln(row.line());
      // **A row that did not reach its population is not a measurement of
      // that population**, and printing the target in the left column while
      // the world held a fraction of it is exactly the kind of quietly wrong
      // table this project has been caught by before. Say so, loudly, on the
      // row itself.
      if (!row.reachedTarget) {
        out.writeln(
          '    WARNING: only ${row.entities} of ${row.bodies} bodies were '
          'alive - this row does NOT describe ${row.bodies} bodies. '
          '${row.escaped} have been recycled after leaving the box, so if '
          'that number is large the arena is not holding them.',
        );
      }
    }
    out
      ..writeln('')
      ..writeln('All times milliseconds. `advance` is the whole game-isolate')
      ..writeln('frame: present + step. `physics` is Box2DPhysicsSystem`s')
      ..writeln('share of `systems`, which is itself the bulk of `step`,')
      ..writeln('timed by a probe system either side of it.')
      ..writeln('')
      ..writeln('`b2bod` is what BOX2D holds, against `bodies` which is what')
      ..writeln('the case asked for (plus three static arena pieces). The two')
      ..writeln('drifting apart is the signature of a leak, and they did:')
      ..writeln('`Entity.destroy` did not fire the world-observation despawn')
      ..writeln('event, so destroyed entities left their bodies behind.')
      ..writeln('')
      ..writeln('`awake` is how many bodies Box2D is still integrating. A')
      ..writeln('sleeping body is nearly free, so `awake` next to `bodies` is')
      ..writeln('the difference between a scene that is heavy and one that is')
      ..writeln('merely agitated - two problems with the same step time and')
      ..writeln('two completely different fixes. `bppairs` climbing much')
      ..writeln('faster than `bodies` means the pile is overlapping.')
      ..writeln('')
      ..writeln('`st/adv` is fixed steps per advance. The moment it exceeds 1')
      ..writeln('the per-advance totals stop sharing a denominator with the')
      ..writeln('per-step ones - divide before comparing. A number above 1 is')
      ..writeln('itself the finding: the sim is no longer keeping up.')
      ..writeln('')
      ..writeln('Minimum, not mean: a sample can only be inflated by noise,')
      ..writeln('never deflated, so the minimum is the closest a wall clock')
      ..writeln('gets to how much work this is.');
    stdout.write(out);
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF07090C),
        // The real `GameView`, not a stub: `present` runs on the game isolate
        // inside `advance` and is part of what is being measured, so a bench
        // that skipped drawing would report a frame the demo never has.
        body: game == null
            ? const Center(child: CircularProgressIndicator())
            : GameView(camera: game.defaultCamera),
      ),
    );
  }
}

/// One population's samples, kept as running minima.
class _Row {
  _Row(this.bodies);

  final int bodies;

  int advance = _none;
  int step = _none;
  int systems = _none;
  int present = _none;
  int physics = _none;
  int stepsPerAdvance = 0;
  double simFps = 0;
  /// How many bodies the case actually had, as opposed to how many were
  /// asked for. Not a minimum - the *last* sample, which is the state the
  /// timings around it describe.
  int entities = 0;

  /// Whether [entities] got within a few percent of [bodies]. A row that did
  /// not is mislabelled, not merely noisy.
  bool get reachedTarget => bodies == 0 || entities >= bodies * 0.95;

  /// Bodies recycled after leaving the box, cumulatively.
  int escaped = 0;

  /// Threads the live Box2D world reports, not the number asked for.
  int threads = 0;

  int b2Bodies = 0;
  int awake = 0;
  int touching = 0;
  int bpPairs = 0;
  int samples = 0;

  static const int _none = 1 << 30;

  void add(PhysicsGame game) {
    // **Only advances that actually ran a fixed step.**
    //
    // `advance` is driven by the display at ~62 Hz and the fixed step is
    // 60 Hz, so roughly one advance in thirty runs *no* step at all and
    // reports `step` and `systems` as zero. Zero wins every minimum, and the
    // first version of this bench duly reported `step 0.00 ms` at every
    // population - next to a `solve` of 36 ms, which is how the mistake was
    // caught rather than believed.
    //
    // Gating on `stepsPerAdvance` used to be the obvious fix and did **not**
    // work, which the second version of this bench proved by reporting the
    // same zeros: `GameState` assigns `_lastSteps` *after* running the
    // presentation pass, and `DemoStats` publishes from inside that pass, so
    // the count on the wire was always one advance stale. `DemoProfile` counts
    // the steps itself now and is current - but gating on `stepMicros` is
    // still the honest test, because it is the number being minimised.
    if (game.advanceMicros.value <= 0 || game.stepMicros.value <= 0) return;
    samples++;
    advance = _min(advance, game.advanceMicros.value);
    step = _min(step, game.stepMicros.value);
    systems = _min(systems, game.systemMicros.value);
    present = _min(present, game.presentMicros.value);
    physics = _min(physics, game.physicsMicros.value);
    // Not a minimum: these describe the row rather than time it, and the last
    // one is the one that matches the state the timings were taken in.
    stepsPerAdvance = game.stepsPerAdvance.value;
    simFps = game.simulationFps;
    entities = game.spawnedCount.value;
    escaped = game.escapedBodies.value;
    threads = game.solverThreads.value;
    b2Bodies = game.physicsBodies.value;
    awake = game.awakeBodies.value;
    touching = game.touchingPairs.value;
    bpPairs = game.broadPhasePairs.value;
  }

  static int _min(int a, int b) => a < b ? a : b;

  String _ms(int micros) =>
      samples == 0 ? '-' : (micros / 1000).toStringAsFixed(2);

  String line() =>
      '  ${bodies.toString().padLeft(6)}'
      '  ${entities.toString().padLeft(6)}'
      '  ${_ms(advance).padLeft(7)}'
      '  ${_ms(step).padLeft(7)}'
      '  ${_ms(systems).padLeft(7)}'
      '  ${_ms(present).padLeft(7)} |'
      '  ${_ms(physics).padLeft(7)} |'
      '  ${b2Bodies.toString().padLeft(6)}'
      '  ${escaped.toString().padLeft(7)}'
      '  ${awake.toString().padLeft(6)}'
      '  ${touching.toString().padLeft(8)}'
      '  ${bpPairs.toString().padLeft(7)} |'
      '  ${stepsPerAdvance.toString().padLeft(5)}'
      '  ${simFps.toStringAsFixed(1).padLeft(6)}';
}
