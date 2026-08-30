import 'package:good/src/scene_handle.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/data.dart';
import 'package:good/src/data/hierarchy.dart';
import 'package:good/src/pool.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/system.dart';
import 'package:flutter_test/flutter_test.dart';

// Small fixture set covering: a component two archetypes share (_Position),
// one only some have (_Health), and the hierarchy's Child mixin (already
// implemented) so OptWith<Child>() has something real to combine with -
// the `withAll(...).withOptional(Child)` shape a system walking a hierarchy
// declares.
mixin _Position on Component {
  final x = Field.float64();
  final y = Field.float64();

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Position>();
  }
}

mixin _Health on Component {
  final hitPoints = Field.uint16(100);

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Health>();
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
    super.describeScene(descriptor);
    player = descriptor.has(_Player.new);
    rock = descriptor.has(_Rock.new);
    trigger = descriptor.has(_Trigger.new);
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
      expect(
        q.matches(level.player.archetype.componentSignature),
        isTrue,
        reason: 'player has both',
      );
      expect(
        q.matches(level.rock.archetype.componentSignature),
        isFalse,
        reason: 'rock has _Position but not _Health',
      );
      expect(
        q.matches(level.trigger.archetype.componentSignature),
        isFalse,
        reason: 'trigger has _Health but not _Position',
      );
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
      expect(
        q.matches(level.rock.archetype.componentSignature),
        isTrue,
        reason: '_Rock has no Child at all, withOptional still matches it',
      );
    });

    test('withAll and withNone combine as AND', () {
      final level = _level();
      final q = build((b) => b.withAll(_Position).withNone(_Health));
      expect(
        q.matches(level.player.archetype.componentSignature),
        isFalse,
        reason: 'player has _Health',
      );
      expect(q.matches(level.rock.archetype.componentSignature), isTrue);
      expect(
        q.matches(level.trigger.archetype.componentSignature),
        isFalse,
        reason: 'trigger lacks _Position and also has _Health',
      );
    });

    test(
      'the reference WorldTransformSystem shape: withAll + withOptional',
      () {
        final level = _level();
        final q = build((b) => b.withAll(_Position).withOptional(Child));
        // Matches every _Position archetype regardless of Child - withOptional
        // must not silently behave like a second withAll.
        expect(q.matches(level.player.archetype.componentSignature), isTrue);
        expect(q.matches(level.rock.archetype.componentSignature), isTrue);
        expect(q.matches(level.trigger.archetype.componentSignature), isFalse);
      },
    );

    test('withAny matches if at least one of the group is present', () {
      final level = _level();
      final q = build((b) => b.withAny(_Health, Child));
      expect(
        q.matches(level.player.archetype.componentSignature),
        isTrue,
        reason: 'player has both',
      );
      expect(
        q.matches(level.rock.archetype.componentSignature),
        isFalse,
        reason: 'rock has neither',
      );
      expect(
        q.matches(level.trigger.archetype.componentSignature),
        isTrue,
        reason: 'trigger has _Health',
      );
    });

    test(
      'two withAny calls are two groups, both of which must be satisfied',
      () {
        final level = _level();
        // (_Position or Child) and (_Health or Child). Only _Player
        // (_Position, _Health, Child) satisfies both groups. _Rock has just
        // _Position - first group yes, second no. _Trigger has just _Health -
        // second group yes, first no. If the two calls merged into one big
        // OR instead of ANDing, all three would match.
        final q = build(
          (b) => b.withAny(_Position, Child).withAny(_Health, Child),
        );
        expect(q.matches(level.player.archetype.componentSignature), isTrue);
        expect(
          q.matches(level.rock.archetype.componentSignature),
          isFalse,
          reason:
              'rock satisfies the first group but not the second - two '
              'withAny calls must AND, not merge into one big OR',
        );
        expect(
          q.matches(level.trigger.archetype.componentSignature),
          isFalse,
          reason: 'trigger satisfies the second group but not the first',
        );
      },
    );

    test('withAny composes with withNone', () {
      final level = _level();
      final q = build((b) => b.withAny(_Position, _Health).withNone(Child));
      expect(
        q.matches(level.player.archetype.componentSignature),
        isFalse,
        reason: 'player matches the any-group but has Child',
      );
      expect(q.matches(level.rock.archetype.componentSignature), isTrue);
      expect(
        q.matches(level.trigger.archetype.componentSignature),
        isTrue,
        reason: 'trigger has _Health (so the any-group passes) and no Child',
      );
    });
  });

  group('Query.run()', () {
    test(
      'yields exactly the entities of matching archetypes, across pages',
      () {
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
      },
    );

    test('each entity reads back its own data, not a neighbour\'s', () {
      final level = _level(pageSize: 64);
      level.pool.beginTick();
      final entities = [
        for (var i = 0; i < 10; i++) level.addEntity(level.player),
      ];
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

  group('QueryDescriptor.has<T>()', () {
    test('matches exactly what query().withAll(T).build() matches', () {
      final level = _level();
      level.pool.beginTick();
      final p = level.addEntity(level.player);
      final r = level.addEntity(level.rock);
      level.addEntity(level.trigger); // _Health only, no _Position
      level.player.x[p] = 42;
      level.rock.x[r] = 7;
      level.pool.commitTick();

      final descriptor = ArchetypeQueryDescriptor();
      final single = descriptor.has<_Position>();
      final built = descriptor.query().withAll(_Position).build();

      expect(single.run().toSet(), built.run().toSet());
      expect(single.run().toSet(), {p, r});
      expect(
        {for (final e in single.run()) e.get<_Position>().x[e]},
        {42.0, 7.0},
      );
    });
  });

  group('Query statics', () {
    test('Query.all matches what query().withAll(...).build() matches', () {
      final level = _level();
      final declared = Query.all(_Position, _Health);
      final built = ArchetypeQueryDescriptor()
          .query()
          .withAll(_Position, _Health)
          .build();

      for (final signature in <int>[
        level.player.archetype.componentSignature,
        level.rock.archetype.componentSignature,
        level.trigger.archetype.componentSignature,
      ]) {
        expect(declared.matches(signature), built.matches(signature));
      }
      expect(
        declared.matches(level.player.archetype.componentSignature),
        isTrue,
      );
      expect(
        declared.matches(level.rock.archetype.componentSignature),
        isFalse,
      );
    });

    test('Query.has<T> is the same query as descriptor.has<T>', () {
      final level = _level();
      level.pool.beginTick();
      final p = level.addEntity(level.player);
      final r = level.addEntity(level.rock);
      level.addEntity(level.trigger);
      level.pool.commitTick();

      final SingleQuery<_Position> declared = Query.has<_Position>();
      expect(
        declared.run().toSet(),
        ArchetypeQueryDescriptor().has<_Position>().run().toSet(),
      );
      expect(declared.run().toSet(), {p, r});
    });

    test('Query.where opens the builder the descriptor hands out', () {
      final level = _level();
      final roots = Query.where().withAll(_Position).withNone(Child).build();

      expect(
        roots.matches(level.rock.archetype.componentSignature),
        isTrue,
        reason: 'rock has _Position and no Child',
      );
      expect(
        roots.matches(level.player.archetype.componentSignature),
        isFalse,
        reason: 'player mixes in Child',
      );
    });

    // What the field form rests on: a system's initialiser runs before the
    // scene it will walk has registered anything, and `groups()` rebuilds
    // whenever `ArchetypeRegistry.count` moves.
    test('a query built before any archetype exists still finds them', () {
      expect(ArchetypeRegistry.count, 0);
      final motes = Query.all(_Position);
      expect(motes.groups(), isEmpty);

      final level = _level();
      level.pool.beginTick();
      final p = level.addEntity(level.player);
      final r = level.addEntity(level.rock);
      level.pool.commitTick();

      expect(motes.run().toSet(), {p, r});
    });
  });

  group('Query.groups()', () {
    test('yields exactly what run() does, across archetypes and pages', () {
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

      final grouped = <Entity>{};
      for (final group in query.groups()) {
        grouped.addAll(group);
      }

      // The two walks must agree exactly. `groups()` is a hand-written
      // iterator over pages and rows where `run()` is two nested `sync*`
      // generators, and a hand-written walk is exactly the kind of thing that
      // silently drops the last row of a page or skips a tombstoned one.
      expect(grouped, query.run().toSet());
      expect(grouped, {...players, ...rocks});
      expect(grouped.length, 40);
    });

    test('a group resolves its component once, and it is the same object', () {
      final level = _level(pageSize: 64);
      for (var i = 0; i < 5; i++) {
        level.addEntity(level.player);
      }

      final descriptor = ArchetypeQueryDescriptor();
      final query = descriptor.query().withAll(_Position).build();
      final group = query.groups().first;

      final component = group.get<_Position>();
      for (final entity in group) {
        // The whole point: this is not a per-entity lookup that happens to be
        // fast, it is the *same object* for every row. Resolving it per entity
        // was ~7% of the engine's CPU in a profile.
        expect(identical(entity.get<_Position>(), component), isTrue);
      }
    });

    test('groups are rebuilt when a new archetype appears', () {
      final level = _level(pageSize: 64);
      level.addEntity(level.player);

      final descriptor = ArchetypeQueryDescriptor();
      final query = descriptor.query().withAll(_Position).build();
      final before = query.groups().length;

      // The list is cached for the life of the query - a system holds one
      // forever - so it has to notice a scene load bringing new archetypes.
      final more = _level(pageSize: 64);
      more.addEntity(more.rock);

      expect(
        query.groups().length,
        greaterThan(before),
        reason:
            'a cached group list that never rebuilds would leave a '
            'newly loaded scene invisible to every existing system',
      );
    });

    test('an empty match yields no groups rather than an empty one', () {
      _level(pageSize: 64);
      final descriptor = ArchetypeQueryDescriptor();
      // No archetype in this fixture has Child without Position: _Player has
      // both, _Rock has neither, _Trigger has neither.
      final query = descriptor
          .query()
          .withAll(Child)
          .withNone(_Position)
          .build();
      expect(query.groups(), isEmpty);
    });
  });

  group('Scene scoping', () {
    test('Query.run(scene) yields only entities from that scene', () {
      final levelA = _level(pageSize: 64);
      final levelB = _level(pageSize: 64);

      final playersA = [
        for (var i = 0; i < 15; i++) levelA.addEntity(levelA.player),
      ];
      final rocksA = [
        for (var i = 0; i < 15; i++) levelA.addEntity(levelA.rock),
      ];

      final playersB = [
        for (var i = 0; i < 15; i++) levelB.addEntity(levelB.player),
      ];
      final rocksB = [
        for (var i = 0; i < 15; i++) levelB.addEntity(levelB.rock),
      ];

      final descriptor = ArchetypeQueryDescriptor();
      final query = descriptor.query().withAll(_Position).build();

      // Unscoped query sees entities from both scenes.
      expect(
        query.run().toSet(),
        {...playersA, ...rocksA, ...playersB, ...rocksB},
      );

      // Scoped query sees only entities from target scene.
      expect(query.run(levelA.handle).toSet(), {...playersA, ...rocksA});
      expect(query.run(levelB.handle).toSet(), {...playersB, ...rocksB});
    });

    test('Query.groups(scene) yields groups scoped to that scene', () {
      final levelA = _level(pageSize: 64);
      final levelB = _level(pageSize: 64);

      final playersA = [
        for (var i = 0; i < 20; i++) levelA.addEntity(levelA.player),
      ];
      final rocksA = [
        for (var i = 0; i < 20; i++) levelA.addEntity(levelA.rock),
      ];

      final playersB = [
        for (var i = 0; i < 20; i++) levelB.addEntity(levelB.player),
      ];
      final rocksB = [
        for (var i = 0; i < 20; i++) levelB.addEntity(levelB.rock),
      ];

      final descriptor = ArchetypeQueryDescriptor();
      final query = descriptor.query().withAll(_Position).build();

      final groupedA = <Entity>{};
      for (final group in query.groups(levelA.handle)) {
        groupedA.addAll(group);
      }
      expect(groupedA, {...playersA, ...rocksA});

      final groupedB = <Entity>{};
      for (final group in query.groups(levelB.handle)) {
        groupedB.addAll(group);
      }
      expect(groupedB, {...playersB, ...rocksB});
    });

    test('Query.run(scene) separates two loads sharing every archetype', () {
      // One SceneStruct, two loaded instances of it, so both scenes share
      // every archetype and the page-level `ownerSceneSlot` skip is the only
      // thing that can separate them.
      final level = _level(pageSize: 64);
      final handleA = level.handle;
      final handleB = SceneRegistry.register(level);

      for (var i = 0; i < 2; i++) {
        handleA.addEntity(level.player); // _Position + _Health + Child
      }
      for (var i = 0; i < 3; i++) {
        handleA.addEntity(level.rock); // _Position only
      }
      for (var i = 0; i < 5; i++) {
        handleB.addEntity(level.player);
      }
      handleB.addEntity(level.rock);

      final descriptor = ArchetypeQueryDescriptor();
      final query = descriptor.query().withAll(_Position).build();

      // A tally by archetype, not a row count: both scenes hold rows of both
      // archetypes, so a walk that skipped the wrong pages - or none at all -
      // can still land on the right total.
      var runsA = 0;
      var healthA = 0;
      for (final entity in query.run(handleA)) {
        runsA++;
        if (entity.tryGet<_Health>() != null) healthA++;
      }
      expect(runsA, 5, reason: 'scene A holds 2 players and 3 rocks');
      expect(healthA, 2, reason: 'only the players carry _Health');

      var runsB = 0;
      var healthB = 0;
      for (final entity in query.run(handleB)) {
        runsB++;
        if (entity.tryGet<_Health>() != null) healthB++;
      }
      expect(runsB, 6, reason: 'scene B holds 5 players and 1 rock');
      expect(healthB, 5);

      expect(query.run().length, 11, reason: 'unscoped walks both loads');
    });

    test('SingleQuery.inScene(scene) walks only that scene', () {
      final levelA = _level();
      final levelB = _level();

      levelA.pool.beginTick();
      final pA = levelA.addEntity(levelA.player);
      levelA.player.x[pA] = 99;
      levelA.pool.commitTick();

      levelB.pool.beginTick();
      final pB = levelB.addEntity(levelB.player);
      levelB.player.x[pB] = 100;
      levelB.pool.commitTick();

      final descriptor = ArchetypeQueryDescriptor();
      final single = descriptor.has<_Position>();
      final scopedA = single.inScene(levelA.handle);

      expect(scopedA.run().toSet(), {pA});
      expect(scopedA.run().single.get<_Position>().x[pA], 99);
      expect(single.run().toSet(), {pA, pB});
    });

    test('Query.inScene(scene) returns a view matching run(scene) / groups(scene)', () {
      final levelA = _level(pageSize: 64);
      final levelB = _level(pageSize: 64);

      final playersA = [
        for (var i = 0; i < 10; i++) levelA.addEntity(levelA.player),
      ];
      levelB.addEntity(levelB.player);

      final descriptor = ArchetypeQueryDescriptor();
      final query = descriptor.query().withAll(_Position).build();
      final scoped = query.inScene(levelA.handle);

      expect(scoped.run().toSet(), playersA.toSet());

      final grouped = <Entity>{};
      for (final group in scoped.groups()) {
        grouped.addAll(group);
      }
      expect(grouped, playersA.toSet());
    });

    test('QueryGroup.inScene(scene) scopes an individual group', () {
      final level = _level(pageSize: 64);
      final handleA = level.handle;
      final handleB = SceneRegistry.register(level);

      final pA = handleA.addEntity(level.player);
      final pB = handleB.addEntity(level.player);

      final descriptor = ArchetypeQueryDescriptor();
      final query = descriptor.query().withAll(_Position, _Health).build();
      final group = query.groups().first;

      expect(group.toSet(), {pA, pB});
      expect(group.inScene(handleA).toSet(), {pA});
      expect(group.inScene(handleB).toSet(), {pB});
    });

    test('a dead scope is refused at the call, on every entry point', () {
      final level = _level();
      level.addEntity(level.player);
      final handle = level.handle;

      final descriptor = ArchetypeQueryDescriptor();
      final query = descriptor.query().withAll(_Position).build();
      final liveGroup = query.groups().first;

      SceneRegistry.unregister(handle);

      // Every one of these is a *block* body, not `() => expr`. `throwsA`
      // pretty-prints whatever the closure returned, and pretty-printing an
      // `Iterable` walks it - so an arrow body hands the matcher a lazy
      // `run()` or a `QueryGroup`, the walk throws inside the matcher's own
      // try, and a check deferred to first `moveNext` is indistinguishable
      // from one made at the call. A block body returns null and cannot be
      // confused that way.
      //
      // The distinction is the point: a caller that asks a scoped `run()`
      // only for `isEmpty` has to be told the scene is gone, not "no rows".
      expect(() {
        query.run(handle);
      }, throwsStateError);
      expect(() {
        query.groups(handle);
      }, throwsStateError);
      expect(() {
        query.inScene(handle);
      }, throwsStateError);
      expect(() {
        liveGroup.inScene(handle);
      }, throwsStateError);
    });

    test('a scope that dies after the call is refused when the walk starts', () {
      final level = _level();
      level.addEntity(level.player);
      level.addEntity(level.rock);
      final handle = level.handle;

      final descriptor = ArchetypeQueryDescriptor();
      final query = descriptor.query().withAll(_Position).build();

      // All three are taken while the scene is loaded and walked after it is
      // gone. A page-level slot test cannot notice this on its own: the pages
      // are freed, so the walk finds nothing and reports an empty scene.
      final pending = query.run(handle);
      final group = query.groups(handle).first;
      final scoped = query.inScene(handle);

      level.player.archetype.releaseScene(handle.slot, level.pool);
      level.rock.archetype.releaseScene(handle.slot, level.pool);
      SceneRegistry.unregister(handle);

      expect(() => pending.toList(), throwsStateError);
      expect(() => group.toList(), throwsStateError);
      expect(() => scoped.run().toList(), throwsStateError);
      expect(() => scoped.groups(), throwsStateError);
    });

    test('a reloaded scene reusing a slot serves its own rows', () {
      final level = _level();
      final first = level.handle;
      final before = first.addEntity(level.player);

      final descriptor = ArchetypeQueryDescriptor();
      final query = descriptor.query().withAll(_Position).build();

      // Warm the per-slot group cache while the first load is live.
      expect(query.groups(first).expand((g) => g).toSet(), {before});
      expect(query.run(first).toSet(), {before});

      level.player.archetype.releaseScene(first.slot, level.pool);
      SceneRegistry.unregister(first);

      // The same SceneStruct loaded again. It takes the slot back - and it
      // declares no new archetypes, so the group list is not rebuilt for an
      // archetype-count change and the cache from the previous load is still
      // sitting there under this slot.
      final second = SceneRegistry.register(level);
      expect(second.slot, first.slot, reason: 'the slot really is reused');
      expect(second.generation, isNot(first.generation));
      final after = second.addEntity(level.player);

      expect(query.run(second).toSet(), {after});
      expect(query.groups(second).expand((g) => g).toSet(), {after});

      // ...and the handle from the load before is still refused. Block
      // bodies again - see the note in the dead-scope test above.
      expect(() {
        query.run(first);
      }, throwsStateError);
      expect(() {
        query.groups(first);
      }, throwsStateError);
      expect(() {
        query.inScene(first);
      }, throwsStateError);
    });
  });
}
