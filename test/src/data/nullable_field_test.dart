import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/src/data/component.dart';
import 'package:goo2d/src/data/object.dart';
import 'package:goo2d/src/data/world.dart';

// ---------------------------------------------------------------------------
// Fixtures — one EntityData per nullable form tested
// ---------------------------------------------------------------------------

class NullableWordData extends EntityData {
  late final Field<int?> n32;
  late final Field<int?> n64;
  late final Field<int?> un8;
  @override
  void describe(DataDescriptor d) {
    n32 = d.newInt32Nullable();
    n64 = d.newInt64Nullable();
    un8 = d.newUint8Nullable();
  }
}

class NullableWordDefaultData extends EntityData {
  late final Field<int?> n32;
  @override
  void describe(DataDescriptor d) {
    n32 = d.newInt32Nullable(initialValue: 42);
  }
}

class NullablePackedData extends EntityData {
  late final Field<int?> b4;
  late final Field<int?> ub4;
  late final Field<int?> b2;
  late final Field<int?> bit;
  @override
  void describe(DataDescriptor d) {
    b4  = d.newInt4Nullable();
    ub4 = d.newUint4Nullable();
    b2  = d.newInt2Nullable();
    bit = d.newBitNullable();
  }
}

class NullableBoolData extends EntityData {
  late final Field<bool?> b;
  @override
  void describe(DataDescriptor d) => b = d.newBoolNullable();
}

class StolenBitData extends EntityData {
  late final Field<int?> i31;
  late final Field<int?> i7;
  late final Field<int?> u7;
  @override
  void describe(DataDescriptor d) {
    i31 = d.newInt31Nullable();
    i7  = d.newInt7Nullable();
    u7  = d.newUint7Nullable();
  }
}

class StolenBitDefaultData extends EntityData {
  late final Field<int?> i31;
  @override
  void describe(DataDescriptor d) {
    i31 = d.newInt31Nullable(initialValue: -1);
  }
}

class TaggedWordData extends EntityData {
  late final Field<int?> i32;
  late final Field<double?> f64;
  late final Field<int?> u16;
  @override
  void describe(DataDescriptor d) {
    i32 = d.newInt32Tagged();
    f64 = d.newFloat64Tagged();
    u16 = d.newUint16Tagged();
  }
}

class TaggedWordDefaultData extends EntityData {
  late final Field<int?> i32;
  @override
  void describe(DataDescriptor d) => i32 = d.newInt32Tagged(initialValue: 99);
}

class TaggedBoolData extends EntityData {
  late final Field<bool?> b;
  @override
  void describe(DataDescriptor d) => b = d.newBoolTagged();
}

// ---------------------------------------------------------------------------
// Custom field fixtures
// ---------------------------------------------------------------------------

class _Vec2 {
  final double x;
  final double y;
  const _Vec2(this.x, this.y);
  @override bool operator ==(Object o) => o is _Vec2 && o.x == x && o.y == y;
  @override int get hashCode => Object.hash(x, y);
}

class _Vec2Parser extends FieldParser<_Vec2> {
  @override
  void describe(FieldDescriptor d) {
    d.addFloat64();
    d.addFloat64();
  }
  @override _Vec2 read(FieldReader r) => _Vec2(r.readFloat64(), r.readFloat64());
  @override void write(_Vec2 v, FieldWriter w) { w.writeFloat64(v.x); w.writeFloat64(v.y); }
}

class _CustomInitData extends EntityData {
  late final Field<_Vec2> v;
  @override
  void describe(DataDescriptor d) =>
      v = d.newField(_Vec2Parser(), initialValue: const _Vec2(3.0, 4.0));
}

class _NullableCustomData extends EntityData {
  late final Field<_Vec2?> v;
  @override
  void describe(DataDescriptor d) => v = d.newFieldNullable(_Vec2Parser());
}

class _NullableCustomInitData extends EntityData {
  late final Field<_Vec2?> v;
  @override
  void describe(DataDescriptor d) =>
      v = d.newFieldNullable(_Vec2Parser(), initialValue: const _Vec2(1.0, 2.0));
}

