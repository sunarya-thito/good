import 'package:goo/src/scene_handle.dart';
import 'package:goo/src/archetype.dart';
import 'package:goo/src/data.dart';
import 'package:goo/src/data/hierarchy.dart';
import 'package:goo/src/pool.dart';
import 'package:goo/src/scene.dart';
import 'package:goo/src/struct.dart';
import 'package:goo/src/system.dart';
import 'package:flutter_test/flutter_test.dart';

// Small fixture set covering: a component two archetypes share (_Position),
// one only some have (_Health), and the hierarchy's Child mixin (already
// implemented) so OptWith<Child>() has something real to combine with -
// mirrors Transform2DSystem's actual `With<Transform2D>() & OptWith<Child>()`
// query shape.
mixin _Position on Component {
  late final DataPointer<double> x;
  late final DataPointer<double> y;

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Position>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    x = data.hasFloat64();
    y = data.hasFloat64();
  }
}

mixin _Health on Component {
  late final DataPointer<int> hitPoints;

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Health>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    hitPoints = data.hasUint16(100);
  }
}

class _Player extends EntityStruct with _Position, _Health, Child {}

class _Rock extends EntityStruct with _Position {}

class _Trigger extends EntityStruct with _Health {}

class _Level extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _Level();

  late final _Player player;
  late final _Rock rock;
  late final _Trigger trigger;

  @override
  void describeScene(SceneDescriptor descriptor) {
    player = descriptor.has(_Player());
    rock = descriptor.has(_Rock());
    trigger = descriptor.has(_Trigger());
  }
}

