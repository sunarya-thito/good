import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/collision/worker/collision_worker.dart';
import 'package:goo2d/src/physics/worker/direct/direct_collider_ops.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';
import 'package:goo2d/goo2d.dart';

/// Rectangular collider for 2D physics.
///
/// The box is centered on the [GameObject]'s [ObjectTransform] position (offset by [Collider.offset])
/// and rotates with the object. [size] controls the full width and height in world units.
/// Rounding the corners with [edgeRadius] makes the box behave more like a rounded rectangle —
/// useful to prevent objects from catching on seams in a tile map.
///
/// ```dart
/// addComponent(
///   ObjectTransform()..position = Vector2(0, 0),
///   Rigidbody()..gravityScale = 0,
///   BoxCollider()
///     ..size = Vector2(2, 1)
///     ..friction = 0.3,
/// );
/// ```
///
/// See also:
/// * [CircleCollider] for round shapes.
/// * [CapsuleCollider] for pill-shaped hitboxes.
class BoxCollider extends Collider {
  @override
  ColliderShapeType get shapeType => ColliderShapeType.box;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    if (hasBoundsOnly) return;
    worker.setColliderProperty(handle, ColliderProp.boxEdgeRadius, _edgeRadius);
    worker.setColliderProperty(handle, ColliderProp.boxSize, _size.clone());
    worker.setColliderProperty(handle, ColliderProp.boxAutoTiling, _autoTiling);
  }

  @override
  @protected
  void syncCollisionGeometry(CollisionWorker w) =>
      w.setShapeBox(handle, _size.x / 2, _size.y / 2);

  /// Rounds each corner of the box by this radius in world units. Default 0 (sharp corners).
  double get edgeRadius => _edgeRadius;
  double _edgeRadius = 0;
  set edgeRadius(double value) {
    _edgeRadius = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.boxEdgeRadius, value);
  }

  /// Full width and height of the box in world units. Default `Vector2(1, 1)`.
  Vector2 get size => _size;
  Vector2 _size = Vector2(1, 1);
  set size(Vector2 value) {
    _size.setFrom(value);
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.boxSize, value.clone());
  }

  /// When true, scales the collider to match the sprite's tiling region. Default false.
  bool get autoTiling => _autoTiling;
  bool _autoTiling = false;
  set autoTiling(bool value) {
    _autoTiling = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.boxAutoTiling, value);
  }

  @override
  int getShapes(PhysicsShapeGroup shapeGroup, [int shapeIndex = 0, int shapeCount = 0]) {
    shapeGroup.addBox(offset, _size, 0, _edgeRadius);
    return 1;
  }

  @override
  bool containsPoint(ui.Offset position) {
    final dx = position.dx - offset.x;
    final dy = position.dy - offset.y;
    return dx.abs() <= _size.x / 2 && dy.abs() <= _size.y / 2;
  }

  @override
  @protected
  ui.Rect computeShapeBounds(Vector2 center, double angle) {
    final hx = _size.x / 2;
    final hy = _size.y / 2;
    final c = math.cos(angle).abs();
    final s = math.sin(angle).abs();
    final ex = hx * c + hy * s;
    final ey = hx * s + hy * c;
    return ui.Rect.fromLTRB(center.x - ex, center.y - ey, center.x + ex, center.y + ey);
  }
}
