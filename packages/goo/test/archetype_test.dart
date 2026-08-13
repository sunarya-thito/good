import 'package:goo/src/asset.dart';
import 'package:goo/src/scene_handle.dart';
import 'package:goo/src/archetype.dart';
import 'package:goo/src/data.dart';
import 'package:goo/src/data/hierarchy.dart';
import 'package:goo/src/pool.dart';
import 'package:goo/src/scene.dart';
import 'package:goo/src/struct.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirrors goo2d's Transform2D exactly - five float64 fields declared after
// a `super.describeStruct(data)` call - so this suite covers the same mixin
// linearization the real consumer relies on, without goo depending on
// goo2d (the dependency runs the other way).
mixin _Transform on Component {
  late final ComponentType<_Transform> componentTransform;

  late final DataPointer<double> offsetX;
  late final DataPointer<double> offsetY;
  late final DataPointer<double> rotation;

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    componentTransform = component.has<_Transform>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    offsetX = data.hasFloat64();
    offsetY = data.hasFloat64();
    rotation = data.hasFloat64();
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

mixin _Flags on Component {
  late final DataPointer<int> team;
  late final DataPointer<int> visible;

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    team = data.hasUint2();
    visible = data.hasUint1(1);
  }
}

class _Player extends EntityStruct<_Player> with _Transform, _Health, _Flags {}

class _Enemy extends EntityStruct<_Enemy> with _Transform, _Flags {}

class _Rock extends EntityStruct<_Rock> {}

class _ChildOnly extends EntityStruct<_ChildOnly> with Child {}

