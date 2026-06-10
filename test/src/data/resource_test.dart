import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/src/data/component.dart';
import 'package:goo2d/src/data/object.dart';
import 'package:goo2d/src/data/world.dart';

class ScoreResource extends WorldResource {
  int value = 0;
}

class TimerResource extends WorldResource {
  double elapsed = 0;
}

class TagData extends EntityData {
  late final Field<int> v;
  @override
  void describe(DataDescriptor d) => v = d.newInt32();
}

void main() {
  group('WorldResource', () {
    test('setResource + getResource round-trips the same instance', () {
      final world = WorldController();
      final res = ScoreResource()..value = 42;
      world.setResource(res);
      expect(world.getResource<ScoreResource>(), same(res));
      expect(world.getResource<ScoreResource>().value, 42);
    });

    test('hasResource returns false before set, true after', () {
      final world = WorldController();
      expect(world.hasResource<ScoreResource>(), isFalse);
      world.setResource(ScoreResource());
      expect(world.hasResource<ScoreResource>(), isTrue);
    });

    test('getResource on unset type throws', () {
      final world = WorldController();
      expect(
        () => world.getResource<TimerResource>(),
        throwsA(isA<AssertionError>()),
      );
    });

    test('two resource types are stored independently', () {
      final world = WorldController();
      world.setResource(ScoreResource()..value = 10);
      world.setResource(TimerResource()..elapsed = 3.14);

      expect(world.getResource<ScoreResource>().value, 10);
      expect(world.getResource<TimerResource>().elapsed, 3.14);
    });

    test('resources are not queryable via withAll', () {
      final world = WorldController();
      world.setResource(ScoreResource());
      // ScoreResource is not an EntityData â€” this should simply return nothing,
      // not crash. We verify by querying for a real EntityData type.
      world.createEntity(TagData.new);
      final count = (world.query()..withAll(TagData)).execute().length;
      expect(count, 1); // only real entity, resource not included
    });
  });
}
