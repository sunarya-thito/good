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

  group('the writer never overwrites what the reader may take', () {
    test('a second write is refused until the reader moves', () {
      write(1);

      expect(buffer.beginWrite(), isNull,
          reason: 'the only slot the reader has released is the one just '
              'published. Writing there would overwrite a frame the reader is '
              'entitled to pick up at any moment - so the frame is skipped '
              'instead, which costs nothing because nobody could have read it');
    });

    test('and is allowed again once the reader takes it', () {
      write(1);
      expect(read(), 1);

      expect(buffer.beginWrite(), isNotNull,
          reason: 'taking a slot hands the other one back');
    });

    test('the slot handed back is never the one being read', () {
      write(1);
      read(); // reader now holds the slot holding marker 1

      // Whatever the writer is given, it must not be the reader's slot.
      final slot = buffer.beginWrite()!;
      slot.asTypedList(64).fillRange(0, 8, 2);

      expect(read(), isNull,
          reason: 'nothing new has been published, so the reader stays where '
              'it is');
      expect(buffer.readUsedBytes, 8);
      // The reader's slot still holds its own frame, untouched by the write
      // that just happened.
      expect(buffer.beginRead(), isNull);
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
      // The writer is now blocked until the reader moves - so "the newest" is
      // 2, and there is no 3 to have missed. That is the pacing the handoff
      // buys: production follows consumption instead of racing ahead.
      expect(buffer.beginWrite(), isNull);
      expect(read(), 2);
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

      // And the handoff it performed is visible to the original writer.
      expect(buffer.beginWrite(), isNotNull,
          reason: 'the far side took a slot, which frees the other one - the '
              'control words are the shared state, not the Dart objects');
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
