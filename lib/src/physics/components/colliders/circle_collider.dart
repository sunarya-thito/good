import 'dart:ui' as ui;
import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/collision/worker/collision_worker.dart';
import 'package:goo2d/src/physics/worker/direct/direct_collider_ops.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';
import 'package:goo2d/goo2d.dart';

/// Circular collider for 2D physics.
///
/// Circles are computationally cheap and rotate symmetrically, making them a good default for
/// small objects such as bullets, coins, and projectiles. Centered on [Collider.offset] from the
/// [ObjectTransform] position.
///
/// ```dart
/// addComponent(
///   ObjectTransform(),
///   Rigidbody()..gravityScale = 1.0,
///   CircleCollider()..radius = 0.3,
/// );
/// ```
///
/// See also:
/// * [BoxCollider] for rectangular shapes.
/// * [CapsuleCollider] for tall or wide oblong shapes.
class CircleCollider extends Collider {
  @override
  ColliderShapeType get shapeType => ColliderShapeType.circle;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    if (hasBoundsOnly) return;
    worker.setColliderProperty(handle, ColliderProp.circleRadius, _radius);
  }

  @override
  @protected
  void syncCollisionGeometry(CollisionWorker w) =>
      w.setShapeCircle(handle, _radius);

  /// Radius of the circle in world units. Default 0.5.
  double get radius => _radius;
  double _radius = 0.5;
  set radius(double value) {
    _radius = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.circleRadius, value);
  }

  @override
  int getShapes(PhysicsShapeGroup shapeGroup, [int shapeIndex = 0, int shapeCount = 0]) {
    shapeGroup.addCircle(offset, _radius);
    return 1;
  }

  @override
  bool containsPoint(ui.Offset position) {
    final dx = position.dx - offset.x;
    final dy = position.dy - offset.y;
    return dx * dx + dy * dy <= _radius * _radius;
  }

  @override
  @protected
  ui.Rect computeShapeBounds(Vector2 center, double angle) {
    return ui.Rect.fromCircle(center: ui.Offset(center.x, center.y), radius: _radius);
  }
}
