import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/physics/worker/direct/direct_joint_ops.dart';
import 'package:goo2d/src/physics/worker/data/joint_type.dart';
import 'package:goo2d/goo2d.dart';

/// Connects two bodies with a spring that oscillates around a rest [distance].
///
/// The spring pulls the bodies together when they are further than [distance] apart, and
/// pushes them apart when they are closer. [frequency] (Hz) controls oscillation speed;
/// [dampingRatio] (0–1) controls how quickly oscillation decays.
///
/// ```dart
/// addComponent(
///   SpringJoint()
///     ..connectedBody = anchorBody
///     ..distance = 2.0
///     ..frequency = 4.0
///     ..dampingRatio = 0.3,
/// );
/// ```
///
/// See also:
/// * [DistanceJoint] for a rigid length constraint without oscillation.
/// * [FixedJoint] to lock both position and orientation.
class SpringJoint extends Joint {
  @override
  int get jointType => JointType.spring;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    worker.setJointProperty(handle, JointProp.anchor, _anchor.clone());
    worker.setJointProperty(handle, JointProp.connectedAnchor, _connectedAnchor.clone());
    worker.setJointProperty(handle, JointProp.autoConfigureConnectedAnchor, _autoConfigureConnectedAnchor);
    worker.setJointProperty(handle, JointProp.distance, _distance);
    worker.setJointProperty(handle, JointProp.autoConfigureDistance, _autoConfigureDistance);
    worker.setJointProperty(handle, JointProp.springDampingRatio, _dampingRatio);
    worker.setJointProperty(handle, JointProp.springFrequency, _frequency);
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

  /// Rest length of the spring in world units. Default 1.0.
  double get distance => _distance;
  double _distance = 1.0;
  set distance(double value) {
    _distance = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.distance, value);
  }

  /// When true, the engine measures and sets [distance] at attach time. Default true.
  bool get autoConfigureDistance => _autoConfigureDistance;
  bool _autoConfigureDistance = true;
  set autoConfigureDistance(bool value) {
    _autoConfigureDistance = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.autoConfigureDistance, value);
  }

  /// Damping ratio (0 = undamped, 1 = critically damped). Default 0.0.
  double get dampingRatio => _dampingRatio;
  double _dampingRatio = 0.0;
  set dampingRatio(double value) {
    _dampingRatio = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.springDampingRatio, value);
  }

  /// Oscillation frequency in Hz. Default 1.0.
  double get frequency => _frequency;
  double _frequency = 1.0;
  set frequency(double value) {
    _frequency = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.springFrequency, value);
  }
}
