import 'dart:ui' as ui;
import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';
import 'package:goo2d/src/physics/worker/direct/direct_collider_ops.dart';
import 'package:goo2d/goo2d.dart';

/// Collider that merges sibling colliders on the same [GameObject] into a single unified shape.
///
/// Other colliders on the same object opt in by setting their [Collider.compositeOperation].
/// The merged result is what the physics engine sees; individual colliders stop generating
/// their own shapes once they are consumed by this collider.
///
/// [geometryType] determines whether the output is outlines (hollow) or polygons (solid).
/// [generationType] controls whether geometry is rebuilt synchronously or deferred.
/// Call [generateGeometry] to force an immediate rebuild at any time.
///
/// See also:
/// * [Collider.compositeOperation] on child colliders to control how each one is merged.
/// * [PolygonCollider] and [EdgeCollider] which are the most common sources for composite merging.
class CompositeCollider extends Collider {
  @override
  ColliderShapeType get shapeType => ColliderShapeType.composite;

  @override
  @protected
  void syncAllProperties() {
    super.syncAllProperties();
    if (hasBoundsOnly) return;
    worker.setColliderProperty(handle, ColliderProp.compositeEdgeRadius, _edgeRadius);
    worker.setColliderProperty(handle, ColliderProp.compositeVertexDistance, _vertexDistance);
    worker.setColliderProperty(handle, ColliderProp.compositeOffsetDistance, _offsetDistance);
    worker.setColliderProperty(handle, ColliderProp.compositeUseDelaunayMesh, _useDelaunayMesh);
    worker.setColliderProperty(handle, ColliderProp.compositeGeometryType, _geometryType.index);
    worker.setColliderProperty(handle, ColliderProp.compositeGenerationType, _generationType.index);
  }

  /// Rounding radius applied to the merged outline in world units. Default 0.
  double get edgeRadius => _edgeRadius;
  double _edgeRadius = 0.0;
  set edgeRadius(double value) {
    _edgeRadius = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.compositeEdgeRadius, value);
  }

  /// Minimum distance between generated vertices; smaller values produce more detailed outlines. Default 0.0005.
  double get vertexDistance => _vertexDistance;
  double _vertexDistance = 0.0005;
  set vertexDistance(double value) {
    _vertexDistance = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.compositeVertexDistance, value);
  }

  /// Distance threshold used to merge nearby vertices during geometry generation. Default 0.00005.
  double get offsetDistance => _offsetDistance;
  double _offsetDistance = 0.00005;
  set offsetDistance(double value) {
    _offsetDistance = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.compositeOffsetDistance, value);
  }

  /// When true, polygons are triangulated with the Delaunay algorithm, enabling concave merged shapes.
  bool get useDelaunayMesh => _useDelaunayMesh;
  bool _useDelaunayMesh = false;
  set useDelaunayMesh(bool value) {
    _useDelaunayMesh = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.compositeUseDelaunayMesh, value);
  }

  /// Whether the merged output is hollow outlines or filled polygon shapes. Default `outlines`.
  GeometryType get geometryType => _geometryType;
  GeometryType _geometryType = GeometryType.outlines;
  set geometryType(GeometryType value) {
    _geometryType = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.compositeGeometryType, value.index);
  }

  /// When to rebuild the composite geometry: `synchronous` rebuilds immediately, `manual` waits for [generateGeometry].
  GenerationType get generationType => _generationType;
  GenerationType _generationType = GenerationType.synchronous;
  set generationType(GenerationType value) {
    _generationType = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(handle, ColliderProp.compositeGenerationType, value.index);
  }

  /// Number of separate outline paths in the merged result.
  Future<int> get pathCount async => (await worker.getColliderProperty(handle, ColliderProp.polygonPathCount)) as int;

  /// Total number of vertices across all merged paths.
  Future<int> get pointCount async => (await worker.getColliderProperty(handle, ColliderProp.shapeCount)) as int;

  /// Returns the vertices of the merged outline path at [index].
  Future<List<Vector2>> getPath(int index) async => const [];

  /// Returns the vertex count of the merged outline path at [index].
  Future<int> getPathPointCount(int index) async => 0;

  /// Returns all colliders that have been merged into this composite.
  Future<List<Collider>> getCompositedColliders() async {
    final handles = await worker.getContactColliders(handle);
    return handles.map((h) => PhysicsSystem.getCollider(h)).whereType<Collider>().toList();
  }

  /// Forces an immediate rebuild of the merged geometry, regardless of [generationType].
  void generateGeometry() {
    if (isAttached) worker.colliderGenerateGeometry(handle);
  }

  @override
  bool containsPoint(ui.Offset position) => false;
}
