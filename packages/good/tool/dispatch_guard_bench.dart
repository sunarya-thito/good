// #126: what does a per-listener try/catch cost in `SignalDispatcher.call`?
//
//   dart compile exe packages/good/tool/dispatch_guard_bench.dart -o build/dgb.exe
//   ./build/dgb.exe
//
// AOT, not `dart run`. JIT and AOT weight devirtualisation and exception-frame
// setup differently, and the engine ships AOT - a JIT number here would decide
// the wrong thing, as it has twice before in this repo.
//
// This compiles because `src/event.dart` imports `package:meta` and nothing
// else: the dispatcher is reachable without dragging Flutter in.
//
// # The question
//
// The fixed tick is `fixedTickEvent.call()`, a `SignalDispatcher` walking a
// list and calling a closure per listener - the hottest dispatch in the
// engine, and deliberately payload-free. Guarding each listener so one
// throwing system cannot kill the isolate means a try/catch *inside* that
// loop. A non-throwing try/catch is supposed to be near-free, but "supposed
// to be" is what benchmarks are for.
//
// # What is measured, and the controls
//
//   real      - the shipped `SignalDispatcher.call`, unguarded
//   replica   - the same loop rewritten here, unguarded
//   guarded   - the same loop with a try/catch per listener
//
// `real` against `replica` is the control that says whether the replica is
// faithful: they are the same code, so a gap between them is measurement
// error and bounds what a `guarded - replica` gap can be trusted to mean.
//
// The second control is `work`, a loop doing deliberately more per listener.
// It exists so a flat result cannot be read as "the harness cannot see
// anything" - if `work` does not stand out, nothing here is measuring.
import 'dart:io';

import 'package:good/src/event.dart';

const int _reps = 400;
const List<int> _sizes = <int>[8, 64, 512, 4096, 32768];

int _median(List<int> xs) {
  xs.sort();
  return xs[xs.length ~/ 2];
}

/// Nanoseconds per call, median of [_reps]. Ticks, not microseconds:
/// `Stopwatch.frequency` is 10MHz here, so a tick is 100ns and
/// `elapsedMicroseconds` would quantise a dispatch of a few hundred
/// nanoseconds into nothing at all.
int _timeNs(void Function() body) {
  final nsPerTick = 1000000000 ~/ Stopwatch().frequency;
  for (var i = 0; i < 200; i++) {
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

int sink = 0;

class _Listener implements GameListener {
  @override
  bool get listensToEvents => true;

  @override
  void disableAfterUncaught([Object? error, StackTrace? stack]) {}

  void fire() => sink++;

  void heavy() {
    for (var i = 0; i < 8; i++) {
      sink += i;
    }
  }
}

void main() {
  stdout.writeln(
    'Nanoseconds per dispatch, median of $_reps. One dispatch per timed span.',
  );
  stdout.writeln();
  stdout.writeln(
    'listeners      real   replica   guarded   guard-replica   '
    'per-listener      work',
  );
  stdout.writeln('-' * 88);

  for (final n in _sizes) {
    final dispatcher = SignalDispatcher<_Listener>((l) => l.fire());
    final listeners = <_Listener>[];
    for (var i = 0; i < n; i++) {
      final l = _Listener();
      listeners.add(l);
      dispatcher.add(l);
    }

    // The shipped loop, byte for byte, minus the guard.
    // A runtime bool, not a const: the real dispatcher reads a final field
    // here, and const-folding it away would measure a loop that does not exist.
    final reverse = _sizes.isEmpty;
    void deliver(_Listener l) => l.fire();
    void replica() {
      for (var n2 = 0; n2 < listeners.length; n2++) {
        final l = listeners[reverse ? listeners.length - 1 - n2 : n2];
        if (!l.listensToEvents) continue;
        deliver(l);
      }
    }

    // The same, with the guard this issue would add.
    void guarded() {
      for (var n2 = 0; n2 < listeners.length; n2++) {
        final l = listeners[reverse ? listeners.length - 1 - n2 : n2];
        if (!l.listensToEvents) continue;
        try {
          deliver(l);
        } catch (_) {
          rethrow;
        }
      }
    }

    // The "this harness can see a difference" control.
    void work() {
      for (var i = 0; i < listeners.length; i++) {
        final l = listeners[i];
        if (!l.listensToEvents) continue;
        l.heavy();
      }
    }

    final real = _timeNs(dispatcher.call);
    final rep = _timeNs(replica);
    final grd = _timeNs(guarded);
    final wrk = _timeNs(work);
    final delta = grd - rep;
    final per = (delta / n).toStringAsFixed(2);

    stdout.writeln(
      '${n.toString().padLeft(9)}  ${real.toString().padLeft(8)}  '
      '${rep.toString().padLeft(8)}  ${grd.toString().padLeft(8)}  '
      '${delta.toString().padLeft(13)}  ${per.padLeft(12)}  '
      '${wrk.toString().padLeft(8)}',
    );
  }

  stdout.writeln();
  stdout.writeln('sink=$sink (kept so nothing above is optimised away)');
}
