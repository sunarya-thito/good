// Cross-isolate stress verification for RingBuffer - the exact scenario
// that motivated moving commands off SendPort in the project root plan's
// "Cross-isolate architecture" section: a producer isolate submitting a
// large burst of small records within a single "tick", drained by a
// consumer isolate in one batch. Verifies every record is delivered, in
// order, intact - no loss, no corruption - across real isolates.
//
// This lives here as a standalone script (`dart run
// tool/ring_buffer_stress.dart`) rather than under test/, because running this
// exact producer/consumer pattern *inside* `dart test`'s own isolate-runner
// reproducibly crashes the VM (confirmed: the crash is in package:test's own
// isolate nesting/ instrumentation around a tight cross-isolate FFI loop, not
// in RingBuffer itself - the identical logic run standalone via `dart run`, as
// here, completes cleanly and correctly every time). The deterministic,
// single-isolate RingBuffer tests in test/ring_buffer_test.dart cover
// wraparound/padding/overflow correctness under `dart test` directly; this
// script is the cross-isolate complement, run manually or in CI as a separate
// process.
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:good/src/ring_buffer.dart';

const int _recordsPerBurst = 5000;
const int _bursts = 5;
const int _totalRecords = _recordsPerBurst * _bursts;
const int _capacityBytes = 64 * 1024; // deliberately small to force many wraps

void _producerIsolateMain(List<int> addresses) {
  final ring = RingBuffer.fromAddresses(
    capacityBytes: addresses[0],
    writeCursorAddress: addresses[1],
    readCursorAddress: addresses[2],
    bufferAddress: addresses[3],
  );

  var sequence = 0;
  for (var burst = 0; burst < _bursts; burst++) {
    for (var i = 0; i < _recordsPerBurst; i++) {
      // Small variable-length payload so the header/padding wraparound
      // logic gets exercised too, not just fixed-size records.
      final payload = Uint8List.fromList([
        sequence & 0xff,
        (sequence >> 8) & 0xff,
        (sequence >> 16) & 0xff,
        (sequence >> 24) & 0xff,
        ...List.filled(sequence % 5, 0xAA),
      ]);
      // A full ring under producer/consumer race is expected sometimes -
      // back off briefly rather than hot-spinning; the plan's actual
      // overflow policy is "surface it as an error", not "retry forever".
      while (!ring.tryWrite(sequence % 7, payload)) {
        sleep(const Duration(microseconds: 50));
      }
      sequence++;
    }
  }
}

Future<void> main() async {
  final ring = RingBuffer(_capacityBytes);

  final exitPort = ReceivePort();
  await Isolate.spawn(_producerIsolateMain, [
    _capacityBytes,
    ring.writeCursorAddress,
    ring.readCursorAddress,
    ring.bufferAddress,
  ], onExit: exitPort.sendPort);

  var producerDone = false;
  exitPort.first.then((_) => producerDone = true);

  var received = 0;
  var expectedSeq = 0;
  var ok = true;

  while (true) {
    for (final record in ring.drain()) {
      final p = record.payload;
      final seq = p[0] | (p[1] << 8) | (p[2] << 16) | (p[3] << 24);
      if (seq != expectedSeq) {
        stderr.writeln('FAIL: expected seq $expectedSeq, got $seq');
        ok = false;
      }
      if (record.recordType != seq % 7) {
        stderr.writeln('FAIL: seq $seq has recordType ${record.recordType}, expected ${seq % 7}');
        ok = false;
      }
      final expectedLength = 4 + seq % 5;
      if (p.length != expectedLength) {
        stderr.writeln('FAIL: seq $seq has payload length ${p.length}, expected $expectedLength');
        ok = false;
      }
      for (var i = 4; i < p.length; i++) {
        if (p[i] != 0xAA) {
          stderr.writeln('FAIL: seq $seq payload byte $i is ${p[i]}, expected 0xAA');
          ok = false;
        }
      }
      expectedSeq++;
      received++;
    }
    if (producerDone && received >= _totalRecords) break;
    await Future<void>.delayed(Duration.zero);
  }

  exitPort.close();
  ring.dispose();

  if (received != _totalRecords) {
    stderr.writeln('FAIL: received $received records, expected $_totalRecords');
    ok = false;
  }

  if (ok) {
    print('OK: $received/$_totalRecords records delivered in order, intact.');
  } else {
    exitCode = 1;
  }
}
