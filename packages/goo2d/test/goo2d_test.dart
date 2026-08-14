import 'package:goo2d/goo2d.dart';
import 'package:flutter_test/flutter_test.dart';

// The same shape the render example declares, minus the experimental
// primary-constructor syntax (which the analyzer is configured for but the
// test VM would need a flag to run). Player and Enemy have byte-identical
// layouts on purpose - they must still get separate archetypes and separate
// storage.
class Player extends EntityStruct with Transform2D, Child {}

class Enemy extends EntityStruct with Transform2D, Child {}

class Rock extends EntityStruct with Transform2D {}

class MainScene extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  MainScene();

  late final Player playerPrefab;
  late final Enemy enemyPrefab;
  late final Rock rockPrefab;

  @override
  void describeScene(SceneDescriptor descriptor) {
    playerPrefab = descriptor.has(Player());
    enemyPrefab = descriptor.has(Enemy());
    rockPrefab = descriptor.has(Rock());
  }
}

MainScene _scene() {
  final scene = MainScene()..initializeScene(MemoryPool(pageSize: 4096));
  scene.handle = SceneRegistry.register(scene);
  addTearDown(scene.pool.dispose);
  return scene;
}

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('Transform2D through the real kernel API', () {
    test(
      'lays out five float64 fields plus Child\'s parent/nextSibling/prevSibling',
      () {
        final scene = _scene();
        // 5 x 64 bits of transform, then Child's three optInt64 fields
        // (parent, nextSibling, prevSibling - each wide enough to hold a
        // full packed Entity handle, not just a 32-bit id): one has-bit
        // plus 7 bits of byte-alignment padding, then 64 bits of value.
        expect(scene.playerPrefab.archetype.bitLength, 5 * 64 + 3 * (1 + 7 + 64));
        expect(scene.playerPrefab.archetype.strideBytes, 67);
        expect(scene.rockPrefab.archetype.strideBytes, 40);
      },
    );

    test('identical layouts still get distinct archetypes and storage', () {
      final scene = _scene();
      expect(
        scene.playerPrefab.archetype.strideBytes,
        scene.enemyPrefab.archetype.strideBytes,
      );
      expect(scene.playerPrefab.archetypeId, isNot(scene.enemyPrefab.archetypeId));
      expect(
        scene.playerPrefab.archetype.componentSignature,
        isNot(scene.enemyPrefab.archetype.componentSignature),
        reason: 'each struct type contributes its own bit',
      );
    });

    test('the example scene spawns and each entity keeps its own transform', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.playerPrefab);
      final enemies = <Entity>[
        for (var i = 0; i < 5; i++) scene.addEntity(scene.enemyPrefab),
      ];

      scene.playerPrefab.transformOffsetX[player] = 320.0;
      scene.playerPrefab.transformOffsetY[player] = 240.0;
      scene.playerPrefab.transformRotation[player] = 1.5;
      for (var i = 0; i < enemies.length; i++) {
        final t = enemies[i].get<Transform2D>();
        t.transformOffsetX[enemies[i]] = i * 10.0;
        t.transformOffsetY[enemies[i]] = i * -10.0;
        t.transformScaleX[enemies[i]] = 1.0 + i;
      }
      scene.pool.commitTick();

      expect(player.get<Transform2D>(), same(scene.playerPrefab));
      expect(scene.playerPrefab.transformOffsetX[player], 320.0);
      expect(scene.playerPrefab.transformOffsetY[player], 240.0);
      expect(scene.playerPrefab.transformRotation[player], 1.5);

      for (var i = 0; i < enemies.length; i++) {
        final e = enemies[i];
        final t = e.get<Transform2D>();
        expect(t, same(scene.enemyPrefab));
        expect(t.transformOffsetX[e], i * 10.0, reason: 'enemy $i');
        expect(t.transformOffsetY[e], i * -10.0, reason: 'enemy $i');
        expect(t.transformScaleX[e], 1.0 + i, reason: 'enemy $i');
      }
    });

    test('the Transform2DSystem inner loop runs unchanged', () {
      final scene = _scene();
      scene.pool.beginTick();
      final entities = <Entity>[
        scene.addEntity(scene.playerPrefab),
        scene.addEntity(scene.enemyPrefab),
        scene.addEntity(scene.rockPrefab),
      ];
      scene.pool.commitTick();

      // Verbatim from Transform2DSystem.onFixedUpdate.
      for (var tick = 0; tick < 3; tick++) {
        scene.pool.beginTick();
        for (final instance in entities) {
          final transform = instance.get<Transform2D>();
          transform.transformOffsetX[instance] += 1;
          transform.transformOffsetY[instance] += 1;
          final optChildren = instance.tryGet<Child>();
          if (optChildren != null) {
            optChildren.parent[instance] = null;
          }
        }
        scene.pool.commitTick();
      }

      for (final instance in entities) {
        final transform = instance.get<Transform2D>();
        expect(transform.transformOffsetX[instance], 3.0);
        expect(transform.transformOffsetY[instance], 3.0);
      }
      // Rock has no Child mixin, so the optional branch was skipped for it.
      expect(entities[0].tryGet<Child>()!.parent[entities[0]], isNull);
      expect(entities[1].tryGet<Child>()!.parent[entities[1]], isNull);
      expect(entities[2].tryGet<Child>(), isNull);
    });

    test('Child.parent starts absent and round-trips through null', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.playerPrefab);
      final other = scene.addEntity(scene.playerPrefab);
      scene.pool.commitTick();

      expect(scene.playerPrefab.parent[player], isNull);

      scene.pool.beginTick();
      scene.playerPrefab.parent[player] = other;
      scene.pool.commitTick();
      expect(scene.playerPrefab.parent[player], other);
      // The nullable flag must not have disturbed the transform bytes.
      expect(scene.playerPrefab.transformOffsetX[player], 0.0);

      scene.pool.beginTick();
      scene.playerPrefab.parent[player] = null;
      scene.pool.commitTick();
      expect(scene.playerPrefab.parent[player], isNull);
    });
  });
}
