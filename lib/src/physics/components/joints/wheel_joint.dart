import 'dart:math' as math;
import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/physics/worker/direct/direct_joint_ops.dart';
import 'package:goo2d/src/physics/worker/direct/direct_body_ops.dart';
import 'package:goo2d/src/physics/worker/data/joint_type.dart';
import 'package:goo2d/goo2d.dart';

/// Combines a spring-damper suspension axis with a free rotation pivot — suitable for vehicle wheels.
///
/// The body can rotate freely around [anchor], while also translating along the suspension axis
/// with a spring governed by [JointSuspension.frequency] and [JointSuspension.dampingRatio].
/// [suspension.angle] sets the axis direction in degrees (90 = vertical suspension).
/// An optional [motor] drives rotation at a target speed (e.g. a wheel spinning).
///
/// ```dart
/// addComponent(
///   WheelJoint()
///     ..connectedBody = chassisBody
///     ..useMotor = true
///     ..motor = JointMotor(motorSpeed: 300, maxMotorTorque: 50)
///     ..suspension = JointSuspension(frequency: 4.0, dampingRatio: 0.7, angle: 90),
/// );
/// ```
///
/// See also:
/// * [HingeJoint] for a pure pivot with no translation.
/// * [SliderJoint] for a pure translation axis with no rotation.
class WheelJoint extends Joint {
  @override
  int get jointType => JointType.wheel;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    worker.setJointProperty(handle, JointProp.anchor, _anchor.clone());
    worker.setJointProperty(handle, JointProp.connectedAnchor, _connectedAnchor.clone());
    worker.setJointProperty(handle, JointProp.autoConfigureConnectedAnchor, _autoConfigureConnectedAnchor);
    worker.setJointProperty(handle, JointProp.useMotor, _useMotor);
    worker.setJointProperty(handle, JointProp.motorSpeed, _motorSpeed);
    worker.setJointProperty(handle, JointProp.maxMotorTorque, _maxMotorTorque);
    worker.setJointProperty(handle, JointProp.springDampingRatio, _dampingRatio);
    worker.setJointProperty(handle, JointProp.springFrequency, _frequency);
    worker.setJointProperty(handle, JointProp.wheelSuspensionAngle, _suspensionAngle);
  }

  /// Local-space wheel attachment point on this body. Default `Vector2.zero()`.
  Vector2 get anchor => _anchor;
  final Vector2 _anchor = Vector2.zero();
  set anchor(Vector2 value) {
    _anchor.setFrom(value);
    if (isAttached) worker.setJointProperty(handle, JointProp.anchor, value.clone());
  }

  /// Local-space attachment point on the chassis body (or world-space if no body is connected).
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

  /// When true, the motor applies torque to spin the wheel. Default false.
  bool get useMotor => _useMotor;
  bool _useMotor = false;
  set useMotor(bool value) {
    _useMotor = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.useMotor, value);
  }

  double _motorSpeed = 0.0;
  double _maxMotorTorque = 10000.0;

  /// Target spin speed (deg/s) and torque cap (N·m). Active when [useMotor] is true.
  JointMotor get motor => JointMotor(motorSpeed: _motorSpeed, maxMotorTorque: _maxMotorTorque);
  set motor(JointMotor value) {
    _motorSpeed = value.motorSpeed;
    _maxMotorTorque = value.maxMotorTorque;
    if (isAttached) {
      worker.setJointProperty(handle, JointProp.motorSpeed, value.motorSpeed);
      worker.setJointProperty(handle, JointProp.maxMotorTorque, value.maxMotorTorque);
    }
  }

  double _dampingRatio = 0.7;
  double _frequency = 2.0;
  double _suspensionAngle = 90.0;

  /// Spring suspension settings: oscillation [frequency] (Hz), [dampingRatio], and axis [angle] (degrees).
  JointSuspension get suspension => JointSuspension(frequency: _frequency, angle: _suspensionAngle, dampingRatio: _dampingRatio);
  set suspension(JointSuspension value) {
    _dampingRatio = value.dampingRatio;
    _frequency = value.frequency;
    _suspensionAngle = value.angle;
    if (isAttached) {
      worker.setJointProperty(handle, JointProp.springDampingRatio, value.dampingRatio);
      worker.setJointProperty(handle, JointProp.springFrequency, value.frequency);
      worker.setJointProperty(handle, JointProp.wheelSuspensionAngle, value.angle);
    }
  }

  Future<double> get jointSpeed async =>
      (await worker.getJointProperty(handle, JointProp.motorSpeed)) as double;

  Future<double> get jointTranslation async =>
      (await worker.getJointProperty(handle, JointProp.lowerTranslation)) as double;

  Future<double> get jointAngle async {
    if (connectedBody == null) return 0.0;
    final rb = gameObject.getComponent<Rigidbody>();
    final rotA = (await worker.getBodyProperty(rb.handle, BodyProp.rotation)) as double;
    final rotB = (await worker.getBodyProperty(connectedBody!.handle, BodyProp.rotation)) as double;
    return rotB - rotA;
  }

  Future<double> get jointLinearSpeed async {
    if (connectedBody == null) return 0.0;
    final rb = gameObject.getComponent<Rigidbody>();
    final velA = (await worker.getBodyProperty(rb.handle, BodyProp.linearVelocity)) as Vector2;
    final velB = (await worker.getBodyProperty(connectedBody!.handle, BodyProp.linearVelocity)) as Vector2;
    final relVel = velB - velA;
    final rad = _suspensionAngle * math.pi / 180.0;
    final axis = Vector2(math.cos(rad), math.sin(rad));
    return relVel.dot(axis);
  }

  Future<double> getMotorTorque(double timeStep) async =>
      (await worker.getJointProperty(handle, JointProp.reactionTorque)) as double;
}
