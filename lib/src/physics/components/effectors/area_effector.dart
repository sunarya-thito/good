import 'package:meta/meta.dart';
import 'package:goo2d/src/physics/worker/direct/direct_effector_ops.dart';
import 'package:goo2d/src/physics/worker/data/effector_type.dart';
import 'package:goo2d/goo2d.dart';

/// Applies a directional force to all bodies that overlap the attached collider.
///
/// The force direction is set by [forceAngle] (in degrees). When [useGlobalAngle] is true,
/// the angle is interpreted in world space; otherwise it is relative to the object's rotation.
/// [forceMagnitude] controls the force strength (N) and [forceVariation] adds random variation
/// each step.
///
/// The collider on this object must have [Collider.usedByEffector] set to true and typically
/// has [Collider.isTrigger] set to true so the effector zone does not produce solid contacts.
///
/// ```dart
/// addComponent(
///   ObjectTransform(),
///   Rigidbody()..bodyType = RigidbodyType.static,
///   BoxCollider()
///     ..size = Vector2(10, 10)
///     ..isTrigger = true
///     ..usedByEffector = true,
///   AreaEffector()
///     ..forceAngle = 90   // push upward
///     ..forceMagnitude = 15.0,
/// );
/// ```
///
/// See also:
/// * [PointEffector] for radial attract/repel forces.
/// * [SurfaceEffector] for conveyor-belt style forces.
class AreaEffector extends Effector {
  @override
  EffectorType get effectorType => EffectorType.area;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    worker.setEffectorProperty(handle, EffectorProp.forceMagnitude, _forceMagnitude);
    worker.setEffectorProperty(handle, EffectorProp.forceVariation, _forceVariation);
    worker.setEffectorProperty(handle, EffectorProp.forceTarget, _forceTarget.index);
    worker.setEffectorProperty(handle, EffectorProp.useGlobalAngle, _useGlobalAngle);
    worker.setEffectorProperty(handle, EffectorProp.angularDrag, _angularDamping);
    worker.setEffectorProperty(handle, EffectorProp.drag, _linearDamping);
    worker.setEffectorProperty(handle, EffectorProp.forceAngle, _forceAngle);
  }

  /// Magnitude of the force applied per step in Newtons. Default 10.0.
  double get forceMagnitude => _forceMagnitude;
  double _forceMagnitude = 10.0;
  set forceMagnitude(double value) {
    _forceMagnitude = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.forceMagnitude, value);
  }

  /// Random variation added to [forceMagnitude] each step. Actual force lies in `[magnitude - variation, magnitude + variation]`.
  double get forceVariation => _forceVariation;
  double _forceVariation = 0.0;
  set forceVariation(double value) {
    _forceVariation = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.forceVariation, value);
  }

  /// Whether the force acts on the body's collider center or its rigidbody center of mass.
  EffectorSelection get forceTarget => _forceTarget;
  EffectorSelection _forceTarget = EffectorSelection.collider;
  set forceTarget(EffectorSelection value) {
    _forceTarget = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.forceTarget, value.index);
  }

  /// When true, [forceAngle] is in world space. When false, it is relative to this object's rotation. Default true.
  bool get useGlobalAngle => _useGlobalAngle;
  bool _useGlobalAngle = true;
  set useGlobalAngle(bool value) {
    _useGlobalAngle = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.useGlobalAngle, value);
  }

  /// Angular drag applied to overlapping bodies. Default 0.0.
  double get angularDamping => _angularDamping;
  double _angularDamping = 0.0;
  set angularDamping(double value) {
    _angularDamping = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.angularDrag, value);
  }

  /// Linear drag applied to overlapping bodies. Default 0.0.
  double get linearDamping => _linearDamping;
  double _linearDamping = 0.0;
  set linearDamping(double value) {
    _linearDamping = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.drag, value);
  }

  /// Direction of the force in degrees. 0 = right, 90 = up. Interpreted per [useGlobalAngle]. Default 0.0.
  double get forceAngle => _forceAngle;
  double _forceAngle = 0.0;
  set forceAngle(double value) {
    _forceAngle = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.forceAngle, value);
  }
}
