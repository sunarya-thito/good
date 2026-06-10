import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/physics/worker/direct/direct_joint_ops.dart';
import 'package:goo2d/src/physics/worker/data/joint_type.dart';
import 'package:goo2d/goo2d.dart';

/// Pulls this body's [anchor] point toward a world-space [target] position using a spring.
///
/// The body is attracted to [target] with a spring of [frequency] (Hz) and [dampingRatio].
/// The force applied is capped at [maxForce] (N). Updating [target] every frame produces a
/// smooth follow effect — useful for mouse-drag interactions or guided movement.
///
/// This joint only requires a single body; [connectedBody] is unused.
///
/// ```dart
/// // Drag a body toward the mouse position each frame
/// final joint = TargetJoint()..maxForce = 500;
/// addComponent(joint);
///
/// // In onUpdate:
/// joint.target = mouseWorldPosition;
/// ```
///
/// See also:
/// * [SpringJoint] to connect two bodies with a spring.
class TargetJoint extends Joint {
  @override
  int get jointType => JointType.target;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    worker.setJointProperty(handle, JointProp.anchor, _anchor.clone());
    worker.setJointProperty(handle, JointProp.target, _target.clone());
    worker.setJointProperty(handle, JointProp.targetMaxForce, _maxForce);
    worker.setJointProperty(handle, JointProp.autoConfigureConnectedAnchor, _autoConfigureTarget);
    worker.setJointProperty(handle, JointProp.springFrequency, _frequency);
    worker.setJointProperty(handle, JointProp.springDampingRatio, _dampingRatio);
  }

  /// Local-space point on this body that the spring pulls toward [target]. Default `Vector2.zero()`.
  Vector2 get anchor => _anchor;
  final Vector2 _anchor = Vector2.zero();
  set anchor(Vector2 value) {
    _anchor.setFrom(value);
    if (isAttached) worker.setJointProperty(handle, JointProp.anchor, value.clone());
  }

  /// World-space position this body is attracted to. Update each frame for tracking behavior. Default `Vector2.zero()`.
  Vector2 get target => _target;
  final Vector2 _target = Vector2.zero();
  set target(Vector2 value) {
    _target.setFrom(value);
    if (isAttached) worker.setJointProperty(handle, JointProp.target, value.clone());
  }

  /// Maximum force (N) the spring can apply per step. Default 1000.0.
  double get maxForce => _maxForce;
  double _maxForce = 1000.0;
  set maxForce(double value) {
    _maxForce = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.targetMaxForce, value);
  }

  /// When true, the engine sets [target] from the current body position at attach time. Default true.
  bool get autoConfigureTarget => _autoConfigureTarget;
  bool _autoConfigureTarget = true;
  set autoConfigureTarget(bool value) {
    _autoConfigureTarget = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.autoConfigureConnectedAnchor, value);
  }

  /// Spring oscillation frequency in Hz. Default 5.0.
  double get frequency => _frequency;
  double _frequency = 5.0;
  set frequency(double value) {
    _frequency = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.springFrequency, value);
  }

  /// Damping ratio (0 = undamped, 1 = critically damped). Default 0.7.
  double get dampingRatio => _dampingRatio;
  double _dampingRatio = 0.7;
  set dampingRatio(double value) {
    _dampingRatio = value;
    if (isAttached) worker.setJointProperty(handle, JointProp.springDampingRatio, value);
  }
}
