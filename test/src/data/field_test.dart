import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/src/data/component.dart';
import 'package:goo2d/src/data/world.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

class Vec2Data extends EntityData {
  late final Field<double> x;
  late final Field<double> y;

  @override
  void describe(DataDescriptor d) {
    x = d.newFloat64();
    y = d.newFloat64();
  }
}

class CounterData extends EntityData {
  late final Field<int> count;

  @override
  void describe(DataDescriptor d) {
    count = d.newInt32();
  }
}

// Custom field test fixtures â€” all private to this file.
class _Point {
  final double x;
  final double y;
  const _Point(this.x, this.y);
}

class _PointParser extends FieldParser<_Point> {
  @override
  void describe(FieldDescriptor d) {
    d.addFloat64(); // x
    d.addFloat64(); // y
  }

  @override
  _Point read(FieldReader r) => _Point(r.readFloat64(), r.readFloat64());

  @override
  void write(_Point v, FieldWriter w) {
    w.writeFloat64(v.x);
    w.writeFloat64(v.y);
  }
}

class _PointData extends EntityData {
  late final Field<_Point> point;

  @override
  void describe(DataDescriptor d) {
    point = d.newField(_PointParser(), initialValue: const _Point(0, 0));
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Field<T>', () {
    test('reads and writes correct slot via QueryResult', () {
      final world = WorldController();
      final e0 = world.createEntity(Vec2Data.new);
      world.createEntity(Vec2Data.new);

      final q = world.query()..withAll(Vec2Data);

      // Set slot 0 = (1.0, 2.0), slot 1 = (3.0, 4.0)
      for (final r in q.withEntity().execute()) {
        final v = r.get<Vec2Data>();
        if (r.entity.index == e0.index) {
          v.x.set(r, 1.0);
          v.y.set(r, 2.0);
        } else {
          v.x.set(r, 3.0);
          v.y.set(r, 4.0);
        }
      }

      // Verify
      for (final r in q.withEntity().execute()) {
        final v = r.get<Vec2Data>();
        if (r.entity.index == e0.index) {
          expect(v.x.get(r), 1.0);
          expect(v.y.get(r), 2.0);
        } else {
          expect(v.x.get(r), 3.0);
          expect(v.y.get(r), 4.0);
        }
      }
    });

    test(
      'two EntityData types use independent backing arrays â€” no aliasing',
      () {
        final world = WorldController();
        world.createEntity(Vec2Data.new, CounterData.new);

        final q = world.query()..withAll(Vec2Data, CounterData);
        final r = q.executeSingle()!;

        final v = r.get<Vec2Data>();
        final c = r.get<CounterData>();

        v.x.set(r, 99.9);
        c.count.set(r, 7);

        expect(v.x.get(r), 99.9);
        expect(c.count.get(r), 7);
      },
    );

    test('nested queries over same type use correct independent cursors', () {
      final world = WorldController();
      world.createEntity(Vec2Data.new);
      world.createEntity(Vec2Data.new);

      int iterations = 0;

      final outer = world.query()..withAll(Vec2Data);
      for (final r1 in outer.withEntity().execute()) {
        r1.get<Vec2Data>().x.set(r1, r1.entity.index.toDouble());

        final inner = world.query()..withAll(Vec2Data);
        for (final r2 in inner.execute()) {
          // Inner cursor must not corrupt outer cursor
          final v = r2.get<Vec2Data>();
          // Reading inner should not change outer's slot
          v.x.get(r2);
        }

        // Outer value must still be what we set
        expect(r1.get<Vec2Data>().x.get(r1), r1.entity.index.toDouble());
        iterations++;
      }
      expect(iterations, 2);
    });

    test('custom field (FieldParser) round-trips a struct via ByteData', () {
      final world = WorldController();
      world.createEntity(_PointData.new);

      final r = (world.query()..withAll(_PointData)).executeSingle()!;
      final pd = r.get<_PointData>();

      pd.point.set(r, const _Point(3.14, -2.72));
      final result = pd.point.get(r);
      expect(result.x, 3.14);
      expect(result.y, -2.72);
    });

    test('custom field: nested queries do not corrupt each other', () {
      final world = WorldController();
      world.createEntity(_PointData.new);
      world.createEntity(_PointData.new);

      int i = 0;
      for (final r1 in (world.query()..withAll(_PointData)).execute()) {
        r1.get<_PointData>().point.set(r1, _Point(i.toDouble(), 0));
        for (final r2 in (world.query()..withAll(_PointData)).execute()) {
          r2.get<_PointData>().point.get(r2);
        }
        expect(r1.get<_PointData>().point.get(r1).x, i.toDouble());
        i++;
      }
    });

    test('Int32 field holds integer values correctly', () {
      final world = WorldController();
      world.createEntity(CounterData.new);

      final r = (world.query()..withAll(CounterData)).executeSingle()!;
      final c = r.get<CounterData>();

      c.count.set(r, 42);
      expect(c.count.get(r), 42);

      c.count.set(r, -1);
      expect(c.count.get(r), -1);
    });
  });
}
