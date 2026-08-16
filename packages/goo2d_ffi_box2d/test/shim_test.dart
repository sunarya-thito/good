// Landing 1's verification gate: proves the vendored Box2D, the shim, the
// generated bindings and the loader work as one chain, before any ECS API
// is built on top of them.
//
// Requires the native library. Build it once with:
//   cd packages/goo2d_ffi_box2d && powershell -File tool/build_native.ps1
//
// These are deliberately assertions about *physics*, not just about calls
// returning. A test that only checked "gooWorldCreate returned nonzero"
// would pass against a shim that never stepped anything - the failure this
// codebase has been caught by before (see the note on benchmarks that
// cannot fail, in the project memory).

import 'dart:ffi';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d_ffi_box2d/goo2d_ffi_box2d.dart';

/// Box2D's own default gravity magnitude, used by the free-fall maths.
const double gravity = 10.0;

/// Box2D's recommended solver sub-step count.
const int subSteps = 4;

const double dt = 1 / 60;

/// Collides with everything.
const int allLayers = -1; // 0xFFFFFFFFFFFFFFFF as a Dart int.

/// Worst-case error of an angle -> b2Rot -> angle round trip, measured by
/// sweeping 20000 angles across the full circle: 1.658e-3 rad, near
/// -2.933. Set just above the measurement.
///
/// Landing 3's "did gameplay move this body" comparison must use a
/// threshold at least this large, or Box2D's own approximation would read
/// as a gameplay edit on every single tick.
const double maxAngleRoundTripError = 2e-3;