// Nested: a FieldParser that embeds a nullable _Vec2 using addNullableField.
class _MaybeVec2 {
  final _Vec2? inner;
  const _MaybeVec2(this.inner);
  @override bool operator ==(Object o) => o is _MaybeVec2 && o.inner == inner;
  @override int get hashCode => inner.hashCode;
}

class _MaybeVec2Parser extends FieldParser<_MaybeVec2> {
  final _Vec2Parser _inner = _Vec2Parser();
  @override
  void describe(FieldDescriptor d) => d.addNullableField(_inner);
  @override _MaybeVec2 read(FieldReader r) => _MaybeVec2(r.readNullableField(_inner));
  @override void write(_MaybeVec2 v, FieldWriter w) => w.writeNullableField(v.inner, _inner);
}

class _NestedNullableData extends EntityData {
  late final Field<_MaybeVec2> f;
  @override
  void describe(DataDescriptor d) =>
      f = d.newField(_MaybeVec2Parser(), initialValue: const _MaybeVec2(null));
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

QueryResult _single(WorldController w, Type type) {
  final q = w.query()..withAll(type);
  return q.executeSingle()!;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('newXNullable (word types)', () {
    test('default value is null', () {
      final world = WorldController();
      world.createEntity(NullableWordData.new);
      final r = _single(world, NullableWordData);
      final d = r.get<NullableWordData>();
      expect(d.n32.get(r), isNull);
      expect(d.n64.get(r), isNull);
      expect(d.un8.get(r), isNull);
    });

    test('round-trip: set non-null then read', () {
      final world = WorldController();
      world.createEntity(NullableWordData.new);
      final r = _single(world, NullableWordData);
      final d = r.get<NullableWordData>();
      d.n32.set(r, 12345);
      expect(d.n32.get(r), 12345);
      d.n64.set(r, -9999999999);
      expect(d.n64.get(r), -9999999999);
      d.un8.set(r, 200);
      expect(d.un8.get(r), 200);
    });

    test('write null after non-null → null', () {
      final world = WorldController();
      world.createEntity(NullableWordData.new);
      final r = _single(world, NullableWordData);
      final d = r.get<NullableWordData>();
      d.n32.set(r, 7);
      d.n32.set(r, null);
      expect(d.n32.get(r), isNull);
    });

    test('zero value is distinct from null', () {
      final world = WorldController();
      world.createEntity(NullableWordData.new);
      final r = _single(world, NullableWordData);
      final d = r.get<NullableWordData>();
      d.n32.set(r, 0);
      expect(d.n32.get(r), 0);
      expect(d.n32.get(r), isNotNull);
    });

    test('initialValue non-null respected', () {
      final world = WorldController();
      world.createEntity(NullableWordDefaultData.new);
      final r = _single(world, NullableWordDefaultData);
      expect(r.get<NullableWordDefaultData>().n32.get(r), 42);
    });

    test('capacity growth preserves null/non-null state', () {
      final world = WorldController();
      const n = 200;
      for (int i = 0; i < n; i++) world.createEntity(NullableWordData.new);

      final q = world.query()..withAll(NullableWordData);
      int idx = 0;
      for (final r in q.withEntity().execute()) {
        final d = r.get<NullableWordData>();
        if (idx % 2 == 0) {
          d.n32.set(r, idx);
        } else {
          d.n32.set(r, null);
        }
        idx++;
      }
      idx = 0;
      for (final r in q.withEntity().execute()) {
        final d = r.get<NullableWordData>();
        if (idx % 2 == 0) {
          expect(d.n32.get(r), idx);
        } else {
          expect(d.n32.get(r), isNull);
        }
        idx++;
      }
    });
  });

  group('newXNullable (packed int types)', () {
    test('default is null for int4/bit/int2', () {
      final world = WorldController();
      world.createEntity(NullablePackedData.new);
      final r = _single(world, NullablePackedData);
      final d = r.get<NullablePackedData>();
      expect(d.b4.get(r), isNull);
      expect(d.ub4.get(r), isNull);
      expect(d.b2.get(r), isNull);
      expect(d.bit.get(r), isNull);
    });

    test('int4Nullable: zero is distinct from null', () {
      final world = WorldController();
      world.createEntity(NullablePackedData.new);
      final r = _single(world, NullablePackedData);
      final d = r.get<NullablePackedData>();
      d.b4.set(r, 0);
      expect(d.b4.get(r), 0);
      expect(d.b4.get(r), isNotNull);
    });

    test('int4Nullable: round-trip positive and negative', () {
      final world = WorldController();
      world.createEntity(NullablePackedData.new);
      final r = _single(world, NullablePackedData);
      final d = r.get<NullablePackedData>();
      d.b4.set(r, 7);
      expect(d.b4.get(r), 7);
      d.b4.set(r, -8);
      expect(d.b4.get(r), -8);
      d.b4.set(r, null);
      expect(d.b4.get(r), isNull);
    });

    test('uint4Nullable: full range 0–15', () {
      final world = WorldController();
      world.createEntity(NullablePackedData.new);
      final r = _single(world, NullablePackedData);
      final d = r.get<NullablePackedData>();
      for (int v = 0; v <= 15; v++) {
        d.ub4.set(r, v);
        expect(d.ub4.get(r), v);
      }
    });

    test('multiple packed nullable fields coexist in same byte', () {
      final world = WorldController();
      world.createEntity(NullablePackedData.new);
      final r = _single(world, NullablePackedData);
      final d = r.get<NullablePackedData>();
      d.b4.set(r, -3);
      d.ub4.set(r, 11);
      d.b2.set(r, -1);
      d.bit.set(r, 1);
      expect(d.b4.get(r), -3);
      expect(d.ub4.get(r), 11);
      expect(d.b2.get(r), -1);
      expect(d.bit.get(r), 1);
    });
  });

  group('newBoolNullable', () {
    test('default is null', () {
      final world = WorldController();
      world.createEntity(NullableBoolData.new);
      final r = _single(world, NullableBoolData);
      expect(r.get<NullableBoolData>().b.get(r), isNull);
    });

    test('false/true/null tri-state all distinct', () {
      final world = WorldController();
      world.createEntity(NullableBoolData.new);
      final r = _single(world, NullableBoolData);
      final d = r.get<NullableBoolData>();

      d.b.set(r, false);
      expect(d.b.get(r), false);
      expect(d.b.get(r), isNotNull);

      d.b.set(r, true);
      expect(d.b.get(r), true);

      d.b.set(r, null);
      expect(d.b.get(r), isNull);
    });
  });

  group('newXMinusBitNullable (stolen-bit)', () {
    test('default is null (sentinel stored)', () {
      final world = WorldController();
      world.createEntity(StolenBitData.new);
      final r = _single(world, StolenBitData);
      final d = r.get<StolenBitData>();
      expect(d.i31.get(r), isNull);
      expect(d.i7.get(r), isNull);
      expect(d.u7.get(r), isNull);
    });

    test('round-trip non-null values', () {
      final world = WorldController();
      world.createEntity(StolenBitData.new);
      final r = _single(world, StolenBitData);
      final d = r.get<StolenBitData>();
      d.i31.set(r, 0);
      expect(d.i31.get(r), 0);
      d.i31.set(r, 2147483647);
      expect(d.i31.get(r), 2147483647);
      d.i31.set(r, -2147483647);
      expect(d.i31.get(r), -2147483647);
    });

    test('write null after non-null', () {
      final world = WorldController();
      world.createEntity(StolenBitData.new);
      final r = _single(world, StolenBitData);
      final d = r.get<StolenBitData>();
      d.i31.set(r, 99);
      d.i31.set(r, null);
      expect(d.i31.get(r), isNull);
    });

    test('initialValue non-null respected', () {
      final world = WorldController();
      world.createEntity(StolenBitDefaultData.new);
      final r = _single(world, StolenBitDefaultData);
      expect(r.get<StolenBitDefaultData>().i31.get(r), -1);
    });

    test('uint7Nullable range 0–254 and null', () {
      final world = WorldController();
      world.createEntity(StolenBitData.new);
      final r = _single(world, StolenBitData);
      final d = r.get<StolenBitData>();
      d.u7.set(r, 0);
      expect(d.u7.get(r), 0);
      d.u7.set(r, 254);
      expect(d.u7.get(r), 254);
      d.u7.set(r, null);
      expect(d.u7.get(r), isNull);
    });
  });

  group('newXTagged (word types)', () {
    test('default is null', () {
      final world = WorldController();
      world.createEntity(TaggedWordData.new);
      final r = _single(world, TaggedWordData);
      final d = r.get<TaggedWordData>();
      expect(d.i32.get(r), isNull);
      expect(d.f64.get(r), isNull);
      expect(d.u16.get(r), isNull);
    });

    test('round-trip int and float tagged', () {
      final world = WorldController();
      world.createEntity(TaggedWordData.new);
      final r = _single(world, TaggedWordData);
      final d = r.get<TaggedWordData>();
      d.i32.set(r, -500000);
      expect(d.i32.get(r), -500000);
      d.f64.set(r, 3.14159);
      expect(d.f64.get(r), closeTo(3.14159, 1e-9));
      d.u16.set(r, 65535);
      expect(d.u16.get(r), 65535);
    });

    test('write null clears tagged field', () {
      final world = WorldController();
      world.createEntity(TaggedWordData.new);
      final r = _single(world, TaggedWordData);
      final d = r.get<TaggedWordData>();
      d.i32.set(r, 1);
      d.i32.set(r, null);
      expect(d.i32.get(r), isNull);
    });

    test('zero value is non-null', () {
      final world = WorldController();
      world.createEntity(TaggedWordData.new);
      final r = _single(world, TaggedWordData);
      final d = r.get<TaggedWordData>();
      d.i32.set(r, 0);
      expect(d.i32.get(r), 0);
      expect(d.i32.get(r), isNotNull);
    });

    test('initialValue non-null respected', () {
      final world = WorldController();
      world.createEntity(TaggedWordDefaultData.new);
      final r = _single(world, TaggedWordDefaultData);
      expect(r.get<TaggedWordDefaultData>().i32.get(r), 99);
    });

    test('capacity growth preserves tagged state', () {
      final world = WorldController();
      const n = 150;
      for (int i = 0; i < n; i++) world.createEntity(TaggedWordData.new);
      final q = world.query()..withAll(TaggedWordData);
      int idx = 0;
      for (final r in q.withEntity().execute()) {
        final d = r.get<TaggedWordData>();
        if (idx % 3 != 0) d.i32.set(r, idx);
        idx++;
      }
      idx = 0;
      for (final r in q.withEntity().execute()) {
        final d = r.get<TaggedWordData>();
        if (idx % 3 != 0) {
          expect(d.i32.get(r), idx);
        } else {
          expect(d.i32.get(r), isNull);
        }
        idx++;
      }
    });
  });

  group('newBoolTagged', () {
    test('default is null', () {
      final world = WorldController();
      world.createEntity(TaggedBoolData.new);
      final r = _single(world, TaggedBoolData);
      expect(r.get<TaggedBoolData>().b.get(r), isNull);
    });

    test('false/true/null tri-state', () {
      final world = WorldController();
      world.createEntity(TaggedBoolData.new);
      final r = _single(world, TaggedBoolData);
      final d = r.get<TaggedBoolData>();

      d.b.set(r, true);
      expect(d.b.get(r), true);

      d.b.set(r, false);
      expect(d.b.get(r), false);
      expect(d.b.get(r), isNotNull);

      d.b.set(r, null);
      expect(d.b.get(r), isNull);
    });
  });

  group('newField initialValue', () {
    test('initialValue applied on entity creation', () {
      final world = WorldController();
      world.createEntity(_CustomInitData.new);
      final r = _single(world, _CustomInitData);
      expect(r.get<_CustomInitData>().v.get(r), const _Vec2(3.0, 4.0));
    });

    test('round-trip set then read', () {
      final world = WorldController();
      world.createEntity(_CustomInitData.new);
      final r = _single(world, _CustomInitData);
      r.get<_CustomInitData>().v.set(r, const _Vec2(9.0, -1.5));
      expect(r.get<_CustomInitData>().v.get(r), const _Vec2(9.0, -1.5));
    });
  });

  group('newFieldNullable', () {
    test('default value is null', () {
      final world = WorldController();
      world.createEntity(_NullableCustomData.new);
      final r = _single(world, _NullableCustomData);
      expect(r.get<_NullableCustomData>().v.get(r), isNull);
    });

    test('round-trip non-null value', () {
      final world = WorldController();
      world.createEntity(_NullableCustomData.new);
      final r = _single(world, _NullableCustomData);
      r.get<_NullableCustomData>().v.set(r, const _Vec2(5.0, 6.0));
      expect(r.get<_NullableCustomData>().v.get(r), const _Vec2(5.0, 6.0));
    });

    test('write null after non-null', () {
      final world = WorldController();
      world.createEntity(_NullableCustomData.new);
      final r = _single(world, _NullableCustomData);
      r.get<_NullableCustomData>().v.set(r, const _Vec2(1.0, 2.0));
      r.get<_NullableCustomData>().v.set(r, null);
      expect(r.get<_NullableCustomData>().v.get(r), isNull);
    });

    test('initialValue non-null respected', () {
      final world = WorldController();
      world.createEntity(_NullableCustomInitData.new);
      final r = _single(world, _NullableCustomInitData);
      expect(r.get<_NullableCustomInitData>().v.get(r), const _Vec2(1.0, 2.0));
    });
  });

  group('nested readNullableField / writeNullableField', () {
    test('default inner null applies on entity creation', () {
      final world = WorldController();
      world.createEntity(_NestedNullableData.new);
      final r = _single(world, _NestedNullableData);
      expect(r.get<_NestedNullableData>().f.get(r), const _MaybeVec2(null));
    });

    test('round-trip non-null inner value', () {
      final world = WorldController();
      world.createEntity(_NestedNullableData.new);
      final r = _single(world, _NestedNullableData);
      r.get<_NestedNullableData>().f.set(r, const _MaybeVec2(_Vec2(7.0, 8.0)));
      expect(r.get<_NestedNullableData>().f.get(r), const _MaybeVec2(_Vec2(7.0, 8.0)));
    });

    test('round-trip null inner value', () {
      final world = WorldController();
      world.createEntity(_NestedNullableData.new);
      final r = _single(world, _NestedNullableData);
      r.get<_NestedNullableData>().f.set(r, const _MaybeVec2(_Vec2(1.0, 2.0)));
      r.get<_NestedNullableData>().f.set(r, const _MaybeVec2(null));
      expect(r.get<_NestedNullableData>().f.get(r), const _MaybeVec2(null));
    });
  });

  group('compact preserves nullable state', () {
    test('interleaved nullable survives compact', () {
      final world = WorldController();
      final a = world.createEntity(NullableWordData.new);
      final b = world.createEntity(NullableWordData.new);
      final c = world.createEntity(NullableWordData.new);

      final q = world.query()..withAll(NullableWordData);
      for (final r in q.withEntity().execute()) {
        r.get<NullableWordData>().n32.set(r, r.entity.index * 10);
      }

      world.removeEntity(b);
      world.compact();

      final results = q.withEntity().execute().toList();
      expect(results.length, 2);
      // a at slot 0: value = 0*10 = 0 (non-null)
      expect(results[0].get<NullableWordData>().n32.get(results[0]), isNotNull);
      // c moved to slot 1: value = 2*10 = 20 (non-null)
      expect(results[1].get<NullableWordData>().n32.get(results[1]), isNotNull);
      expect(a, isNotNull);
      expect(c, isNotNull);
    });

    test('tagged nullable survives compact', () {
      final world = WorldController();
      world.createEntity(TaggedWordData.new);
      final mid = world.createEntity(TaggedWordData.new);
      world.createEntity(TaggedWordData.new);

      final q = world.query()..withAll(TaggedWordData);
      int idx = 0;
      for (final r in q.withEntity().execute()) {
        if (idx == 1) r.get<TaggedWordData>().i32.set(r, 777);
        idx++;
      }

      world.removeEntity(mid);
      world.compact();

      final results = q.execute().toList();
      expect(results.length, 2);
      expect(results[0].get<TaggedWordData>().i32.get(results[0]), isNull);
      expect(results[1].get<TaggedWordData>().i32.get(results[1]), isNull);
    });
  });
}
