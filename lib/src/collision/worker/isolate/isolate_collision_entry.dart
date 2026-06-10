import 'dart:isolate';
import 'dart:typed_data';
import 'package:goo2d/src/collision/engine/collision_engine.dart';
import 'package:goo2d/src/collision/worker/isolate/isolate_collision_protocol.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';
import 'package:goo2d/src/rpc/buffer.dart';

/// Entry point for the collision isolate.
void collisionIsolateEntry(SendPort mainPort) {
  final engine = CollisionEngine();
  final commandPort = ReceivePort();
  mainPort.send(commandPort.sendPort);

  late SendPort responsePort;

  commandPort.listen((message) {
    if (message is SendPort) {
      responsePort = message;
      return;
    }

    final bytes = message as Uint8List;
    final data = ByteData.sublistView(bytes);
    final requestId = data.getUint16(0);
    final payload = ByteData.sublistView(bytes, 2);

    _dispatch(engine, payload);

    // Always send a response (delta or empty) when requestId != 0
    if (requestId != 0) {
      final delta = engine.step();
      final response = IsolateCollisionProtocol.writeDelta(delta);
      final out = Uint8ListBuffer(2 + response.offset);
      out.write(2, () => out.byteData.setUint16(out.offset, requestId));
      final r = response.compact;
      out.ensureCapacity(r.length);
      out.write(r.length, () {
        for (var i = 0; i < r.length; i++) {
          out.byteData.setUint8(out.offset + i, r[i]);
        }
      });
      responsePort.send(out.compact);
    }
  });
}

void _dispatch(CollisionEngine engine, ByteData data) {
  final opcode = data.getUint8(0);
  var off = 1;

  if (opcode != CollisionOpcode.stepWithBatch) return;

  final opCount = data.getInt32(off); off += 4;
  for (var i = 0; i < opCount; i++) {
    final op = data.getUint8(off); off += 1;
    switch (op) {
      case CollisionBatchOp.createShape:
        final h = data.getInt32(off); off += 4;
        final t = data.getUint8(off); off += 1;
        engine.createShape(h, ColliderShapeType.values[t]);

      case CollisionBatchOp.destroyShape:
        engine.destroyShape(data.getInt32(off)); off += 4;

      case CollisionBatchOp.setTransform:
        final h = data.getInt32(off); off += 4;
        final x = data.getFloat32(off); off += 4;
        final y = data.getFloat32(off); off += 4;
        final a = data.getFloat32(off); off += 4;
        engine.setTransform(h, x, y, a);

      case CollisionBatchOp.setEnabled:
        final h = data.getInt32(off); off += 4;
        final v = data.getUint8(off) != 0; off += 1;
        engine.setEnabled(h, v);

      case CollisionBatchOp.setLayer:
        final h = data.getInt32(off); off += 4;
        final v = data.getInt32(off); off += 4;
        engine.setLayer(h, v);

      case CollisionBatchOp.setExcludeLayers:
        final h = data.getInt32(off); off += 4;
        final v = data.getInt32(off); off += 4;
        engine.setExcludeLayers(h, v);

      case CollisionBatchOp.setOffset:
        final h = data.getInt32(off); off += 4;
        final ox = data.getFloat32(off); off += 4;
        final oy = data.getFloat32(off); off += 4;
        engine.setOffset(h, ox, oy);

      case CollisionBatchOp.setBox:
        final h = data.getInt32(off); off += 4;
        final hw = data.getFloat32(off); off += 4;
        final hh = data.getFloat32(off); off += 4;
        engine.setBox(h, hw, hh);

      case CollisionBatchOp.setCircle:
        final h = data.getInt32(off); off += 4;
        final r = data.getFloat32(off); off += 4;
        engine.setCircle(h, r);

      case CollisionBatchOp.setCapsule:
        final h = data.getInt32(off); off += 4;
        final hl = data.getFloat32(off); off += 4;
        final r = data.getFloat32(off); off += 4;
        final dir = data.getUint8(off); off += 1;
        engine.setCapsule(h, hl, r, dir);

      case CollisionBatchOp.setPolygon:
        final h = data.getInt32(off); off += 4;
        final count = data.getInt32(off); off += 4;
        final verts = Float32List(count * 2);
        for (var vi = 0; vi < count * 2; vi++) {
          verts[vi] = data.getFloat32(off); off += 4;
        }
        engine.setPolygon(h, verts);

      case CollisionBatchOp.setEdge:
        final h = data.getInt32(off); off += 4;
        final x0 = data.getFloat32(off); off += 4;
        final y0 = data.getFloat32(off); off += 4;
        final x1 = data.getFloat32(off); off += 4;
        final y1 = data.getFloat32(off); off += 4;
        engine.setEdge(h, x0, y0, x1, y1);

      case CollisionBatchOp.setLayerMask:
        final layer = data.getInt32(off); off += 4;
        final mask = data.getInt32(off); off += 4;
        engine.setLayerMask(layer, mask);

      case CollisionBatchOp.setIgnoreLayer:
        final l1 = data.getInt32(off); off += 4;
        final l2 = data.getInt32(off); off += 4;
        final ignore = data.getUint8(off) != 0; off += 1;
        engine.setIgnoreLayerCollision(l1, l2, ignore);
    }
  }
}