void main() {
  group('shim', () {
    test('reports the vendored Box2D version', () {
      final packed = box2d.gooB2Version();
      final major = packed >> 16;
      final minor = (packed >> 8) & 0xFF;
      final revision = packed & 0xFF;
      expect(
        '$major.$minor.$revision',
        '3.1.1',
        reason: 'the vendored source is v3.1.1; a mismatch means a '
            'different library was loaded from the search path',
      );
    });

    test('a world handle is non-zero and survives destruction', () {
      final world = box2d.gooWorldCreate(0, -gravity);
      expect(world, isNot(0));
      box2d.gooWorldDestroy(world);
    });

    test('a dynamic body falls at the expected rate', () {
      final world = box2d.gooWorldCreate(0, -gravity);
      final body = box2d.gooBodyCreate(world, bodyTypeDynamic, 0, 0, 0);
      box2d.gooShapeAddCircle(
        body, 0, 0, 0.5, 1, 0.6, 0, 1, allLayers, 0,
      );

      for (var i = 0; i < 60; i++) {
        box2d.gooWorldStep(world, dt, subSteps);
      }

      final out = calloc<Float>(3);
      box2d.gooBodyGetTransform(body, out);
      final y = out[1];
      calloc.free(out);
      box2d.gooWorldDestroy(world);

      // s = 1/2 g t^2 after one second. Box2D's semi-implicit Euler
      // overshoots slightly, hence the tolerance rather than an equality -
      // but a body that is not simulating at all reads 0, and a body with
      // the wrong gravity sign reads +5, so this is a real discriminator.
      expect(y, closeTo(-0.5 * gravity, 0.1));
    });

    test('a falling body comes to rest on a static floor', () {
      final world = box2d.gooWorldCreate(0, -gravity);

      final ball = box2d.gooBodyCreate(world, bodyTypeDynamic, 0, 0, 0);
      box2d.gooShapeAddCircle(ball, 0, 0, 0.5, 1, 0.6, 0, 1, allLayers, 0);

      // Floor centred at -10 with half-height 1, so its surface is at -9.
      final floor = box2d.gooBodyCreate(world, bodyTypeStatic, 0, -10, 0);
      box2d.gooShapeAddBox(
        floor, 0, 0, 50, 1, 0, 1, 0.6, 0, 1, allLayers, 0,
      );

      for (var i = 0; i < 300; i++) {
        box2d.gooWorldStep(world, dt, subSteps);
      }

      final out = calloc<Float>(3);
      box2d.gooBodyGetTransform(ball, out);
      final y = out[1];
      calloc.free(out);
      box2d.gooWorldDestroy(world);

      // Surface at -9 plus the ball's 0.5 radius. If the shapes were not
      // actually created, the ball would fall straight past this.
      expect(y, closeTo(-8.5, 0.05));
    });

    test('a static body does not move', () {
      final world = box2d.gooWorldCreate(0, -gravity);
      final body = box2d.gooBodyCreate(world, bodyTypeStatic, 3, 7, 0);
      box2d.gooShapeAddBox(body, 0, 0, 1, 1, 0, 1, 0.6, 0, 1, allLayers, 0);

      for (var i = 0; i < 60; i++) {
        box2d.gooWorldStep(world, dt, subSteps);
      }

      final out = calloc<Float>(3);
      box2d.gooBodyGetTransform(body, out);
      expect(out[0], closeTo(3, 1e-5));
      expect(out[1], closeTo(7, 1e-5));
      calloc.free(out);
      box2d.gooWorldDestroy(world);
    });

    test('handles round-trip and report validity', () {
      final world = box2d.gooWorldCreate(0, -gravity);
      final body = box2d.gooBodyCreate(world, bodyTypeDynamic, 0, 0, 0);

      expect(box2d.gooBodyIsValid(body), 1);
      expect(box2d.gooBodyIsValid(0), 0, reason: 'zero is the null handle');

      box2d.gooBodyDestroy(body);
      expect(
        box2d.gooBodyIsValid(body),
        0,
        reason: "Box2D's generation counter should make the stale handle "
            'report invalid rather than answering for a reused slot',
      );

      box2d.gooWorldDestroy(world);
    });

    test('a shape resolves back to the body that owns it', () {
      final world = box2d.gooWorldCreate(0, -gravity);
      final body = box2d.gooBodyCreate(world, bodyTypeDynamic, 0, 0, 0);
      final shape = box2d.gooShapeAddCircle(
        body, 0, 0, 0.5, 1, 0.6, 0, 1, allLayers, 0,
      );

      expect(shape, isNot(0));
      expect(box2d.gooShapeGetBody(shape), body);
      box2d.gooWorldDestroy(world);
    });

    test('a degenerate polygon is refused rather than silently created', () {
      final world = box2d.gooWorldCreate(0, -gravity);
      final body = box2d.gooBodyCreate(world, bodyTypeDynamic, 0, 0, 0);

      final points = calloc<Float>(6);
      // Three collinear points enclose no area.
      points[0] = 0;
      points[1] = 0;
      points[2] = 1;
      points[3] = 0;
      points[4] = 2;
      points[5] = 0;
      expect(
        box2d.gooShapeAddPolygon(
          body, points, 3, 1, 0.6, 0, 1, allLayers, 0,
        ),
        0,
        reason: 'a collinear hull would otherwise become a collider that '
            'exists and collides with nothing',
      );

      // Too few points.
      expect(
        box2d.gooShapeAddPolygon(
          body, points, 2, 1, 0.6, 0, 1, allLayers, 0,
        ),
        0,
      );

      // Beyond B2_MAX_POLYGON_VERTICES.
      expect(
        box2d.gooShapeAddPolygon(
          body, points, 9, 1, 0.6, 0, 1, allLayers, 0,
        ),
        0,
      );

      // A real triangle is accepted.
      points[4] = 0;
      points[5] = 1;
      expect(
        box2d.gooShapeAddPolygon(
          body, points, 3, 1, 0.6, 0, 1, allLayers, 0,
        ),
        isNot(0),
      );

      calloc.free(points);
      box2d.gooWorldDestroy(world);
    });

    test('a capsule shorter than it is wide degenerates to a circle', () {
      // Matches CapsuleBody.containsLocalPoint's own documented behaviour:
      // the degenerate case has an obvious right answer, so it gets it
      // rather than an assert.
      final world = box2d.gooWorldCreate(0, -gravity);
      final body = box2d.gooBodyCreate(world, bodyTypeDynamic, 0, 0, 0);
      expect(
        box2d.gooShapeAddCapsule(
          body, 0, 0, 1.0, 0.5, 1, 0.6, 0, 1, allLayers, 0,
        ),
        isNot(0),
      );
      box2d.gooWorldDestroy(world);
    });
  });

  group('bulk transfer', () {
    test('pushes and pulls many bodies in one call each', () {
      final world = box2d.gooWorldCreate(0, -gravity);
      const count = 32;

      final handles = calloc<Int64>(count);
      for (var i = 0; i < count; i++) {
        handles[i] = box2d.gooBodyCreate(world, bodyTypeDynamic, 0, 0, 0);
      }

      // Push a distinct transform per body.
      final xya = calloc<Float>(count * 3);
      for (var i = 0; i < count; i++) {
        xya[i * 3] = i.toDouble();
        xya[i * 3 + 1] = -i.toDouble();
        xya[i * 3 + 2] = 0;
      }
      box2d.gooBodiesPushTransforms(handles, xya, count);

      // Read them straight back; nothing has stepped, so they must match.
      final out = calloc<Float>(count * 3);
      box2d.gooBodiesPullTransforms(handles, out, count);
      for (var i = 0; i < count; i++) {
        expect(out[i * 3], closeTo(i.toDouble(), 1e-4));
        expect(out[i * 3 + 1], closeTo(-i.toDouble(), 1e-4));
      }

      calloc.free(handles);
      calloc.free(xya);
      calloc.free(out);
      box2d.gooWorldDestroy(world);
    });

    test('skips null handles and leaves their slots untouched', () {
      // This is what lets the Dart side keep a stable sparse array across a
      // tick in which entities died, instead of compacting every frame.
      final world = box2d.gooWorldCreate(0, -gravity);
      final live = box2d.gooBodyCreate(world, bodyTypeDynamic, 5, 6, 0);

      final handles = calloc<Int64>(2);
      handles[0] = 0; // null handle
      handles[1] = live;

      final out = calloc<Float>(6);
      out[0] = 42; // a value the caller already had
      out[1] = 43;

      box2d.gooBodiesPullTransforms(handles, out, 2);

      expect(out[0], 42, reason: 'a skipped slot must not be zeroed');
      expect(out[1], 43);
      expect(out[3], closeTo(5, 1e-4));
      expect(out[4], closeTo(6, 1e-4));

      calloc.free(handles);
      calloc.free(out);
      box2d.gooWorldDestroy(world);
    });

    test('skips stale handles rather than crashing', () {
      final world = box2d.gooWorldCreate(0, -gravity);
      final body = box2d.gooBodyCreate(world, bodyTypeDynamic, 1, 2, 0);
      box2d.gooBodyDestroy(body);

      final handles = calloc<Int64>(1);
      handles[0] = body; // now stale
      final out = calloc<Float>(3);
      out[0] = 99;

      box2d.gooBodiesPullTransforms(handles, out, 1);
      expect(out[0], 99);

      calloc.free(handles);
      calloc.free(out);
      box2d.gooWorldDestroy(world);
    });

    test('velocities survive a push/pull round trip', () {
      final world = box2d.gooWorldCreate(0, 0); // no gravity
      const count = 4;
      final handles = calloc<Int64>(count);
      for (var i = 0; i < count; i++) {
        handles[i] = box2d.gooBodyCreate(world, bodyTypeDynamic, 0, 0, 0);
        box2d.gooShapeAddCircle(
          handles[i], 0, 0, 0.5, 1, 0.6, 0, 1, allLayers, 0,
        );
      }

      final vel = calloc<Float>(count * 3);
      for (var i = 0; i < count; i++) {
        vel[i * 3] = 1.0 + i;
        vel[i * 3 + 1] = 2.0 + i;
        vel[i * 3 + 2] = 0.5 * i;
      }
      box2d.gooBodiesPushVelocities(handles, vel, count);

      final out = calloc<Float>(count * 3);
      box2d.gooBodiesPullVelocities(handles, out, count);
      for (var i = 0; i < count; i++) {
        expect(out[i * 3], closeTo(1.0 + i, 1e-4));
        expect(out[i * 3 + 1], closeTo(2.0 + i, 1e-4));
        expect(out[i * 3 + 2], closeTo(0.5 * i, 1e-4));
      }

      calloc.free(handles);
      calloc.free(vel);
      calloc.free(out);
      box2d.gooWorldDestroy(world);
    });
  });

  group('rotation', () {
    test('survives the angle round trip within Box2D approximation error', () {
      // b2MakeRot does NOT call libm - it uses Bhaskara-style rational
      // approximations (b2ComputeCosSin, src/math_functions.c:107). So an
      // angle -> b2Rot -> angle round trip is lossy, and this tolerance
      // documents that rather than hiding it.
      //
      // The bound is measured, not guessed: sweeping 20000 angles across
      // the full circle (with the +/-pi branch cut handled) puts the worst
      // case at 1.658e-3 rad, near -2.933. maxAngleRoundTripError is set
      // just above that.
      //
      // This is why goo2d must never push back an angle it merely pulled -
      // see the accumulation test below, which is the part that actually
      // bites.
      final world = box2d.gooWorldCreate(0, 0);
      final out = calloc<Float>(3);

      for (final angle in <double>[
        0,
        math.pi / 6,
        math.pi / 3,
        math.pi / 2,
        2,
        -1.2,
      ]) {
        final body = box2d.gooBodyCreate(world, bodyTypeStatic, 0, 0, angle);
        box2d.gooBodyGetTransform(body, out);
        expect(
          out[2],
          closeTo(angle, maxAngleRoundTripError),
          reason: 'angle $angle did not survive the b2Rot round trip',
        );
      }

      calloc.free(out);
      box2d.gooWorldDestroy(world);
    });

    test('a pulled angle pushed back in converges to a WRONG value', () {
      // Locks in the reason goo2d treats Box2D as authoritative for a
      // dynamic body's rotation and never round-trips one.
      //
      // The approximation's error is not zero-mean noise that washes out -
      // it has attractors at multiples of pi/4, and feeding a pulled angle
      // back in walks steadily towards the nearest one. This is a physics
      // bug that would look like "rotation slowly goes wrong" and would be
      // extremely hard to attribute after the fact, so it is pinned here
      // where the cause is named.
      final world = box2d.gooWorldCreate(0, 0);
      final body = box2d.gooBodyCreate(world, bodyTypeStatic, 0, 0, 0);
      final out = calloc<Float>(3);

      // 10000 cycles is where the measurement settles to within 1e-5 of the
      // attractor; convergence is asymptotic, so 2000 only gets to ~0.757
      // and would make the pi/4 assertion below flaky-looking rather than
      // wrong. Each cycle is two native calls, so this still runs in
      // milliseconds.
      const start = 0.3;
      var angle = start;
      for (var i = 0; i < 10000; i++) {
        box2d.gooBodySetTransform(body, 0, 0, angle);
        box2d.gooBodyGetTransform(body, out);
        angle = out[2];
      }
      final drift = (angle - start).abs();

      calloc.free(out);
      box2d.gooWorldDestroy(world);

      expect(
        drift,
        greaterThan(0.1),
        reason: 'if this ever stops drifting, Box2D has changed its cos/sin '
            'approximation and the sync policy can be revisited - until '
            'then, never push back a pulled angle',
      );
      expect(
        angle,
        closeTo(math.pi / 4, 0.01),
        reason: 'the attractor is pi/4, roughly 27 degrees away from where '
            'this body was actually put',
      );
    });

    test('a body spins under angular velocity', () {
      final world = box2d.gooWorldCreate(0, 0);
      final body = box2d.gooBodyCreate(world, bodyTypeDynamic, 0, 0, 0);
      box2d.gooShapeAddBox(body, 0, 0, 1, 1, 0, 1, 0.6, 0, 1, allLayers, 0);
      box2d.gooBodySetAngularVelocity(body, 1.0); // rad/s

      for (var i = 0; i < 60; i++) {
        box2d.gooWorldStep(world, dt, subSteps);
      }

      final out = calloc<Float>(3);
      box2d.gooBodyGetTransform(body, out);
      expect(out[2], closeTo(1.0, 0.01), reason: 'one radian after one second');
      calloc.free(out);
      box2d.gooWorldDestroy(world);
    });
  });

  group('filtering', () {
    test('a zero mask stops a body colliding', () {
      // This is how goo2d's ColliderBody.enable is expressed, since Box2D
      // v3 has no per-shape enable flag.
      final world = box2d.gooWorldCreate(0, -gravity);

      final ball = box2d.gooBodyCreate(world, bodyTypeDynamic, 0, 0, 0);
      final shape = box2d.gooShapeAddCircle(
        ball, 0, 0, 0.5, 1, 0.6, 0, 1, allLayers, 0,
      );

      final floor = box2d.gooBodyCreate(world, bodyTypeStatic, 0, -10, 0);
      box2d.gooShapeAddBox(
        floor, 0, 0, 50, 1, 0, 1, 0.6, 0, 1, allLayers, 0,
      );

      // Disable the ball's shape: category kept, mask cleared.
      box2d.gooShapeSetFilter(shape, 1, 0);

      for (var i = 0; i < 300; i++) {
        box2d.gooWorldStep(world, dt, subSteps);
      }

      final out = calloc<Float>(3);
      box2d.gooBodyGetTransform(ball, out);
      final y = out[1];
      calloc.free(out);
      box2d.gooWorldDestroy(world);

      expect(
        y,
        lessThan(-20),
        reason: 'with a zero mask the ball should fall straight through the '
            'floor it would otherwise rest on at -8.5',
      );
    });

  });

  group('threading', () {
    // **Every test here carries a timeout**, because the failure mode of a
    // task system is a hang, not a wrong answer. Box2D's solver tasks
    // synchronise at barriers, so a pool that dispatches them wrongly waits
    // forever - and an unbounded test would take the whole suite with it
    // rather than reporting.
    const timeout = Timeout(Duration(seconds: 20));

    /// Drops a grid of boxes onto a floor and returns where they ended up.
    List<double> settle(int workers, int count) {
      final world = workers > 1
          ? box2d.gooWorldCreateThreaded(0, -gravity, workers)
          : box2d.gooWorldCreate(0, -gravity);

      final floor = box2d.gooBodyCreate(world, bodyTypeStatic, 0, -20, 0);
      box2d.gooShapeAddBox(floor, 0, 0, 200, 1, 0, 1, 0.6, 0, 1, allLayers, 0);

      final handles = calloc<Int64>(count);
      for (var i = 0; i < count; i++) {
        final x = (i % 40) * 1.5 - 30.0;
        final y = -18 + (i ~/ 40) * 1.5;
        handles[i] = box2d.gooBodyCreate(world, bodyTypeDynamic, x, y, 0);
        box2d.gooShapeAddBox(
          handles[i], 0, 0, 0.5, 0.5, 0, 1, 0.4, 0, 1, allLayers, 0,
        );
      }

      for (var i = 0; i < 150; i++) {
        box2d.gooWorldStep(world, dt, subSteps);
      }

      final out = calloc<Float>(count * 3);
      box2d.gooBodiesPullTransforms(handles, out, count);
      final result = <double>[for (var i = 0; i < count * 3; i++) out[i]];
      calloc
        ..free(out)
        ..free(handles);
      box2d.gooWorldDestroy(world);
      return result;
    }

    test('a threaded world reports its worker count', () {
      final world = box2d.gooWorldCreateThreaded(0, -gravity, 4);
      expect(box2d.gooWorldWorkerCount(world), 4);
      box2d.gooWorldDestroy(world);

      // One worker means no pool at all, which is exactly gooWorldCreate.
      final serial = box2d.gooWorldCreateThreaded(0, -gravity, 1);
      expect(box2d.gooWorldWorkerCount(serial), 1);
      box2d.gooWorldDestroy(serial);
    }, timeout: timeout);

    test('a threaded world steps at all', () {
      // The deadlock canary. If the pool dispatches solver tasks wrongly this
      // never returns, and the timeout above turns that into a failure.
      final world = box2d.gooWorldCreateThreaded(0, -gravity, 4);
      final ball = box2d.gooBodyCreate(world, bodyTypeDynamic, 0, 0, 0);
      box2d.gooShapeAddCircle(ball, 0, 0, 0.5, 1, 0.6, 0, 1, allLayers, 0);

      for (var i = 0; i < 60; i++) {
        box2d.gooWorldStep(world, dt, subSteps);
      }

      final out = calloc<Float>(3);
      box2d.gooBodyGetTransform(ball, out);
      final y = out[1];
      calloc.free(out);
      box2d.gooWorldDestroy(world);

      expect(
        y,
        closeTo(-0.5 * gravity, 0.2),
        reason: 'one second of free fall, threaded, is the same physics',
      );
    }, timeout: timeout);

    test('threaded and serial worlds settle a pile the same way', () {
      // Not bit-identical - Box2D's constraint graph is coloured differently
      // with more workers, so contact ordering differs and the arithmetic is
      // not associative. What must hold is that the pile ends up in the same
      // place, which is the thing a game cares about and the thing a broken
      // pool would destroy.
      const count = 400;
      final serial = settle(1, count);
      final threaded = settle(4, count);

      var worst = 0.0;
      for (var i = 0; i < count; i++) {
        final dx = (serial[i * 3] - threaded[i * 3]).abs();
        final dy = (serial[i * 3 + 1] - threaded[i * 3 + 1]).abs();
        if (dx > worst) worst = dx;
        if (dy > worst) worst = dy;
      }

      expect(
        worst,
        lessThan(1.0),
        reason: 'every body should be within a body-width of where the '
            'single-threaded world put it',
      );
      // And the pile is genuinely resting on the floor rather than both runs
      // agreeing on having fallen through it.
      for (var i = 0; i < count; i++) {
        expect(threaded[i * 3 + 1], greaterThan(-21));
      }
    }, timeout: timeout);
  });

  group('diagnostics', () {
    test('a body that comes to rest stops being awake', () {
      // The diagnostic that separates "this scene is heavy" from "this scene
      // is agitated". Both present as a large step time and they have
      // completely different fixes, so the count has to be observable - and
      // it has to be observed *falling*, not merely read, or a shim that
      // returned a constant would pass.
      final world = box2d.gooWorldCreate(0, -gravity);

      final floor = box2d.gooBodyCreate(world, bodyTypeStatic, 0, -10, 0);
      box2d.gooShapeAddBox(floor, 0, 0, 50, 1, 0, 1, 0.6, 0, 1, allLayers, 0);

      for (var i = 0; i < 8; i++) {
        final ball = box2d.gooBodyCreate(world, bodyTypeDynamic, i * 2.0, 0, 0);
        // Zero restitution: a bouncy body keeps its island awake, which is
        // exactly the effect this test would otherwise be measuring.
        box2d.gooShapeAddCircle(ball, 0, 0, 0.5, 1, 0.6, 0, 1, allLayers, 0);
      }

      box2d.gooWorldStep(world, dt, subSteps);
      final falling = box2d.gooWorldAwakeBodyCount(world);

      // Long enough to fall 9 m and for the sleep timer to expire.
      for (var i = 0; i < 400; i++) {
        box2d.gooWorldStep(world, dt, subSteps);
      }
      final resting = box2d.gooWorldAwakeBodyCount(world);

      final counters = calloc<Int32>(5);
      box2d.gooWorldCounters(world, counters, 5);
      final bodies = counters[0];
      final shapes = counters[1];
      calloc.free(counters);
      box2d.gooWorldDestroy(world);

      expect(falling, 8, reason: 'every dynamic body should start awake');
      expect(resting, 0, reason: 'a settled pile should sleep');
      // Static bodies count too - 8 balls and the floor.
      expect(bodies, 9);
      expect(shapes, 9);
    });
  });
}

// b2BodyType values, asserted to match in goo_box2d.c.
const int bodyTypeStatic = 0;
const int bodyTypeDynamic = 2;
