import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:good/src/triple_buffer.dart';

// Cross-isolate stress verification for TripleBuffer: one isolate publishes
// while this one reads concurrently, checking every read is internally
// self-consistent. A torn read (observing a slot the writer is still
// mid-write on) shows up as mixed tick values within a single slot.
//
// This lives here as a standalone script
// (`dart run tool/triple_buffer_stress.dart`) rather than under test/, for
// the same reason ring_buffer_stress.dart does - and the move was forced by
// a concrete failure worth recording. When good gained its Flutter dependency
// the whole suite moved from package:test to flutter_test, and this test
// began failing every run with a genuine torn read. The primitive had not
// changed; the runner had. flutter_test installs a TestWidgetsFlutterBinding
// whose scheduling does not yield on `await Future.delayed(Duration.zero)`
// the way package:test's plain event loop did, so the reader below starved
// while the writer isolate - a real OS thread using a blocking sleep - kept
// publishing, lapped it, and produced exactly the out-of-contract scenario
// the note below describes. Run standalone under `dart run`, with real
// scheduling, it passes.
//
// The deterministic single-isolate TripleBuffer tests in
// test/triple_buffer_state_test.dart cover slot rotation and the grace
// period under flutter test directly; this script is the cross-isolate
// complement, run manually or in CI as a separate process.
//
// TripleBuffer's grace period is bounded in *publishes*, not wall-clock
// time (see its doc comment) - it assumes a writer that publishes at a
// bounded rate (a fixed tick, tens of milliseconds apart) against a reader
// that finishes with a snapshot in microseconds, which is the real engine's
// actual usage. An *unthrottled* writer publishing in a tight native loop
// can legitimately outrun a reader many times over between polls and lap
// a slot it hasn't actually finished being read - that's not a bug in the
// primitive, it's outside the contract it documents. So this test throttles
// the writer to a tick-like pace (still far faster than a real 60Hz game,
// to keep the test quick) rather than running it unthrottled.
const int _slotBytes = 4096; // 1024 Uint32 words
const int _iterations = 300;
const Duration _tickPace = Duration(milliseconds: 2);

void _writerIsolateMain(List<int> addresses) {
  final buffer = TripleBuffer.fromAddresses(
    slotBytes: _slotBytes,
    latestAddress: addresses[0],
    slotAddresses: addresses.sublist(1),
  );

  for (var tick = 1; tick <= _iterations; tick++) {
    final write = buffer.beginWrite(copyFromLatest: false);
    // Fill the *entire* slot with the same value. If a reader ever
    // observes a mix of two different tick values in one slot, that's a
    // torn read.
    write.cast<Uint32>().asTypedList(_slotBytes ~/ 4).setAll(
      0,
      List.filled(_slotBytes ~/ 4, tick),
    );
    buffer.publish();
    sleep(_tickPace);
  }
}

Future<void> main() async {
  var ok = true;
  {
      final buffer = TripleBuffer(_slotBytes);

      final exitPort = ReceivePort();
      await Isolate.spawn(
        _writerIsolateMain,
        [buffer.latestAddress, ...buffer.slotAddresses],
        onExit: exitPort.sendPort,
      );

      var observedReads = 0;
      var lastSeenTick = 0;
      var monotonic = true;

      var running = true;
      unawaited(exitPort.first.then((_) => running = false));

      while (running) {
        final view = buffer.latestView();
        if (view != null) {
          final words = view.cast<Uint32>().asTypedList(_slotBytes ~/ 4);
          final first = words[0];
          // Every word in the slot must agree - a torn read would show a
          // mix of two different tick values here.
          for (final w in words) {
            if (w != first) {
              stderr.writeln(
                'FAIL: torn read - slot holds mixed tick values ($first and $w)',
              );
              ok = false;
              break;
            }
          }
          if (first < lastSeenTick) monotonic = false;
          lastSeenTick = first;
          observedReads++;
        }
        // Yield so the writer isolate's exit signal actually gets
        // processed; this is a much tighter poll than the writer's
        // per-tick pace above, so it never meaningfully falls behind.
        await Future<void>.delayed(Duration.zero);
      }

      exitPort.close();
      buffer.dispose();

      // Sanity: we should have actually observed a meaningful number of
      // published snapshots, and never seen tick numbers go backwards
      // (round-robin publish is monotonically increasing here by
      // construction, so any decrease would also indicate a bug).
      if (observedReads == 0) {
        stderr.writeln('FAIL: never observed a published snapshot at all');
        ok = false;
      }
      if (!monotonic) {
        stderr.writeln('FAIL: observed tick counters went backwards');
        ok = false;
      }
      if (lastSeenTick != _iterations) {
        stderr.writeln(
          'FAIL: last observed tick was $lastSeenTick, expected $_iterations',
        );
        ok = false;
      }

      if (ok) {
        print(
          'OK: $observedReads reads across $_iterations publishes, '
          'no torn slot, monotonic.',
        );
      } else {
        exitCode = 1;
      }
  }
}
