// What does a Box2D step actually cost per body?
//
// AOT ONLY. Compile and run:
//   cd packages/goo2d_physics_box2d
//   dart compile exe tool/physics_bench.dart -o build/physics_bench.exe
//   build/physics_bench.exe
//
// A `flutter test` bench is JIT, and JIT has been wrong about this codebase by
// roughly two orders of magnitude twice - see the project's own notes on it.
// Anything measured here would change code, so it has to be AOT.
//
// That constraint is why this imports only `goo2d_ffi_box2d` and never
// `goo2d_physics_box2d` itself: the ECS layer pulls in goo2d, which pulls in
// Flutter, which cannot be AOT-compiled to a standalone exe. So this prices
// the *solver and the FFI boundary*, which is the part a Dart-side change
// cannot make faster anyway. The ECS overhead on top is what the demo's own
// `caseMicros` readout measures, on the device, where it matters.
//
// Requires the native library. packages/goo2d_ffi_box2d/README.md has the
// build for each platform.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:goo2d_ffi_box2d/goo2d_ffi_box2d.dart';

const int bodyTypeStatic = 0;
const int bodyTypeDynamic = 2;
const int allLayers = -1;
const double dt = 1 / 60;
const int subSteps = 4;

/// Reported as the minimum of this many timed rounds. A round can only be
/// inflated by noise - preemption, a scheduler hiccup - never deflated, so the
/// minimum is the closest a wall clock gets to "how much work is this". The
/// mean has been actively misleading in this project before.
const int rounds = 5;

void main() {
  stdout.writeln('box2d ${_version()}   $rounds rounds, reporting minimum');
  stdout.writeln('');
  stdout.writeln('  bodies      step   per body   settled');
  stdout.writeln('  ------------------------------------------');

  for (final count in <int>[100, 500, 1000, 2000, 5000]) {
    _run(count);
  }

  stdout.writeln('');
  stdout.writeln('  --- workers, 5000 bodies -------------------');
  stdout.writeln('  workers      step   per body    speedup');
  stdout.writeln('  ------------------------------------------');
  final serial = _run(5000, workers: 1, report: false);
  for (final workers in <int>[1, 2, 4, 6, 8]) {
    final best = _run(5000, workers: workers, report: false);
    stdout.writeln(
      '  ${workers.toString().padLeft(7)}'
      '  ${best.toStringAsFixed(1).padLeft(8)}us'
      '  ${(best * 1000 / 5000).toStringAsFixed(0).padLeft(7)}ns'
      '  ${(serial / best).toStringAsFixed(2).padLeft(9)}x',
    );
  }
  stdout.writeln('');
  stdout.writeln('Box2D warns that only performance cores help - efficiency');
  stdout.writeln('cores and hyper-threading "provide little benefit and may');
  stdout.writeln('even harm performance" - so expect this to stop improving');
  stdout.writeln('at the physical core count and then get worse.');

  stdout.writeln('');
  stdout.writeln('`per body` is one full world step divided by body count.');
  stdout.writeln('`settled` is how many bodies came to rest on the floor - if');
  stdout.writeln('that is not the body count, the pile was still collapsing');
  stdout.writeln('and the timing describes a different problem than intended.');
  stdout.writeln('');
  stdout.writeln('Cost per body climbs with count because this is a dense');
  stdout.writeln('STACK: 60 columns, so 5000 bodies is a pile 80 rows deep and');
  stdout.writeln('the solver has a contact graph to match. That is the worst');
  stdout.writeln('case on purpose. A scene of the same body count spread out,');
  stdout.writeln('or mostly asleep, costs far less - do not read these as the');
  stdout.writeln('price of simply having N bodies.');
}

String _version() {
  final packed = box2d.gooB2Version();
  return '${packed >> 16}.${(packed >> 8) & 0xFF}.${packed & 0xFF}';
}

/// Returns the best step time in microseconds.
double _run(int count, {int workers = 1, bool report = true}) {
  var best = double.infinity;
  var settled = 0;

  for (var round = 0; round < rounds; round++) {
    final world = workers > 1
        ? box2d.gooWorldCreateThreaded(0, -10, workers)
        : box2d.gooWorldCreate(0, -10);

    // A floor wide enough to hold the whole pile.
    final floor = box2d.gooBodyCreate(world, bodyTypeStatic, 0, -20, 0);
    box2d.gooShapeAddBox(
      floor, 0, 0, 400, 1, 0, 1, 0.6, 0, 1, allLayers, 0,
    );

    final handles = calloc<Int64>(count);
    // A grid, spaced so nothing starts overlapping - bodies spawned inside
    // each other spend the run being pushed apart, which is a different
    // measurement wearing this one's clothes.
    const columns = 60;
    for (var i = 0; i < count; i++) {
      final x = (i % columns) * 1.5 - columns * 0.75;
      final y = -18 + (i ~/ columns) * 1.5;
      handles[i] = box2d.gooBodyCreate(world, bodyTypeDynamic, x, y, 0);
      box2d.gooShapeAddBox(
        handles[i], 0, 0, 0.5, 0.5, 0, 1, 0.4, 0, 1, allLayers, 0,
      );
    }

    // Let the pile settle before timing, so the measurement is of a stack at
    // rest rather than of the initial collapse - the steady state a game
    // spends its time in.
    for (var i = 0; i < 120; i++) {
      box2d.gooWorldStep(world, dt, subSteps);
    }

    const timed = 120;
    final clock = Stopwatch()..start();
    for (var i = 0; i < timed; i++) {
      box2d.gooWorldStep(world, dt, subSteps);
    }
    clock.stop();

    final perStep = clock.elapsedMicroseconds / timed;
    if (perStep < best) best = perStep;

    // The mechanism check, not just the symptom. A bench that reports a
    // beautiful number while every body has quietly fallen through the floor
    // is measuring an empty world - and would read as a speed-up.
    if (round == rounds - 1) {
      final out = calloc<Float>(count * 3);
      box2d.gooBodiesPullTransforms(handles, out, count);
      for (var i = 0; i < count; i++) {
        if (out[i * 3 + 1] > -21) settled++;
      }
      calloc.free(out);
    }

    calloc.free(handles);
    box2d.gooWorldDestroy(world);
  }

  if (report) {
    final perBody = best * 1000 / count;
    stdout.writeln(
      '  ${count.toString().padLeft(6)}'
      '  ${best.toStringAsFixed(1).padLeft(8)}us'
      '  ${perBody.toStringAsFixed(0).padLeft(7)}ns'
      '  ${settled.toString().padLeft(8)}',
    );
  }

  if (settled != count) {
    stdout.writeln(
      '    WARNING: only $settled of $count bodies are above the floor with '
      '$workers worker(s) - this row is timing a world that is falling '
      'apart, not a stack.',
    );
  }
  return best;
}
