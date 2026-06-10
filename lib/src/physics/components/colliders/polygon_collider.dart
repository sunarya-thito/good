import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/collision/worker/collision_worker.dart';
import 'package:goo2d/src/physics/worker/direct/direct_collider_ops.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';
import 'package:goo2d/goo2d.dart';

/// Closed polygon collider for 2D physics.
///
/// Defines the shape by a list of [points] that are treated as a closed loop — the last point
/// connects back to the first. The polygon must be convex unless [useDelaunayMesh] is true, in
/// which case the engine triangulates the shape using the Delaunay algorithm, allowing concave polygons.
///
/// [createFromSprite] can auto-generate a polygon outline by tracing the opaque pixels of a
/// [GameSprite], which is convenient for irregular sprite shapes.
///
/// ```dart
/// addComponent(
///   ObjectTransform(),
///   Rigidbody()..bodyType = RigidbodyType.static,
///   PolygonCollider()..points = [
///     Vector2(-1, 0), Vector2(0, 2), Vector2(1, 0),
///   ],
/// );
/// ```
///
/// See also:
/// * [EdgeCollider] for open-chain (non-closed) line shapes.
/// * [CompositeCollider] to merge multiple polygon colliders.
class PolygonCollider extends Collider {
  @override
  ColliderShapeType get shapeType => ColliderShapeType.polygon;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    if (hasBoundsOnly) return;
    worker.setColliderProperty(handle, ColliderProp.polygonUseDelaunayMesh, _useDelaunayMesh);
    worker.setColliderProperty(handle, ColliderProp.polygonAutoTiling, _autoTiling);
    worker.setColliderProperty(handle, ColliderProp.polygonPathCount, _pathCount);
    worker.setColliderProperty(handle, ColliderProp.polygonPoints, List.from(_points));
  }

  @override
  @protected
  void syncCollisionGeometry(CollisionWorker w) {
    if (_points.length < 3) return;
    final verts = Float32List(_points.length * 2);
    for (var i = 0; i < _points.length; i++) {
      verts[i * 2]     = _points[i].x;
      verts[i * 2 + 1] = _points[i].y;
    }
    w.setShapePolygon(handle, verts);
  }

  /// When true, the engine triangulates the polygon using the Delaunay algorithm, enabling concave shapes. Default false.
  bool get useDelaunayMesh => _useDelaunayMesh;
  bool _useDelaunayMesh = false;
  set useDelaunayMesh(bool value) {
    _useDelaunayMesh = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.polygonUseDelaunayMesh, value);
  }

  /// When true, adjusts the polygon to match the sprite's tiling bounds. Default false.
  bool get autoTiling => _autoTiling;
  bool _autoTiling = false;
  set autoTiling(bool value) {
    _autoTiling = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.polygonAutoTiling, value);
  }

  /// Number of separate paths (sub-shapes) this polygon contains. Default 1.
  int get pathCount => _pathCount;
  int _pathCount = 1;
  set pathCount(int value) {
    _pathCount = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.polygonPathCount, value);
  }

  /// Vertices of the polygon in local space. Must have at least 3 points. Last point connects to first.
  List<Vector2> get points => _points;
  List<Vector2> _points = [];
  set points(List<Vector2> value) {
    _points = List.from(value);
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.polygonPoints, List.from(_points));
  }

  void setPath(int index, List<Vector2> points) {
    if (index == 0) this.points = points;
  }

  /// Generates [points] by tracing the opaque pixels of [sprite].
  ///
  /// [detail] (0.01–1.0) controls vertex density — lower values produce fewer vertices.
  /// Pixels with alpha below [alphaTolerance] (0–255) are treated as transparent.
  /// Returns false if the sprite image is not loaded or no opaque region is found.
  Future<bool> createFromSprite(
    GameSprite sprite, {
    double detail = 0.25,
    int alphaTolerance = 200,
    bool holeDetection = true,
  }) async {
    final texture = sprite.texture;
    if (!texture.isLoaded) return false;
    final byteData = await texture.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return false;

    final bytes = byteData.buffer.asUint8List();
    final tw = texture.width;
    final sr = sprite.rect;
    final x0 = sr.left.round(), y0 = sr.top.round();
    final sw = sr.width.round(), sh = sr.height.round();
    final ppu = sprite.pixelsPerUnit;

    bool isOpaque(int col, int row) {
      final px = (x0 + col) + (y0 + row) * tw;
      return bytes[px * 4 + 3] >= alphaTolerance;
    }

    final upperRow = List<int?>.filled(sw, null);
    final lowerRow = List<int?>.filled(sw, null);
    for (var col = 0; col < sw; col++) {
      for (var row = 0; row < sh; row++) {
        if (isOpaque(col, row)) {
          upperRow[col] ??= row;
          lowerRow[col] = row;
        }
      }
    }

    final step = (1.0 / detail.clamp(0.01, 1.0)).round().clamp(1, sw);

    Vector2 toWorld(double col, double row) =>
        Vector2((col - sw / 2) / ppu, -(row - sh / 2) / ppu);

    final outline = <Vector2>[];
    for (var col = 0; col < sw; col += step) {
      if (upperRow[col] != null) outline.add(toWorld(col.toDouble(), upperRow[col]!.toDouble()));
    }
    for (var col = sw - 1; col >= 0; col -= step) {
      final b = lowerRow[col];
      if (b != null && b != upperRow[col]) outline.add(toWorld(col.toDouble(), b.toDouble()));
    }

    if (outline.length < 3) return false;
    points = outline;
    return true;
  }

  List<Vector2> getPath(int index) => index == 0 ? points : [];
  int getTotalPointCount() => _points.length;

  @override
  int getShapes(PhysicsShapeGroup shapeGroup, [int shapeIndex = 0, int shapeCount = 0]) {
    if (_points.length < 3) return 0;
    shapeGroup.addPolygon(_points.map((p) => p + offset).toList());
    return 1;
  }

  @override
  bool containsPoint(ui.Offset position) {
    if (_points.length < 3) return false;
    final px = position.dx - offset.x;
    final py = position.dy - offset.y;
    bool inside = false;
    int j = _points.length - 1;
    for (int i = 0; i < _points.length; i++) {
      final xi = _points[i].x, yi = _points[i].y;
      final xj = _points[j].x, yj = _points[j].y;
      if ((yi > py) != (yj > py) && px < (xj - xi) * (py - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  void createPrimitive(int sides, Vector2 scale, Vector2 offset) {
    final newPoints = <Vector2>[];
    final angleStep = (2 * math.pi) / sides;
    for (var i = 0; i < sides; i++) {
      final angle = i * angleStep;
      newPoints.add(Vector2(
        offset.x + scale.x * 0.5 * (1 + math.cos(angle)),
        offset.y + scale.y * 0.5 * (1 + math.sin(angle)),
      ));
    }
    points = newPoints;
  }

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
