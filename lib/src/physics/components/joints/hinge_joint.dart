import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/physics/components/joint.dart';
import 'package:goo2d/src/physics/worker/direct/direct_joint_ops.dart';
import 'package:goo2d/src/physics/worker/data/joint_type.dart';
import 'package:goo2d/goo2d.dart';

/// Constrains this body to rotate around a single pivot point, optionally with limits and a motor.
///
/// Rotation is free by default. Set [useLimits] to true and assign a [JointAngleLimits] to [limits]
/// to clamp the rotation range. Set [useMotor] to true and assign a [JointMotor] to [motor] to
/// drive the rotation at a target speed.
///
/// Typical uses: door hinges, windmills, rotating platforms, ragdoll limb joints.
///
/// ```dart
/// addComponent(
///   HingeJoint()
///     ..connectedBody = wallBody
///     ..useLimits = true
///     ..limits = JointAngleLimits(min: -45, max: 45),
/// );
/// ```
///
/// See also:
/// * [SliderJoint] to constrain along a line instead of a pivot.
/// * [WheelJoint] for combined rotation + spring suspension.
class HingeJoint extends Joint {
  @override
  int get jointType => JointType.hinge;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    worker.setJointProperty(handle, JointProp.anchor, _anchor.clone());
    worker.setJointProperty(handle, JointProp.connectedAnchor, _connectedAnchor.clone());
    worker.setJointProperty(handle, JointProp.autoConfigureConnectedAnchor, _autoConfigureConnectedAnchor);
    worker.setJointProperty(handle, JointProp.useLimits, _useLimits);
    worker.setJointProperty(handle, JointProp.lowerAngle, _lowerAngle);
    worker.setJointProperty(handle, JointProp.upperAngle, _upperAngle);
    worker.setJointProperty(handle, JointProp.useMotor, _useMotor);
    worker.setJointProperty(handle, JointProp.motorSpeed, _motorSpeed);
    worker.setJointProperty(handle, JointProp.maxMotorTorque, _maxMotorTorque);
    worker.setJointProperty(handle, JointProp.angularOffset, _referenceAngle);
  }

  /// Local-space pivot point on this body. Default `Vector2.zero()`.
  Vector2 get anchor => _anchor;
  final Vector2 _anchor = Vector2.zero();
  set anchor(Vector2 value) {
    _anchor.setFrom(value);
    if (isAttached) worker.setJointProperty(handle, JointProp.anchor, value.clone());
  }

  /// Local-space pivot point on [connectedBody], or world-space if no body is connected.
  Vector2 get connectedAnchor => _connectedAnchor;
  final Vector2 _connectedAnchor = Vector2.zero();
  set connectedAnchor(Vector2 value) {
    _connectedAnchor.setFrom(value);
    if (isAttached) worker.setJointProperty(handle, JointProp.connectedAnchor, value.clone());
  }

  /// When true, the engine sets [connectedAnchor] automatically. Default true.
  bool get autoConfigureConnectedAnchor => _autoConfigureConnectedAnchor;
  bool _autoConfigureConnectedAnchor = true;
  set autoConfigureConnectedAnchor(bool value) {
    _autoConfigureConnectedAnchor = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.autoConfigureConnectedAnchor, value);
  }

  bool useConnectedAnchor = true;

  /// When true, rotation is clamped to the range defined by [limits]. Default false.
  bool get useLimits => _useLimits;
  bool _useLimits = false;
  set useLimits(bool value) {
    _useLimits = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.useLimits, value);
  }

  double _lowerAngle = 0.0;
  double _upperAngle = 360.0;

  /// Minimum and maximum rotation angles in degrees. Active when [useLimits] is true.
  JointAngleLimits get limits => JointAngleLimits(min: _lowerAngle, max: _upperAngle);
  set limits(JointAngleLimits value) {
    _lowerAngle = value.min;
    _upperAngle = value.max;
    if (isAttached) {
      worker.setJointProperty(handle, JointProp.lowerAngle, value.min);
      worker.setJointProperty(handle, JointProp.upperAngle, value.max);
    }
  }

  /// When true, the motor drives rotation toward [motor.motorSpeed]. Default false.
  bool get useMotor => _useMotor;
  bool _useMotor = false;
  set useMotor(bool value) {
    _useMotor = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.useMotor, value);
  }

  double _motorSpeed = 0.0;
  double _maxMotorTorque = 10000.0;

  /// Target rotation speed (deg/s) and torque cap (N·m). Active when [useMotor] is true.
  JointMotor get motor => JointMotor(motorSpeed: _motorSpeed, maxMotorTorque: _maxMotorTorque);
  set motor(JointMotor value) {
    _motorSpeed = value.motorSpeed;
    _maxMotorTorque = value.maxMotorTorque;
    if (isAttached) {
      worker.setJointProperty(handle, JointProp.motorSpeed, value.motorSpeed);
      worker.setJointProperty(handle, JointProp.maxMotorTorque, value.maxMotorTorque);
    }
  }

  /// Initial angular offset between the two bodies at rest, in radians. Default 0.0.
  double get referenceAngle => _referenceAngle;
  double _referenceAngle = 0.0;
  set referenceAngle(double value) {
    _referenceAngle = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.angularOffset, value);
  }

  /// Current limit enforcement state (at lower bound, upper bound, or inactive).
  JointLimitState get limitState => JointLimitState.inactive;

  /// Returns the torque the motor is currently applying, scaled by [timeStep].
  Future<double> getMotorTorque(double timeStep) async =>
      (await worker.getJointProperty(handle, JointProp.reactionTorque)) as double;

  /// Current angular velocity of the joint in deg/s.
  Future<double> get jointSpeed async =>
      (await worker.getJointProperty(handle, JointProp.motorSpeed)) as double;

  /// Current rotation angle of this body relative to [connectedBody], in radians.
  Future<double> get jointAngle async =>
      (await worker.getJointProperty(handle, JointProp.lowerAngle)) as double;
}
