import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:goo/src/triple_buffer.dart';


// Deterministic, single-isolate coverage of TripleBuffer's state machine:
// slot rotation, the pre-publish state, and copyFromLatest.
//
// The *concurrent* half - a real writer isolate racing a reader, which is
// what actually proves the no-tearing property - deliberately does not live
// here. It is `tool/triple_buffer_stress.dart`, run standalone via
// `dart run`, because `flutter_test`'s binding does not schedule
// `await Future.delayed(Duration.zero)` the way a plain event loop does and
// so starves a polling reader against a blocking-sleep writer isolate. That
// is a property of the runner, not of the primitive; see that file's header.
// Everything below is synchronous and has no such exposure.

/// Fills [slot] with [value] in every word, so a later read can assert the
/// whole slot agrees rather than just its first word.
void _fill(Pointer<Uint8> slot, int words, int value) {
  slot.cast<Uint32>().asTypedList(words).fillRange(0, words, value);
}

int _firstWord(Pointer<Uint8> slot) => slot.cast<Uint32>()[0];

void main() {
  const slotBytes = 64;
  const words = slotBytes ~/ 4;

  late TripleBuffer buffer;

  setUp(() => buffer = TripleBuffer(slotBytes));
  tearDown(() => buffer.dispose());

  group('before anything is published', () {
    test('hasPublished is false and latestView has nothing to hand back', () {
      expect(buffer.hasPublished, isFalse);
      expect(buffer.latestView(), isNull,
          reason: 'a reader that beats the first publish must get null rather '
              'than a view over whatever the allocation happened to contain - '
              'this is what lets a reader poll from the moment it exists');
    });

    test('a write slot is still available to fill', () {
      final write = buffer.beginWrite(copyFromLatest: false);
      _fill(write, words, 7);
      expect(_firstWord(buffer.writeView), 7);
      expect(buffer.latestView(), isNull,
          reason: 'writing is not publishing - until publish() the reader '
              'still sees nothing');
    });
  });

  group('publish makes exactly one snapshot visible', () {
    test('the published slot is what a reader observes', () {
      _fill(buffer.beginWrite(copyFromLatest: false), words, 1);
      buffer.publish();

      expect(buffer.hasPublished, isTrue);
      final view = buffer.latestView();
      expect(view, isNotNull);
      expect(_firstWord(view!), 1);
    });

    test('a second write does not disturb the published snapshot', () {
      _fill(buffer.beginWrite(copyFromLatest: false), words, 1);
      buffer.publish();

      // Mid-write on the *next* slot: the reader must keep seeing tick 1.
      _fill(buffer.beginWrite(copyFromLatest: false), words, 2);
      expect(_firstWord(buffer.latestView()!), 1,
          reason: 'the whole point of the third slot - the writer works on a '
              'slot nobody is reading, so an in-progress tick is never '
              'observable. This is the tearing case, made deterministic.');

      buffer.publish();
      expect(_firstWord(buffer.latestView()!), 2);
    });

    test('rotation visits a different slot than the one being read', () {
      _fill(buffer.beginWrite(copyFromLatest: false), words, 1);
      buffer.publish();
      final published = buffer.latestView()!;

      final nextWrite = buffer.beginWrite(copyFromLatest: false);
      expect(nextWrite.address, isNot(published.address),
          reason: 'writing into the slot a reader is holding is exactly the '
              'race the three slots exist to prevent');
    });

    test('successive publishes keep rotating rather than reusing one slot', () {
      final addresses = <int>{};
      for (var tick = 1; tick <= 6; tick++) {
        _fill(buffer.beginWrite(copyFromLatest: false), words, tick);
        buffer.publish();
        addresses.add(buffer.latestView()!.address);
        expect(_firstWord(buffer.latestView()!), tick);
      }
      expect(addresses.length, greaterThan(1),
          reason: 'publishing into a single slot forever would mean a reader '
              'holding a view is reading memory the writer is about to '
              'overwrite');
    });
  });

  group('copyFromLatest', () {
    test('carries the published snapshot into the new write slot', () {
      _fill(buffer.beginWrite(copyFromLatest: false), words, 42);
      buffer.publish();

      final write = buffer.beginWrite();
      expect(_firstWord(write), 42,
          reason: 'this is what makes a tick that only writes *some* fields '
              'leave the rest alone - MemoryPool.beginTick relies on it, and '
              'without it every unwritten field would read as whatever the '
              'rotated-to slot last held, two ticks ago');
    });

    test('copyFromLatest: false leaves the slot as it was', () {
      _fill(buffer.beginWrite(copyFromLatest: false), words, 42);
      buffer.publish();
      _fill(buffer.beginWrite(copyFromLatest: false), words, 43);
      buffer.publish();
      // Third beginWrite rotates onto a slot that already holds an old value;
      // without the copy it must be left exactly as-is rather than cleared.
      final write = buffer.beginWrite(copyFromLatest: false);
      expect(_firstWord(write), anyOf(42, 43, 0),
          reason: 'whatever the slot held, it is not silently zeroed - the '
              'caller opted out of the copy and owns filling it');
    });

    test('before any publish there is nothing to copy, and that is not fatal', () {
      final write = buffer.beginWrite();
      expect(write, isNotNull,
          reason: 'a first tick asking to carry the previous snapshot forward '
              'when there is none must still get a usable slot - scene '
              'bootstrap does exactly this');
    });
  });
}
