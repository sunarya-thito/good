import 'package:meta/meta.dart';
import 'package:goo2d/src/physics/worker/direct/direct_effector_ops.dart';
import 'package:goo2d/src/physics/worker/data/effector_type.dart';
import 'package:goo2d/goo2d.dart';

/// Simulates a fluid region that applies buoyant lift and drag to overlapping bodies.
///
/// Place this on a trigger collider to define a water or lava zone. Bodies whose collider
/// center is below [surfaceLevel] (in world-Y) receive an upward force proportional to
/// the difference between the body's [Rigidbody.mass] and the fluid [density].
/// [linearDamping] and [angularDamping] slow movement inside the fluid, giving a viscous feel.
///
/// An optional current can be layered on top via [flowAngle] and [flowMagnitude].
///
/// The collider must have [Collider.usedByEffector] = true and [Collider.isTrigger] = true.
///
/// ```dart
/// addComponent(
///   ObjectTransform()..position = Vector2(0, -3),
///   Rigidbody()..bodyType = RigidbodyType.static,
///   BoxCollider()
///     ..size = Vector2(20, 6)
///     ..isTrigger = true
///     ..usedByEffector = true,
///   BuoyancyEffector()
///     ..surfaceLevel = 0.0
///     ..density = 0.8
///     ..linearDamping = 2.0,
/// );
/// ```
///
/// See also:
/// * [AreaEffector] for directional wind-like forces.
class BuoyancyEffector extends Effector {
  @override
  EffectorType get effectorType => EffectorType.buoyancy;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    worker.setEffectorProperty(handle, EffectorProp.buoyancyDensity, _density);
    worker.setEffectorProperty(handle, EffectorProp.surfaceLevel, _surfaceLevel);
    worker.setEffectorProperty(handle, EffectorProp.linearDrag, _linearDamping);
    worker.setEffectorProperty(handle, EffectorProp.angularDragBuoyancy, _angularDamping);
    worker.setEffectorProperty(handle, EffectorProp.flowAngle, _flowAngle);
    worker.setEffectorProperty(handle, EffectorProp.flowMagnitude, _flowMagnitude);
    worker.setEffectorProperty(handle, EffectorProp.flowVariation, _flowVariation);
  }

  /// Fluid density in kg/m². Bodies lighter than this float; heavier bodies sink. Default 1.0.
  double get density => _density;
  double _density = 1.0;
  set density(double value) {
    _density = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.buoyancyDensity, value);
  }

  /// World-Y coordinate of the fluid surface. Bodies above this line are not affected. Default 0.0.
  double get surfaceLevel => _surfaceLevel;
  double _surfaceLevel = 0.0;
  set surfaceLevel(double value) {
    _surfaceLevel = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.surfaceLevel, value);
  }

  /// Linear drag applied to submerged bodies, slowing translation. Default 1.0.
  double get linearDamping => _linearDamping;
  double _linearDamping = 1.0;
  set linearDamping(double value) {
    _linearDamping = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.linearDrag, value);
  }

  /// Angular drag applied to submerged bodies, slowing rotation. Default 1.0.
  double get angularDamping => _angularDamping;
  double _angularDamping = 1.0;
  set angularDamping(double value) {
    _angularDamping = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.angularDragBuoyancy, value);
  }

  /// Direction of the current in degrees. 0 = right. Default 0.0.
  double get flowAngle => _flowAngle;
  double _flowAngle = 0.0;
  set flowAngle(double value) {
    _flowAngle = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.flowAngle, value);
  }

  /// Strength of the current force in Newtons. Default 0.0 (no current).
  double get flowMagnitude => _flowMagnitude;
  double _flowMagnitude = 0.0;
  set flowMagnitude(double value) {
    _flowMagnitude = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.flowMagnitude, value);
  }

  /// Random variation added to [flowMagnitude] each step. Default 0.0.
  double get flowVariation => _flowVariation;
  double _flowVariation = 0.0;
  set flowVariation(double value) {
    _flowVariation = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.flowVariation, value);
  }
}
