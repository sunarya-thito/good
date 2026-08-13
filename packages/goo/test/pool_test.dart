import 'dart:ffi';

import 'package:goo/src/pool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MemoryPool / MemoryPage', () {
    test('allocate -> write -> commitTick -> read round-trips bytes', () {
      final pool = MemoryPool(pageSize: 4096);
      addTearDown(pool.dispose);

      final page = pool.allocatePage();
      pool.beginTick();
      final offset = page.allocate(8);
      page.resolveWrite(offset).asTypedList(8).setAll(0, [1, 2, 3, 4, 5, 6, 7, 8]);
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
}
