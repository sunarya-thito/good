// #76: what does pulling a static body's transform actually cost?
//
//   cd packages/goo2d_physics_box2d
//   dart compile exe tool/static_pull_bench.dart -o build/static_pull_bench.exe
//   build/static_pull_bench.exe
//
// **AOT, not `flutter test`.** The JIT runner has been wrong about this
// codebase's costs by roughly 100x, so a number produced under it is not
// evidence. This is a standalone binary against the raw FFI shim, which is
// possible because `goo2d_ffi_box2d`'s Dart is `dart:ffi` and `dart:io` only -
// `nativeLibraryPathOverride` exists for tools that run outside a Flutter app.
//
// Needs the native library. Either build it - packages/goo2d_ffi_box2d/README.md
// has the build for each platform - or point GOO_BOX2D_LIB at an existing one.
//
// # The question
//
// Since #74, `_writeBack` throws away a static body's pulled transform. The
// pull still happens, because `_handles` drives both `gooBodiesPullTransforms`
// and `gooBodiesPullVelocities`, and a static body's velocity mirror is
// load-bearing (#67: a body turned static must report zero). Separating them
// needs a third handle array and a real change to the batching, so the
// question is whether the waste is worth that.
//
// # What the scene contains, and why it could show a difference
//
// A bench that cannot fail is worse than none, and this one's failure mode is
// obvious: **the waste is proportional to static geometry**, so a scene with
// little of it cannot show anything. Every case here is therefore
// static-heavy, in the shape the issue names - a mostly-static tilemap:
//
//   static bodies: 1000, 5000, 20000, each a 1x1 box on a row at y = 0
//   dynamic bodies: 500 throughout, half that size, dropped onto that row
//
// Every body carries a real shape. An earlier draft created them bare, which
// made the step almost free and left the saving measured against a denominator
// of zero - the ratio this issue turns on was unreadable.
//
// Two controls guard against reading noise as a result:
//
//   * `pullT(all)` against `pullT(all)` - the same work twice, which
//     establishes what "no difference" measures like on this machine.
//   * a `static = 0` case, where the calls are identical by construction and
//     any gap is measurement error.
//
// # Two candidates, and only one of them could be built
//
// `pullT(dyn)` passes the dynamic tail on its own. That is the floor - the
// least work anything could do - but reaching it means compacting the handles
// and carrying a second slot mapping so `_writeBack` can still find the row a
// result came from.
//
// `pullT(zeroed)` passes a full-width array with the static rows set to 0.
// The shim opens with `if (h == 0) continue`, so this skips the same bodies
// while every surviving index still lines up with its slot: no compaction, no
// second mapping, and `_writeBack` unchanged. It is the version that would
// actually be written, so it is the one the saving is taken from. `pullT(dyn)`
// stays in the table to show how much the cheap version gives away.
//
// # What the saving is measured against
//
// Not the step alone. `_step` in physics_system.dart pushes transforms, steps
// every world, then pulls transforms and velocities - and the third handle
// array shortens exactly one of those four calls. So the denominator is the
// native part of a tick as it stands today:
//
//   push + step + pullT(all) + pullV(all)
//
// The velocity pull stays full width whatever happens, because #67 needs it.
// So does the Dart-side `_writeBack` loop, for the same reason, which is why
// neither is part of the saving.
//
// The push goes through a zeroed array, matching `_pushHandles`: the shim
// skips a null handle, so a tick that changed nothing still scans the slots
// and pushes none of them. Handing it live handles instead - as a first draft
// did - prices `b2Body_SetTransform` on 20000 statics, which moves every one
// of their broadphase proxies and is work no tick actually does.
//
// # The step is reported twice, because a tilemap has two regimes
//
// A settled pile sleeps, and Box2D charges almost nothing for a sleeping
// body: the step falls to a few hundred nanoseconds and the saving looks
// enormous against it. An agitated one pays the solver in full. Neither is
// the honest single denominator, so both are here, and the agitated column
// keeps the pile awake by pushing velocities every tick (its own cost
// measured and subtracted). The truth for a given game sits between them.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:goo2d_ffi_box2d/goo2d_ffi_box2d.dart';

