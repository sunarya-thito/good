// Landing 5: raycast and overlap queries.
//
// Requires the native library. packages/goo2d_ffi_box2d/README.md has the
// build for each platform.

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d_physics_box2d/goo2d_physics_box2d.dart';

late Game run;
late Box2DPhysicsSystem physics;

/// A static wall, so nothing moves while a query runs.
class _Wall extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  late final BoxBody box;

  @override
  void describeCollider(ColliderDescriptor d) {
    super.describeCollider(d);
    box = d.hasBoxCollider(halfWidth: 1, halfHeight: 1);
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    bodyType.defaultValue = BodyType2D.staticBody;
  }
}

/// On layer 3, for the mask tests.
class _Hidden extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  late final BoxBody box;

  @override
  void describeCollider(ColliderDescriptor d) {
    super.describeCollider(d);
    box = d.hasBoxCollider(halfWidth: 1, halfHeight: 1, layer: 3);
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    bodyType.defaultValue = BodyType2D.staticBody;
  }
}

class _Scene extends SceneStruct {
  late Scene handle;
  late final _Wall wall;
  late final _Hidden hidden;

  @override
  void onSceneMounted(Scene scene) => handle = scene;

  Entity addEntity<T extends EntityStruct>(T p) => handle.addEntity(p);

  @override
  void describeScene(SceneDescriptor d) {
    super.describeScene(d);
    wall = d.has(_Wall.new);
    hidden = d.has(_Hidden.new);
  }
}

class _GameState extends GameState<_Game> {
  @override
  void onMounted() => loadScene(_Scene());

  @override
  void describeSystems(SystemDescriptor d) {
    super.describeSystems(d);
    physics = d.has(Box2DPhysicsSystem.new);
  }
}

class _Game extends Game {
  @override
  int get pageSize => 4096;

  @override
  GameState createState() => _GameState();
}

/// Advances far enough to actually run fixed steps.
///
/// `advance` accumulates real time and runs whole fixed steps only, so
/// advancing by less than one `fixedTimeStep` (16667us by default) runs
/// *zero* of them - the body then never leaves the position it was created
/// at, and a ray fired from the origin starts inside it. That is exactly how
/// this was first written, and the resulting miss looked like a broken
/// raycast rather than a test that never stepped.
void _settle() {
  for (var i = 0; i < 5; i++) {
    run.state.advance(const Duration(milliseconds: 20));
  }
}

Future<_Scene> _boot() async {
  run = await Game.startInline(_Game.new);
  addTearDown(() async {
    if (run.isRunning) await run.stop();
    physics.dispose();
  });
  return run.state.singleScene<_Scene>();
}

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test('a ray hits a wall in its path', () async {
    final scene = await _boot();
    final wall = scene.addEntity(scene.wall);
    scene.wall.transformOffsetX[wall] = 10;
    _settle();

    // From the origin, 20 units to the right. The wall spans x 9..11.
    expect(physics.raycast(scene.handle, 0, 0, 20, 0), isTrue);
    expect(physics.hitEntity, wall);
    expect(physics.hitCollider, isA<BoxBody>());
    expect(physics.hitX, closeTo(9, 0.01), reason: 'the near face is at x=9');
    expect(physics.hitNormalX, closeTo(-1, 0.01), reason: 'facing the ray');
    expect(physics.hitFraction, closeTo(9 / 20, 0.01));
  });

  test('a ray that reaches nothing misses', () async {
    final scene = await _boot();
    final wall = scene.addEntity(scene.wall);
    scene.wall.transformOffsetX[wall] = 10;
    _settle();

    expect(
      physics.raycast(scene.handle, 0, 0, 5, 0),
      isFalse,
      reason:
          'the ray stops at x=5, short of the wall at x=9 - the '
          'translation IS the length',
    );
    expect(
      physics.raycast(scene.handle, 0, 50, 20, 0),
      isFalse,
      reason: 'well above it',
    );
  });

  test('a ray reports the closest of several hits', () async {
    final scene = await _boot();
    final near = scene.addEntity(scene.wall);
    scene.wall.transformOffsetX[near] = 5;
    final far = scene.addEntity(scene.wall);
    scene.wall.transformOffsetX[far] = 15;
    _settle();

    expect(physics.raycast(scene.handle, 0, 0, 30, 0), isTrue);
    expect(physics.hitEntity, near, reason: 'closest, not first found');
  });

  test('a layer mask excludes a collider', () async {
    final scene = await _boot();
    final hidden = scene.addEntity(scene.hidden);
    scene.hidden.transformOffsetX[hidden] = 10;
    _settle();

    // _Hidden is on layer 3, so its category bit is 1 << 3 = 8.
    expect(
      physics.raycast(scene.handle, 0, 0, 20, 0),
      isTrue,
      reason: 'default mask is all',
    );
    expect(
      physics.raycast(scene.handle, 0, 0, 20, 0, layerMask: 1),
      isFalse,
      reason: 'a mask of layer 0 only should not see a layer-3 collider',
    );
    expect(physics.raycast(scene.handle, 0, 0, 20, 0, layerMask: 8), isTrue);
  });

  test('overlap finds colliders in a box and nothing outside it', () async {
    final scene = await _boot();
    final inside = scene.addEntity(scene.wall);
    scene.wall.transformOffsetX[inside] = 0;
    final outside = scene.addEntity(scene.wall);
    scene.wall.transformOffsetX[outside] = 100;
    _settle();

    final count = physics.overlapBox(scene.handle, -5, -5, 5, 5);
    expect(count, 1);
    expect(physics.overlapEntityAt(0), inside);
    expect(physics.overlapColliderAt(0), isA<BoxBody>());

    expect(
      physics.overlapBox(scene.handle, -500, -500, 500, 500),
      2,
      reason: 'a box covering both should find both',
    );
    expect(
      physics.overlapBox(scene.handle, 40, 40, 50, 50),
      0,
      reason: 'empty space should find nothing',
    );
  });

  test('overlap honours a layer mask', () async {
    final scene = await _boot();
    final hidden = scene.addEntity(scene.hidden);
    scene.hidden.transformOffsetX[hidden] = 0;
    _settle();

    expect(physics.overlapBox(scene.handle, -5, -5, 5, 5), 1);
    expect(physics.overlapBox(scene.handle, -5, -5, 5, 5, layerMask: 1), 0);
  });

  test('a query before anything exists is a clean miss', () async {
    final scene = await _boot();
    expect(physics.raycast(scene.handle, 0, 0, 10, 0), isFalse);
    expect(physics.overlapBox(scene.handle, -1, -1, 1, 1), 0);
  });
}
