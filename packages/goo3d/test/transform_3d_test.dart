import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:goo3d/goo3d.dart';

class _Turret extends EntityStruct with Transform3D {}

// A deliberately different archetype - the extra field ahead of Transform3D's
// own fields shifts its row layout, so anything that read one archetype's
// entity through the other's DataPointer would address the wrong storage and
// these tests would say so.
class _Enemy extends EntityStruct with Transform3D {
  late final DataPointer<int> health;

  @override
  void describeStruct(DataDescriptor data) {
    health = data.hasInt32(100);
    super.describeStruct(data);
  }
}

class _Scene extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene`, so a
  /// headless fixture registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _Scene();

  late final _Turret turret;
  late final _Enemy enemy;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    turret = descriptor.has(_Turret());
    enemy = descriptor.has(_Enemy());
  }
}

_Scene _scene() {
  final scene = _Scene()..initializeScene(MemoryPool(pageSize: 4096));
  scene.handle = SceneRegistry.register(scene);
  addTearDown(scene.pool.dispose);
  return scene;
}

/// Spawns one turret with [write] applied inside a tick, and commits.
Entity _turret(_Scene scene, [void Function(Entity entity)? write]) {
  scene.pool.beginTick();
  final entity = scene.addEntity(scene.turret);
  write?.call(entity);
  scene.pool.commitTick();
  return entity;
}

const double _tolerance = 1e-12;

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('defaults', () {
    test('rotation defaults to the identity quaternion and scale to 1', () {
      final scene = _scene();
      final entity = _turret(scene);
      expect(scene.turret.transformRotationX[entity], 0);
      expect(scene.turret.transformRotationY[entity], 0);
      expect(scene.turret.transformRotationZ[entity], 0);
      expect(
        scene.turret.transformRotationW[entity],
        1,
        reason: 'w defaults to 1, not to the field default of 0 - an all-zero '
            'quaternion is not a rotation at all',
      );
      expect(scene.turret.transformScaleX[entity], 1);
      expect(scene.turret.transformScaleY[entity], 1);
      expect(scene.turret.transformScaleZ[entity], 1);
      expect(scene.turret.transformOffsetX[entity], 0);
      expect(scene.turret.transformOffsetY[entity], 0);
      expect(scene.turret.transformOffsetZ[entity], 0);
    });

    test('an unrotated entity faces -Z, with +X right and +Y up', () {
      final scene = _scene();
      final entity = _turret(scene);
      expect(entity<Transform3D>().forwardX, 0);
      expect(entity<Transform3D>().forwardY, 0);
      expect(entity<Transform3D>().forwardZ, -1);
      expect(entity<Transform3D>().rightX, 1);
      expect(entity<Transform3D>().rightY, 0);
      expect(entity<Transform3D>().rightZ, 0);
      expect(entity<Transform3D>().upX, 0);
      expect(entity<Transform3D>().upY, 1);
      expect(entity<Transform3D>().upZ, 0);
    });
  });

  group('setEuler', () {
    test('round-trips through the yaw/pitch/roll getters', () {
      final scene = _scene();
      final entity = _turret(
        scene,
        (e) => e<Transform3D>().setEuler(yaw: 0.5, pitch: -0.3, roll: 1.2),
      );
      expect(entity<Transform3D>().yaw, closeTo(0.5, 1e-12));
      expect(entity<Transform3D>().pitch, closeTo(-0.3, 1e-12));
      expect(entity<Transform3D>().roll, closeTo(1.2, 1e-12));
    });

    test('writes a unit quaternion', () {
      final scene = _scene();
      final t = scene.turret;
      final entity = _turret(
        scene,
        (e) => e<Transform3D>().setEuler(yaw: 2.1, pitch: 0.9, roll: -2.7),
      );
      final x = t.transformRotationX[entity];
      final y = t.transformRotationY[entity];
      final z = t.transformRotationZ[entity];
      final w = t.transformRotationW[entity];
      expect(math.sqrt(x * x + y * y + z * z + w * w), closeTo(1, _tolerance));
    });

    test('yaw turns about +Y: a quarter turn faces -X', () {
      final scene = _scene();
      final entity = _turret(scene, (e) => e<Transform3D>().setEuler(yaw: math.pi / 2));
      expect(entity<Transform3D>().forwardX, closeTo(-1, _tolerance));
      expect(entity<Transform3D>().forwardY, closeTo(0, _tolerance));
      expect(entity<Transform3D>().forwardZ, closeTo(0, _tolerance));
      // The whole basis turns with it, right-handed throughout.
      expect(entity<Transform3D>().rightZ, closeTo(-1, _tolerance));
      expect(entity<Transform3D>().upY, closeTo(1, _tolerance));
    });

    test('pitch turns about +X: a quarter turn looks straight up', () {
      final scene = _scene();
      final entity = _turret(scene, (e) => e<Transform3D>().setEuler(pitch: math.pi / 2));
      expect(entity<Transform3D>().forwardX, closeTo(0, _tolerance));
      expect(entity<Transform3D>().forwardY, closeTo(1, _tolerance));
      expect(entity<Transform3D>().forwardZ, closeTo(0, _tolerance));
    });

    test('roll turns about +Z, which leaves forward alone', () {
      final scene = _scene();
      final entity = _turret(scene, (e) => e<Transform3D>().setEuler(roll: math.pi / 2));
      expect(entity<Transform3D>().forwardZ, closeTo(-1, _tolerance));
      expect(entity<Transform3D>().upX, closeTo(-1, _tolerance),
          reason: 'a quarter roll puts the entity\'s up along -X');
      expect(entity<Transform3D>().rightY, closeTo(1, _tolerance));
    });

    test('yaw survives a pitch that would gimbal-lock three raw angles', () {
      final scene = _scene();
      // Straight down. Yaw and roll are no longer separable in Euler terms,
      // so the readback convention is "roll reports 0, yaw carries it" - but
      // the *orientation* is exact either way, which is what the basis
      // vectors below check.
      final entity = _turret(
        scene,
        (e) => e<Transform3D>().setEuler(yaw: math.pi / 2, pitch: -math.pi / 2),
      );
      expect(entity<Transform3D>().pitch, closeTo(-math.pi / 2, 1e-9));
      expect(entity<Transform3D>().roll, 0);
      expect(entity<Transform3D>().yaw, closeTo(math.pi / 2, 1e-9));
      expect(entity<Transform3D>().forwardY, closeTo(-1, 1e-12));
    });
  });

  group('lookAt', () {
    test('faces a target on +X', () {
      final scene = _scene();
      final entity = _turret(scene, (e) => e<Transform3D>().lookAt(10, 0, 0));
      expect(entity<Transform3D>().forwardX, closeTo(1, _tolerance));
      expect(entity<Transform3D>().forwardY, closeTo(0, _tolerance));
      expect(entity<Transform3D>().forwardZ, closeTo(0, _tolerance));
      expect(entity<Transform3D>().yaw, closeTo(-math.pi / 2, 1e-12));
    });

    test('is measured from the entity, not from the origin', () {
      final scene = _scene();
      final t = scene.turret;
      final entity = _turret(scene, (e) {
        t.transformOffsetX[e] = 100;
        t.transformOffsetZ[e] = 5;
        // Straight ahead of where it already is, along -Z.
        e<Transform3D>().lookAt(100, 0, -5);
      });
      expect(entity<Transform3D>().forwardX, closeTo(0, _tolerance));
      expect(entity<Transform3D>().forwardZ, closeTo(-1, _tolerance));
    });

    test('a half turn - the case the naive matrix-to-quaternion divides by '
        'zero on', () {
      final scene = _scene();
      final entity = _turret(scene, (e) => e<Transform3D>().lookAt(0, 0, 8));
      expect(entity<Transform3D>().forwardX, closeTo(0, _tolerance));
      expect(entity<Transform3D>().forwardY, closeTo(0, _tolerance));
      expect(entity<Transform3D>().forwardZ, closeTo(1, _tolerance));
      expect(entity<Transform3D>().upY, closeTo(1, _tolerance));
    });

    test('straight down keeps +X to the right', () {
      final scene = _scene();
      final t = scene.turret;
      final entity = _turret(scene, (e) {
        t.transformOffsetY[e] = 20;
        e<Transform3D>().lookAt(0, 0, 0);
      });
      expect(entity<Transform3D>().forwardY, closeTo(-1, _tolerance));
      expect(entity<Transform3D>().rightX, closeTo(1, _tolerance));
      expect(entity<Transform3D>().upZ, closeTo(-1, _tolerance));
      expect(entity<Transform3D>().pitch, closeTo(-math.pi / 2, 1e-8));
    });

    test('straight up keeps +X to the right', () {
      final scene = _scene();
      final entity = _turret(scene, (e) => e<Transform3D>().lookAt(0, 20, 0));
      expect(entity<Transform3D>().forwardY, closeTo(1, _tolerance));
      expect(entity<Transform3D>().rightX, closeTo(1, _tolerance));
      expect(entity<Transform3D>().upZ, closeTo(1, _tolerance));
    });

    test('a target at the entity\'s own position leaves the rotation alone',
        () {
      final scene = _scene();
      final entity = _turret(scene, (e) => e<Transform3D>().setEuler(yaw: 0.75));
      scene.pool.beginTick();
      entity<Transform3D>().lookAt(0, 0, 0);
      scene.pool.commitTick();
      expect(
        entity<Transform3D>().yaw,
        closeTo(0.75, _tolerance),
        reason: 'there is no direction to face, so nothing should be written',
      );
    });
  });

  group('the accessor the helpers hang off', () {
    test('is the entity itself, with nothing wrapped around it', () {
      final scene = _scene();
      scene.pool.beginTick();
      final entity = scene.addEntity(scene.turret);
      scene.pool.commitTick();

      // `Accessor<T>` erases to Entity erases to int, so the view is the
      // handle. That is what makes reaching a helper through it free, and it
      // is why an accessor can be passed anywhere an entity is wanted.
      expect(identical(entity<Transform3D>().entity, entity), isTrue);
      expect(scene.turret.transformScaleX[entity<Transform3D>()], 1);
    });

    test('resolves each entity\'s own archetype, not the one it was written '
        'next to', () {
      final scene = _scene();
      scene.pool.beginTick();
      final turret = scene.addEntity(scene.turret);
      final enemy = scene.addEntity(scene.enemy);
      scene.pool.commitTick();

      // _Enemy has an extra leading field, so its rotation columns sit at a
      // different offset. Both writes have to land in their own layout.
      scene.pool.beginTick();
      turret<Transform3D>().setEuler(yaw: 0.5);
      enemy<Transform3D>().setEuler(yaw: -0.5);
      scene.pool.commitTick();

      expect(scene.turret.transformRotationY[turret], math.sin(0.25));
      expect(scene.enemy.transformRotationY[enemy], -math.sin(0.25));
      expect(
        scene.enemy.health[enemy],
        100,
        reason: 'the write must not have gone through _Turret\'s offsets, '
            'which would land on _Enemy\'s leading field',
      );
    });

    test('distanceTo is correct across two different archetypes', () {
      final scene = _scene();
      scene.pool.beginTick();
      final turret = scene.addEntity(scene.turret);
      final enemy = scene.addEntity(scene.enemy);
      scene.enemy
        ..transformOffsetX[enemy] = 2
        ..transformOffsetY[enemy] = 3
        ..transformOffsetZ[enemy] = 6;
      scene.pool.commitTick();

      expect(turret<Transform3D>().distanceTo(enemy), 7);
      expect(
        enemy<Transform3D>().distanceTo(turret),
        7,
        reason: 'symmetric, and neither side is read through the other\'s row '
            'layout - _Enemy has an extra leading field',
      );
    });

    test('lookAtEntity faces the other entity across archetypes', () {
      final scene = _scene();
      scene.pool.beginTick();
      final turret = scene.addEntity(scene.turret);
      final enemy = scene.addEntity(scene.enemy);
      scene.enemy.transformOffsetX[enemy] = -4;
      scene.pool.commitTick();

      scene.pool.beginTick();
      turret<Transform3D>().lookAtEntity(enemy);
      scene.pool.commitTick();

      expect(turret<Transform3D>().forwardX, closeTo(-1, _tolerance));
    });
  });
}