class _Level extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct<T>>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _Level();

  late final _Player player;
  late final _Enemy enemy;

  @override
  void describeScene(SceneDescriptor descriptor) {
    player = descriptor.has(_Player());
    enemy = descriptor.has(_Enemy());
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

  group('Entity encoding', () {
    test('packs and unpacks archetype / page / row at the extremes', () {
      const zero = Entity.pack(0, 0, 0);
      expect([zero.archetypeId, zero.pageIndex, zero.rowOffset], [0, 0, 0]);

      const max = Entity.pack(0xFFFF, 0xFFFF, 0xFFFFFFFF);
      expect(max.archetypeId, 0xFFFF);
      expect(max.pageIndex, 0xFFFF);
      expect(max.rowOffset, 0xFFFFFFFF,
          reason: 'the top bit lands in the sign position; unpacking masks');

      const mixed = Entity.pack(0x8001, 0x0203, 0x04050607);
      expect(mixed.archetypeId, 0x8001);
      expect(mixed.pageIndex, 0x0203);
      expect(mixed.rowOffset, 0x04050607);

      // Fields must not bleed into each other.
      const onlyRow = Entity.pack(0, 0, 0xFFFFFFFF);
      expect(onlyRow.archetypeId, 0);
      expect(onlyRow.pageIndex, 0);
      const onlyPage = Entity.pack(0, 0xFFFF, 0);
      expect(onlyPage.archetypeId, 0);
      expect(onlyPage.rowOffset, 0);
    });
  });

  group('registries', () {
    test('a component type keeps one stable bit across archetypes', () {
      final level = _level();
      final transformBit = ComponentTypeRegistry.bitFor(_Transform);

      // Both structs mix in _Transform, so both signatures carry that bit...
      expect(level.player.archetype.componentSignature & transformBit, transformBit);
      expect(level.enemy.archetype.componentSignature & transformBit, transformBit);
      // ...but only the player carries _Health.
      final healthBit = ComponentTypeRegistry.bitFor(_Health);
      expect(level.player.archetype.componentSignature & healthBit, healthBit);
      expect(level.enemy.archetype.componentSignature & healthBit, 0);
      // The struct's own type is a component type too (EntityStruct
      // declares `component.has<T>()` for itself).
      expect(
        level.player.archetype.componentSignature &
            ComponentTypeRegistry.bitFor(_Player),
        isNot(0),
      );
    });

    test('the 64-type ceiling is a clear error, not silent wraparound', () {
      // Fill the registry with throwaway types, then ask for one more.
      final types = <Type>[
        int, double, num, String, bool, Object, Symbol, Type,
        List, Map, Set, Iterable, Duration, Uri, RegExp, StringBuffer,
        Pattern, Comparable, Function, Error, Exception, StackTrace,
        BigInt, DateTime, Stopwatch, Runes, Match, Sink, Invocation,
        Expando, Future, Stream, Never, Null, //
      ];
      for (final t in types) {
        ComponentTypeRegistry.bitFor(t);
      }
      while (ComponentTypeRegistry.assignedCount < 64) {
        // Each generic instantiation is a distinct Type.
        ComponentTypeRegistry.bitFor(
          _distinctTypes[ComponentTypeRegistry.assignedCount % _distinctTypes.length],
        );
        if (ComponentTypeRegistry.assignedCount == types.length) break;
      }
      // Top the registry up to exactly 64 with fresh generic types.
      for (final t in _distinctTypes) {
        if (ComponentTypeRegistry.assignedCount >= 64) break;
        ComponentTypeRegistry.bitFor(t);
      }
      expect(ComponentTypeRegistry.assignedCount, 64);
      expect(() => ComponentTypeRegistry.bitFor(_Player), throwsStateError);
    });

    test('distinct structs get distinct archetypes even with identical fields', () {
      // _Enemy and this second struct have byte-identical layouts. Phase 1
      // deliberately does not deduplicate them.
      final level = _level();
      expect(level.player.archetypeId, isNot(level.enemy.archetypeId));
      expect(ArchetypeRegistry.byId(level.enemy.archetypeId), same(level.enemy.archetype));
      expect(ArchetypeRegistry.byId(level.player.archetypeId).prefab, same(level.player));
    });

    test('a prefab cannot be registered twice', () {
      final shared = _Rock();
      final pool = MemoryPool(pageSize: 256);
      addTearDown(pool.dispose);
      final owner = _Level();
      final storage =
          ArchetypeRegistry.register(pool, owner, GameAssets(), shared);
      shared.bindArchetype(owner, storage);
      expect(
        () => shared.bindArchetype(owner, storage),
        throwsStateError,
      );
    });

    test('an unregistered prefab explains itself instead of crashing', () {
      expect(() => _Rock().archetype, throwsStateError);
      final level = _level();
      expect(() => level.initializeScene(level.pool), throwsStateError,
          reason: 'archetype registration is a one-time pass');
    });
  });

  group('Entity.get / tryGet', () {
    test('return the prefab for components the archetype has', () {
      final level = _level();
      level.pool.beginTick();
      final entity = level.addEntity(level.player);
      level.pool.commitTick();

      expect(entity.get<_Transform>(), same(level.player));
      expect(entity.get<_Health>(), same(level.player));
      expect(entity.get<_Player>(), same(level.player));
      expect(entity.tryGet<_Transform>(), same(level.player));
    });

    test('tryGet is null and get throws for components the archetype lacks', () {
      final level = _level();
      level.pool.beginTick();
      final enemy = level.addEntity(level.enemy);
      level.pool.commitTick();

      expect(enemy.tryGet<_Health>(), isNull);
      expect(enemy.tryGet<_Player>(), isNull);
      expect(() => enemy.get<_Health>(), throwsStateError);
      expect(enemy.get<_Transform>(), same(level.enemy));
    });
  });

  group('end to end', () {
    test('two entities of one archetype keep separate rows', () {
      final level = _level();
      final p = level.player;

      level.pool.beginTick();
      final a = level.addEntity(p);
      final b = level.addEntity(p);
      p.offsetX[a] = 1.0;
      p.offsetY[a] = 2.0;
      p.rotation[a] = 3.0;
      p.hitPoints[a] = 55;
      p.team[a] = 1;
      p.visible[a] = 0;

      p.offsetX[b] = -10.0;
      p.offsetY[b] = -20.0;
      p.rotation[b] = -30.0;
      p.hitPoints[b] = 999;
      p.team[b] = 3;
      p.visible[b] = 1;
      level.pool.commitTick();

      expect(a.rowOffset, isNot(b.rowOffset));
      expect(a.archetypeId, b.archetypeId);

      final ta = a.get<_Transform>();
      expect([ta.offsetX[a], ta.offsetY[a], ta.rotation[a]], [1.0, 2.0, 3.0]);
      expect(a.get<_Health>().hitPoints[a], 55);
      expect([p.team[a], p.visible[a]], [1, 0]);

      final tb = b.get<_Transform>();
      expect([tb.offsetX[b], tb.offsetY[b], tb.rotation[b]], [-10.0, -20.0, -30.0]);
      expect(b.get<_Health>().hitPoints[b], 999);
      expect([p.team[b], p.visible[b]], [3, 1]);
    });

    test('entities of different archetypes never share storage', () {
      final level = _level();
      level.pool.beginTick();
      final hero = level.addEntity(level.player);
      final foe = level.addEntity(level.enemy);
      level.player.offsetX[hero] = 100.0;
      level.enemy.offsetX[foe] = -100.0;
      level.pool.commitTick();

      // Same page index and row offset are entirely possible - each
      // archetype has its own page list, so only the archetype id
      // distinguishes them.
      expect(hero.archetypeId, isNot(foe.archetypeId));
      expect(hero.get<_Transform>().offsetX[hero], 100.0);
      expect(foe.get<_Transform>().offsetX[foe], -100.0);
    });

    test('the Transform2DSystem pattern accumulates one step per tick', () {
      final level = _level();
      final p = level.player;

      level.pool.beginTick();
      final a = level.addEntity(p);
      final b = level.addEntity(p);
      p.offsetX[a] = 0.0;
      p.offsetX[b] = 100.0;
      level.pool.commitTick();

      for (var tick = 0; tick < 10; tick++) {
        level.pool.beginTick();
        for (final e in [a, b]) {
          final t = e.get<_Transform>();
          t.offsetX[e] += 1.0;
          t.offsetY[e] += 2.0;
        }
        level.pool.commitTick();
      }

      expect(p.offsetX[a], 10.0);
      expect(p.offsetY[a], 20.0);
      expect(p.offsetX[b], 110.0);
      expect(p.offsetY[b], 20.0);
    });

    test('a fresh row reads its declared defaults immediately', () {
      // Regression: allocateRow used to stamp defaults only into the write
      // slot, so a read (which resolves the *published* slot) saw whatever
      // the previous tenant of that offset left behind until the next tick.
      final level = _level();
      level.pool.beginTick();
      level.addEntity(level.player);
      level.pool.commitTick();
      level.pool.beginTick();
      level.pool.commitTick();

      level.pool.beginTick();
      final fresh = level.addEntity(level.player);
      expect(fresh.get<_Health>().hitPoints[fresh], 100);
      expect(level.player.visible[fresh], 1);
      level.pool.commitTick();
      expect(fresh.get<_Health>().hitPoints[fresh], 100);
    });

    test('a row spawned outside a tick keeps its defaults', () {
      // Regression: beginTick copies the published slot over the write
      // slot, so defaults written outside a tick window were erased by the
      // next beginTick - silently, and permanently.
      final level = _level();
      level.pool.beginTick();
      level.addEntity(level.player);
      level.pool.commitTick();
      level.pool.beginTick();
      level.pool.commitTick();

      final outside = level.addEntity(level.player);
      expect(outside.get<_Health>().hitPoints[outside], 100);
      level.pool.beginTick();
      level.pool.commitTick();
      expect(outside.get<_Health>().hitPoints[outside], 100);
    });

    test('writes outside a tick window assert rather than vanish', () {
      final level = _level();
      level.pool.beginTick();
      final e = level.addEntity(level.player);
      level.pool.commitTick();

      expect(
        () => level.player.offsetX[e] = 5.0,
        throwsA(isA<AssertionError>()),
        reason: 'beginTick would copy the published slot over this write',
      );
    });

    test('a read within the spawn tick sees the last published snapshot', () {
      // Pins the documented semantic in data_layout.dart: reads resolve the
      // published snapshot, so a same-tick write is not visible until the
      // next commitTick. Systems must initialize by writing, never by
      // read-modify-write, on the tick an entity is created.
      final level = _level();
      // The page needs published history for this to be observable at all:
      // before the first commitTick there is no snapshot and reads fall
      // back to the write slot.
      level.pool.beginTick();
      level.addEntity(level.player);
      level.pool.commitTick();

      level.pool.beginTick();
      final e = level.addEntity(level.player);
      level.player.offsetX[e] = 42.0;
      expect(level.player.offsetX[e], 0.0, reason: 'the declared default');
      level.pool.commitTick();
      expect(level.player.offsetX[e], 42.0);
    });

    test('addEntity rejects a prefab from another scene', () {
      final a = _level();
      final b = _level();
      expect(() => a.addEntity(b.player), throwsStateError);
    });

    test('addEntity rejects a prefab that was never registered', () {
      // The prefab is validated before the parent: everything about the
      // primary argument is checked before anything about the optional one.
      // So an unregistered prefab is refused for *being* unregistered, even
      // when the call also names a parent that could not accept it - which is
      // the more useful of the two diagnostics, because it names the mistake
      // that has to be fixed first.
      //
      // The parent-side rejections (not a Child, parent has no Parent mixin)
      // need prefabs this file deliberately does not have - its fixtures mix
      // in neither Child nor Parent - and are covered in hierarchy_test.dart
      // against registered ones.
      final level = _level();
      level.pool.beginTick();
      final parent = level.addEntity(level.player); // no Parent mixin
      level.pool.commitTick();
      expect(
        () => level.addEntity(_ChildOnly(), parent: parent),
        throwsStateError,
      );
    });
  });
}

/// Generic instantiations, each a distinct `Type`, used to fill
/// `ComponentTypeRegistry` to its ceiling.
const List<Type> _distinctTypes = <Type>[
  List<int>, List<double>, List<String>, List<bool>, List<Object>,
  List<num>, List<Symbol>, List<Type>, List<Duration>, List<Uri>,
  Map<int, int>, Map<int, double>, Map<int, String>, Map<int, bool>,
  Map<String, int>, Map<String, double>, Map<String, String>,
  Set<int>, Set<double>, Set<String>, Set<bool>, Set<Object>,
  Iterable<int>, Iterable<double>, Iterable<String>, Iterable<bool>,
  Future<int>, Future<double>, Future<String>, Future<bool>,
  Stream<int>, Stream<double>, Stream<String>, Stream<bool>,
  List<List<int>>, List<Map<int, int>>, List<Set<int>>, Map<int, List<int>>,
];