_Level _level({int pageSize = 4096}) {
  final level = _Level()..initializeScene(MemoryPool(pageSize: pageSize));
  level.handle = SceneRegistry.register(level);
  addTearDown(level.pool.dispose);
  return level;
}

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('withAll / withNone / withAny / withOptional matching', () {
    Query build(QueryBuilder Function(QueryBuilder b) chain) =>
        chain(ArchetypeQueryDescriptor().query()).build();

    test('withAll matches only archetypes that declared every listed type', () {
      final level = _level();
      final q = build((b) => b.withAll(_Position));
      expect(q.matches(level.player.archetype.componentSignature), isTrue);
      expect(q.matches(level.rock.archetype.componentSignature), isTrue);
      expect(q.matches(level.trigger.archetype.componentSignature), isFalse);
    });

    test('withAll with several types requires all of them, not any', () {
      final level = _level();
      final q = build((b) => b.withAll(_Position, _Health));
      expect(q.matches(level.player.archetype.componentSignature), isTrue,
          reason: 'player has both');
      expect(q.matches(level.rock.archetype.componentSignature), isFalse,
          reason: 'rock has _Position but not _Health');
      expect(q.matches(level.trigger.archetype.componentSignature), isFalse,
          reason: 'trigger has _Health but not _Position');
    });

    test('withNone matches only archetypes that lack every listed type', () {
      final level = _level();
      final q = build((b) => b.withNone(_Health));
      expect(q.matches(level.player.archetype.componentSignature), isFalse);
      expect(q.matches(level.rock.archetype.componentSignature), isTrue);
      expect(q.matches(level.trigger.archetype.componentSignature), isFalse);
    });

    test('withOptional never narrows - matches with or without the type', () {
      final level = _level();
      final q = build((b) => b.withOptional(Child));
      expect(q.matches(level.player.archetype.componentSignature), isTrue);
      expect(q.matches(level.rock.archetype.componentSignature), isTrue,
          reason: '_Rock has no Child at all, withOptional still matches it');
    });

    test('withAll and withNone combine as AND', () {
      final level = _level();
      final q = build((b) => b.withAll(_Position).withNone(_Health));
      expect(q.matches(level.player.archetype.componentSignature), isFalse,
          reason: 'player has _Health');
      expect(q.matches(level.rock.archetype.componentSignature), isTrue);
      expect(q.matches(level.trigger.archetype.componentSignature), isFalse,
          reason: 'trigger lacks _Position and also has _Health');
    });

    test('the reference WorldTransformSystem shape: withAll + withOptional', () {
      final level = _level();
      final q = build((b) => b.withAll(_Position).withOptional(Child));
      // Matches every _Position archetype regardless of Child - withOptional
      // must not silently behave like a second withAll.
      expect(q.matches(level.player.archetype.componentSignature), isTrue);
      expect(q.matches(level.rock.archetype.componentSignature), isTrue);
      expect(q.matches(level.trigger.archetype.componentSignature), isFalse);
    });

    test('withAny matches if at least one of the group is present', () {
      final level = _level();
      final q = build((b) => b.withAny(_Health, Child));
      expect(q.matches(level.player.archetype.componentSignature), isTrue,
          reason: 'player has both');
      expect(q.matches(level.rock.archetype.componentSignature), isFalse,
          reason: 'rock has neither');
      expect(q.matches(level.trigger.archetype.componentSignature), isTrue,
          reason: 'trigger has _Health');
    });

    test('two withAny calls are two groups, both of which must be satisfied', () {
      final level = _level();
      // (_Position or Child) and (_Health or Child). Only _Player
      // (_Position, _Health, Child) satisfies both groups. _Rock has just
      // _Position - first group yes, second no. _Trigger has just _Health -
      // second group yes, first no. If the two calls merged into one big
      // OR instead of ANDing, all three would match.
      final q = build((b) => b.withAny(_Position, Child).withAny(_Health, Child));
      expect(q.matches(level.player.archetype.componentSignature), isTrue);
      expect(q.matches(level.rock.archetype.componentSignature), isFalse,
          reason: 'rock satisfies the first group but not the second - two '
              'withAny calls must AND, not merge into one big OR');
      expect(q.matches(level.trigger.archetype.componentSignature), isFalse,
          reason: 'trigger satisfies the second group but not the first');
    });

    test('withAny composes with withNone', () {
      final level = _level();
      final q = build((b) => b.withAny(_Position, _Health).withNone(Child));
      expect(q.matches(level.player.archetype.componentSignature), isFalse,
          reason: 'player matches the any-group but has Child');
      expect(q.matches(level.rock.archetype.componentSignature), isTrue);
      expect(q.matches(level.trigger.archetype.componentSignature), isTrue,
          reason: 'trigger has _Health (so the any-group passes) and no Child');
    });
  });

  group('Query.run()', () {
    test('yields exactly the entities of matching archetypes, across pages', () {
      final level = _level(pageSize: 64); // small, forces multiple pages
      final players = <Entity>[];
      for (var i = 0; i < 20; i++) {
        players.add(level.addEntity(level.player));
      }
      final rocks = <Entity>[];
      for (var i = 0; i < 20; i++) {
        rocks.add(level.addEntity(level.rock));
      }
      level.addEntity(level.trigger); // must never show up below

      final descriptor = ArchetypeQueryDescriptor();
      final query = descriptor.query().withAll(_Position).build();
      final results = query.run().toSet();

      expect(results, {...players, ...rocks});
      expect(results.length, 40);
    });

    test('each entity reads back its own data, not a neighbour\'s', () {
      final level = _level(pageSize: 64);
      level.pool.beginTick();
      final entities = [for (var i = 0; i < 10; i++) level.addEntity(level.player)];
      for (var i = 0; i < entities.length; i++) {
        level.player.x[entities[i]] = i.toDouble();
      }
      level.pool.commitTick();

      final descriptor = ArchetypeQueryDescriptor();
      final seen = <double>[];
      for (final e in descriptor.query().withAll(_Position).build().run()) {
        seen.add(e.get<_Position>().x[e]);
      }
      expect(seen.toSet(), List.generate(10, (i) => i.toDouble()).toSet());
    });

    test('an empty scene / no matching archetype yields nothing', () {
      _level();
      final descriptor = ArchetypeQueryDescriptor();
      expect(descriptor.query().withAll(_Position).build().run(), isEmpty);
    });
  });

  group('runQuery / get / tryGet cursor', () {
    test('get<T>() and tryGet<T>() read through the current entity', () {
      final level = _level();
      level.pool.beginTick();
      final p = level.addEntity(level.player);
      level.player.x[p] = 5;
      level.pool.commitTick();

      final descriptor = ArchetypeQueryDescriptor();
      final query = descriptor.query().withAll(_Position).withOptional(Child).build();
      var ran = false;
      query.runQuery(() {
        ran = true;
        expect(query.get<_Position>().x[p], 5);
        expect(query.tryGet<Child>(), isNotNull, reason: '_Player mixes in Child');
        expect(query.tryGet<_Health>(), isNotNull, reason: '_Player mixes in _Health too');
      });
      expect(ran, isTrue);
    });

    test('tryGet<T>() is null for a component the matched entity lacks', () {
      final level = _level();
      level.addEntity(level.rock); // no Child, no _Health

      final descriptor = ArchetypeQueryDescriptor();
      final query = descriptor.query().withAll(_Position).build();
      var ran = false;
      query.runQuery(() {
        ran = true;
        expect(query.tryGet<Child>(), isNull);
        expect(query.tryGet<_Health>(), isNull);
        expect(() => query.get<Child>(), throwsStateError);
      });
      expect(ran, isTrue);
    });

    test('get<T>() outside runQuery throws instead of returning stale data', () {
      final descriptor = ArchetypeQueryDescriptor();
      final query = descriptor.query().withAll(_Position).build();
      expect(() => query.get<_Position>(), throwsStateError);
      expect(query.tryGet<_Position>(), isNull);
    });

    test('SingleQuery<T>.component is get<T>() sugar through the cursor', () {
      final level = _level();
      level.pool.beginTick();
      final p = level.addEntity(level.player);
      level.player.x[p] = 42;
      level.pool.commitTick();

      final descriptor = ArchetypeQueryDescriptor();
      final single = descriptor.has<_Position>();
      var ran = false;
      single.runQuery(() {
        ran = true;
        expect(single.component.x[p], 42);
      });
      expect(ran, isTrue);
    });
  });
}
