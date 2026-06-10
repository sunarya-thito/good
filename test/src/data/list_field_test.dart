import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/src/data/component.dart';
import 'package:goo2d/src/data/world.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

class _ViewData extends EntityData {
  late final Field<Int32List> ints;
  @override
  void describe(DataDescriptor d) {
    ints = d.newInt32ListView(4);
  }
}

class _CopyData extends EntityData {
  late final Field<Int32List> ints;
  @override
  void describe(DataDescriptor d) {
    ints = d.newInt32List(4);
  }
}

class _NullableViewData extends EntityData {
  late final Field<Int32List?> ints;
  @override
  void describe(DataDescriptor d) {
    ints = d.newInt32ListViewNullable(3);
  }
}

class _NullableCopyData extends EntityData {
  late final Field<Int32List?> ints;
  @override
  void describe(DataDescriptor d) {
    ints = d.newInt32ListNullable(3);
  }
}

class _InitViewData extends EntityData {
  late final Field<Int32List> ints;
  @override
  void describe(DataDescriptor d) {
    ints = d.newInt32ListView(2, initialValue: Int32List.fromList([10, 20]));
  }
}

class _InitNullableViewData extends EntityData {
  late final Field<Int32List?> ints;
  @override
  void describe(DataDescriptor d) {
    ints = d.newInt32ListViewNullable(2,
        initialValue: Int32List.fromList([7, 8]));
  }
}

class _Float32ViewData extends EntityData {
  late final Field<Float32List> floats;
  @override
  void describe(DataDescriptor d) {
    floats = d.newFloat32ListView(3);
  }
}

class _MultiListData extends EntityData {
  late final Field<Uint8List> bytes;
  late final Field<Float64List> doubles;
  @override
  void describe(DataDescriptor d) {
    bytes = d.newUint8ListView(4);
    doubles = d.newFloat64ListView(2);
  }
}

// MutableFieldParser test fixture
class _Int32ListParser extends FieldParser<Int32List>
    with MutableFieldParser<Int32List> {
  final int count;
  _Int32ListParser(this.count);

  @override
  void describe(FieldDescriptor d) => d.addInt32ListView(count);

  @override
  Int32List read(FieldReader r) => r.readInt32ListView(count);

  @override
  void write(Int32List v, FieldWriter w) => w.writeInt32ListView(v, count);
}