const int _bodyTypeStatic = 0;
const int _bodyTypeDynamic = 2;
const int _allLayers = -1;
const int _dynamicBodies = 500;
const int _reps = 400;
const double _dt = 1 / 60;
const int _subSteps = 4;

int _median(List<int> xs) {
  xs.sort();
  return xs[xs.length ~/ 2];
}

/// Nanoseconds per call, taking the median of [_reps] runs.
///
/// Median and not mean: this shares a machine with whatever else is running,
/// and preemption only ever adds. The minimum would be the cleanest read of
/// "how much work is this", and the median is a fairer read of what a frame
/// actually pays.
///
/// Timed in ticks, not microseconds. `Stopwatch.frequency` is 10 MHz here, so
/// a tick is 100 ns, and `elapsedMicroseconds` was throwing away the low digit
/// - which mattered, because the 500-body pull this has to resolve lands at a
/// few microseconds and every number came out a round multiple of 1000.
///
/// One call per timed span, deliberately. Repeating the call inside the span
/// would warm 500 bodies into cache while 20000 kept spilling out of it, which
/// tilts the comparison toward the narrow pull - the very thing being asked
/// about.
int _timeNs(void Function() body) {
  final nsPerTick = 1000000000 ~/ Stopwatch().frequency;
  // Warm the code path before measuring - the first call through an FFI
  // trampoline is not the price a game pays for the next hundred thousand.
  for (var i = 0; i < 50; i++) {
    body();
  }
  final samples = <int>[];
  final watch = Stopwatch();
  for (var r = 0; r < _reps; r++) {
    watch
      ..reset()
      ..start();
    body();
    watch.stop();
    samples.add(watch.elapsedTicks * nsPerTick);
  }
  return _median(samples);
}

String _pad(Object v, int w) => v.toString().padLeft(w);

