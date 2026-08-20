import 'dart:ffi';

import 'package:good/src/pool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MemoryPool / MemoryPage', () {
    test('allocate -> write -> commitTick -> read round-trips bytes', () {
      final pool = MemoryPool(pageSize: 4096);
      addTearDown(pool.dispose);

      final page = pool.allocatePage();
      pool.beginTick();
      final offset = page.allocate(8);
      page.resolveWrite(offset).asTypedList(8).setAll(0, [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
      ]);
      pool.commitTick();

      final read = page.resolveRead(offset);
      expect(read, isNotNull);
      expect(read!.asTypedList(8), [1, 2, 3, 4, 5, 6, 7, 8]);
    });

    test('in-place mutation across ticks accumulates (copy-forward works)', () {
      final pool = MemoryPool(pageSize: 4096);
      addTearDown(pool.dispose);

      final page = pool.allocatePage();
      pool.beginTick();
      final offset = page.allocate(4);
      page.resolveWrite(offset).cast<Uint32>().value = 0;
      pool.commitTick();

      for (var tick = 0; tick < 5; tick++) {
        pool.beginTick();
        // A system resolves the *same* row via its stable offset every
        // tick - it never re-allocates or caches last tick's raw pointer.
        final view = page.resolveWrite(offset).cast<Uint32>();
        view.value = view.value + 1; // read-modify-write
        pool.commitTick();
      }

      expect(page.resolveRead(offset)!.cast<Uint32>().value, 5);
    });

    test('a page is stride-locked to its first allocate() size', () {
      final pool = MemoryPool(pageSize: 4096);
      addTearDown(pool.dispose);

      final page = pool.allocatePage();
      pool.beginTick();
      page.allocate(16);
      expect(() => page.allocate(8), throwsArgumentError);
    });

    test('free() recycles a row for a later allocate() of the same stride', () {
      final pool = MemoryPool(pageSize: 4096);
      addTearDown(pool.dispose);

      final page = pool.allocatePage();
      pool.beginTick();
      final a = page.allocate(4);
      final b = page.allocate(4);
      expect(a, isNot(b));

      page.free(a);
      final c = page.allocate(4);
      // The freed row was reused rather than growing the page further.
      expect(c, a);
    });

    test('allocatePage always creates a fresh page', () {
      final pool = MemoryPool(pageSize: 16);
      addTearDown(pool.dispose);

      final page = pool.allocatePage();
      pool.beginTick();
      page.allocate(16); // exactly fills the page, no room left
      expect(page.isFull, isTrue);

      final second = pool.allocatePage();
      expect(second, isNot(same(page)));
      expect(pool.pageCount, 2);
    });

    test('resolveRead returns null before the first commitTick', () {
      final pool = MemoryPool(pageSize: 4096);
      addTearDown(pool.dispose);

      final page = pool.allocatePage();
      pool.beginTick();
      final offset = page.allocate(4);
      expect(page.resolveRead(offset), isNull);
    });
  });

  // Structural changes made *while a query is walking* - the rule being that
  // a row created during a walk is never seen by that walk.
  //
  // Both allocation paths are exercised separately and deliberately: they are
  // what used to disagree. A bump-allocated row lands above the walk's cursor
  // and was therefore included; a row recycled by `free` lands below it and
  // was not. Same call, two behaviours, decided by allocation history - so a
  // test that only covers one path would have passed against the old code.
  group('a row created during a walk is invisible to that walk', () {
    late MemoryPool pool;
    late MemoryPage page;

    setUp(() {
      pool = MemoryPool(pageSize: 4096);
      page = pool.allocatePage();
      addTearDown(pool.dispose);
    });

    test('bump-allocated: it appears next tick, not to this walk', () {
      final first = page.allocate(8);
      late int spawned;

      final seen = <int>[];
      for (final offset in page.rowOffsets) {
        seen.add(offset);
        if (offset == first) spawned = page.allocate(8);
      }

      expect(
        seen,
        [first],
        reason:
            'the new row sits above the cursor, so the walk must not '
            'reach it even though the loop had not finished',
      );
      expect(
        page.rowOffsets,
        [first],
        reason:
            'and a second walk in the same tick agrees with the first - '
            'two queries in one tick must not disagree about what exists',
      );

      pool.beginTick();
      expect(page.rowOffsets, [first, spawned], reason: 'deferred, not lost');
    });

    test('recycled from a freed row: same answer, though it lands behind', () {
      final a = page.allocate(8);
      final b = page.allocate(8);
      final c = page.allocate(8);
      page.free(a); // nothing has walked yet, so it recycles immediately
      expect(page.rowOffsets, [b, c]);

      late int recycled;
      final seen = <int>[];
      for (final offset in page.rowOffsets) {
        seen.add(offset);
        if (offset == b) recycled = page.allocate(8);
      }

      expect(recycled, a, reason: 'the freed row is what got reused');
      expect(
        seen,
        [b, c],
        reason:
            'the recycled row is *behind* the cursor, so nothing about '
            'iteration order hides it - only the deferral does. This is the '
            'case the old code got wrong in the other direction, which is '
            'why both allocation paths are tested',
      );

      pool.beginTick();
      expect(page.rowOffsets, [a, b, c]);
    });
  });

  group('a row freed during a walk stays readable until it ends', () {
    late MemoryPool pool;
    late MemoryPage page;

    setUp(() {
      pool = MemoryPool(pageSize: 4096);
      page = pool.allocatePage();
      addTearDown(pool.dispose);
    });

    test('it is still yielded, and still reads back its own bytes', () {
      pool.beginTick();
      final a = page.allocate(8);
      final b = page.allocate(8);
      page.resolveWrite(a).asTypedList(8).setAll(0, [9, 9, 9, 9, 9, 9, 9, 9]);
      pool.commitTick();

      final seen = <int>[];
      for (final offset in page.rowOffsets) {
        seen.add(offset);
        if (offset == a) page.free(a);
      }

      expect(
        seen,
        [a, b],
        reason:
            'an unmount handler is told about a row and then reads it - '
            'freeing must not pull it out from under the walk announcing it',
      );
      expect(page.resolveRead(a)!.asTypedList(8), [9, 9, 9, 9, 9, 9, 9, 9]);

      pool.beginTick();
      expect(page.rowOffsets, [b], reason: 'and it is gone by the next tick');
    });

    test('freeing every row mid-walk does not throw', () {
      page.allocate(8);
      page.allocate(8);
      page.allocate(8);

      // Against the old code this was a ConcurrentModificationError: `free`
      // mutated the same `Set` the lazy walk consulted per candidate row.
      expect(() {
        for (final offset in page.rowOffsets) {
          page.free(offset);
        }
      }, returnsNormally);

      pool.beginTick();
      expect(page.rowOffsets, isEmpty);
    });

    test('a walk abandoned by `break` does not strand the page', () {
      final a = page.allocate(8);
      page.allocate(8);

      for (final offset in page.rowOffsets) {
        page.free(offset);
        break;
      }

      // The reason the deferral is cleared on the tick boundary rather than
      // when the iterator finishes: a `for-in` left by `break` never resumes
      // the `sync*` body, so a `finally` there would never run and a
      // scope-counted version would defer forever. `ActiveCameraResolver`
      // breaks out of a query deliberately, so this is a live path.
      pool.beginTick();
      expect(page.rowOffsets, hasLength(1));
      expect(page.rowOffsets, isNot(contains(a)));
    });
  });

  group('the resolved-row cache', () {
    test('the epoch moves on beginTick, commitTick and freePage', () {
      final pool = MemoryPool(pageSize: 4096, maxPages: 4);
      addTearDown(pool.dispose);
      final page = pool.allocatePage();
      page.allocate(64);

      final atStart = pool.epoch;
      pool.beginTick();
      final afterBegin = pool.epoch;
      pool.commitTick();
      final afterCommit = pool.epoch;

      expect(
        afterBegin,
        greaterThan(atStart),
        reason: 'beginTick rotates the write slot',
      );
      expect(
        afterCommit,
        greaterThan(afterBegin),
        reason:
            'commitTick publishes, which moves every *read* base - '
            'presentation runs after this and reads through the cache, so '
            'missing it would hand the renderer last tickrows',
      );

      pool.freePage(page);
      expect(
        pool.epoch,
        greaterThan(afterCommit),
        reason:
            'a cached base into a freed page is a use-after-free, and '
            'shared memory cannot report one - it just returns wrong bytes',
      );
    });

    group('what allocate refuses', () {
      // Two of these three are wiring mistakes - decided by which isolate
      // holds the page and by which archetype owns it, both fixed before any
      // entity exists - so they are asserts now. A page filling up is the
      // one that depends on how many entities the game made, and it stays a
      // throw in every build.

      test('a page adopted from another isolate cannot allocate', () {
        final pool = MemoryPool(pageSize: 4096);
        addTearDown(pool.dispose);
        final source = pool.allocatePage();
        pool.beginTick();
        source.allocate(8);
        pool.commitTick();

        final adopted = pool.adoptPage(
          ownerArchetypeId: 0,
          latestAddress: source.resolveRead(0)!.address,
          slotAddresses: [source.resolveWrite(0).address],
        );

        expect(
          () => adopted.allocate(8),
          throwsStateError,
          reason:
              'the allocating isolate owns row occupancy - a second one '
              'handing out offsets would hand out the same ones',
        );
      });

      // The stride lock already has a case: 'a page is stride-locked to its
      // first allocate() size', above.

      test('a full page still throws in every build', () {
        // Not an assert: this one is about how many entities exist, which is
        // a property of the running game rather than of the code.
        final pool = MemoryPool(pageSize: 64);
        addTearDown(pool.dispose);
        final page = pool.allocatePage();

        for (var i = 0; i < 4; i++) {
          page.allocate(16);
        }
        expect(page.isFull, isTrue);
        expect(() => page.allocate(16), throwsStateError);
      });
    });
  });
}
