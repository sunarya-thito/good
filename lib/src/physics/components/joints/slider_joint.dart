import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/physics/worker/direct/direct_joint_ops.dart';
import 'package:goo2d/src/physics/worker/data/joint_type.dart';
import 'package:goo2d/goo2d.dart';

/// Constrains this body to slide along a single axis defined by [angle], optionally with limits and a motor.
///
/// The body can translate along the axis but cannot rotate or move perpendicular to it.
/// Set [useLimits] = true and assign [limits] to clamp the travel range in world units.
/// Set [useMotor] = true and assign [motor] to drive the body along the axis at a target speed.
///
/// Typical uses: elevators, sliding doors, pistons.
///
/// ```dart
/// addComponent(
///   SliderJoint()
///     ..connectedBody = frameBody
///     ..angle = 90.0  // slide vertically
///     ..useLimits = true
///     ..limits = JointTranslationLimits(min: 0, max: 5),
/// );
/// ```
///
/// See also:
/// * [HingeJoint] to rotate around a pivot instead of sliding.
/// * [WheelJoint] for suspension combined with rotation.
class SliderJoint extends Joint {
  @override
  int get jointType => JointType.slider;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    worker.setJointProperty(handle, JointProp.anchor, _anchor.clone());
    worker.setJointProperty(handle, JointProp.connectedAnchor, _connectedAnchor.clone());
    worker.setJointProperty(handle, JointProp.autoConfigureConnectedAnchor, _autoConfigureConnectedAnchor);
    worker.setJointProperty(handle, JointProp.useTranslationLimits, _useLimits);
    worker.setJointProperty(handle, JointProp.useMotor, _useMotor);
    worker.setJointProperty(handle, JointProp.sliderAngle, _angle);
    worker.setJointProperty(handle, JointProp.autoConfigureAngle, _autoConfigureAngle);
  }

  /// Local-space attachment point on this body. Default `Vector2.zero()`.
  Vector2 get anchor => _anchor;
  final Vector2 _anchor = Vector2.zero();
  set anchor(Vector2 value) {
    _anchor.setFrom(value);
    if (isAttached) worker.setJointProperty(handle, JointProp.anchor, value.clone());
  }

  /// Local-space attachment point on [connectedBody], or world-space if no body is connected.
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

  /// When true, the motor drives translation along the axis. Default false.
  bool get useMotor => _useMotor;
  bool _useMotor = false;
  set useMotor(bool value) {
    _useMotor = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.useMotor, value);
  }

  /// Axis angle in degrees along which sliding is permitted. 0 = horizontal. Default 0.0.
  double get angle => _angle;
  double _angle = 0.0;
  set angle(double value) {
    _angle = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.sliderAngle, value);
  }

  /// When true, the body cannot slide outside the range defined by [limits]. Default false.
  bool get useLimits => _useLimits;
  bool _useLimits = false;
  set useLimits(bool value) {
    _useLimits = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.useTranslationLimits, value);
  }

  /// When true, the engine derives [angle] from the current body positions at attach time. Default true.
  bool get autoConfigureAngle => _autoConfigureAngle;
  bool _autoConfigureAngle = true;
  set autoConfigureAngle(bool value) {
    _autoConfigureAngle = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.autoConfigureAngle, value);
  }

  double _motorSpeed = 0.0;
  double _maxMotorTorque = 10000.0;
  double _lowerTranslation = 0.0;
  double _upperTranslation = 0.0;

  /// Target speed (world units/s) and force cap (N) for the linear motor. Active when [useMotor] is true.
  JointMotor get motor => JointMotor(motorSpeed: _motorSpeed, maxMotorTorque: _maxMotorTorque);
  set motor(JointMotor value) {
    _motorSpeed = value.motorSpeed;
    _maxMotorTorque = value.maxMotorTorque;
    if (isAttached) {
      worker.setJointProperty(handle, JointProp.motorSpeed, value.motorSpeed);
      worker.setJointProperty(handle, JointProp.maxMotorTorque, value.maxMotorTorque);
    }
  }

  /// Minimum and maximum travel in world units. Active when [useLimits] is true.
  JointTranslationLimits get limits => JointTranslationLimits(min: _lowerTranslation, max: _upperTranslation);
  set limits(JointTranslationLimits value) {
    _lowerTranslation = value.min;
    _upperTranslation = value.max;
    if (isAttached) {
      worker.setJointProperty(handle, JointProp.lowerTranslation, value.min);
      worker.setJointProperty(handle, JointProp.upperTranslation, value.max);
    }
  }

  JointLimitState get limitState => JointLimitState.inactive;

  Future<double> get jointTranslation async =>
      (await worker.getJointProperty(handle, JointProp.lowerTranslation)) as double;

  Future<double> get jointSpeed async =>
      (await worker.getJointProperty(handle, JointProp.motorSpeed)) as double;

  double get referenceAngle => _angle;

  Future<double> getMotorForce(double timeStep) async {
    final raw = (await worker.getJointProperty(handle, JointProp.reactionForce)) as Vector2;
    return timeStep > 0 ? raw.length / timeStep : 0.0;
  }
}
