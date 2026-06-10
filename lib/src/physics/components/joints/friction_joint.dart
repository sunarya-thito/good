import 'package:meta/meta.dart';
import 'package:goo2d/src/physics/worker/direct/direct_joint_ops.dart';
import 'package:goo2d/goo2d.dart';

/// Applies damping forces to slow both the linear and angular velocity of the connected bodies toward zero.
///
/// Unlike a collision's friction, this joint acts as a persistent drag source — useful for
/// simulating sliding friction on a surface, a pivot with resistance, or a damped joint.
/// [maxForce] caps the linear damping force (N) and [maxTorque] caps the angular (N·m).
///
/// ```dart
/// addComponent(
///   FrictionJoint()
///     ..connectedBody = groundBody
///     ..maxForce = 30.0
///     ..maxTorque = 5.0,
/// );
/// ```
///
/// See also:
/// * [HingeJoint] with a motor for explicit speed control.
class FrictionJoint extends Joint {
  @override
  int get jointType => 2;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    worker.setJointProperty(handle, JointProp.maxForce, _maxForce);
    worker.setJointProperty(handle, JointProp.maxTorque, _maxTorque);
  }

  /// Maximum damping force (N) applied to slow linear velocity. Default 0.
  double get maxForce => _maxForce;
  double _maxForce = 0;
  set maxForce(double value) {
    _maxForce = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.maxForce, value);
  }

  /// Maximum damping torque (N·m) applied to slow angular velocity. Default 0.
  double get maxTorque => _maxTorque;
  double _maxTorque = 0;
  set maxTorque(double value) {
    _maxTorque = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.maxTorque, value);
  }
}
