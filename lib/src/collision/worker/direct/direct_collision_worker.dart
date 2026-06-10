import 'dart:typed_data';
import 'package:goo2d/src/collision/engine/collision_engine.dart';
import 'package:goo2d/src/collision/worker/collision_delta.dart';
import 'package:goo2d/src/collision/worker/collision_worker.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';

/// Synchronous collision worker — runs [CollisionEngine] on the calling thread.
/// Used on web (no isolate support) and in unit tests via [forceDirectWorker].
class DirectCollisionWorker implements CollisionWorker {
  CollisionEngine? _engine;
  int _nextHandle = 1;

  @override
  Future<void> initialize() async {
    _engine = CollisionEngine();
  }

  @override
  void dispose() {
    _engine = null;
  }

  @override
  int createShape(ColliderShapeType type) {
    final h = _nextHandle++;
    _engine!.createShape(h, type);
    return h;
  }

  @override
  void destroyShape(int handle) => _engine!.destroyShape(handle);

  @override
  void setShapeTransform(int handle, double x, double y, double angle) =>
      _engine!.setTransform(handle, x, y, angle);

  @override
  void setShapeEnabled(int handle, bool enabled) =>
      _engine!.setEnabled(handle, enabled);

  @override
  void setShapeLayer(int handle, int layer) =>
      _engine!.setLayer(handle, layer);

  @override
  void setShapeExcludeLayers(int handle, int excludeLayers) =>
      _engine!.setExcludeLayers(handle, excludeLayers);

  @override
  void setShapeOffset(int handle, double ox, double oy) =>
      _engine!.setOffset(handle, ox, oy);

  @override
  void setShapeBox(int handle, double halfW, double halfH) =>
      _engine!.setBox(handle, halfW, halfH);

  @override
  void setShapeCircle(int handle, double radius) =>
      _engine!.setCircle(handle, radius);

  @override
  void setShapeCapsule(int handle, double halfLen, double radius, int dir) =>
      _engine!.setCapsule(handle, halfLen, radius, dir);

  @override
  void setShapePolygon(int handle, Float32List vertices) =>
      _engine!.setPolygon(handle, vertices);

  @override
  void setShapeEdge(
          int handle, double x0, double y0, double x1, double y1) =>
      _engine!.setEdge(handle, x0, y0, x1, y1);

  @override
  void setLayerMask(int layer, int mask) => _engine!.setLayerMask(layer, mask);

  @override
  void setIgnoreLayerCollision(int layer1, int layer2, bool ignore) =>
      _engine!.setIgnoreLayerCollision(layer1, layer2, ignore);

  @override
  Future<CollisionDelta> step() async => _engine!.step();
}
