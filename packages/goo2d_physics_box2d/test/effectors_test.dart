// Unity's Effector 2D family, which Box2D does not have.
//
// Requires the native library. packages/goo2d_ffi_box2d/README.md has the
// build for each platform.
//
// **Positive y is UP.** A buoyancy surface is above the water it floats
// things in, so "submerged" means a SMALLER y than the surface.
//
// Every test here drives the effector from a system that sorts BEFORE
// Box2DPhysicsSystem, because that is the only correct way to use one: a
// force applied after the step lands a tick late, and one applied outside a
// tick window is discarded entirely.

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d_physics_box2d/goo2d_physics_box2d.dart';

late Game run;
late Box2DPhysicsSystem physics;

class _Box extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  late final BoxBody box;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    box = descriptor.hasBoxCollider(halfWidth: 0.5, halfHeight: 0.5);
  }
}

class _Scene extends SceneStruct {
  late Scene handle;
  late final _Box box;

  @override
  void onSceneMounted(Scene scene) => handle = scene;

  Entity add() => handle.addEntity(box);

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    box = descriptor.has(_Box.new);
  }
}

/// Runs whatever the test set, every fixed step, before physics.
class _EffectorSystem extends GameSystem with FixedTickable {
  void Function(Box2DPhysicsSystem physics)? each;

  /// Runs once on the next fixed step, then clears. Test setup that writes
  /// a component has to happen inside a tick window like any other mutation.
  void Function()? once;

  /// **Before the physics system.** An effector is a force, and a force
  /// applied after `b2World_Step` is a force the step it was meant for never
  /// saw.
  @override
  int compareTo(GameSystem other) => other is Box2DPhysicsSystem ? -1 : 0;

  @override
  void onFixedUpdate() {
    final setup = once;
    if (setup != null) {
      once = null;
      setup();
    }
    each?.call(state.getSystem<Box2DPhysicsSystem>());
  }
}

// ignore: library_private_types_in_public_api
late _EffectorSystem effectors;

class _GameState extends GameState<_Game> {
  @override
  void onMounted() => loadScene(_Scene());

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    effectors = descriptor.has(_EffectorSystem.new);
    // No gravity, so each test measures its effector and nothing else. The
    // buoyancy test puts gravity back by hand, because floating against
    // nothing is not a test of buoyancy.
    physics = descriptor.has(() => Box2DPhysicsSystem(gravityY: 0));
  }
}

class _Game extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(microseconds: 16667);

  @override
  GameState createState() => _GameState();
}

const Duration _step = Duration(microseconds: 16667);

Future<_Scene> _boot() async {
  run = await Game.startInline(_Game());
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return run.state.singleScene<_Scene>();
}

void _advance(int steps) {
  for (var i = 0; i < steps; i++) {
    run.state.advance(_step);
  }
}

void main() {
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test(
    'an area effector pushes bodies inside it and nothing outside',
    () async {
      final scene = await _boot();
      final inside = scene.add();
      final outside = scene.add();
      effectors.once = () => scene.box.transformOffsetX[outside] = 100;
      _advance(2);

      effectors.each = (physics) =>
          physics.areaEffector(scene.handle, -10, -10, 10, 10, forceX: 50);
      _advance(60);

      expect(
        scene.box.transformOffsetX[inside],
        greaterThan(1),
        reason: 'a body in the region should be pushed along +x',
      );
      expect(
        scene.box.transformOffsetX[outside],
        closeTo(100, 0.5),
        reason:
            'and one outside it must not be touched - an effector that '
            'moved everything would pass a test that only looked inside',
      );
    },
  );

  test(
    'a point effector repels on positive force and attracts on negative',
    () async {
      final scene = await _boot();
      final body = scene.add();
      effectors.once = () => scene.box.transformOffsetX[body] = 3;
      _advance(2);

      effectors.each = (physics) =>
          physics.pointEffector(scene.handle, 0, 0, radius: 10, force: 400);
      _advance(45);
      final pushed = scene.box.transformOffsetX[body];
      expect(pushed, greaterThan(3.5), reason: 'positive force pushes away');

      // Same effector, negative force: it must pull back, not merely stop. The
      // radius has to cover where the repel actually left it - at 20 the body
      // had already been pushed to x=22 and simply sat outside the region,
      // which reads as "attraction does nothing" rather than "bad test".
      scene.box.setVelocity(body, 0, 0);
      effectors.each = (physics) =>
          physics.pointEffector(scene.handle, 0, 0, radius: 60, force: -400);
      _advance(45);
      expect(
        scene.box.transformOffsetX[body],
        lessThan(pushed),
        reason: 'negative force attracts, matching Unity',
      );
    },
  );

  test('a point effector does not reach past its radius', () async {
    // The region searched is a square AABB but the effect is a circle. Without
    // rejecting the corners an explosion reaches 41% further on the diagonal
    // than the radius it was given, which is invisible until a designer
    // wonders why a blast kills through a wall.
    final scene = await _boot();
    final corner = scene.add();
    // 8.49 from the centre, outside a radius of 7 but inside its square.
    effectors.once = () => scene.box
      ..transformOffsetX[corner] = 6
      ..transformOffsetY[corner] = 6;
    _advance(2);

    effectors.each = (physics) =>
        physics.pointEffector(scene.handle, 0, 0, radius: 7, force: 4000);
    _advance(60);

    expect(
      scene.box.transformOffsetX[corner],
      closeTo(6, 0.5),
      reason:
          'a body 8.49 from the centre is outside a radius of 7, even '
          'though it sits inside the square the broad phase searched',
    );
  });

  test('a buoyancy effector floats a body up to the surface', () async {
    final scene = await _boot();
    final body = scene.add();
    // Submerged: +y is UP, so 5 below a surface at 0.
    effectors.once = () => scene.box.transformOffsetY[body] = -5;
    _advance(2);

    effectors.each = (physics) {
      // Gravity by hand, since the world has none - floating against nothing
      // would prove nothing.
      scene.box.applyForce(body, 0, -10);
      physics.buoyancyEffector(scene.handle, -50, 50, surfaceY: 0, density: 3);
    };
    _advance(240);

    final y = scene.box.transformOffsetY[body];
    expect(
      y,
      greaterThan(-4),
      reason: 'it should have risen towards the surface',
    );
    expect(
      y,
      lessThan(2),
      reason:
          'and settled near it rather than being fired out of the water - '
          'the depth cap is what makes it settle instead of launching',
    );
  });

  test('a surface effector carries a body along at its speed', () async {
    final scene = await _boot();
    final body = scene.add();
    _advance(2);

    effectors.each = (physics) =>
        physics.surfaceEffector(scene.handle, -20, -5, 20, 5, speed: 4);
    _advance(60);

    expect(
      scene.box.linearVelocityX[body],
      closeTo(4, 0.5),
      reason: 'a conveyor should bring a body to belt speed and hold it there',
    );
  });
}
