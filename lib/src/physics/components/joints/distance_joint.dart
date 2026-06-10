import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/physics/worker/direct/direct_joint_ops.dart';
import 'package:goo2d/src/physics/worker/data/joint_type.dart';
import 'package:goo2d/goo2d.dart';

/// Constrains two bodies so their anchor points stay a fixed [distance] apart.
///
/// By default, [maxDistanceOnly] is false, meaning the constraint acts as a rigid rod.
/// Set [maxDistanceOnly] to true to make it behave like a rope: the bodies can come closer
/// but cannot exceed [distance]. Set [autoConfigureDistance] to have the engine measure the
/// initial distance at attach time.
///
/// ```dart
/// // Pendulum: pin a ball to a ceiling anchor
/// addComponent(
///   DistanceJoint()
///     ..connectedBody = ceilingBody
///     ..distance = 3.0
///     ..maxDistanceOnly = false,
/// );
/// ```
///
/// See also:
/// * [SpringJoint] to add oscillation to a distance constraint.
/// * [FixedJoint] to lock both position and rotation.
class DistanceJoint extends Joint {
  @override
  int get jointType => JointType.distance;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    worker.setJointProperty(handle, JointProp.anchor, _anchor.clone());
    worker.setJointProperty(handle, JointProp.connectedAnchor, _connectedAnchor.clone());
    worker.setJointProperty(handle, JointProp.autoConfigureConnectedAnchor, _autoConfigureConnectedAnchor);
    worker.setJointProperty(handle, JointProp.distance, _distance);
    worker.setJointProperty(handle, JointProp.autoConfigureDistance, _autoConfigureDistance);
    worker.setJointProperty(handle, JointProp.maxDistanceOnly, _maxDistanceOnly ? 1.0 : 0.0);
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

  /// When true, the engine measures and sets [distance] at attach time. Default true.
  bool get autoConfigureDistance => _autoConfigureDistance;
  bool _autoConfigureDistance = true;
  set autoConfigureDistance(bool value) {
    _autoConfigureDistance = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.autoConfigureDistance, value);
  }

  /// When true, the joint acts as a rope (pushes apart is not constrained). Default false.
  bool get maxDistanceOnly => _maxDistanceOnly;
  bool _maxDistanceOnly = false;
  set maxDistanceOnly(bool value) {
    _maxDistanceOnly = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.maxDistanceOnly, value ? 1.0 : 0.0);
  }

  /// Required separation between the two anchor points in world units. Default 1.0.
  double get distance => _distance;
  double _distance = 1.0;
  set distance(double value) {
    _distance = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.distance, value);
  }
}
