// Declared effectors - the `describeEffector` half of the API, where
// `effectors_test.dart` covers the `Effectors2D` functions underneath.
//
// Requires the native library. packages/goo2d_ffi_box2d/README.md has the
// build for each platform.
//
// **Positive y is UP**, so the zone's negative forceY blows its contents down.
//
// Every test asserts a body's **velocity**, never a field the test itself
// wrote. Asserting `wind.forceY[entity] == -400` would pass whether or not the
// walk in `Box2DPhysicsSystem` ever ran - the same trap as the arena test that
// asserted a component field instead of the Box2D shape, and could not fail.
// A velocity can only move if the force actually reached Box2D.
//
// Note what is *absent* from these tests: any system of the test's own, and
// any `compareTo`. That is the whole point of declaring an effector - the
// physics system walks it before its own step, so the ordering every caller of
// the functions has to reproduce by hand is simply not the game's problem.

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d_physics_box2d/goo2d_physics_box2d.dart';

late Game run;
late Box2DPhysicsSystem physics;

/// A wind zone: a region, and an effector acting through it. No rigid body of
/// its own - a force field is not a thing that falls.
class _Zone extends EntityStruct with Transform2D, Collider2D, Effector2D {
  late final BoxBody region;
  late final AreaEffector wind;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    region = descriptor.hasBoxCollider(
      halfWidth: 50,
      halfHeight: 50,
      isTrigger: true,
    );
  }

  @override
  void describeEffector(EffectorDescriptor descriptor) {
    super.describeEffector(descriptor);
    wind = descriptor.hasAreaEffector(region, forceY: -400);
  }
}

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
  late final _Zone zone;

  late Entity zoneEntity;

  @override
  void onSceneMounted(Scene scene) {
    handle = scene;
    zoneEntity = scene.addEntity(zone);
  }

  Entity add() => handle.addEntity(box);

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    box = descriptor.has(_Box.new);
    zone = descriptor.has(_Zone.new);
  }
}

/// Only ever used to get a write into a tick window - component mutation has
/// to happen inside one like any other. It declares no ordering against the
/// physics system on purpose: a declared effector does not need one.
class _Setup extends GameSystem with FixedTickable {
  void Function()? once;

  @override
  void onFixedUpdate() {
    final setup = once;
    if (setup != null) {
      once = null;
      setup();
    }
  }
}

// ignore: library_private_types_in_public_api
late _Setup setup;

class _GameState extends GameState<_Game> {
  @override
  void onMounted() => loadScene(_Scene());

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    setup = descriptor.has(_Setup.new);
    // No gravity, so the only thing that can move a body vertically is the
    // effector under test.
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
  run = await Game.startInline(_Game.new);
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

  test('a declared area effector pushes a body inside its region', () async {
    final scene = await _boot();
    late Entity box;
    setup.once = () => box = scene.add();
    // Three steps: one to run the setup and spawn, one for the body to be
    // created from it (this backend queues on the spawn tick and creates on
    // the next), then the rest to accumulate velocity.
    _advance(12);

    expect(
      scene.box.linearVelocityY[box],
      lessThan(-1),
      reason:
          'the wind blows toward -y and gravity is off, so nothing else '
          'in this scene could have moved the body at all',
    );
  });

  test('enable = false stops the force without removing anything', () async {
    final scene = await _boot();
    late Entity box;
    setup.once = () => box = scene.add();
    _advance(12);

    final moving = scene.box.linearVelocityY[box];
    expect(moving, lessThan(-1), reason: 'the wind is on to begin with');

    setup.once = () => scene.zone.wind.enable[scene.zoneEntity] = false;
    // Settle first, deliberately. The write publishes at the end of its tick
    // and the walk reads the published snapshot, so exactly one more step of
    // force lands after the flag is set - measured at 6.67, which is
    // 400 N over 16.667 ms on a unit-mass box, i.e. precisely one step. That
    // is the engine's standard pipeline, documented on `Effector.enable`, and
    // asserting it away here would be asserting the pipeline does not exist.
    _advance(3);
    final coasting = scene.box.linearVelocityY[box];

    _advance(30);

    // The real claim: once disabled, the velocity stops *changing*. Damping is
    // 0, so a body under no force holds what it has. Comparing two readings
    // after the disable is what separates "stopped pushing" from "never
    // pushed" - `lessThan(0)` would pass in both cases.
    expect(
      scene.box.linearVelocityY[box],
      closeTo(coasting, 0.001),
      reason:
          'a disabled effector applies no further force, so an undamped '
          'body coasts',
    );
    expect(
      coasting,
      lessThan(moving),
      reason: 'and it kept the velocity the wind had already given it',
    );
  });

  test('the region travels with its entity', () async {
    final scene = await _boot();
    late Entity box;
    setup.once = () {
      box = scene.add();
      // One write moves the whole force field. With the functions underneath
      // this would be four recomputed constants at the call site, which is
      // the ergonomic complaint that produced this API.
      scene.zone.transformOffsetX[scene.zoneEntity] = 10000;
    };
    _advance(12);

    expect(
      scene.box.linearVelocityY[box],
      closeTo(0, 0.001),
      reason: 'the zone moved far away, so its wind moved with it',
    );
  });
}
