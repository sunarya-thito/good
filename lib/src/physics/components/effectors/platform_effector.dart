import 'package:meta/meta.dart';
import 'package:goo2d/src/physics/worker/direct/direct_effector_ops.dart';
import 'package:goo2d/src/physics/worker/data/effector_type.dart';
import 'package:goo2d/goo2d.dart';

/// Makes a collider passable from below and solid from above — a one-way platform.
///
/// When [useOneWay] is true, a body can pass through the collider from the underside but
/// cannot fall through from the top. [surfaceArc] (in degrees) defines the top arc that is
/// treated as solid; everything outside that arc is passable. A value of 180° means exactly
/// the top hemisphere is solid, which suits most platformer floors.
///
/// [rotationalOffset] rotates the effective surface normal if the platform is tilted.
///
/// The collider must have [Collider.usedByEffector] = true.
///
/// ```dart
/// addComponent(
///   ObjectTransform(),
///   Rigidbody()..bodyType = RigidbodyType.static,
///   BoxCollider()
///     ..size = Vector2(5, 0.3)
///     ..usedByEffector = true,
///   PlatformEffector()
///     ..useOneWay = true
///     ..surfaceArc = 170.0,
/// );
/// ```
///
/// See also:
/// * [SurfaceEffector] to add conveyor-belt movement along the surface.
class PlatformEffector extends Effector {
  @override
  EffectorType get effectorType => EffectorType.platform;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    worker.setEffectorProperty(handle, EffectorProp.useOneWay, _useOneWay);
    worker.setEffectorProperty(handle, EffectorProp.useOneWayGrouping, _useOneWayGrouping);
    worker.setEffectorProperty(handle, EffectorProp.surfaceArc, _surfaceArc);
    worker.setEffectorProperty(handle, EffectorProp.useSideFriction, _useSideFriction);
    worker.setEffectorProperty(handle, EffectorProp.useSideBounce, _useSideBounce);
    worker.setEffectorProperty(handle, EffectorProp.sideArc, _sideArc);
    worker.setEffectorProperty(handle, EffectorProp.rotationalOffset, _rotationalOffset);
  }

  /// When true, bodies can pass through the underside of the collider. Default true.
  bool get useOneWay => _useOneWay;
  bool _useOneWay = true;
  set useOneWay(bool value) {
    _useOneWay = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.useOneWay, value);
  }

  /// When true, all colliders on the same [GameObject] share the one-way behavior. Default false.
  bool get useOneWayGrouping => _useOneWayGrouping;
  bool _useOneWayGrouping = false;
  set useOneWayGrouping(bool value) {
    _useOneWayGrouping = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.useOneWayGrouping, value);
  }

  /// Angular width of the solid top surface in degrees. Default 180° (full upper hemisphere).
  double get surfaceArc => _surfaceArc;
  double _surfaceArc = 180.0;
  set surfaceArc(double value) {
    _surfaceArc = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.surfaceArc, value);
  }

  /// Whether friction is applied when a body contacts the side faces. Default true.
  bool get useSideFriction => _useSideFriction;
  bool _useSideFriction = true;
  set useSideFriction(bool value) {
    _useSideFriction = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.useSideFriction, value);
  }

  /// Whether bounce is applied when a body contacts the side faces. Default true.
  bool get useSideBounce => _useSideBounce;
  bool _useSideBounce = true;
  set useSideBounce(bool value) {
    _useSideBounce = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.useSideBounce, value);
  }

  /// Angular width of the side area in degrees. 0 = no distinct side region. Default 0.
  double get sideArc => _sideArc;
  double _sideArc = 0.0;
  set sideArc(double value) {
    _sideArc = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.sideArc, value);
  }

  /// Rotates the effector's surface normal by this many degrees to compensate for tilted platforms. Default 0.
  double get rotationalOffset => _rotationalOffset;
  double _rotationalOffset = 0.0;
  set rotationalOffset(double value) {
    _rotationalOffset = value;
    if (isAttached) worker.setEffectorProperty(handle, EffectorProp.rotationalOffset, value);
  }
}
