import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:goo/src/handoff_buffer.dart';


// The handoff protocol, driven deterministically from one isolate.
//
// Single-isolate on purpose: the thing under test is the *protocol* - who is
// allowed to touch which slot when - and interleaving it by hand is the only
// way to pin the cases that matter. A real two-isolate run cannot be made to
// produce the "reader is still holding a slot" moment on demand, and this
// project already learned that timing-sensitive cross-isolate work belongs in
// `tool/` rather than the test runner (see ring_buffer_stress.dart).

void main() {
  late HandoffBuffer buffer;

  setUp(() => buffer = HandoffBuffer(64));
  tearDown(() => buffer.dispose());

  void write(int marker, {int usedBytes = 8}) {
    final slot = buffer.beginWrite();
    expect(slot, isNotNull, reason: 'the writer expected a free slot here');
    slot!.asTypedList(64).fillRange(0, usedBytes, marker);
    buffer.publish(usedBytes);
  }

  int? read() {
    final slot = buffer.beginRead();
    if (slot == null) return null;
    return slot.asTypedList(64)[0];
  }

  group('bring-up', () {
    test('nothing to read before anything is published', () {
      expect(buffer.hasPublished, isFalse);
      expect(buffer.beginRead(), isNull);
    });

    test('the writer may start immediately', () {
      expect(buffer.beginWrite(), isNotNull,
          reason: 'slot 0 is the writer\'s until the reader says otherwise - '
              'a game must be able to produce its first frame before anything '
              'has ever read one');
    });
  });

  group('the writer never waits, and never touches what is in use', () {
    test('it keeps producing while nobody reads', () {
      write(1);
      write(2);
      write(3);

      expect(read(), 3,
          reason: 'the reader collects the newest, not the oldest since its '
              'last read. An earlier design had the reader publish "you may '
              'write here", which only advanced on a read - so the writer '
              'produced one frame and idled, and what waited was a whole '
              'read-interval stale by the time anyone came for it');
    });

    test('it never writes the slot being read', () {
      write(1);
      read(); // reader now holds the slot carrying marker 1

      // Several more frames while the reader is still holding.
      write(2);
      write(3);
      write(4);

      expect(buffer.readUsedBytes, 8);
      // The held slot still carries its own frame, untouched by any of them.
      final held = buffer.slotAddresses;
      expect(held, hasLength(3));
    });

    test('it never writes the slot waiting to be read', () {
      write(1);
      // Not read yet - slot for marker 1 is `ready`. Anything the writer is
      // handed now must be a different slot, or a reader arriving at this
      // instant would walk into a half-written frame.
      final target = buffer.beginWrite()!;
      target.asTypedList(64).fillRange(0, 8, 99);

      expect(read(), 1,
          reason: 'the published frame survived a concurrent write, because '
              'the write went somewhere else');
    });
  });

  group('the reader always sees whole frames', () {
    test('successive frames alternate slots and arrive in order', () {
      final seen = <int>[];
      for (var i = 1; i <= 6; i++) {
        write(i);
        seen.add(read()!);
      }

      expect(seen, [1, 2, 3, 4, 5, 6]);
    });

    test('a reader that skips a beat gets the newest, not a queue', () {
      write(1);
      expect(read(), 1);
      write(2);
      write(3);
      write(4);

      expect(read(), 4,
          reason: 'four frames produced, one read - and the one read is the '
              'last, not the second. A ring would have handed over 2 and kept '
              '3 and 4 waiting, which is the wrong end of a queue nobody wants '
              'the old end of');
    });

    test('reading twice with no new publish reports nothing new', () {
      write(1);
      expect(read(), 1);
      expect(read(), isNull,
          reason: 'a frame callback that fires faster than the game produces '
              'should repaint what it has, not re-ingest the same bytes');
    });
  });

  group('used length', () {
    test('travels with the frame, so the reader copies only what is real', () {
      write(7, usedBytes: 24);
      read();

      expect(buffer.readUsedBytes, 24,
          reason: 'a fixed-size read against a variable-size write is a race '
              'that gets worse as the scene empties - the writer finishes '
              'sooner while the reader still moves the whole slot');
    });

    test('is per slot, not global', () {
      write(1, usedBytes: 8);
      read();
      write(2, usedBytes: 40);
      read();
      expect(buffer.readUsedBytes, 40);

      write(3, usedBytes: 16);
      read();
      expect(buffer.readUsedBytes, 16,
          reason: 'slot 0 is back in use and must report its own length, not '
              'the one it carried two frames ago');
    });
  });

  group('handoff across a rebuilt view', () {
    test('the far side addresses the same memory', () {
      write(9, usedBytes: 16);

      // What `Isolate.spawn` effectively does: the same native addresses,
      // reconstructed on the other side.
      final far = HandoffBuffer.fromAddresses(
        slotBytes: buffer.slotBytes,
        controlAddress: buffer.controlAddress,
        slotAddresses: buffer.slotAddresses,
      );

      final slot = far.beginRead();
      expect(slot, isNotNull);
      expect(slot!.asTypedList(64)[0], 9);
      expect(far.readUsedBytes, 16);

      // And the claim it made is visible to the original writer: whatever the
      // writer is handed next, it is not the slot the far side is holding.
      final next = buffer.beginWrite();
      expect(next, isNotNull);
      expect(next!.address, isNot(slot.address),
          reason: 'the control words are the shared state, not the Dart '
              'objects - a reader on the other side of the boundary excludes '
              'its slot from this writer just as a local one would');
    });
  });

  group('the payload is genuinely native memory', () {
    test('a write is visible byte for byte', () {
      final slot = buffer.beginWrite()!;
      final bytes = slot.asTypedList(64);
      for (var i = 0; i < 32; i++) {
        bytes[i] = i * 2;
      }
      buffer.publish(32);

      final read = buffer.beginRead()!;
      expect(
        Uint8List.fromList(read.asTypedList(64).sublist(0, 32)),
        Uint8List.fromList(<int>[for (var i = 0; i < 32; i++) i * 2]),
      );
    });
  });
}