class _MutableParserData extends EntityData {
  late final Field<Int32List> ints;
  @override
  void describe(DataDescriptor d) {
    ints = d.newField(_Int32ListParser(3), initialValue: Int32List(3));
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('newInt32ListView (zero-copy)', () {
    test('default value is all zeros', () {
      final world = WorldController();
      world.createEntity(_ViewData.new);
      final r = (world.query()..withAll(_ViewData)).executeSingle()!;
      final v = r.get<_ViewData>().ints.get(r);
      expect(v.length, 4);
      expect(v, everyElement(0));
    });

    test('mutating the view immediately mutates the pool', () {
      final world = WorldController();
      world.createEntity(_ViewData.new);
      final r = (world.query()..withAll(_ViewData)).executeSingle()!;
      final d = r.get<_ViewData>();

      final view1 = d.ints.get(r);
      view1[0] = 99;
      view1[3] = -5;

      final view2 = d.ints.get(r);
      expect(view2[0], 99);
      expect(view2[3], -5);
    });

    test('two reads return views into shared memory', () {
      final world = WorldController();
      world.createEntity(_ViewData.new);
      final r = (world.query()..withAll(_ViewData)).executeSingle()!;
      final d = r.get<_ViewData>();

      final a = d.ints.get(r);
      final b = d.ints.get(r);
      // Same byte offset into the pool means shared memory.
      expect(a.offsetInBytes, b.offsetInBytes);
      // Mutation through a is immediately visible in b.
      a[2] = 77;
      expect(b[2], 77);
    });

    test('set() writes all elements', () {
      final world = WorldController();
      world.createEntity(_ViewData.new);
      final r = (world.query()..withAll(_ViewData)).executeSingle()!;
      final d = r.get<_ViewData>();

      d.ints.set(r, Int32List.fromList([1, 2, 3, 4]));
      final v = d.ints.get(r);
      expect(v.toList(), [1, 2, 3, 4]);
    });

    test('initialValue applied on entity creation', () {
      final world = WorldController();
      world.createEntity(_InitViewData.new);
      final r = (world.query()..withAll(_InitViewData)).executeSingle()!;
      final v = r.get<_InitViewData>().ints.get(r);
      expect(v.toList(), [10, 20]);
    });

    test('two entities are independent', () {
      final world = WorldController();
      world.createEntity(_ViewData.new);
      world.createEntity(_ViewData.new);

      final q = world.query()..withAll(_ViewData);
      final results = q.withEntity().execute().toList();
      final r0 = results[0];
      final r1 = results[1];

      r0.get<_ViewData>().ints.get(r0)[0] = 10;
      r1.get<_ViewData>().ints.get(r1)[0] = 20;

      expect(r0.get<_ViewData>().ints.get(r0)[0], 10);
      expect(r1.get<_ViewData>().ints.get(r1)[0], 20);
    });
  });

  group('newInt32List (copy)', () {
    test('default value is all zeros', () {
      final world = WorldController();
      world.createEntity(_CopyData.new);
      final r = (world.query()..withAll(_CopyData)).executeSingle()!;
      final v = r.get<_CopyData>().ints.get(r);
      expect(v.length, 4);
      expect(v, everyElement(0));
    });

    test('mutating the copy does NOT affect the pool', () {
      final world = WorldController();
      world.createEntity(_CopyData.new);
      final r = (world.query()..withAll(_CopyData)).executeSingle()!;
      final d = r.get<_CopyData>();

      d.ints.set(r, Int32List.fromList([1, 2, 3, 4]));
      final copy = d.ints.get(r);
      copy[0] = 999;

      expect(d.ints.get(r)[0], 1); // pool unchanged
    });

    test('two reads return independent copies', () {
      final world = WorldController();
      world.createEntity(_CopyData.new);
      final r = (world.query()..withAll(_CopyData)).executeSingle()!;
      final d = r.get<_CopyData>();

      d.ints.set(r, Int32List.fromList([5, 6, 7, 8]));
      final a = d.ints.get(r);
      final b = d.ints.get(r);
      expect(identical(a, b), isFalse);
      expect(a.toList(), b.toList());
    });
  });

  group('newInt32ListViewNullable', () {
    test('default is null', () {
      final world = WorldController();
      world.createEntity(_NullableViewData.new);
      final r = (world.query()..withAll(_NullableViewData)).executeSingle()!;
      expect(r.get<_NullableViewData>().ints.get(r), isNull);
    });

    test('set non-null, read back', () {
      final world = WorldController();
      world.createEntity(_NullableViewData.new);
      final r = (world.query()..withAll(_NullableViewData)).executeSingle()!;
      final d = r.get<_NullableViewData>();

      d.ints.set(r, Int32List.fromList([3, 1, 4]));
      final v = d.ints.get(r);
      expect(v, isNotNull);
      expect(v!.toList(), [3, 1, 4]);
    });

    test('set null after non-null', () {
      final world = WorldController();
      world.createEntity(_NullableViewData.new);
      final r = (world.query()..withAll(_NullableViewData)).executeSingle()!;
      final d = r.get<_NullableViewData>();

      d.ints.set(r, Int32List.fromList([1, 2, 3]));
      d.ints.set(r, null);
      expect(d.ints.get(r), isNull);
    });

    test('mutating the nullable view mutates the pool', () {
      final world = WorldController();
      world.createEntity(_NullableViewData.new);
      final r = (world.query()..withAll(_NullableViewData)).executeSingle()!;
      final d = r.get<_NullableViewData>();

      d.ints.set(r, Int32List.fromList([0, 0, 0]));
      d.ints.get(r)![1] = 42;
      expect(d.ints.get(r)![1], 42);
    });

    test('initialValue applied on entity creation', () {
      final world = WorldController();
      world.createEntity(_InitNullableViewData.new);
      final r =
          (world.query()..withAll(_InitNullableViewData)).executeSingle()!;
      final v = r.get<_InitNullableViewData>().ints.get(r);
      expect(v, isNotNull);
      expect(v!.toList(), [7, 8]);
    });
  });

  group('newInt32ListNullable (copy)', () {
    test('default is null', () {
      final world = WorldController();
      world.createEntity(_NullableCopyData.new);
      final r = (world.query()..withAll(_NullableCopyData)).executeSingle()!;
      expect(r.get<_NullableCopyData>().ints.get(r), isNull);
    });

    test('set non-null, copy is independent', () {
      final world = WorldController();
      world.createEntity(_NullableCopyData.new);
      final r = (world.query()..withAll(_NullableCopyData)).executeSingle()!;
      final d = r.get<_NullableCopyData>();

      d.ints.set(r, Int32List.fromList([9, 8, 7]));
      final copy = d.ints.get(r)!;
      copy[0] = 0;
      expect(d.ints.get(r)![0], 9); // pool unchanged
    });
  });

  group('Float32ListView', () {
    test('round-trip float values', () {
      final world = WorldController();
      world.createEntity(_Float32ViewData.new);
      final r = (world.query()..withAll(_Float32ViewData)).executeSingle()!;
      final d = r.get<_Float32ViewData>();

      d.floats.set(r, Float32List.fromList([1.5, -2.5, 3.0]));
      final v = d.floats.get(r);
      expect(v[0], closeTo(1.5, 1e-6));
      expect(v[1], closeTo(-2.5, 1e-6));
      expect(v[2], closeTo(3.0, 1e-6));
    });
  });

  group('multiple list fields', () {
    test('two list fields coexist without aliasing', () {
      final world = WorldController();
      world.createEntity(_MultiListData.new);
      final r = (world.query()..withAll(_MultiListData)).executeSingle()!;
      final d = r.get<_MultiListData>();

      d.bytes.set(r, Uint8List.fromList([10, 20, 30, 40]));
      d.doubles.set(r, Float64List.fromList([1.1, 2.2]));

      expect(d.bytes.get(r).toList(), [10, 20, 30, 40]);
      expect(d.doubles.get(r)[0], closeTo(1.1, 1e-10));
      expect(d.doubles.get(r)[1], closeTo(2.2, 1e-10));
    });
  });

  group('MutableFieldParser skip', () {
    test('read then write skips copy when value is already in place', () {
      // This tests the MutableFieldParser identity-check optimization.
      // We write a value, read it back (returns a view), then write that same
      // view back. The _ByteDataWriter.writeField should detect the buffer
      // identity and skip the copy rather than writing bytes.
      final world = WorldController();
      world.createEntity(_MutableParserData.new);
      final r = (world.query()..withAll(_MutableParserData)).executeSingle()!;
      final d = r.get<_MutableParserData>();

      d.ints.set(r, Int32List.fromList([5, 10, 15]));
      final view = d.ints.get(r);
      // Mutate directly through view — value is already in pool memory.
      view[0] = 99;
      // Write the view back; _ByteDataWriter should detect identity and skip.
      d.ints.set(r, view);
      expect(d.ints.get(r).toList(), [99, 10, 15]);
    });
  });

  group('capacity growth', () {
    test('ListView views become stale after growth; fresh reads are valid', () {
      final world = WorldController();
      // Create enough entities to force at least one grow.
      for (var i = 0; i < 70; i++) {
        world.createEntity(_ViewData.new);
      }

      // Get a query result and write a value.
      final q = world.query()..withAll(_ViewData);
      for (final r in q.withEntity().execute()) {
        r.get<_ViewData>().ints.set(r, Int32List.fromList([r.entity.index, 0, 0, 0]));
      }

      // Verify all entities survived growth with correct values.
      for (final r in q.withEntity().execute()) {
        expect(r.get<_ViewData>().ints.get(r)[0], r.entity.index);
      }
    });
  });
}
