// Declared effectors - the `Effector.*` half of the API, where
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
//
// The buoyancy tests at the end are the exception, and deliberately so. They
// run the declared effector and the one-shot `Effectors2D.buoyancyEffector`
// over the same geometry, because those two callers of the same correct
// function drifted apart once already - #197 - and only a test that drives
// both of them can catch that happening again. The one-shot half is what
// needs a system and a `compareTo`; the declared half still needs neither.

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d_physics_box2d/goo2d_physics_box2d.dart';

part 'effector_declared_test.g.dart';

late Game run;
late Box2DPhysicsSystem physics;

/// A wind zone: a region, and an effector acting through it. No rigid body of
/// its own - a force field is not a thing that falls.
class _Zone extends EntityStruct with Transform2D, Collider2D, Effector2D {
  final region = ColliderBody.box(
    halfWidth: 50,
    halfHeight: 50,
    isTrigger: true,
  );
  // `late final` because the initialiser names `region`, the field above:
  // an ordinary field initialiser cannot reach `this`.
  late final wind = Effector.area(region: region, forceY: -400);
}

/// A pool of water, 100 wide and 20 tall. Declared at the origin its fluid is
/// `y` in `[-10, +10]`, because **the water line is the region's top edge** -
/// see `BuoyancyEffector`.
///
/// `density: 3` against the boxes' own 1, so a submerged box is pushed up
/// harder than gravity pulls it down and the lift is unmistakable.
class _Pool extends EntityStruct with Transform2D, Collider2D, Effector2D {
  final region = ColliderBody.box(
    halfWidth: 50,
    halfHeight: 10,
    isTrigger: true,
  );
  late final water = Effector.buoyancy(region: region, density: 3);
}

class _Box extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  final box = ColliderBody.box(halfWidth: 0.5, halfHeight: 0.5);
}

/// The one way the field form can be written wrong: a region built inside the
/// effector call, so no field holds the body.
///
/// It reads perfectly well, and nothing about the types objects. What it
/// produces is a `ColliderBody` no collector reads - so no column is laid out
/// for it, `Collider2D.bodies` never sees it, and the physics walk would read
/// `halfWidth` off a column that was never given row space.
class _Loose extends EntityStruct with Transform2D, Collider2D, Effector2D {
  late final wind = Effector.area(
    region: ColliderBody.box(halfWidth: 5, halfHeight: 5, isTrigger: true),
    forceY: -400,
  );
}

class _LooseScene extends SceneStruct {
  @sub
  final zone = _Loose();
}

class _Scene extends SceneStruct {
  late Scene handle;
  @sub
  final box = _Box();
  @sub
  final zone = _Zone();
  @sub
  final waterZone = _Pool();

  late Entity zoneEntity;

  @override
  void onSceneMounted(Scene scene) {
    handle = scene;
    zoneEntity = scene.addEntity(zone);
  }

  Entity add() => handle.addEntity(box);

  /// The pool is added by the test that wants it, not on mount, so the wind
  /// tests are not sharing a scene with a body of water.
  Entity addPool() => handle.addEntity(waterZone);

  /// The wind zone is 100x100 at the origin and would swamp any buoyancy
  /// measurement taken there. Moving it is the same one write the "the region
  /// travels with its entity" test makes, which measures the wind's reach at
  /// exactly 0 afterwards - so this leaks no force into the readings below.
  void moveWindAway() => zone.transformOffsetX[zoneEntity] = 10000;
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

/// Drives the one-shot `Effectors2D.buoyancyEffector`, and only that. The
/// `compareTo` is the whole reason it exists: a force applied after
/// `b2World_Step` is a force the step it was meant for never saw, so every
/// caller of the functions has to declare this ordering by hand. A declared
/// effector is walked by the physics system itself and needs none of it.
class _OneShot extends GameSystem with FixedTickable {
  void Function(Box2DPhysicsSystem physics)? each;

  @override
  int compareTo(GameSystem other) => other is Box2DPhysicsSystem ? -1 : 0;

