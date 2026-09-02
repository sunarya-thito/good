import 'dart:math' as math;

import 'package:goo2d/goo2d.dart';

import 'physics_system.dart';
import 'rigid_body.dart';

/// Unity's Effector 2D family, as functions - the primitive layer.
///
/// # These are the primitive; `effector.dart` is the API most games want
///
/// Each function finds bodies in a region and applies a force, right now,
/// against explicit world-space coordinates. That is the right shape for a
/// one-shot - an explosion, a shockwave - or for a region computed from
/// gameplay state that no entity owns.
///
/// For a *standing* effector, declare one instead: see `Effector2D` and
/// `AreaEffector.of` in `effector.dart`. The region lives on the entity's own
/// collider, so it travels with the entity, every knob becomes a per-entity
/// field, and `Box2DPhysicsSystem` walks it before its own step - so the
/// `compareTo` below stops being something each game has to get right.
///
/// Two overlapping zones need no ordering rule either way: forces accumulate,
/// and addition is commutative.
///
/// # Calling these directly: from a fixed step, before physics
///
/// A force applied outside a tick window is discarded, and one applied after
/// `Box2DPhysicsSystem` has run lands a step late. Give the calling system a
/// `compareTo` that sorts it before the physics system.
///
/// Each call also names the scene to search - the handle `loadScene` returned.
/// There is no default, because a query that fell back to the one loaded scene
/// would search the wrong world the day a HUD loads.
///
/// ```dart
/// class Shockwave extends GameSystem with FixedTickable {
///   late Scene arena;
///
///   @override
///   int compareTo(GameSystem other) =>
///       other is Box2DPhysicsSystem ? -1 : 0;
///
///   @override
///   void onFixedUpdate() {
///     getSystem<Box2DPhysicsSystem>().areaEffector(
///       arena, -20, -20, 20, 0, forceX: 30,
///     );
///   }
/// }
/// ```
///
/// # What each one is
///
/// | Unity | function | declared |
/// |---|---|---|
/// | Area Effector 2D | [Effectors2D.areaEffector] | `AreaEffector` |
/// | Point Effector 2D | [Effectors2D.pointEffector] | `PointEffector` |
/// | Buoyancy Effector 2D | [Effectors2D.buoyancyEffector] | `BuoyancyEffector` |
/// | Surface Effector 2D | [Effectors2D.surfaceEffector] | `SurfaceEffector` |
/// | Platform Effector 2D | **not here** - see below | - |
///
/// **Platform Effector 2D is not here.** A one-way platform has to reject a
/// contact *during* the solve, based on which way the body is travelling, and
/// Box2D v3 resolves contacts inside `b2World_Step` with no callback out.
/// Faking it from outside - disabling the shape when something approaches
/// from below - changes behaviour a frame late and lets a fast body through.
/// It needs shim support that does not exist yet, and a broken one-way
/// platform is worse than an absent one.
extension Effectors2D on Box2DPhysicsSystem {
  /// A uniform force on every body overlapping a box - Unity's Area Effector
  /// 2D. Wind, currents, updraughts.
  ///
  /// The region is a **broad-phase AABB**, so a body near a corner can be
  /// caught without truly overlapping. That is the useful primitive for a
  /// force field, where an exact boundary is not something a player can see.
  ///
  /// Returns how many bodies were affected, which is the cheapest way to tell
  /// a mis-placed region from a mis-scaled force.
  int areaEffector(
    Scene scene,
    double minX,
    double minY,
    double maxX,
    double maxY, {
    double forceX = 0,
    double forceY = 0,
    double torque = 0,
    int layerMask = -1,
    int maxBodies = 256,
  }) {
    final found = overlapBox(
      scene,
      minX,
      minY,
      maxX,
      maxY,
      layerMask: layerMask,
      maxResults: maxBodies,
    );
    var affected = 0;
    for (var i = 0; i < found; i++) {
      final entity = overlapEntityAt(i);
      if (!entity.has<RigidBody2D>()) continue;
      final body = entity<RigidBody2D>().component;
      if (forceX != 0 || forceY != 0) body.applyForce(entity, forceX, forceY);
      if (torque != 0) body.applyTorque(entity, torque);
      affected++;
    }
    return affected;
  }

