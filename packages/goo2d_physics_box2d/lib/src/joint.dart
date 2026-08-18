import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:goo2d_ffi_box2d/goo2d_ffi_box2d.dart';

/// A joint, as a type rather than a bare `int`.
///
/// # Why an extension type
///
/// It **is** an int at runtime - the packed `b2JointId` - so this costs
/// nothing: no allocation, no wrapper object, no indirection, and it still
/// travels through a `List<Joint>` as a tagged integer. What it buys is that
/// a joint handle can no longer be passed where a body handle, an entity or a
/// count was meant, which the previous `int` return type allowed silently.
///
/// The methods live here rather than on `Box2DPhysicsSystem` because none of
/// them need the system: every shim entry point takes the handle and nothing
/// else. `physics.destroyJoint(j)` was only ever a function looking for its
/// receiver.
///
/// # Lifetime
///
/// **Box2D destroys a joint when either of its bodies is destroyed**, so a
/// handle goes stale on its own without anything here being told. Every
/// method is a no-op on a stale or [none] handle rather than a crash - which
/// matters more than usual, because reaching into freed Box2D memory kills
/// the process with no Dart exception at all.
extension type const Joint(int handle) {
  /// The absent joint. Returned by every `create*Joint` that could not make
  /// one - usually because a body did not exist yet.
  static const Joint none = Joint(0);

  /// Whether this still names a live joint.
  bool get exists => handle != 0 && box2d.gooJointIsValid(handle) != 0;

  /// Removes the joint. Safe on a handle whose bodies have already gone, and
  /// safe to call twice.
  void destroy() => box2d.gooJointDestroy(handle);

  /// Drives the joint under power. [speed] is rad/s for a revolute joint and
  /// m/s for a distance one; [maxEffort] is the torque or force the motor may
  /// spend reaching it.
  ///
  /// **A motor with zero [maxEffort] does nothing**, which looks exactly like
  /// the joint being broken. There is no default for it on purpose.
  void setMotor({bool enable = true, double speed = 0, double maxEffort = 0}) =>
      box2d.gooJointSetMotor(handle, enable ? 1 : 0, speed, maxEffort);

  /// Moves a mouse joint's world-space target. A no-op on any other joint
  /// type, so a caller cannot silently steer the wrong thing.
  void moveTarget(double x, double y) =>
      box2d.gooJointSetMouseTarget(handle, x, y);

  /// Reads how hard this joint is pulling, returning the torque in newton
  /// metres and leaving the force in [forceX] and [forceY].
  ///
  /// This is what a **breakable** joint is made of - Box2D has no breaking of
  /// its own, so a game compares this against a threshold each tick and calls
  /// [destroy] when it is exceeded.
  ///
  /// The force lands in static fields rather than a returned record because a
  /// breakable joint reads this every tick for every joint it watches, and a
  /// record there would allocate on exactly that path (the no-allocation rule).
  /// They are valid only until the next call, which is the same contract the
  /// raycast results carry.
  double readReaction() {
    final out = _reaction ??= calloc<Float>(2);
    final torque = box2d.gooJointGetReaction(handle, out);
    forceX = out[0];
    forceY = out[1];
    return torque;
  }

  /// The force from the last [readReaction], in newtons.
  static double forceX = 0;
  static double forceY = 0;

  /// Scratch for [readReaction]. One allocation for the whole process, not
  /// one per call.
  static Pointer<Float>? _reaction;
}
