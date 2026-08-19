import 'dart:math' as math;

import 'package:goo2d/goo2d.dart';
import 'package:flutter_test/flutter_test.dart';

class _Turret extends EntityStruct with Transform2D {}

// A deliberately different archetype (extra field ahead of Transform2D's
// own fields would shift its row layout) - the reference case for "each
// helper resolves its own argument's Transform2D, not the receiver's".
class _Enemy extends EntityStruct with Transform2D {
  final health = Field.int32(100);
}

class _Scene extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _Scene();

  late final _Turret turret;
  late final _Enemy enemy;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    turret = descriptor.has(_Turret.new);
    enemy = descriptor.has(_Enemy.new);
  }
}

_Scene _scene() {
  final scene = _Scene()..initializeScene(MemoryPool(pageSize: 4096));
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

  group('Transform2D helpers', () {
    test('distanceTo is correct across two different archetypes', () {
      final scene = _scene();
      scene.pool.beginTick();
      final turret = scene.addEntity(scene.turret);
      final enemy = scene.addEntity(scene.enemy);
      scene.turret.transformOffsetX[turret] = 0;
      scene.turret.transformOffsetY[turret] = 0;
      scene.enemy.transformOffsetX[enemy] = 3;
      scene.enemy.transformOffsetY[enemy] = 4;
      scene.pool.commitTick();

      // 3-4-5 triangle, and turret/enemy are genuinely different archetypes
      // (Enemy has an extra leading `health` field) - proof this reads each
      // entity's own storage, not the receiver's.
      expect(scene.turret.distanceTo(turret, enemy), 5.0);
      expect(
        scene.enemy.distanceTo(enemy, turret),
        5.0,
        reason: 'symmetric regardless of which side is the receiver',
      );
    });

    test('distanceTo is zero for the same entity against itself', () {
      final scene = _scene();
      scene.pool.beginTick();
      final turret = scene.addEntity(scene.turret);
      scene.turret.transformOffsetX[turret] = 42;
      scene.pool.commitTick();
      expect(scene.turret.distanceTo(turret, turret), 0.0);
    });

    test('lookAt sets rotation via atan2, matching the renderer\'s own rotation convention', () {
      final scene = _scene();
      scene.pool.beginTick();
      final turret = scene.addEntity(scene.turret);
      scene.turret.transformOffsetX[turret] = 0;
      scene.turret.transformOffsetY[turret] = 0;
      scene.pool.commitTick();

      scene.pool.beginTick();
      scene.turret.lookAt(turret, 0, 10); // straight up (+y)
      scene.pool.commitTick();
      expect(
        scene.turret.transformRotation[turret],
        closeTo(math.pi / 2, 1e-9),
      );

      scene.pool.beginTick();
      scene.turret.lookAt(turret, 10, 0); // straight along +x
      scene.pool.commitTick();
      expect(scene.turret.transformRotation[turret], closeTo(0, 1e-9));
    });

    test(
      'lookAtEntity faces another entity\'s position, across archetypes',
      () {
        final scene = _scene();
        scene.pool.beginTick();
        final turret = scene.addEntity(scene.turret);
        final enemy = scene.addEntity(scene.enemy);
        scene.turret.transformOffsetX[turret] = 0;
        scene.turret.transformOffsetY[turret] = 0;
        scene.enemy.transformOffsetX[enemy] = 0;
        scene.enemy.transformOffsetY[enemy] = 5;
        scene.pool.commitTick();

        scene.pool.beginTick();
        scene.turret.lookAtEntity(turret, enemy);
        scene.pool.commitTick();
        expect(
          scene.turret.transformRotation[turret],
          closeTo(math.pi / 2, 1e-9),
        );
      },
    );

    test(
      'forwardX/forwardY are the unit direction the current rotation points',
      () {
        final scene = _scene();
        scene.pool.beginTick();
        final turret = scene.addEntity(scene.turret);
        scene.turret.transformRotation[turret] = 0;
        scene.pool.commitTick();
        expect(scene.turret.forwardX(turret), closeTo(1, 1e-9));
        expect(scene.turret.forwardY(turret), closeTo(0, 1e-9));

        scene.pool.beginTick();
        scene.turret.transformRotation[turret] = math.pi / 2;
        scene.pool.commitTick();
        expect(scene.turret.forwardX(turret), closeTo(0, 1e-9));
        expect(scene.turret.forwardY(turret), closeTo(1, 1e-9));
      },
    );
  });
}