  /// Attraction or repulsion about a point - Unity's Point Effector 2D.
  /// Explosions, magnets, gravity wells.
  ///
  /// A **positive** [force] pushes away and a negative one pulls in, matching
  /// Unity. [radius] bounds both the region searched and the falloff.
  ///
  /// [falloff] divides the force by the distance, which is what makes an
  /// explosion feel local instead of uniform. The force is never divided by a
  /// distance below [minDistance]: at the exact centre the direction is
  /// undefined and the magnitude infinite, and games that skip that guard
  /// launch anything spawned on top of the effector into orbit.
  int pointEffector(
    Scene scene,
    double x,
    double y, {
    required double radius,
    required double force,
    bool falloff = true,
    double minDistance = 0.5,
    int layerMask = -1,
    int maxBodies = 256,
  }) {
    final found = overlapBox(
      scene,
      x - radius,
      y - radius,
      x + radius,
      y + radius,
      layerMask: layerMask,
      maxResults: maxBodies,
    );
    var affected = 0;
    for (var i = 0; i < found; i++) {
      final entity = overlapEntityAt(i);
      if (!entity.has<RigidBody2D>() || !entity.has<Transform2D>()) continue;
      final body = entity<RigidBody2D>().component;
      final transform = entity<Transform2D>().component;

      final dx = transform.transformOffsetX[entity] - x;
      final dy = transform.transformOffsetY[entity] - y;
      final distance = _length(dx, dy);
      // The AABB is square and the region is a circle, so the corners have to
      // be rejected here - otherwise an explosion reaches 41% further on the
      // diagonal than the radius it was given.
      if (distance > radius) continue;

      final safe = distance < minDistance ? minDistance : distance;
      final scale = (falloff ? force / safe : force) / safe;
      body.applyForce(entity, dx * scale, dy * scale);
      affected++;
    }
    return affected;
  }

  /// Buoyancy and drag below a surface line - Unity's Buoyancy Effector 2D.
  /// Water, lava, anything a body floats in.
  ///
  /// [surfaceY] is the waterline; **anything at a smaller y is submerged**,
  /// because goo2d's +y is up. A body's depth drives the lift, so it bobs
  /// and settles instead of being pushed with a constant force.
  ///
  /// [density] is the *fluid's*, against the body's own: below 1 the body
  /// sinks, above it floats. [linearDrag] and [angularDrag] are what stop it
  /// oscillating forever, and a buoyancy effector without them is a spring.
  int buoyancyEffector(
    Scene scene,
    double minX,
    double maxX, {
    required double surfaceY,
    double depth = 100,
    double density = 2,
    double linearDrag = 1,
    double angularDrag = 1,
    double gravityY = -10,
    int layerMask = -1,
    int maxBodies = 256,
  }) {
    // The fluid volume hangs *below* the waterline, so `surfaceY` is the box's
    // maximum y and not its minimum - overlapBox wants them in that order.
    final found = overlapBox(
      scene,
      minX,
      surfaceY - depth,
      maxX,
      surfaceY,
      layerMask: layerMask,
      maxResults: maxBodies,
    );
    var affected = 0;
    for (var i = 0; i < found; i++) {
      final entity = overlapEntityAt(i);
      if (!entity.has<RigidBody2D>() || !entity.has<Transform2D>()) continue;
      final body = entity<RigidBody2D>().component;
      final transform = entity<Transform2D>().component;

      final submerged = surfaceY - transform.transformOffsetY[entity];
      if (submerged <= 0) continue;

      // Lift proportional to depth, capped at one body-depth so a body deep
      // under the surface is not fired out like a cork - Unity's effector
      // behaves the same way, and the cap is what makes it settle.
      final scale = submerged > 1 ? 1.0 : submerged;
      body
        // Against gravity, whichever way that points: with the default
        // [gravityY] of -10 this is a positive (upward) force.
        ..applyForce(entity, 0, -density * gravityY * scale)
        ..applyForce(
          entity,
          -body.bodyLinearVelocityX[entity] * linearDrag,
          -body.bodyLinearVelocityY[entity] * linearDrag,
        )
        ..applyTorque(entity, -body.bodyAngularVelocity[entity] * angularDrag);
      affected++;
    }
    return affected;
  }

  /// Drags bodies along a surface at a fixed speed - Unity's Surface Effector
  /// 2D. Conveyor belts, moving walkways, treadmills.
  ///
  /// Implemented as a force towards [speed] and not by setting velocity,
  /// so a body can still be pushed against the belt, stack on other bodies,
  /// and be thrown off the end. Setting velocity directly would make the belt
  /// win every argument, which is the usual way this gets built and the usual
  /// reason it feels wrong.
  int surfaceEffector(
    Scene scene,
    double minX,
    double minY,
    double maxX,
    double maxY, {
    required double speed,
    double speedY = 0,
    double force = 20,
    int layerMask = -1,
    int maxBodies = 256,
  }) {
    final found = overlapBox(
      scene,
      minX,
      minY,
      maxX,
      maxY,
      layerMask: layerMask,
      maxResults: maxBodies,
    );
    var affected = 0;
    for (var i = 0; i < found; i++) {
      final entity = overlapEntityAt(i);
      if (!entity.has<RigidBody2D>()) continue;
      final body = entity<RigidBody2D>().component;

      final dvx = speed - body.bodyLinearVelocityX[entity];
      final dvy = speedY - body.bodyLinearVelocityY[entity];
      body.applyForce(entity, dvx * force, dvy * force);
      affected++;
    }
    return affected;
  }
}

double _length(double x, double y) => math.sqrt(x * x + y * y);
