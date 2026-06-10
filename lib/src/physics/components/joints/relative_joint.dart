import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/physics/worker/direct/direct_joint_ops.dart';
import 'package:goo2d/src/physics/worker/data/joint_type.dart';
import 'package:goo2d/goo2d.dart';

/// Drives two bodies to maintain a fixed relative position and orientation without anchors.
///
/// Unlike [FixedJoint], this joint corrects position via forces rather than constraint equations,
/// which makes it softer and avoids the positional drift correction snapping common in stiff solvers.
/// [linearOffset] is the desired offset in the space of [connectedBody]. [angularOffset] is
/// the desired angle difference in radians. [correctionScale] (0–1) controls how aggressively
/// the joint corrects each step; [maxForce] and [maxTorque] cap correction.
///
/// ```dart
/// addComponent(
///   RelativeJoint()
///     ..connectedBody = leaderBody
///     ..linearOffset = Vector2(0, 1)  // stay 1 unit above the leader
///     ..correctionScale = 0.5,
/// );
/// ```
///
/// See also:
/// * [FixedJoint] for a rigid constraint based on anchor matching.
class RelativeJoint extends Joint {
  @override
  int get jointType => JointType.relative;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    worker.setJointProperty(handle, JointProp.linearOffset, _linearOffset.clone());
    worker.setJointProperty(handle, JointProp.angularOffset, _angularOffset);
    worker.setJointProperty(handle, JointProp.correctionScale, _correctionScale);
    worker.setJointProperty(handle, JointProp.autoConfigureOffset, _autoConfigureOffset);
    worker.setJointProperty(handle, JointProp.maxForce, _maxForce);
    worker.setJointProperty(handle, JointProp.maxTorque, _maxTorque);
  }

  /// Desired positional offset in [connectedBody]'s local space. Default `Vector2.zero()`.
  Vector2 get linearOffset => _linearOffset;
  final Vector2 _linearOffset = Vector2.zero();
  set linearOffset(Vector2 value) {
    _linearOffset.setFrom(value);
    if (isAttached) worker.setJointProperty(handle, JointProp.linearOffset, value.clone());
  }

  /// Desired angular offset in radians. Default 0.0.
  double get angularOffset => _angularOffset;
  double _angularOffset = 0.0;
  set angularOffset(double value) {
    _angularOffset = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.angularOffset, value);
  }

  /// Fraction of the positional/angular error corrected per step (0–1). Default 0.3.
  double get correctionScale => _correctionScale;
  double _correctionScale = 0.3;
  set correctionScale(double value) {
    _correctionScale = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.correctionScale, value);
  }

  /// When true, the engine measures and sets [linearOffset] and [angularOffset] at attach time. Default true.
  bool get autoConfigureOffset => _autoConfigureOffset;
  bool _autoConfigureOffset = true;
  set autoConfigureOffset(bool value) {
    _autoConfigureOffset = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.autoConfigureOffset, value);
  }

  /// Maximum correction force (N) per step. Default 1000.0.
  double get maxForce => _maxForce;
  double _maxForce = 1000.0;
  set maxForce(double value) {
    _maxForce = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.maxForce, value);
  }

  /// Maximum correction torque (N·m) per step. Default 1000.0.
  double get maxTorque => _maxTorque;
  double _maxTorque = 1000.0;
  set maxTorque(double value) {
    _maxTorque = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.maxTorque, value);
  }

  /// Current world-space target position derived from [connectedBody] and [linearOffset].
  Future<Vector2> get target async => (await worker.getJointProperty(handle, JointProp.target)) as Vector2;
}
