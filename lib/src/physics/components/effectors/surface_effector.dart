import 'package:meta/meta.dart';
import 'package:goo2d/src/physics/worker/direct/direct_effector_ops.dart';
import 'package:goo2d/src/physics/worker/data/effector_type.dart';
import 'package:goo2d/goo2d.dart';

/// Applies a tangential force along the surface of the attached collider, simulating a conveyor belt.
///
/// Bodies that contact this collider are pushed along its surface at [speed] world units per second.
/// [forceScale] controls how strongly the effector corrects the body's surface-tangent velocity —
/// 1.0 means the force is strong enough to reach exactly [speed]; lower values produce a weaker push.
///
/// [useFriction] and [useBounce] allow the effector to override the collider's own friction and
/// bounciness settings along the surface. [useContactForce] toggles whether a direct force (instead
/// of friction manipulation) is used to drive the body.
///
/// The collider must have [Collider.usedByEffector] = true.
///
/// ```dart
/// // Horizontal conveyor belt moving to the right
/// addComponent(
///   ObjectTransform(),
///   Rigidbody()..bodyType = RigidbodyType.static,
///   BoxCollider()
///     ..size = Vector2(8, 0.3)
///     ..usedByEffector = true,
///   SurfaceEffector()..speed = 4.0,
/// );
/// ```
///
/// See also:
/// * [PlatformEffector] for one-way platforms.
/// * [AreaEffector] for forces applied inside a volume.
class SurfaceEffector extends Effector {
  @override
  EffectorType get effectorType => EffectorType.surface;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    worker.setEffectorProperty(handle, EffectorProp.speed, _speed);
    worker.setEffectorProperty(handle, EffectorProp.speedVariation, _speedVariation);
    worker.setEffectorProperty(handle, EffectorProp.forceScale, _forceScale);
    worker.setEffectorProperty(handle, EffectorProp.useContactForce, _useContactForce);
    worker.setEffectorProperty(handle, EffectorProp.useFriction, _useFriction);
    worker.setEffectorProperty(handle, EffectorProp.useBounce, _useBounce);
  }

  /// Target surface speed in world units per second. Default 1.0.
  double get speed => _speed;
  double _speed = 1.0;
  set speed(double value) {
    _speed = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.speed, value);
  }

  /// Random variation added to [speed] per contact. Default 0.0.
  double get speedVariation => _speedVariation;
  double _speedVariation = 0.0;
  set speedVariation(double value) {
    _speedVariation = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.speedVariation, value);
  }

  /// Fraction of the corrective force applied to reach [speed]. 1.0 = full correction. Default 1.0.
  double get forceScale => _forceScale;
  double _forceScale = 1.0;
  set forceScale(double value) {
    _forceScale = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.forceScale, value);
  }

  /// When true, a direct force is used to push the body; when false, friction is manipulated instead. Default true.
  bool get useContactForce => _useContactForce;
  bool _useContactForce = true;
  set useContactForce(bool value) {
    _useContactForce = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.useContactForce, value);
  }

  /// When true, the effector overrides the collider's friction along the surface. Default true.
  bool get useFriction => _useFriction;
  bool _useFriction = true;
  set useFriction(bool value) {
    _useFriction = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.useFriction, value);
  }

  /// When true, the effector overrides the collider's bounciness along the surface. Default true.
  bool get useBounce => _useBounce;
  bool _useBounce = true;
  set useBounce(bool value) {
    _useBounce = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.useBounce, value);
  }
}
