import 'dart:typed_data';
import 'package:goo2d/src/collision/worker/collision_delta.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';

/// Abstract interface for trigger-only collision execution strategies.
///
/// Two implementations exist:
/// - [DirectCollisionWorker]: synchronous, runs on the calling thread (web / tests).
/// - [IsolateCollisionWorker]: runs the engine on a separate isolate (native).
///
/// All mutation methods are synchronous — they accumulate into a pending batch.
/// [step] flushes the batch (isolate mode) or executes directly (sync mode)
/// and returns the [CollisionDelta] for this frame.
abstract class CollisionWorker {
  Future<void> initialize();
  void dispose();

  /// Allocates a new shape of [type] and returns its handle.
  /// The handle is allocated on the caller thread (no isolate round-trip).
  int createShape(ColliderShapeType type);
  void destroyShape(int handle);

  void setShapeTransform(int handle, double x, double y, double angle);
  void setShapeEnabled(int handle, bool enabled);
  void setShapeLayer(int handle, int layer);
  void setShapeExcludeLayers(int handle, int excludeLayers);
  void setShapeOffset(int handle, double ox, double oy);
  void setShapeBox(int handle, double halfW, double halfH);
  void setShapeCircle(int handle, double radius);
  void setShapeCapsule(int handle, double halfLen, double radius, int dir);

  /// [vertices] is a flat x,y pair array: length must be even.
  void setShapePolygon(int handle, Float32List vertices);
  void setShapeEdge(int handle, double x0, double y0, double x1, double y1);

  void setLayerMask(int layer, int mask);
  void setIgnoreLayerCollision(int layer1, int layer2, bool ignore);

  Future<CollisionDelta> step();
}
