// Landing 2/3 verification: proves that a goo2d prefab mixing in
// RigidBody2D actually simulates through the real Box2D, and that the
// transform-authority rules hold.
//
// Requires the native library:
//   cd packages/goo2d_ffi_box2d && powershell -File tool/build_native.ps1
//
// **Positive y is DOWN**, matching goo2d's own projection into Flutter's
// canvas - so a floor sits at a LARGER y than the bodies falling onto it,
// and free fall increases y. Box2D's own examples are written y-up; this
// engine is not, and `Box2DPhysicsSystem.gravityY` defaults accordingly.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d_physics_box2d/goo2d_physics_box2d.dart';

/// The live run under test. Follows goo2d's own test convention (see
/// world_transform_test.dart): the helper returns the `Game` while tests
/// also need the run, and one inline run per isolate makes one binding
/// enough.
late Game run;

/// The physics system under test, captured at declare time so tests can
/// dispose the Box2D world.
late Box2DPhysicsSystem physics;

/// A dynamic crate: a box collider on a simulated body.
class _Crate extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  late final BoxBody box;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    box = descriptor.hasBoxCollider(halfWidth: 0.5, halfHeight: 0.5);
  }
}

/// A static floor.
class _Floor extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  late final BoxBody box;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    box = descriptor.hasBoxCollider(halfWidth: 50, halfHeight: 1);
  }

  @override
  void describeRigidBody(RigidBody2DDescriptor descriptor) {
    super.describeRigidBody(descriptor);
    descriptor.has(type: BodyType2D.staticBody);
  }
}

/// A bouncy ball, covering the circle shape and restitution.
class _Ball extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  late final CircleBody circle;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    circle = descriptor.hasCircleCollider(radius: 0.5, restitution: 0.8);
  }
}

/// A kinematic moving platform: gameplay sets its velocity, the solver
/// integrates it.
class _Platform extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  late final BoxBody box;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    box = descriptor.hasBoxCollider(halfWidth: 4, halfHeight: 0.5);
  }

  @override
  void describeRigidBody(RigidBody2DDescriptor descriptor) {
    super.describeRigidBody(descriptor);
    descriptor.has(type: BodyType2D.kinematicBody);
  }
}

/// A body that never rotates.
class _Pinned extends EntityStruct with Transform2D, Collider2D, RigidBody2D {
  late final CircleBody circle;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    circle = descriptor.hasCircleCollider(radius: 0.5);
  }

  @override
  void describeRigidBody(RigidBody2DDescriptor descriptor) {
    super.describeRigidBody(descriptor);
    descriptor.has(fixedRotation: true);
  }
}

class _Scene extends SceneStruct {
  late Scene handle;

  late final _Crate crate;
  late final _Floor floor;
  late final _Ball ball;
  late final _Pinned pinned;
  late final _Platform platform;

  @override
  void onSceneMounted(Scene scene) => handle = scene;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    crate = descriptor.has(_Crate());
    floor = descriptor.has(_Floor());
    ball = descriptor.has(_Ball());
    pinned = descriptor.has(_Pinned());
    platform = descriptor.has(_Platform());
  }
}

/// A pending teleport: (entity, x, y). Applied by [_GameplaySystem] on the
/// next tick, then cleared.
(Entity, double, double)? _teleport;

/// A pending body-type change, applied the same way.
(Entity, BodyType2D)? _retype;

/// A pending rotation write: (entity, radians). Same reason as [_teleport] -
/// a transform write has to come from inside a tick window.
(Entity, double)? _turn;

/// Stands in for ordinary gameplay code. Component mutation is only legal
/// inside a tick window, so a test that wants to move something mid-run has
/// to do it from a system like any real game would.
class _GameplaySystem extends GameSystem with FixedTickable {
  @override
  void onFixedUpdate() {
    final retype = _retype;
    if (retype != null) {
      _retype = null;
      final (entity, type) = retype;
      entity.get<RigidBody2D>().bodyType[entity] = type;
    }

    final turn = _turn;
    if (turn != null) {
      _turn = null;
      final (entity, angle) = turn;
      entity.get<Transform2D>().transformRotation[entity] = angle;
    }

    final pending = _teleport;
    if (pending == null) return;
    _teleport = null;

    final (entity, x, y) = pending;
    entity.get<Transform2D>()
      ..transformOffsetX[entity] = x
      ..transformOffsetY[entity] = y;
  }

  // No compareTo: Box2DPhysicsSystem already claims to run first, and a
  // second system claiming to run before it would make the comparator
  // inconsistent - which Game._sortSystems does not detect as a cycle, it
  // just produces whichever order the sort lands on.
}

class _GameState extends GameState<_Game> {
  @override
  void onMounted() {
    loadScene(_Scene());
  }

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_GameplaySystem());
    physics = descriptor.has(Box2DPhysicsSystem(workerCount: _workers));
  }
}

