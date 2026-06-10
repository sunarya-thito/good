import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/collision/worker/collision_worker.dart';
import 'package:goo2d/src/physics/worker/direct/direct_collider_ops.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';
import 'package:goo2d/goo2d.dart';

/// Open-chain line collider for 2D physics.
///
/// Defines a sequence of connected line segments through a list of [points]. Unlike [PolygonCollider],
/// the shape is not closed — the first and last points are not automatically joined. This makes it
/// suitable for terrain edges, walls, and platforms where the interior of the shape should not matter.
///
/// Requires at least two points to produce any physics shape.
///
/// Adjacent point hints ([useAdjacentStartPoint], [useAdjacentEndPoint]) tell the solver how the edge
/// continues outside the defined range, preventing ghost collisions at segment junctions.
///
/// ```dart
/// addComponent(
///   ObjectTransform(),
///   Rigidbody()..bodyType = RigidbodyType.static,
///   EdgeCollider()..points = [Vector2(-5, 0), Vector2(0, 1), Vector2(5, 0)],
/// );
/// ```
///
/// See also:
/// * [PolygonCollider] for closed convex or concave polygons.
/// * [CompositeCollider] to merge multiple edge colliders into one shape.
class EdgeCollider extends Collider {
  @override
  ColliderShapeType get shapeType => ColliderShapeType.edge;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    if (hasBoundsOnly) return;
    worker.setColliderProperty(handle, ColliderProp.edgePoints, List.from(_points));
    worker.setColliderProperty(handle, ColliderProp.edgeUseAdjacentStartPoint, _useAdjacentStartPoint);
    worker.setColliderProperty(handle, ColliderProp.edgeUseAdjacentEndPoint, _useAdjacentEndPoint);
    worker.setColliderProperty(handle, ColliderProp.edgeAdjacentStartPoint, _adjacentStartPoint.clone());
    worker.setColliderProperty(handle, ColliderProp.edgeAdjacentEndPoint, _adjacentEndPoint.clone());
    worker.setColliderProperty(handle, ColliderProp.edgeRadius, _edgeRadius);
  }

  // In collision mode only the first segment is registered (single-edge limit of CollisionEngine).
  @override
  @protected
  void syncCollisionGeometry(CollisionWorker w) {
    if (_points.length < 2) return;
    w.setShapeEdge(handle,
        _points[0].x, _points[0].y, _points[1].x, _points[1].y);
  }

  /// Ordered list of vertices that define the edge chain in local space. Must have at least 2 points.
  List<Vector2> get points => _points;
  List<Vector2> _points = [];
  set points(List<Vector2> value) {
    _points = List.from(value);
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.edgePoints, List.from(_points));
  }

  /// When true, [adjacentStartPoint] hints at the edge continuation before the first vertex, preventing ghost collisions.
  bool get useAdjacentStartPoint => _useAdjacentStartPoint;
  bool _useAdjacentStartPoint = false;
  set useAdjacentStartPoint(bool value) {
    _useAdjacentStartPoint = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.edgeUseAdjacentStartPoint, value);
  }

  /// When true, [adjacentEndPoint] hints at the edge continuation after the last vertex, preventing ghost collisions.
  bool get useAdjacentEndPoint => _useAdjacentEndPoint;
  bool _useAdjacentEndPoint = false;
  set useAdjacentEndPoint(bool value) {
    _useAdjacentEndPoint = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.edgeUseAdjacentEndPoint, value);
  }

  /// Ghost vertex before the first point, used when [useAdjacentStartPoint] is true.
  Vector2 get adjacentStartPoint => _adjacentStartPoint;
  Vector2 _adjacentStartPoint = Vector2.zero();
  set adjacentStartPoint(Vector2 value) {
    _adjacentStartPoint.setFrom(value);
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.edgeAdjacentStartPoint, value.clone());
  }

  /// Ghost vertex after the last point, used when [useAdjacentEndPoint] is true.
  Vector2 get adjacentEndPoint => _adjacentEndPoint;
  Vector2 _adjacentEndPoint = Vector2.zero();
  set adjacentEndPoint(Vector2 value) {
    _adjacentEndPoint.setFrom(value);
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.edgeAdjacentEndPoint, value.clone());
  }

  /// Thickness added around each edge segment in world units. 0 = infinitely thin. Default 0.
  double get edgeRadius => _edgeRadius;
  double _edgeRadius = 0;
  set edgeRadius(double value) {
    _edgeRadius = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.edgeRadius, value);
  }

  /// Number of line segments (always `points.length - 1` when at least 2 points are set).
  int get edgeCount => _points.length > 1 ? _points.length - 1 : 0;

  /// Number of vertices in [points].
  int get pointCount => _points.length;

  void reset() {
    points = [Vector2(-1, 0), Vector2(1, 0)];
  }

  List<Vector2> getPoints() => points;

  bool setPoints(List<Vector2> points) {
    if (points.length < 2) return false;
    this.points = points;
    return true;
  }

  @override
  int getShapes(PhysicsShapeGroup shapeGroup, [int shapeIndex = 0, int shapeCount = 0]) {
    if (_points.length < 2) return 0;
    final worldPoints = _points.map((p) => p + offset).toList();
    final idx = shapeGroup.addEdges(worldPoints, _edgeRadius);
    if (_useAdjacentStartPoint || _useAdjacentEndPoint) {
      shapeGroup.setShapeAdjacentVertices(idx, _useAdjacentStartPoint, _useAdjacentEndPoint, _adjacentStartPoint, _adjacentEndPoint);
    }
    return 1;
  }

  @override
  bool containsPoint(ui.Offset position) => false;

  @override
  @protected
  ui.Rect computeShapeBounds(Vector2 center, double angle) {
    if (_points.isEmpty) return ui.Rect.fromCenter(center: ui.Offset(center.x, center.y), width: 0, height: 0);
    final c = math.cos(angle);
    final s = math.sin(angle);
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in _points) {
      final wx = p.x * c - p.y * s + center.x;
      final wy = p.x * s + p.y * c + center.y;
      if (wx < minX) minX = wx;
      if (wy < minY) minY = wy;
      if (wx > maxX) maxX = wx;
      if (wy > maxY) maxY = wy;
    }
    return ui.Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}
