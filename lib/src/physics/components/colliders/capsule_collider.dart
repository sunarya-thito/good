import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/collision/worker/collision_worker.dart';
import 'package:goo2d/src/physics/worker/direct/direct_collider_ops.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';
import 'package:goo2d/goo2d.dart';

/// Pill-shaped collider for 2D physics.
///
/// A capsule is a rectangle with semicircular caps on two ends. It is commonly used for
/// characters because it produces smooth sliding along floors without catching on edge seams.
/// [direction] controls whether the caps are on the top/bottom (`vertical`) or left/right (`horizontal`).
/// [size] sets the full extent including the caps in world units.
///
/// ```dart
/// addComponent(
///   ObjectTransform(),
///   Rigidbody()..freezeRotation = true,
///   CapsuleCollider()
///     ..size = Vector2(0.8, 1.8)
///     ..direction = CapsuleDirection.vertical,
/// );
/// ```
///
/// See also:
/// * [BoxCollider] for rectangular shapes.
/// * [CircleCollider] for fully round shapes.
class CapsuleCollider extends Collider {
  @override
  ColliderShapeType get shapeType => ColliderShapeType.capsule;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    if (hasBoundsOnly) return;
    worker.setColliderProperty(handle, ColliderProp.capsuleSize, _size.clone());
    worker.setColliderProperty(handle, ColliderProp.capsuleDirection, _direction.index);
  }

  @override
  @protected
  void syncCollisionGeometry(CollisionWorker w) {
    final isVert = _direction == CapsuleDirection.vertical;
    final radius = isVert ? _size.x / 2 : _size.y / 2;
    final halfLen = ((isVert ? _size.y - _size.x : _size.x - _size.y) / 2)
        .clamp(0.0, double.infinity);
    w.setShapeCapsule(handle, halfLen, radius, _direction.index);
  }

  /// Full extent of the capsule in world units, including the semicircular caps. Default `Vector2(1, 2)`.
  Vector2 get size => _size;
  Vector2 _size = Vector2(1, 2);
  set size(Vector2 value) {
    _size.setFrom(value);
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.capsuleSize, value.clone());
  }

  /// Axis along which the capsule is elongated. `vertical` puts caps on the top and bottom; `horizontal` on the sides.
  CapsuleDirection get direction => _direction;
  CapsuleDirection _direction = CapsuleDirection.vertical;
  set direction(CapsuleDirection value) {
    _direction = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.capsuleDirection, value.index);
  }

  @override
  int getShapes(PhysicsShapeGroup shapeGroup, [int shapeIndex = 0, int shapeCount = 0]) {
    final isVert = _direction == CapsuleDirection.vertical;
    final radius = isVert ? _size.x / 2 : _size.y / 2;
    final halfBody = ((isVert ? _size.y - _size.x : _size.x - _size.y) / 2).clamp(0.0, double.infinity);
    final v0 = isVert ? Vector2(offset.x, offset.y + halfBody) : Vector2(offset.x + halfBody, offset.y);
    final v1 = isVert ? Vector2(offset.x, offset.y - halfBody) : Vector2(offset.x - halfBody, offset.y);
    shapeGroup.addCapsule(v0, v1, radius);
    return 1;
  }

  @override
  bool containsPoint(ui.Offset position) {
    final px = position.dx - offset.x;
    final py = position.dy - offset.y;
    if (_direction == CapsuleDirection.vertical) {
      final radius = _size.x / 2;
      final halfBody = ((_size.y - _size.x) / 2).clamp(0.0, double.infinity);
      final cy = py.clamp(-halfBody, halfBody);
      return px * px + (py - cy) * (py - cy) <= radius * radius;
    } else {
      final radius = _size.y / 2;
      final halfBody = ((_size.x - _size.y) / 2).clamp(0.0, double.infinity);
      final cx = px.clamp(-halfBody, halfBody);
      return (px - cx) * (px - cx) + py * py <= radius * radius;
    }
  }

  @override
  @protected
  ui.Rect computeShapeBounds(Vector2 center, double angle) {
    final hx = _size.x * 0.5;
    final hy = _size.y * 0.5;
    final isVertical = _direction == CapsuleDirection.vertical;
    final radius = isVertical ? hx : hy;
    final halfLen = (isVertical ? hy - radius : hx - radius).clamp(0.0, double.infinity);
    final dx = isVertical ? -math.sin(angle) * halfLen : math.cos(angle) * halfLen;
    final dy = isVertical ? math.cos(angle) * halfLen : math.sin(angle) * halfLen;
    final minX = math.min(center.x + dx, center.x - dx) - radius;
    final minY = math.min(center.y + dy, center.y - dy) - radius;
    final maxX = math.max(center.x + dx, center.x - dx) + radius;
    final maxY = math.max(center.y + dy, center.y - dy) + radius;
    return ui.Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}