class _Game extends Game {
  // 4 KiB rather than the 64 MiB default: these fixtures hold a few hundred
  // entities at most, and the default would allocate three 64 MiB pages per
  // test.
  @override
  int get pageSize => 4096;

  /// A 60 Hz step, so the free-fall arithmetic below is the familiar one.
  @override
  Duration get fixedTimeStep => const Duration(microseconds: 16667);

  @override
  GameState createState() => _GameState();
}

const Duration _step = Duration(microseconds: 16667);

/// Worker threads the fixture's physics system is built with. A file-level
/// binding because the system is constructed inside `describeSystems`, which
/// the Game calls and which takes no arguments.
int _workers = 1;

Future<_Scene> _boot({int workers = 1}) async {
  _workers = workers;
  final game = _Game();
  run = await Game.startInline(game);
  addTearDown(() async {
    // Stop FIRST, then dispose. Stopping unloads the scenes, which unmounts
    // every entity and destroys its Box2D body - so disposing first would
    // leave that teardown destroying bodies inside a world that had already
    // been freed.
    if (run.isRunning) await run.stop();
    physics.dispose();
  });
  return run.state.getScene<_Scene>();
}

void _advance(int steps) {
  for (var i = 0; i < steps; i++) {
    run.state.advance(_step);
  }
}

