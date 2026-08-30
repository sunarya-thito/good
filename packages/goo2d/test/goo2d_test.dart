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
    super.describeScene(descriptor);
    playerPrefab = descriptor.has(Player.new);
    enemyPrefab = descriptor.has(Enemy.new);
    rockPrefab = descriptor.has(Rock.new);
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
    test("lays out five float64 fields plus Child's three links", () {
      final scene = _scene();
      // 5 x 64 bits of transform, then Child's three optEntity fields
      // (childParent, childNextSibling, childPrevSibling - each wide enough
      // to hold a full packed Entity handle, not just a 32-bit id): 64 bits of
      // value each, and the three has-bits sharing one byte rather than taking
      // a byte apiece. The first has-bit opens that byte and the alignment
      // rounding before its value strands the other seven; `declareFlagBit`
      // hands the next two flags those bits instead of extending the row.
      expect(scene.playerPrefab.archetype.bitLength, 5 * 64 + (1 + 7) + 3 * 64);
      expect(scene.playerPrefab.archetype.strideBytes, 65);
      expect(scene.rockPrefab.archetype.strideBytes, 40);
    });

    test('identical layouts still get distinct archetypes and storage', () {
      final scene = _scene();
      expect(
        scene.playerPrefab.archetype.strideBytes,
        scene.enemyPrefab.archetype.strideBytes,
      );
      expect(
        scene.playerPrefab.archetypeId,
        isNot(scene.enemyPrefab.archetypeId),
      );
      expect(
        scene.playerPrefab.archetype.componentSignature,
        isNot(scene.enemyPrefab.archetype.componentSignature),
        reason: 'each struct type contributes its own bit',
      );
    });

    test(
      'the example scene spawns and each entity keeps its own transform',
      () {
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
      },
    );

    test('a fixed-tick inner loop steps once per tick over a query shape', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.playerPrefab);
      final enemy = scene.addEntity(scene.enemyPrefab);
      final rock = scene.addEntity(scene.rockPrefab);
      final entities = <Entity>[player, enemy, rock];
      // The column directly, not `addEntity(parent:)` - neither prefab here
      // mixes in `Parent`, and what this walk needs is a `childParent` that
      // holds something, not a spliced sibling chain.
      scene.enemyPrefab.childParent[enemy] = player;
      scene.pool.commitTick();

      // The shape a `FixedTickable` system's inner loop has over a
      // `withAll(Transform2D).withOptional(Child)` query: resolve the
      // component off the row, read-modify-write its columns in place, and
      // branch on whether the optional one is there. Reads serve the last
      // published snapshot, so `+= 1` is exactly one step per tick however
      // many times the row is touched.
      var parentedSeen = 0;
      for (var tick = 0; tick < 3; tick++) {
        scene.pool.beginTick();
        for (final instance in entities) {
          final transform = instance.get<Transform2D>();
          transform.transformOffsetX[instance] += 1;
          transform.transformOffsetY[instance] += 1;
          final optChild = instance.tryGet<Child>();
          if (optChild != null && optChild.childParent[instance] != null) {
            parentedSeen++;
          }
        }
        scene.pool.commitTick();
      }

      for (final instance in entities) {
        final transform = instance.get<Transform2D>();
        expect(transform.transformOffsetX[instance], 3.0);
        expect(transform.transformOffsetY[instance], 3.0);
      }

      // The optional branch ran against a link that was really there - one
      // parented entity across three ticks - and the link survived the walk.
      // An assertion that only ever sees unparented entities cannot tell a
      // loop reading `childParent` from one clearing it: the placeholder
      // system body deleted from `data/transform.dart` in #185 cleared the
      // column on every match and passed this test, because nothing here
      // had a parent to lose.
      expect(parentedSeen, 3);
      expect(enemy.tryGet<Child>()!.childParent[enemy], player);
      expect(player.tryGet<Child>()!.childParent[player], isNull);
      // Rock has no Child mixin, so the optional branch was skipped for it.
      expect(rock.tryGet<Child>(), isNull);
    });

    test('Child.childParent starts absent and round-trips through null', () {
      final scene = _scene();
      scene.pool.beginTick();
      final player = scene.addEntity(scene.playerPrefab);
      final other = scene.addEntity(scene.playerPrefab);
      scene.pool.commitTick();

      expect(scene.playerPrefab.childParent[player], isNull);

      scene.pool.beginTick();
      scene.playerPrefab.childParent[player] = other;
      scene.pool.commitTick();
      expect(scene.playerPrefab.childParent[player], other);
      // The nullable flag must not have disturbed the transform bytes.
      expect(scene.playerPrefab.transformOffsetX[player], 0.0);

      scene.pool.beginTick();
      scene.playerPrefab.childParent[player] = null;
      scene.pool.commitTick();
      expect(scene.playerPrefab.childParent[player], isNull);
    });
  });
}
