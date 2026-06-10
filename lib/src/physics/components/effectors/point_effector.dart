import 'package:meta/meta.dart';
import 'package:goo2d/src/physics/worker/direct/direct_effector_ops.dart';
import 'package:goo2d/src/physics/worker/data/effector_type.dart';
import 'package:goo2d/goo2d.dart';

/// Applies radial forces from a single point — attracts or repels overlapping bodies.
///
/// Positive [forceMagnitude] pushes bodies away from this object's position; negative values
/// pull them in. The force scales with inverse distance when [forceMode] is
/// `EffectorForceMode.inverseLinear` or `inverseSquared`, which produces a gravity-like
/// or magnet-like falloff. [distanceScale] controls how quickly the force changes with distance.
///
/// The collider must have [Collider.usedByEffector] = true and [Collider.isTrigger] = true.
///
/// ```dart
/// // A black-hole style attractor
/// addComponent(
///   ObjectTransform(),
///   Rigidbody()..bodyType = RigidbodyType.static,
///   CircleCollider()
///     ..radius = 8.0
///     ..isTrigger = true
///     ..usedByEffector = true,
///   PointEffector()
///     ..forceMagnitude = -50.0  // negative = attract
///     ..forceMode = EffectorForceMode.inverseSquared,
/// );
/// ```
///
/// See also:
/// * [AreaEffector] for uniform directional force over an area.
class PointEffector extends Effector {
  @override
  EffectorType get effectorType => EffectorType.point;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    worker.setEffectorProperty(handle, EffectorProp.pointForceMagnitude, _forceMagnitude);
    worker.setEffectorProperty(handle, EffectorProp.pointForceVariation, _forceVariation);
    worker.setEffectorProperty(handle, EffectorProp.distanceScale, _distanceScale);
    worker.setEffectorProperty(handle, EffectorProp.pointForceSource, _forceSource.index);
    worker.setEffectorProperty(handle, EffectorProp.pointForceTarget, _forceTarget.index);
    worker.setEffectorProperty(handle, EffectorProp.pointForceMode, _forceMode.index);
    worker.setEffectorProperty(handle, EffectorProp.pointAngularDrag, _angularDamping);
    worker.setEffectorProperty(handle, EffectorProp.pointDrag, _linearDamping);
  }

  /// Signed force magnitude in Newtons. Positive = repel, negative = attract. Default 10.0.
  double get forceMagnitude => _forceMagnitude;
  double _forceMagnitude = 10.0;
  set forceMagnitude(double value) {
    _forceMagnitude = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.pointForceMagnitude, value);
  }

  /// Random variation added to [forceMagnitude] each step. Default 0.0.
  double get forceVariation => _forceVariation;
  double _forceVariation = 0.0;
  set forceVariation(double value) {
    _forceVariation = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.pointForceVariation, value);
  }

  /// Divisor applied to the distance before computing falloff. Larger values make the force reach further. Default 1.0.
  double get distanceScale => _distanceScale;
  double _distanceScale = 1.0;
  set distanceScale(double value) {
    _distanceScale = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.distanceScale, value);
  }

  /// Which point on this object the force originates from. Default `collider`.
  EffectorSelection get forceSource => _forceSource;
  EffectorSelection _forceSource = EffectorSelection.collider;
  set forceSource(EffectorSelection value) {
    _forceSource = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.pointForceSource, value.index);
  }

  /// Which point on the receiving body the force is applied to. Default `collider`.
  EffectorSelection get forceTarget => _forceTarget;
  EffectorSelection _forceTarget = EffectorSelection.collider;
  set forceTarget(EffectorSelection value) {
    _forceTarget = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.pointForceTarget, value.index);
  }

  /// How the force scales with distance: `constant`, `inverseLinear`, or `inverseSquared`. Default `constant`.
  EffectorForceMode get forceMode => _forceMode;
  EffectorForceMode _forceMode = EffectorForceMode.constant;
  set forceMode(EffectorForceMode value) {
    _forceMode = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.pointForceMode, value.index);
  }

  /// Angular drag applied to affected bodies. Default 0.0.
  double get angularDamping => _angularDamping;
  double _angularDamping = 0.0;
  set angularDamping(double value) {
    _angularDamping = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.pointAngularDrag, value);
  }

  /// Linear drag applied to affected bodies. Default 0.0.
  double get linearDamping => _linearDamping;
  double _linearDamping = 0.0;
  set linearDamping(double value) {
    _linearDamping = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.pointDrag, value);
  }
}
