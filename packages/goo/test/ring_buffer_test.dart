// Deterministic, single-isolate coverage for RingBuffer: wraparound,
// padding, overflow, and ordering. For the cross-isolate producer/consumer
// stress verification, see ../tool/ring_buffer_stress.dart - it isn't a
// dart test case because running that exact pattern inside package:test's
// own isolate runner reproducibly crashes the VM (see that script's doc
// comment for the full explanation).
import 'dart:typed_data';

import 'package:goo/src/ring_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RingBuffer', () {
    test('a single write is readable back in order', () {
      final ring = RingBuffer(256);
      addTearDown(ring.dispose);

      expect(ring.tryWrite(1, Uint8List.fromList([1, 2, 3])), isTrue);
      final records = ring.drain();
      expect(records, hasLength(1));
      expect(records.single.recordType, 1);
      expect(records.single.payload, [1, 2, 3]);
    });

    test('multiple writes drain in write order, in one batch', () {
      final ring = RingBuffer(256);
      addTearDown(ring.dispose);

      for (var i = 0; i < 10; i++) {
        expect(ring.tryWrite(i, Uint8List.fromList([i])), isTrue);
      }
      final records = ring.drain();
      expect(records.map((r) => r.recordType).toList(), List.generate(10, (i) => i));
    });

    test('drain is empty when nothing new was written', () {
      final ring = RingBuffer(256);
      addTearDown(ring.dispose);

      ring.tryWrite(1, Uint8List.fromList([9]));
      expect(ring.drain(), hasLength(1));
      expect(ring.drain(), isEmpty);
    });

    test('a record too large for the whole buffer is rejected up front', () {
      final ring = RingBuffer(16); // 8 byte header + 8 byte payload capacity
      addTearDown(ring.dispose);

      expect(ring.tryWrite(1, Uint8List(9)), isFalse);
    });

    test('overflow: tryWrite returns false once the buffer is genuinely full', () {
      final ring = RingBuffer(32); // room for exactly two 8-byte (0-payload) records
      addTearDown(ring.dispose);

      expect(ring.tryWrite(1, Uint8List(0)), isTrue);
      expect(ring.tryWrite(2, Uint8List(0)), isTrue);
      expect(ring.tryWrite(3, Uint8List(0)), isTrue);
      expect(ring.tryWrite(4, Uint8List(0)), isTrue);
      // 32 bytes / 8 bytes per empty-payload record = exactly 4 fit.
      expect(ring.tryWrite(5, Uint8List(0)), isFalse);

      // Draining frees space for more writes - not a permanent wedge.
      expect(ring.drain(), hasLength(4));
      expect(ring.tryWrite(6, Uint8List(0)), isTrue);
    });

    test('wraparound: writes that straddle the physical buffer end are handled', () {
      final ring = RingBuffer(64);
      addTearDown(ring.dispose);

      // Fill (header 8B + 40B payload = 48B) then drain, leaving the write
      // cursor at physical offset 48 with only 16 bytes left before the
      // 64-byte wrap - too little for the next record's 28 needed bytes,
      // forcing the padding path even though the buffer is fully drained
      // (plenty of *total* free space, just not contiguous).
      expect(ring.tryWrite(1, Uint8List(40)), isTrue);
      expect(ring.drain(), hasLength(1));

      final payload = Uint8List.fromList(List.generate(20, (i) => i));
      expect(ring.tryWrite(99, payload), isTrue);
      final records = ring.drain();
      expect(records, hasLength(1));
      expect(records.single.recordType, 99);
      expect(records.single.payload, payload);
    });

    test('many small writes across many wraps preserve order and content', () {
      final ring = RingBuffer(256);
      addTearDown(ring.dispose);

      final expected = <List<int>>[];
      for (var batch = 0; batch < 50; batch++) {
        final writesThisBatch = <List<int>>[];
        for (var i = 0; i < 5; i++) {
          final payload = List.generate(1 + (batch + i) % 5, (j) => (batch + i + j) & 0xff);
          expect(ring.tryWrite(batch * 10 + i, Uint8List.fromList(payload)), isTrue);
          writesThisBatch.add(payload);
        }
        expected.addAll(writesThisBatch);
        final records = ring.drain();
        for (var i = 0; i < records.length; i++) {
          expect(records[i].payload, writesThisBatch[i]);
        }
      }
    });
  });
}
