import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/physics/worker/direct/direct_joint_ops.dart';
import 'package:goo2d/src/physics/worker/data/joint_type.dart';
import 'package:goo2d/goo2d.dart';

/// Rigidly connects this body to [connectedBody] (or the world) at matching anchor points.
///
/// The joint tries to keep the two bodies at a fixed relative position and orientation.
/// [frequency] and [dampingRatio] introduce spring behavior — at the defaults of 0 the
/// connection is completely rigid. Increase [frequency] (Hz) to allow some oscillation and
/// [dampingRatio] (0–1) to control how quickly oscillations decay.
///
/// [anchor] is the local-space attachment point on this body.
/// [connectedAnchor] is the local-space point on the connected body (or in world space if
/// [connectedBody] is null). Set [autoConfigureConnectedAnchor] to have the engine compute it.
///
/// ```dart
/// // Bolt a crate to a moving platform
/// final platform = ...; // Rigidbody on another object
/// addComponent(
///   FixedJoint()
///     ..connectedBody = platform
///     ..frequency = 10.0
///     ..dampingRatio = 0.5,
/// );
/// ```
///
/// See also:
/// * [SpringJoint] for an explicit spring with a rest distance.
/// * [HingeJoint] to allow rotation around the anchor.
class FixedJoint extends Joint {
  @override
  int get jointType => JointType.fixed;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    worker.setJointProperty(handle, JointProp.anchor, _anchor.clone());
    worker.setJointProperty(handle, JointProp.connectedAnchor, _connectedAnchor.clone());
    worker.setJointProperty(handle, JointProp.autoConfigureConnectedAnchor, _autoConfigureConnectedAnchor);
    worker.setJointProperty(handle, JointProp.springFrequency, _frequency);
    worker.setJointProperty(handle, JointProp.springDampingRatio, _dampingRatio);
    worker.setJointProperty(handle, JointProp.angularOffset, _referenceAngle);
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

  /// When true, the engine sets [connectedAnchor] automatically at attach time. Default true.
  bool get autoConfigureConnectedAnchor => _autoConfigureConnectedAnchor;
  bool _autoConfigureConnectedAnchor = true;
  set autoConfigureConnectedAnchor(bool value) {
    _autoConfigureConnectedAnchor = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.autoConfigureConnectedAnchor, value);
  }

  /// Spring oscillation frequency in Hz. 0 = completely rigid. Default 0.0.
  double get frequency => _frequency;
  double _frequency = 0.0;
  set frequency(double value) {
    _frequency = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.springFrequency, value);
  }

  /// Damping ratio for the spring (0 = no damping, 1 = critically damped). Default 0.0.
  double get dampingRatio => _dampingRatio;
  double _dampingRatio = 0.0;
  set dampingRatio(double value) {
    _dampingRatio = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.springDampingRatio, value);
  }

  /// Target angle offset between the two bodies in radians. Default 0.0.
  double get referenceAngle => _referenceAngle;
  double _referenceAngle = 0.0;
  set referenceAngle(double value) {
    _referenceAngle = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.angularOffset, value);
  }
}