  @override
  void onFixedUpdate() => each?.call(state.getSystem<Box2DPhysicsSystem>());
}

// ignore: library_private_types_in_public_api
late _OneShot oneShot;

/// World gravity for the next [_boot]. Zero for the wind tests, so the only
/// thing that can move a body vertically is the effector under test; -10 for
/// the buoyancy ones, because floating against nothing is not floating.
double _gravityY = 0;

class _GameState extends GameState<_Game> {
  @override
  void onMounted() => loadScene(_Scene());

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    setup = descriptor.has(_Setup.new);
    oneShot = descriptor.has(_OneShot.new);
    physics = descriptor.has(() => Box2DPhysicsSystem(gravityY: _gravityY));
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

Future<_Scene> _boot({double gravityY = 0}) async {
  _gravityY = gravityY;
  addTearDown(() => _gravityY = 0);
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
  _installDeclarations();

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test('an effector reaching a body no field holds is refused', () {
    // Declared headless: an effector is declared when a scene declares the
    // prefab, which is inside `initializeScene`, so this is the failure a
    // game would hit at boot with no game to boot - and it is a boot failure
    // on purpose. Left to run, it is a column with no row space, read once
    // per step from inside the physics walk.
    Object? caught;
    try {
      _LooseScene().initializeScene(MemoryPool(pageSize: 4096));
    } catch (error) {
      caught = error;
    }
    expect(caught, isNotNull, reason: 'declaring the prefab has to fail');
    expect(
      caught.toString(),
      allOf(
        contains('_Loose'),
        contains('AreaEffector'),
        contains('not one of its own declared bodies'),
      ),
      reason:
          'the message has to name the prefab and the effector - the column '
          'that would fail later names neither, and a caller reading '
          '"halfWidth has no row space" has nothing to act on',
    );
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
      scene.box.bodyLinearVelocityY[box],
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

    final moving = scene.box.bodyLinearVelocityY[box];
    expect(moving, lessThan(-1), reason: 'the wind is on to begin with');

    setup.once = () => scene.zone.wind.enable[scene.zoneEntity] = false;
    // Settle first, deliberately. The write publishes at the end of its tick
    // and the walk reads the published snapshot, so exactly one more step of
    // force lands after the flag is set - measured at 6.67, which is
    // 400 N over 16.667 ms on a unit-mass box, i.e. precisely one step. That
    // is the engine's standard pipeline, documented on `Effector.enable`, and
    // asserting it away here would be asserting the pipeline does not exist.
    _advance(3);
    final coasting = scene.box.bodyLinearVelocityY[box];

    _advance(30);

    // The real claim: once disabled, the velocity stops *changing*. Damping is
    // 0, so a body under no force holds what it has. Comparing two readings
    // after the disable is what separates "stopped pushing" from "never
    // pushed" - `lessThan(0)` would pass in both cases.
    expect(
      scene.box.bodyLinearVelocityY[box],
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
      scene.box.bodyLinearVelocityY[box],
      closeTo(0, 0.001),
      reason: 'the zone moved far away, so its wind moved with it',
    );
  });

  // #197. The declared dispatch handed `buoyancyEffector` the region's
  // *bottom* as the water line, and that function hangs its fluid *below* the
  // line it is given - so the water ended up one full region-height under the
  // region it was declared on. The pool below is 20 tall at the origin: the
  // declared water is `y` in [-10, +10], and the volume the bug produced was
  // [-30, -10].
  //
  // Both rows are asserted, and both are needed. "Some body somewhere got
  // lift" is exactly what the misplaced volume already did, so a test written
  // that way passes over the bug without noticing it.
  group('a declared buoyancy effector', () {
    test('floats a body inside its region', () async {
      final scene = await _boot(gravityY: -10);
      late Entity floater;
      setup.once = () {
        floater = scene.add();
        scene.addPool();
        scene.moveWindAway();
      };
      // Spawn, then the tick that creates the body from it.
      _advance(2);
      _advance(60);

      // Measured against the unfixed dispatch: -10.17, which is a second of
      // plain gravity. The body sat squarely in the declared water and got
      // nothing at all from it.
      expect(
        scene.box.bodyLinearVelocityY[floater],
        greaterThan(0),
        reason:
            'a box in water three times its own density has to be rising a '
            'second in, not falling',
      );

      _advance(360);
      final y = scene.box.transformOffsetY[floater];
      expect(
        y,
        greaterThan(0),
        reason:
            'and the water has to still be holding it up, above the height '
            'it was dropped at',
      );
      expect(
        y,
        lessThan(25),
        reason:
            'near the water line at +10 rather than fired out of it - the '
            'depth cap is what makes it bob instead of launching',
      );
    });

    test('leaves a body below its region alone', () async {
      final scene = await _boot(gravityY: -10);
      late Entity sinker;
      setup.once = () {
        sinker = scene.add();
        // Under the pool, in the empty space the misplaced fluid used to
        // occupy. Nothing is declared here, so nothing may act here.
        scene.box.transformOffsetY[sinker] = -20;
        scene.addPool();
        scene.moveWindAway();
      };
      _advance(2);
      _advance(60);

      // Measured against the unfixed dispatch: +12.64, rising from -20 to
      // -12.68. The phantom volume was floating a body that was never in any
      // declared water.
      expect(
        scene.box.bodyLinearVelocityY[sinker],
        closeTo(-10.17, 0.5),
        reason:
            'a body outside every effector falls under gravity and nothing '
            'else, so a second of it is -10 m/s and no other number',
      );
      expect(
        scene.box.transformOffsetY[sinker],
        lessThan(-20),
        reason: 'and it is lower than it started, not higher',
      );
    });

    // The one-shot function was correct all along, and that is what made the
    // defect survivable: the tested caller and the broken caller were
    // different callers of the same function. Driving both over one geometry
    // is what keeps them from parting again.
    test('the one-shot function agrees with the declared one', () async {
      final scene = await _boot(gravityY: -10);
      late Entity floater;
      late Entity sinker;
      setup.once = () {
        floater = scene.add();
        sinker = scene.add();
        scene.box.transformOffsetY[sinker] = -20;
        // No pool entity: the same water, given as four numbers instead.
        scene.moveWindAway();
      };
      oneShot.each = (physics) => physics.buoyancyEffector(
        scene.handle,
        -50,
        50,
        surfaceY: 10,
        depth: 20,
        density: 3,
      );
      _advance(2);
      _advance(60);

      expect(
        scene.box.bodyLinearVelocityY[floater],
        greaterThan(0),
        reason:
            'the same water written out by hand floats the same body - if '
            'this passes while the declared test fails, the dispatch is '
            'passing the wrong region edge again',
      );
      expect(
        scene.box.bodyLinearVelocityY[sinker],
        closeTo(-10.17, 0.5),
        reason: 'and leaves the body below it alone, exactly as declaring did',
      );
    });
  });
}
