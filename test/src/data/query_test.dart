import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/src/data/component.dart';
import 'package:goo2d/src/data/world.dart';

class AData extends EntityData {
  late final Field<int> v;
  @override
  void describe(DataDescriptor d) => v = d.newInt32();
}

class BData extends EntityData {
  late final Field<int> v;
  @override
  void describe(DataDescriptor d) => v = d.newInt32();
}

class CData extends EntityData {
  late final Field<int> v;
  @override
  void describe(DataDescriptor d) => v = d.newInt32();
}

void main() {
  group('QueryBuilder', () {
    test('withAll(A) returns only entities with A', () {
      final world = WorldController();
      world.createEntity(AData.new);
      world.createEntity(BData.new);
      world.createEntity(AData.new, BData.new);

      final results = (world.query()..withAll(AData)).execute().toList();
      expect(results.length, 2);
    });

    test('withAll(A, B) returns only entities with both', () {
      final world = WorldController();
      world.createEntity(AData.new);
      world.createEntity(BData.new);
      world.createEntity(AData.new, BData.new);

      final results = (world.query()..withAll(AData, BData))
          .execute()
          .toList();
      expect(results.length, 1);
    });

    test('withAny(A, B) returns entities with A, B, or both', () {
      final world = WorldController();
      world.createEntity(AData.new);
      world.createEntity(BData.new);
      world.createEntity(CData.new);
      world.createEntity(AData.new, BData.new);

      final results = (world.query()..withAny(AData, BData))
          .execute()
          .toList();
      expect(results.length, 3); // A, B, A+B â€” not C
    });

    test('withNone(A) excludes entities that have A', () {
      final world = WorldController();
      world.createEntity(AData.new);
      world.createEntity(BData.new);
      world.createEntity(AData.new, BData.new);

      final results = (world.query()..withNone(AData)).execute().toList();
      expect(results.length, 1);
    });

    test('executeSingle returns null when nothing matches', () {
      final world = WorldController();
      world.createEntity(BData.new);

      final r = (world.query()..withAll(AData)).executeSingle();
      expect(r, isNull);
    });

    test('executeSingle returns the entity when exactly one matches', () {
      final world = WorldController();
      world.createEntity(AData.new);

      final r = (world.query()..withAll(AData)).executeSingle();
      expect(r, isNotNull);
    });

    test('get<T>() returns correct EntityData type', () {
      final world = WorldController();
      world.createEntity(AData.new, BData.new);

      final r = (world.query()..withAll(AData, BData)).executeSingle()!;
      expect(r.get<AData>(), isA<AData>());
      expect(r.get<BData>(), isA<BData>());
    });

    test('nested queries â€” outer cursor unaffected by inner iteration', () {
      final world = WorldController();
      for (int i = 0; i < 3; i++) {
        world.createEntity(AData.new);
      }

      int outerCount = 0;
      for (final r1 in (world.query()..withAll(AData)).withEntity().execute()) {
        r1.get<AData>().v.set(r1, r1.entity.index * 10);
        for (final r2 in (world.query()..withAll(AData)).execute()) {
          r2.get<AData>().v.get(r2); // just read â€” must not corrupt r1
        }
        expect(r1.get<AData>().v.get(r1), r1.entity.index * 10);
        outerCount++;
      }
      expect(outerCount, 3);
    });
  });
}
