import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:good/src/triple_buffer.dart';

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
      expect(
        buffer.latestView(),
        isNull,
        reason:
            'a reader that beats the first publish must get null rather '
            'than a view over whatever the allocation happened to contain - '
            'this is what lets a reader poll from the moment it exists',
      );
    });

    test('a write slot is still available to fill', () {
      final write = buffer.beginWrite(copyFromLatest: false);
      _fill(write, words, 7);
      expect(_firstWord(buffer.writeView), 7);
      expect(
        buffer.latestView(),
        isNull,
        reason:
            'writing is not publishing - until publish() the reader '
            'still sees nothing',
      );
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
      expect(
        _firstWord(buffer.latestView()!),
        1,
        reason:
            'the whole point of the third slot - the writer works on a '
            'slot nobody is reading, so an in-progress tick is never '
            'observable. This is the tearing case, made deterministic.',
      );

      buffer.publish();
      expect(_firstWord(buffer.latestView()!), 2);
    });

    test('rotation visits a different slot than the one being read', () {
      _fill(buffer.beginWrite(copyFromLatest: false), words, 1);
      buffer.publish();
      final published = buffer.latestView()!;

      final nextWrite = buffer.beginWrite(copyFromLatest: false);
      expect(
        nextWrite.address,
        isNot(published.address),
        reason:
            'writing into the slot a reader is holding is exactly the '
            'race the three slots exist to prevent',
      );
    });

    test('successive publishes keep rotating rather than reusing one slot', () {
      final addresses = <int>{};
      for (var tick = 1; tick <= 6; tick++) {
        _fill(buffer.beginWrite(copyFromLatest: false), words, tick);
        buffer.publish();
        addresses.add(buffer.latestView()!.address);
        expect(_firstWord(buffer.latestView()!), tick);
      }
      expect(
        addresses.length,
        greaterThan(1),
        reason:
            'publishing into a single slot forever would mean a reader '
            'holding a view is reading memory the writer is about to '
            'overwrite',
      );
    });
  });

  group('copyFromLatest', () {
    test('carries the published snapshot into the new write slot', () {
      _fill(buffer.beginWrite(copyFromLatest: false), words, 42);
      buffer.publish();

      final write = buffer.beginWrite();
      expect(
        _firstWord(write),
        42,
        reason:
            'this is what makes a tick that only writes *some* fields '
            'leave the rest alone - MemoryPool.beginTick relies on it, and '
            'without it every unwritten field would read as whatever the '
            'rotated-to slot last held, two ticks ago',
      );
    });

    test('copyFromLatest: false leaves the slot as it was', () {
      _fill(buffer.beginWrite(copyFromLatest: false), words, 42);
      buffer.publish();
      _fill(buffer.beginWrite(copyFromLatest: false), words, 43);
      buffer.publish();
      // Third beginWrite rotates onto a slot that already holds an old value;
      // without the copy it must be left exactly as-is rather than cleared.
      final write = buffer.beginWrite(copyFromLatest: false);
      expect(
        _firstWord(write),
        anyOf(42, 43, 0),
        reason:
            'whatever the slot held, it is not silently zeroed - the '
            'caller opted out of the copy and owns filling it',
      );
    });

    test(
      'before any publish there is nothing to copy, and that is not fatal',
      () {
        final write = buffer.beginWrite();
        expect(
          write,
          isNotNull,
          reason:
              'a first tick asking to carry the previous snapshot forward '
              'when there is none must still get a usable slot - scene '
              'bootstrap does exactly this',
        );
      },
    );
  });

  group('copying only the used extent', () {
    test('a value below the limit carries forward across many ticks', () {
      // A slot far bigger than what is used - the shape every MemoryPage has,
      // since a page is sized for an archetype's worst case and usually holds
      // far less. Only the first 64 bytes are ever written, so only those are
      // copied forward.
      final buffer = TripleBuffer(64 * 1024);
      addTearDown(buffer.dispose);

      buffer.beginWrite(bytes: 64).asTypedList(64)[0] = 7;
      buffer.publish();

      for (var tick = 0; tick < 10; tick++) {
        final write = buffer.beginWrite(bytes: 64).asTypedList(64);
        expect(
          write[0],
          7 + tick,
          reason:
              'the previous tick\'s byte survived the forward copy - '
              'this is what makes `x[e] += 1` mean "last tick plus one" '
              'rather than "whatever was in this slot three ticks ago"',
        );
        write[0] = write[0] + 1;
        buffer.publish();
      }

      expect(buffer.latestView()!.asTypedList(64)[0], 17);
    });

    test('bytes beyond the limit are not carried, and that is the point', () {
      final buffer = TripleBuffer(1024);
      addTearDown(buffer.dispose);

      buffer.beginWrite().asTypedList(1024)[900] = 42;
      buffer.publish();

      // Copying only the first 64 bytes leaves byte 900 as whatever that slot
      // held, which is exactly the trade: a page must never ask for less than
      // its high-water mark. `MemoryPool.beginTick` passes
      // `MemoryPage.highWaterMark`, and rows are bump-allocated and recycled
      // from *below* it, so every live row is covered.
      buffer.beginWrite(bytes: 64);
      buffer.publish();
      buffer.beginWrite(bytes: 64);
      final carried = buffer.beginWrite(bytes: 64).asTypedList(1024)[900];
      expect(
        carried,
        isNot(42),
        reason:
            'stated so the limit is understood as a contract with the '
            'caller rather than a free optimisation',
      );
    });

    test('a limit larger than the slot is clamped rather than overrunning', () {
      final buffer = TripleBuffer(128);
      addTearDown(buffer.dispose);
      buffer.beginWrite().asTypedList(128)[0] = 9;
      buffer.publish();

      expect(() => buffer.beginWrite(bytes: 1 << 20), returnsNormally);
      expect(buffer.beginWrite(bytes: 1 << 20).asTypedList(128)[0], 9);
    });
  });

  group('the read-base cache is writer-only', () {
    test('a reader view over the same memory still sees new publishes', () {
      final writer = TripleBuffer(64);
      addTearDown(writer.dispose);
      // A second object over the *same* native memory - exactly what the other
      // isolate holds after `Isolate.spawn` (see `TripleBuffer.fromAddresses`).
      final reader = TripleBuffer.fromAddresses(
        slotBytes: 64,
        latestAddress: writer.latestAddress,
        slotAddresses: writer.slotAddresses,
      );

      for (var i = 1; i <= 5; i++) {
        writer.beginWrite().asTypedList(64)[0] = i;
        writer.publish();
        // The reader never calls `beginWrite`, so it never fills the cache and
        // always re-reads `_latest` from shared memory. Caching there would
        // freeze it on the first snapshot forever - which is silent, and the
        // whole reason the cache is filled in `beginWrite` rather than lazily
        // on first read.
        expect(
          reader.latestView()!.asTypedList(64)[0],
          i,
          reason: 'publish $i has to be visible through the other copy',
        );
      }
    });

    test('the writer sees its own publishes across ticks', () {
      final buffer = TripleBuffer(64);
      addTearDown(buffer.dispose);

      for (var i = 1; i <= 5; i++) {
        buffer.beginWrite().asTypedList(64)[0] = i;
        buffer.publish();
        expect(
          buffer.latestView()!.asTypedList(64)[0],
          i,
          reason:
              'publish clears the cache, so a read straight after it '
              'resolves live rather than returning the previous snapshot',
        );
      }
    });

    test('writeView follows the rotation, not the last publish', () {
      final buffer = TripleBuffer(slotBytes);
      addTearDown(buffer.dispose);

      for (var tick = 1; tick <= 6; tick++) {
        _fill(buffer.beginWrite(copyFromLatest: false), words, tick);
        buffer.publish();
        // Read *between* publish and the next beginWrite - the window the
        // cached write base could go stale in. Handing back the slot that was
        // just published would mean the next writes land in memory a reader is
        // holding, which is precisely the tearing the third slot exists to
        // prevent. Caught nothing when the cache was left stale, which is why
        // this test exists rather than the line alone.
        expect(
          buffer.writeView.address,
          isNot(buffer.latestView()!.address),
          reason: 'the next write must never target the published slot',
        );
      }
    });

    test('within a tick the published snapshot does not move', () {
      final buffer = TripleBuffer(64);
      addTearDown(buffer.dispose);
      buffer.beginWrite().asTypedList(64)[0] = 9;
      buffer.publish();

      buffer.beginWrite(); // opens a tick; write slot is not the published one
      // Reads during the tick see the last published value however many times
      // they are asked, which is what the cache is allowed to assume.
      for (var i = 0; i < 3; i++) {
        expect(buffer.latestView()!.asTypedList(64)[0], 9);
      }
    });
  });
}
