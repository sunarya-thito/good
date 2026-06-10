import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/src/data/component.dart';
import 'package:goo2d/src/data/world.dart';

class TagData extends EntityData {
  late final Field<int> value;
  @override
  void describe(DataDescriptor d) => value = d.newInt32();
}

class HealthData extends EntityData {
  late final Field<double> hp;
  @override
  void describe(DataDescriptor d) => hp = d.newFloat64();
}

void main() {
  group('Entity storage', () {
    test('createEntity allocates a slot; field returns default value', () {
      final world = WorldController();
      world.createEntity(TagData.new);
      final r = (world.query()..withAll(TagData)).executeSingle()!;
      // Default Int32List value is 0
      expect(r.get<TagData>().value.get(r), 0);
    });

    test('createEntity with two types allocates slots in both arrays', () {
      final world = WorldController();
      world.createEntity(TagData.new, HealthData.new);
      final r = (world.query()..withAll(TagData, HealthData))
          .executeSingle()!;
      expect(r.get<TagData>().value.get(r), 0);
      expect(r.get<HealthData>().hp.get(r), 0.0);
    });

    test(
      'removeEntity frees the slot; entity no longer appears in queries',
      () {
        final world = WorldController();
        final e = world.createEntity(TagData.new);
        world.removeEntity(e);
        final r = (world.query()..withAll(TagData)).executeSingle();
        expect(r, isNull);
      },
    );

    test('slot is marked dead after removal; invisible to queries', () {
      final world = WorldController();
      final e = world.createEntity(TagData.new);
      world.removeEntity(e);
      expect((world.query()..withAll(TagData)).executeSingle(), isNull);
    });

    test('stale entity reference throws on getData', () {
      final world = WorldController();
      final e = world.createEntity(TagData.new);
      world.removeEntity(e);
      expect(() => e.getData<TagData>(), throwsA(isA<AssertionError>()));
    });

    test('capacity growth: creating many entities preserves data', () {
      final world = WorldController();
      const n = 200; // exceeds initial capacity of 64
      final entities = List.generate(n, (_) => world.createEntity(TagData.new));

      // Set unique values
      final q = world.query()..withAll(TagData);
      for (final r in q.withEntity().execute()) {
        r.get<TagData>().value.set(r, r.entity.index);
      }

      // Re-read and verify all values are intact after potential grow
      for (final r in q.withEntity().execute()) {
        expect(r.get<TagData>().value.get(r), r.entity.index);
      }
      expect(entities.length, n);
    });

    test('high-water trim: freeing last slot shrinks count immediately', () {
      final world = WorldController();
      world.createEntity(TagData.new); // slot 0
      final e1 = world.createEntity(TagData.new); // slot 1
      world.removeEntity(e1); // frees last slot â†’ _count shrinks to 1
      // Only one entity should be visible to queries.
      final results = (world.query()..withAll(TagData)).execute().toList();
      expect(results.length, 1);
    });

    test('compact: alive entities are packed; dead gaps eliminated', () {
      final world = WorldController();
      final a = world.createEntity(TagData.new); // slot 0
      final b = world.createEntity(TagData.new); // slot 1 â€” will be removed
      final c = world.createEntity(TagData.new); // slot 2

      // Set distinguishable values.
      for (final r in (world.query()..withAll(TagData)).withEntity().execute()) {
        r.get<TagData>().value.set(r, r.entity.index * 7);
      }

      // Remove the middle entity to create an interior gap.
      world.removeEntity(b);

      world.compact();

      // After compact, exactly two entities remain and slots are 0 and 1.
      final results = (world.query()..withAll(TagData)).withEntity().execute().toList();
      expect(results.length, 2);
      expect(results.map((r) => r.entity.index).toList(), [0, 1]);

      // a stayed at slot 0 â€” handle is still valid.
      expect(() => a.getData<TagData>(), returnsNormally);
      // c moved from slot 2 to slot 1; old slot 2 is in the dead tail.
      expect(() => c.getData<TagData>(), throwsA(isA<AssertionError>()));
    });

    test('compact: no-op when already dense', () {
      final world = WorldController();
      world.createEntity(TagData.new);
      world.createEntity(TagData.new);
      expect(() => world.compact(), returnsNormally);
      expect((world.query()..withAll(TagData)).execute().length, 2);
    });

    test('slot reuse: removed entity slot is reused; old ref rejected', () {
      final world = WorldController();
      final e1 = world.createEntity(TagData.new) as dynamic;
      final slot1 = e1.index as int;
      world.removeEntity(e1);

      // Next entity should reuse the freed slot
      final e2 = world.createEntity(TagData.new) as dynamic;
      expect(e2.index, slot1);

      // Old reference has wrong generation â†’ throws
      expect(() => e1.getData<TagData>(), throwsA(isA<AssertionError>()));
    });
  });
}