void main() {
  final override = Platform.environment['GOO_BOX2D_LIB'];
  if (override != null) nativeLibraryPathOverride = override;

  stdout.writeln('Nanoseconds per call, median of $_reps, one call per span.');
  stdout.writeln();
  stdout.writeln(
    'static  pullT(all)  pullT(zeroed)   saved  pullT(dyn)  pullV(all)'
    '    push   step:slept  saved/tick   step:awake  saved/tick',
  );
  stdout.writeln('-' * 120);

  for (final staticCount in <int>[0, 1000, 5000, 20000]) {
    final world = box2d.gooWorldCreate(0, -10);
    final total = staticCount + _dynamicBodies;

    final handles = calloc<Int64>(total);
    final out = calloc<Float>(total * 3);
    final vel = calloc<Float>(total * 3);
    // Stays all-zero: this is `_pushHandles` on a tick where gameplay moved
    // nothing, which is the tick a static-heavy scene mostly runs.
    final pushHandles = calloc<Int64>(total);
    final dynamicVel = calloc<Float>(_dynamicBodies * 3);
    // The array the fix would actually add: full width, zeroed at the static
    // rows. `gooBodiesPullTransforms` does `if (h == 0) continue`, so this
    // needs no compaction and no second slot mapping - it is filled exactly
    // the way `_pushHandles` already is.
    final pullHandles = calloc<Int64>(total);

    // Statics first, so `pullT(dyn)` can be the tail of the same array and the
    // two calls differ only in how many bodies they touch.
    for (var i = 0; i < staticCount; i++) {
      final b = box2d.gooBodyCreate(world, _bodyTypeStatic, i * 1.0, 0, 0);
      box2d.gooShapeAddBox(b, 0, 0, 0.5, 0.5, 0, 1, 0.6, 0, 1, _allLayers, 0);
      handles[i] = b;
    }
    for (var i = 0; i < _dynamicBodies; i++) {
      final b = box2d.gooBodyCreate(world, _bodyTypeDynamic, i * 1.0, 8, 0);
      box2d.gooShapeAddBox(b, 0, 0, 0.25, 0.25, 0, 1, 0.4, 0, 1, _allLayers, 0);
      handles[staticCount + i] = b;
    }

    final dynamicHandles = handles + staticCount;
    for (var i = 0; i < _dynamicBodies; i++) {
      pullHandles[staticCount + i] = handles[staticCount + i];
    }

    // Step until the drop has become contact work, so the denominator is a
    // tick with the solver doing something rather than a free fall.
    for (var i = 0; i < 120; i++) {
      box2d.gooWorldStep(world, _dt, _subSteps);
    }

    final all = _timeNs(
      () => box2d.gooBodiesPullTransforms(handles, out, total),
    );
    final allAgain = _timeNs(
      () => box2d.gooBodiesPullTransforms(handles, out, total),
    );
    final dyn = _timeNs(
      () => box2d.gooBodiesPullTransforms(dynamicHandles, out, _dynamicBodies),
    );
    final zeroed = _timeNs(
      () => box2d.gooBodiesPullTransforms(pullHandles, out, total),
    );
    final pullV = _timeNs(
      () => box2d.gooBodiesPullVelocities(handles, vel, total),
    );
    final push = _timeNs(
      () => box2d.gooBodiesPushTransforms(pushHandles, out, total),
    );
    final sleptStep = _timeNs(() => box2d.gooWorldStep(world, _dt, _subSteps));
    final sleptAwake = box2d.gooWorldAwakeBodyCount(world);

    // Now the agitated regime. Writing a velocity wakes a body, so doing it
    // every tick keeps the pile off the sleeping path for good.
    for (var i = 0; i < _dynamicBodies; i++) {
      dynamicVel[i * 3] = 3;
      dynamicVel[i * 3 + 1] = 1;
      dynamicVel[i * 3 + 2] = 0;
    }
    void wake() => box2d.gooBodiesPushVelocities(
      dynamicHandles,
      dynamicVel,
      _dynamicBodies,
    );
    final wakeCost = _timeNs(wake);
    final wakeAndStep = _timeNs(() {
      wake();
      box2d.gooWorldStep(world, _dt, _subSteps);
    });
    final awakeStep = wakeAndStep - wakeCost;
    final awakeAwake = box2d.gooWorldAwakeBodyCount(world);

    final saved = all - zeroed;
    String ratio(int step) {
      final tick = push + step + all + pullV;
      final pct = tick == 0 ? 0.0 : saved * 100 / tick;
      return '${pct.toStringAsFixed(2).padLeft(9)}%';
    }

    stdout.writeln(
      '${_pad(staticCount, 6)}  ${_pad(all, 10)}  ${_pad(zeroed, 13)}  '
      '${_pad(saved, 6)}  ${_pad(dyn, 10)}  ${_pad(pullV, 10)}  '
      '${_pad(push, 6)}  ${_pad(sleptStep, 11)}  ${ratio(sleptStep)}  '
      '${_pad(awakeStep, 11)}  ${ratio(awakeStep)}',
    );
    stdout.writeln(
      '        control: pullT(all) twice differed by '
      '${(all - allAgain).abs()} ns; '
      'awake $sleptAwake then $awakeAwake of $total',
    );

    calloc
      ..free(handles)
      ..free(out)
      ..free(vel)
      ..free(pushHandles)
      ..free(dynamicVel)
      ..free(pullHandles);
    box2d.gooWorldDestroy(world);
  }

  stdout.writeln();
  stdout.writeln(
    'A 60 Hz frame is 16,666,667 ns, so divide a saving by 166,667 for the '
    'share of\na whole frame it returns.',
  );
}