void main() {
  setUp(() {
    _teleport = null;
    _retype = null;
    _turn = null;
  });

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('bodies', () {
    test('a spawned entity gets a Box2D body on the next fixed step', () async {
      final scene = await _boot();
      final crate = scene.addEntity(scene.crate);

      // **Not on the spawn itself, deliberately.** Creating the body during
      // `onEntitySpawned` would read the entity's transform and collider in
      // the same tick the prefab wrote them, and `_readRow` serves the last
      // *published* snapshot - so a recycled row hands back its previous
      // occupant's size. See `Box2DPhysicsSystem.onEntitySpawned`.
      expect(
        scene.crate.bodyHandle[crate],
        0,
        reason: 'the body is queued on spawn, not created',
      );

      _advance(1);

      expect(
        scene.crate.bodyHandle[crate],
        isNot(0),
        reason: 'the first fixed step should have created it',
      );
    });

    test('a dynamic body falls under gravity', () async {
      final scene = await _boot();
      final crate = scene.addEntity(scene.crate);

      _advance(60);

      expect(
        scene.crate.transformOffsetY[crate],
        closeTo(-5.0, 0.2),
        reason: 'one second of free fall is about 1/2 g t^2, and world +y is '
            'up so falling is toward a smaller y',
      );
    });

    test('a static body does not move', () async {
      final scene = await _boot();
      final floor = scene.addEntity(scene.floor);
      scene.floor.transformOffsetY[floor] = -10;

      _advance(60);

      expect(scene.floor.transformOffsetY[floor], closeTo(-10, 1e-4));
    });

    test('a falling body rests on a static floor', () async {
      final scene = await _boot();

      final floor = scene.addEntity(scene.floor);
      scene.floor.transformOffsetY[floor] = -10;

      final crate = scene.addEntity(scene.crate);

      _advance(300);

      // Floor surface at -9, plus the crate's 0.5 half-height. A crate that
      // fell straight past means the shapes were never created.
      expect(
        scene.crate.transformOffsetY[crate],
        closeTo(-8.5, 0.1),
        reason: 'the crate should rest on the floor, not fall through it',
      );
    });

    test('velocity is mirrored back into the component', () async {
      final scene = await _boot();
      final crate = scene.addEntity(scene.crate);

      _advance(30);

      expect(
        scene.crate.linearVelocityY[crate],
        lessThan(-1),
        reason: 'a falling body should report a downward (negative y) '
            'velocity',
      );
    });

    test('a bouncy ball rebounds off the floor', () async {
      final scene = await _boot();

      final floor = scene.addEntity(scene.floor);
      scene.floor.transformOffsetY[floor] = -10;

      final ball = scene.addEntity(scene.ball);

      var landed = false;
      var highestAfterBounce = -100.0;
      for (var i = 0; i < 400; i++) {
        run.state.advance(_step);
        final y = scene.ball.transformOffsetY[ball];
        if (!landed && y < -8.4) landed = true;
        if (landed && y > highestAfterBounce) highestAfterBounce = y;
      }

      expect(landed, isTrue, reason: 'the ball should reach the floor');
      expect(
        highestAfterBounce,
        greaterThan(-8.0),
        reason: 'restitution 0.8 should send it back up appreciably - up '
            'being a larger y',
      );
    });
  });

  group('transform authority', () {
    test('gameplay can teleport a dynamic body', () async {
      final scene = await _boot();
      final crate = scene.addEntity(scene.crate);

      _advance(30);
      expect(scene.crate.transformOffsetY[crate], lessThan(-0.5));

      // The write goes through a system rather than straight from the test
      // body: component mutation is only legal inside a tick window
      // (`_writeRow` asserts it), because a write between ticks is one the
      // next beginTick would discard. Real gameplay code is always inside a
      // system, so this is what a teleport actually looks like.
      _teleport = (crate, 100.0, 100.0);

      // TWO ticks, and the reason is the engine's core read rule rather than
      // anything about physics: `_readRow` serves the last *published*
      // snapshot, so a value written during tick N is not visible to any
      // reader until N+1 - including a system that runs later in the very
      // same tick. Ordering `_TeleportSystem` before the physics system
      // therefore does not and cannot help.
      //
      // So a gameplay transform write reaches Box2D one tick after it is
      // made. That is the same one-tick pipeline everything else in this
      // engine runs on, and it is a documented property of the integration,
      // not a bug to tune away.
      _advance(2);

      expect(
        scene.crate.transformOffsetX[crate],
        closeTo(100, 0.1),
        reason: 'x is untouched by gravity, so it should land exactly on the '
            'teleport target',
      );
      expect(
        scene.crate.transformOffsetY[crate],
        closeTo(100, 0.5),
        reason: 'the body should have moved to the teleport target rather '
            'than staying where the solver had it - the tolerance allows for '
            'the momentum it still carried into the step after arriving',
      );
    });

    test('an untouched spinning body tracks its angular velocity', () async {
      // The guard against b2MakeRot's approximation drift. If the system
      // pushed every dynamic body back every tick, the rotation would
      // converge towards a multiple of pi/4 instead of tracking - about 27
      // degrees away. See goo2d_ffi_box2d's README.
      final scene = await _boot();
      final crate = scene.addEntity(scene.crate);

      // One step first: a body is created on the fixed step after its spawn,
      // so a force or velocity applied before that has no body to reach and
      // is silently dropped. See `Box2DPhysicsSystem.onEntitySpawned`.
      _advance(1);

      scene.crate.setAngularVelocity(crate, 1.0); // rad/s
      _advance(60);

      expect(
        scene.crate.transformRotation[crate],
        closeTo(1.0, 0.02),
        reason: 'one radian after one second; drift towards pi/4 (0.785) '
            'would mean pulled angles are being pushed back in',
      );
    });

    // #74. `b2MakeRot` is a rational approximation, so an angle pushed in and
    // pulled back out does not come back the same; do that once per tick and
    // the error compounds towards a multiple of pi/4. These are exact-equality
    // assertions on purpose - the defect is a slow drift, and any tolerance
    // wide enough to be comfortable is wide enough to hide it. Before the
    // fix the floor below read 0.7184847593307495 at 1000 ticks and
    // 0.7853957414627075 at 10000.
    const authored = 0.3;

    test('a static body holds the angle it was authored at', () async {
      final scene = await _boot();
      final floor = scene.addEntity(scene.floor);
      scene.floor.transformRotation[floor] = authored;

      _advance(10000);

      expect(
        scene.floor.transformRotation[floor],
        authored,
        reason: 'the solver never moves a static body, so nothing should '
            'ever have written its rotation - not even back to itself',
      );
    });

    test('a kinematic body holds its angle when nothing turns it', () async {
      final scene = await _boot();
      final platform = scene.addEntity(scene.platform);
      scene.platform.transformRotation[platform] = authored;

      // Kinematic is NOT the same case as static: the solver integrates a
      // kinematic body's velocity, so its transform is a result and is read
      // back. That first read is Box2D's own reading of the authored angle -
      // `authored` put through b2MakeRot and back - so it is not 0.3, and it
      // is not supposed to be. What matters is that it then stops moving.
      _advance(1);
      final settled = scene.platform.transformRotation[platform];
      expect(settled, isNot(authored));

      _advance(9999);

      expect(
        scene.platform.transformRotation[platform],
        settled,
        reason: 'with no angular velocity there is nothing to integrate, so '
            'the angle read on the first tick is the one it keeps',
      );
    });

    test('a kinematic body still turns when given angular velocity', () async {
      // The other half of the one above: skipping the push must not have
      // cost kinematic bodies their motion, which is the solver's to give.
      final scene = await _boot();
      final platform = scene.addEntity(scene.platform);
      _advance(1);

      scene.platform.setAngularVelocity(platform, 1.0); // rad/s
      _advance(60);

      expect(
        scene.platform.transformRotation[platform],
        closeTo(1.0, 0.02),
        reason: 'one radian after one second, the same as a dynamic body',
      );
    });

    test('gameplay can turn a static body', () async {
      final scene = await _boot();
      final floor = scene.addEntity(scene.floor);
      scene.floor.transformRotation[floor] = authored;
      _advance(10);

      _turn = (floor, 1.2);
      // Two ticks for the same reason the teleport test needs two: a write
      // made during tick N is not readable until N+1.
      _advance(2);

      expect(
        scene.floor.transformRotation[floor],
        1.2,
        reason: 'a static body is gameplay\'s to place, and the value it is '
            'given is the value it keeps',
      );

      _advance(10000);

      expect(
        scene.floor.transformRotation[floor],
        1.2,
        reason: 'and it does not start drifting from the new angle either',
      );
    });

    test('a body turned static holds the angle it froze at', () async {
      // The #67 path: a crate that lands and is frozen in place used to enter
      // the drift loop from the other direction.
      final scene = await _boot();
      final crate = scene.addEntity(scene.crate);
      _advance(1);

      _turn = (crate, authored);
      _advance(2);
      _retype = (crate, BodyType2D.staticBody);
      _advance(3);

      final frozen = scene.crate.transformRotation[crate];
      _advance(10000);

      expect(
        scene.crate.transformRotation[crate],
        frozen,
        reason: 'freezing a body must not hand it to the round-trip that '
            'static bodies are now kept out of',
      );
    });

    test('fixedRotation refuses angular velocity', () async {
      final scene = await _boot();
      final pinned = scene.addEntity(scene.pinned);

      scene.pinned.setAngularVelocity(pinned, 5.0);
      _advance(60);

      expect(
        scene.pinned.transformRotation[pinned],
        closeTo(0, 1e-6),
        reason: 'fixedRotation should refuse the spin entirely',
      );
    });
  });

  group('forces', () {
    test('an impulse changes motion on the same tick', () async {
      final scene = await _boot();
      final crate = scene.addEntity(scene.crate);
      _advance(1);

      // Straight through to Box2D, so it lands on this tick's step rather
      // than being pipelined through the component snapshot.
      scene.crate.applyImpulse(crate, 50, 0);
      _advance(1);

      expect(
        scene.crate.transformOffsetX[crate],
        greaterThan(0.05),
        reason: 'an impulse should have moved the crate sideways at once',
      );
    });

    test('a force accumulates while it is applied', () async {
      final scene = await _boot();
      final crate = scene.addEntity(scene.crate);
      _advance(1);

      for (var i = 0; i < 30; i++) {
        scene.crate.applyForce(crate, 200, 0);
        _advance(1);
      }
      final pushed = scene.crate.transformOffsetX[crate];

      // Stop pushing; drag is zero, so it coasts rather than stopping - but
      // it must not keep accelerating.
      final speedWhilePushed = scene.crate.linearVelocityX[crate];
      for (var i = 0; i < 30; i++) {
        _advance(1);
      }

      expect(pushed, greaterThan(0.5), reason: 'the force should have moved it');
      expect(
        scene.crate.linearVelocityX[crate],
        closeTo(speedWhilePushed, 0.5),
        reason: 'with the force removed it should coast, not keep speeding up',
      );
    });

    test('torque spins a body', () async {
      final scene = await _boot();
      final crate = scene.addEntity(scene.crate);
      _advance(1);

      for (var i = 0; i < 30; i++) {
        scene.crate.applyTorque(crate, 20);
        _advance(1);
      }

      expect(scene.crate.angularVelocity[crate].abs(), greaterThan(0.1));
    });

    test('setVelocity takes effect immediately', () async {
      final scene = await _boot();
      final crate = scene.addEntity(scene.crate);
      _advance(1);

      scene.crate.setVelocity(crate, 10, 0);
      _advance(1);

      expect(scene.crate.transformOffsetX[crate], greaterThan(0.1));
    });

    test('a force on a body with no handle is a no-op, not a crash', () async {
      // Reachable from a prefab's own onEntityMounted, which runs before the
      // physics system has created the body.
      final scene = await _boot();
      final crate = scene.addEntity(scene.crate);
      scene.crate.bodyHandle[crate] = 0;
      expect(() => scene.crate.applyForce(crate, 10, 0), returnsNormally);
      expect(() => scene.crate.applyImpulse(crate, 10, 0), returnsNormally);
      expect(() => scene.crate.applyTorque(crate, 10), returnsNormally);
    });

    test('a body can be taken out of simulation and put back', () async {
      final scene = await _boot();
      final crate = scene.addEntity(scene.crate);
      _advance(2);

      scene.crate.setSimulated(crate, false);
      final parked = scene.crate.transformOffsetY[crate];
      _advance(60);
      expect(
        scene.crate.transformOffsetY[crate],
        closeTo(parked, 1e-3),
        reason: 'a disabled body should not fall',
      );

      scene.crate.setSimulated(crate, true);
      _advance(60);
      expect(
        scene.crate.transformOffsetY[crate],
        lessThan(parked - 0.5),
        reason: 're-enabling should let gravity take it again',
      );
    });
  });

  // A `bodyType` write on a live body, which `_fill` turns into Box2D's own
  // b2Body_SetType. Three ticks between the write and the assertion in each
  // test: one for the write to publish, one for the step that applies it,
  // and one more so the tick after the change is included rather than
  // straddled.
  group('body type', () {
    test('a dynamic body turned static stops where it is', () async {
      final scene = await _boot();
      final crate = scene.addEntity(scene.crate);

      _advance(30);
      expect(
        scene.crate.transformOffsetY[crate],
        lessThan(-0.5),
        reason: 'it has to be falling for stopping to mean anything',
      );

      _retype = (crate, BodyType2D.staticBody);
      _advance(3);
      final stopped = scene.crate.transformOffsetY[crate];

      _advance(120);

      expect(
        scene.crate.transformOffsetY[crate],
        closeTo(stopped, 1e-6),
        reason: 'the solver does not move a static body, so two seconds of '
            'gravity should leave it exactly where it was',
      );
      expect(
        scene.crate.linearVelocityY[crate],
        closeTo(0, 1e-6),
        reason: 'a static body does not keep the velocity it was '
            'carrying',
      );
    });

    test('a static body turned dynamic starts falling', () async {
      final scene = await _boot();
      final floor = scene.addEntity(scene.floor);
      scene.floor.transformOffsetY[floor] = -10;

      _advance(30);
      expect(
        scene.floor.transformOffsetY[floor],
        closeTo(-10, 1e-4),
        reason: 'still static, still parked',
      );

      _retype = (floor, BodyType2D.dynamicBody);
      _advance(60);

      expect(
        scene.floor.transformOffsetY[floor],
        lessThan(-11),
        reason: 'about a second of free fall, less the ticks the write spent '
            'reaching the solver',
      );
    });

    test('a body turned kinematic stops accelerating', () async {
      final scene = await _boot();
      final crate = scene.addEntity(scene.crate);

      _advance(30);

      _retype = (crate, BodyType2D.kinematicBody);
      _advance(3);
      final coasting = scene.crate.linearVelocityY[crate];
      expect(coasting, lessThan(-0.4), reason: 'it was falling when it '
          'changed, and Box2D leaves a kinematic body the velocity it had');

      _advance(60);

      // The distinguishing property: gravity is what a kinematic body is
      // exempt from, not motion. A dynamic body would be a second of g
      // faster by now.
      expect(
        scene.crate.linearVelocityY[crate],
        closeTo(coasting, 1e-6),
        reason: 'a kinematic body coasts at whatever velocity it has - a '
            'still-dynamic one would have gained about 9.8 m/s',
      );
    });

    test('a type change keeps the body handle and its shapes', () async {
      final scene = await _boot();

      final floor = scene.addEntity(scene.floor);
      scene.floor.transformOffsetY[floor] = -10;
      final crate = scene.addEntity(scene.crate);

      _advance(1);
      final handle = scene.crate.bodyHandle[crate];
      expect(handle, isNot(0));

      // Out to static and back, so both directions are exercised on one
      // body - and the halt in between is what stops this test passing on a
      // build where the type change never reaches Box2D at all.
      _retype = (crate, BodyType2D.staticBody);
      _advance(3);
      final parked = scene.crate.transformOffsetY[crate];
      _advance(60);
      expect(
        scene.crate.transformOffsetY[crate],
        closeTo(parked, 1e-6),
        reason: 'the change has to have taken effect for the rest of this '
            'test to be about anything',
      );

      _retype = (crate, BodyType2D.dynamicBody);
      _advance(300);

      expect(
        scene.crate.bodyHandle[crate],
        handle,
        reason: 'a type change must not rebuild the body - a new handle here '
            'would mean its shapes and joints had been dropped with the old '
            'one',
      );
      expect(
        scene.crate.transformOffsetY[crate],
        closeTo(-8.5, 0.1),
        reason: 'it still has the box collider it was created with, so it '
            'lands on the floor rather than falling through where its '
            'shapes used to be',
      );
    });
  });

  group('bulk transfer', () {
    test('many bodies simulate without their slots crossing', () async {
      // Also grows the scratch buffers past their initial capacity of 64.
      final scene = await _boot();

      final crates = <Entity>[];
      for (var i = 0; i < 100; i++) {
        final crate = scene.addEntity(scene.crate);
        scene.crate.transformOffsetX[crate] = i * 2.0;
        crates.add(crate);
      }

      _advance(60);

      for (var i = 0; i < crates.length; i++) {
        expect(
          scene.crate.transformOffsetY[crates[i]],
          closeTo(-5.0, 0.2),
          reason: 'crate $i should have fallen like every other',
        );
        expect(
          scene.crate.transformOffsetX[crates[i]],
          closeTo(i * 2.0, 1e-3),
          reason: 'crate $i drifted sideways, which would mean scratch slots '
              'and component rows got out of step',
        );
      }
    });

    test('bodies of several archetypes simulate in one pass', () async {
      // Slots are filled in query-group order, so this covers the
      // archetype-change branch in the write-back loop.
      final scene = await _boot();

      // Spread out, or they spawn on top of each other and the solver spends
      // the test pushing them apart instead of letting them fall.
      final crate = scene.addEntity(scene.crate);
      final ball = scene.addEntity(scene.ball);
      scene.ball.transformOffsetX[ball] = 10;
      final pinned = scene.addEntity(scene.pinned);
      scene.pinned.transformOffsetX[pinned] = 20;

      _advance(60);

      for (final (name, y) in [
        ('crate', scene.crate.transformOffsetY[crate]),
        ('ball', scene.ball.transformOffsetY[ball]),
        ('pinned', scene.pinned.transformOffsetY[pinned]),
      ]) {
        expect(y, closeTo(-5.0, 0.2), reason: '$name should have fallen');
      }
    });
  });

  group('body lifetime', () {
    test('destroying an entity destroys its Box2D body', () async {
      // **The leak.** `Entity.destroy` used to fire only the prefab's narrow
      // `unmountedEvent`; the broad `entityDespawnedEvent` this system listens
      // to went in on the scene-unload path alone. So a game that recycles
      // entities - and every game does - left one Box2D body behind per
      // destroy, forever, with no Dart-visible symptom at all.
      //
      // It presented as a solver whose cost climbed without bound while the
      // entity count held steady. Box2D reported **57 882 awake bodies** for a
      // demo scene of 4000 before this was found, which is why the assertion
      // below is on Box2D's own count and not on anything Dart tracks: the
      // Dart side was right the whole time.
      final scene = await _boot();

      final counters = Int32List(5);
      final before = physics.counters(counters)[0];

      final crates = <Entity>[
        for (var i = 0; i < 20; i++) scene.addEntity(scene.crate),
      ];
      _advance(1);
      expect(
        physics.counters(counters)[0],
        before + 20,
        reason: 'each spawned entity should have created exactly one body',
      );

      for (final crate in crates) {
        crate.destroy();
      }
      _advance(1);

      expect(
        physics.counters(counters)[0],
        before,
        reason: 'every destroyed entity must take its Box2D body with it',
      );
    });

    test('a destroyed body stops being simulated', () async {
      // The count returning to baseline could in principle be satisfied by a
      // handle table that forgets while the body keeps stepping. This checks
      // the world is actually lighter: nothing awake once the pile is gone.
      final scene = await _boot();
      scene.addEntity(scene.floor);
      scene.floor.transformOffsetY[scene.addEntity(scene.floor)] = 5;

      final crates = <Entity>[
        for (var i = 0; i < 10; i++) scene.addEntity(scene.crate),
      ];
      _advance(2);
      expect(physics.awakeBodyCount, greaterThan(0));

      for (final crate in crates) {
        crate.destroy();
      }
      _advance(2);

      expect(
        physics.awakeBodyCount,
        0,
        reason: 'with every dynamic body destroyed nothing should be awake',
      );
    });
  });

  group('teardown', () {
    test('stopping the game releases the Box2D world', () async {
      // **`GameSystem.unmountEvent` was declared from the start and fired by
      // nothing.** So `dispose` documented "call it yourself after stopping",
      // nothing ever did, and every run leaked a Box2D world - plus, once the
      // demo threaded by default, its worker threads. That is the reported
      // "window closed but the process is still alive" made worse.
      //
      // Asserted on the world handle rather than on a call count, because a
      // hook that fires and disposes nothing would pass the latter.
      final scene = await _boot();
      scene.addEntity(scene.crate);
      _advance(2);

      expect(physics.activeWorkerCount, greaterThan(0),
          reason: 'a world should exist while the game is running');

      await run.stop();

      expect(
        physics.activeWorkerCount,
        0,
        reason: 'stopping should have released the world, so there is no '
            'longer one to report a worker count for',
      );
    });

    test('a threaded world releases its threads too', () async {
      // Same path, with a pool attached - the case that leaks OS threads
      // rather than just memory. A timeout because joining threads that are
      // mid-task hangs, and that is what a wrong teardown order does.
      final scene = await _boot(workers: 4);
      scene.addEntity(scene.crate);
      _advance(2);
      expect(physics.activeWorkerCount, 4);

      await run.stop();

      expect(physics.activeWorkerCount, 0);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('threading', () {
    test('a threaded system simulates the same as a serial one', () async {
      // End to end through the ECS, not just the shim: the pool is created
      // lazily on first body creation, which is on the game isolate, and this
      // is the only test that exercises that path.
      //
      // A timeout because the failure mode of a task system is a hang. If the
      // pool dispatched Box2D's solver tasks wrongly they would wait at a
      // barrier forever, and an unbounded test would take the suite with it.
      final scene = await _boot(workers: 4);
      final crate = scene.addEntity(scene.crate);

      _advance(60);

      expect(
        scene.crate.transformOffsetY[crate],
        closeTo(-5.0, 0.2),
        reason: 'one second of free fall is the same physics on any number '
            'of threads',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('joints', () {
    /// A static anchor above the origin, plus a crate hanging below it. Both
    /// advanced one step first, because a body exists on the fixed step after
    /// its entity spawns and a joint needs both bodies to be real.
    Future<(_Scene, Entity, Entity)> pair() async {
      final scene = await _boot();
      final anchor = scene.addEntity(scene.floor);
      final crate = scene.addEntity(scene.crate);
      // The anchor above (positive y is up), the crate at the origin.
      scene.floor.transformOffsetY[anchor] = 10;
      _advance(1);
      return (scene, anchor, crate);
    }

    test('a distance joint stops a body falling past its length', () async {
      // The mechanism, not the call. A joint that was created and then did
      // nothing would leave the crate in free fall, and after two seconds
      // that is unmistakable: ~20 m down against a 10 m tether.
      final (scene, anchor, crate) = await pair();

      final joint = physics.createDistanceJoint(anchor, crate, length: 10);
      expect(joint, isNot(0), reason: 'both bodies exist by now');

      _advance(120);

      final y = scene.crate.transformOffsetY[crate];
      expect(
        y,
        closeTo(0, 0.5),
        reason: 'the anchor is at +10 and the tether is 10 long, so the crate '
            'hangs at about 0; free fall would have it near -20. The anchor '
            'has to be genuinely above the crate for this to mean anything - '
            'below it, the crate would be balanced on top of a rigid tether '
            'and would sit at 0 whether the joint worked or not',
      );
    });

    test('a revolute joint holds a body at its pivot', () async {
      // A hinge pins the two anchor points together, so the crate cannot
      // translate away from the anchor even though it may swing about it.
      final (scene, anchor, crate) = await pair();

      final joint = physics.createRevoluteJoint(
        anchor,
        crate,
        // The anchor's local (0, -10) is the crate's origin in world space.
        anchorAX: 0,
        anchorAY: -10,
      );
      expect(joint, isNot(Joint.none));

      _advance(120);

      expect(
        scene.crate.transformOffsetY[crate],
        closeTo(0, 0.5),
        reason: 'pinned to the anchor point, not falling',
      );
    });

    test('a joint reports the force it is carrying', () async {
      // What a breakable joint is built from. A crate of about 1 kg on a
      // tether under gravity 10 pulls with roughly 10 N - the assertion is
      // deliberately loose, because the point is that it is a real, non-zero
      // reading and not that it matches a hand-computed number.
      final (_, anchor, crate) = await pair();
      final joint = physics.createDistanceJoint(anchor, crate, length: 10);
      // **After stepping, and it has to be.** A constraint force is the
      // impulse the solver applied over the last step, so a joint read before
      // it has ever been solved reports exactly zero - which is what the
      // first version of this test did, and it read as the feature being
      // broken rather than the test being wrong.
      _advance(120);

      joint.readReaction();
      final magnitude = Joint.forceX.abs() + Joint.forceY.abs();
      expect(
        magnitude,
        greaterThan(0.1),
        reason: 'a loaded tether should report a non-zero constraint force',
      );
    });

    test('destroying a body invalidates its joints', () async {
      // Box2D destroys a joint with either of its bodies, so a Dart handle
      // goes stale on its own. Every joint call has to survive that rather
      // than reach into freed memory - which is a process kill, not an
      // exception.
      final (_, anchor, crate) = await pair();
      final joint = physics.createDistanceJoint(anchor, crate, length: 10);
      expect(joint.exists, isTrue);

      crate.destroy();
      _advance(1);

      expect(
        joint.exists,
        isFalse,
        reason: 'the joint went with the body',
      );
      // All of these must be no-ops on the stale handle.
      joint
        ..setMotor(speed: 1, maxEffort: 1)
        ..readReaction()
        ..destroy();
    });

    test('a prismatic joint allows its axis and blocks the others', () async {
      // Unity's Slider Joint 2D. A horizontal axis under downward gravity is
      // the sharp test: the body must not fall, and must still be free to
      // slide when pushed.
      final (scene, anchor, crate) = await pair();
      expect(
        physics.createPrismaticJoint(anchor, crate, axisX: 1, axisY: 0),
        isNot(0),
      );

      _advance(60);
      // Both local anchors default to (0, 0), so the joint pulls the crate's
      // origin onto the ANCHOR's origin at y = +10 and then holds it there.
      // Gravity is perpendicular to the axis, so it never sinks past that.
      expect(
        scene.crate.transformOffsetY[crate],
        closeTo(10, 0.2),
        reason: 'gravity is perpendicular to the axis, so it cannot fall',
      );

      scene.crate.applyImpulse(crate, 40, 0);
      _advance(30);
      expect(
        scene.crate.transformOffsetX[crate].abs(),
        greaterThan(0.5),
        reason: 'and it must still slide freely along the axis it was given',
      );
    });

    test('a weld joint holds a body rigidly', () async {
      // Unity's Fixed Joint 2D. Welded to a static anchor 10 above, the crate
      // must stay where it was welded rather than fall or swing.
      final (scene, anchor, crate) = await pair();
      expect(physics.createWeldJoint(anchor, crate), isNot(0));

      _advance(120);

      // Local anchors both (0, 0), so the weld holds the crate's origin on
      // the anchor's - which is at y = +10, not where the crate started.
      expect(scene.crate.transformOffsetY[crate], closeTo(10, 0.2));
      expect(scene.crate.transformOffsetX[crate], closeTo(0, 0.2));
    });

    test('a wheel joint suspends along its axis', () async {
      // Unity's Wheel Joint 2D. The spring carries the body, so it settles
      // *somewhere* under the anchor rather than free-falling - and stays.
      final (scene, anchor, crate) = await pair();
      expect(physics.createWheelJoint(anchor, crate), isNot(0));

      _advance(180);
      final settled = scene.crate.transformOffsetY[crate];
      _advance(60);

      expect(
        settled,
        greaterThan(-15),
        reason: 'suspended, not in free fall - three seconds unconstrained is '
            'about 45 m below the anchor, and down is a smaller y',
      );
      expect(
        scene.crate.transformOffsetY[crate],
        closeTo(settled, 0.5),
        reason: 'and it has come to rest rather than still sinking',
      );
    });

    test('a motor joint with zero offset acts as friction', () async {
      // Unity splits this into Relative Joint 2D and Friction Joint 2D; they
      // are one Box2D joint and differ only in what you ask it to hold. With
      // no offset it drives towards no relative motion, so an impulse dies
      // away instead of carrying the body off.
      final (scene, anchor, crate) = await pair();
      expect(
        physics.createMotorJoint(anchor, crate, maxForce: 500, maxTorque: 500),
        isNot(0),
      );
      _advance(30);

      scene.crate.applyImpulse(crate, 60, 0);
      _advance(90);

      expect(
        scene.crate.linearVelocityX[crate].abs(),
        lessThan(1.0),
        reason: 'the motor should have arrested the impulse',
      );
    });

    test('a mouse joint drags a body to its target', () async {
      // Unity's Target Joint 2D. Asserted on the body arriving, because a
      // joint that was created and then pulled with no force would leave it
      // exactly where a missing joint would.
      final (scene, anchor, crate) = await pair();
      final joint = physics.createMouseJoint(
        anchor,
        crate,
        targetX: 6,
        targetY: -4,
        // Critically damped and stiff. Box2D's defaults are springy, and a
        // springy drag overshoots and keeps ringing - the first version of
        // this test sampled mid-oscillation at x = 12 against a target of 6
        // and looked like a broken joint rather than an under-damped one.
        hertz: 5,
        dampingRatio: 1,
        maxForce: 4000,
      );
      expect(joint, isNot(Joint.none));

      _advance(240);

      // The whole point of the type: it arrives. It did not before - the
      // shim created the joint AT the target, which anchors whichever point
      // of the body is already there, so separation solved to zero and the
      // joint did nothing.
      expect(scene.crate.transformOffsetX[crate], closeTo(6, 0.5));
      // **The y axis is deliberately not asserted, and that is a known gap.**
      // With a target 4 m below the body it settles further down still - a sag far larger than gravity over this spring should
      // produce, and raising hertz from 5 to 15 and maxForce from 4e3 to 2e5
      // changed it by 0.008 m, which rules out plain stiffness. Something
      // about how v3's mouse joint resolves the vertical is not what I
      // assumed, and asserting a number I cannot explain would be pinning a
      // guess. x is asserted because it demonstrably tracks and steers.

      // And the target is steerable, which is the whole point of the type.
      joint.moveTarget(-6, -4);
      _advance(240);
      expect(
        scene.crate.transformOffsetX[crate],
        closeTo(-6, 0.5),
        reason: 'retargeting should haul it back the other way',
      );
    });

    test('joining an entity spawned this tick makes no joint', () async {
      // The trap this API's doc calls out: a body is created on the fixed
      // step *after* its entity spawns, so joining immediately after
      // `addEntity` finds nothing. It reports that by returning 0 rather than
      // by appearing to work.
      final scene = await _boot();
      final anchor = scene.addEntity(scene.floor);
      _advance(1);
      final fresh = scene.addEntity(scene.crate);

      expect(
        physics.createDistanceJoint(anchor, fresh, length: 5),
        0,
        reason: 'the fresh entity has no body until the next fixed step',
      );

      _advance(1);
      expect(
        physics.createDistanceJoint(anchor, fresh, length: 5),
        isNot(0),
        reason: 'and one step later it does',
      );
    });
  });
}
