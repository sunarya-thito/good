import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:goo2d/src/collision/worker/collision_delta.dart';
import 'package:goo2d/src/collision/worker/collision_worker.dart';
import 'package:goo2d/src/collision/worker/isolate/isolate_collision_entry.dart';
import 'package:goo2d/src/collision/worker/isolate/isolate_collision_protocol.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';
import 'package:goo2d/src/rpc/buffer.dart';

/// Collision worker that runs [CollisionEngine] on a dedicated Dart isolate.
///
/// All mutation methods accumulate into an ordered batch.
/// [step] flushes the batch as a single message, awaits the delta response,
/// and retains any ops that arrived during the await for the next frame.
class IsolateCollisionWorker implements CollisionWorker {
  Isolate? _isolate;
  SendPort? _commandPort;
  ReceivePort? _responsePort;
  Future<void>? _ready;

  int _nextRequestId = 0;
  final Map<int, Completer<ByteData>> _pending = {};

  // Handle IDs allocated on the main thread
  int _nextHandle = 1;

  // Ordered op batch
  final Uint8ListBuffer _opsBuffer = Uint8ListBuffer();
  int _opCount = 0;

  void _op(int opType, void Function() write) {
    _opsBuffer.write(
        1, () => _opsBuffer.byteData.setUint8(_opsBuffer.offset, opType));
    write();
    _opCount++;
  }

  void _wi(int v) => _opsBuffer.write(
      4, () => _opsBuffer.byteData.setInt32(_opsBuffer.offset, v));
  void _wf(double v) => _opsBuffer.write(
      4, () => _opsBuffer.byteData.setFloat32(_opsBuffer.offset, v));
  void _wb(bool v) => _opsBuffer.write(
      1, () => _opsBuffer.byteData.setUint8(_opsBuffer.offset, v ? 1 : 0));
  void _wu(int v) => _opsBuffer.write(
      1, () => _opsBuffer.byteData.setUint8(_opsBuffer.offset, v));

  int _allocRequestId() {
    _nextRequestId = _nextRequestId % 0xFFFF + 1;
    return _nextRequestId;
  }

  @override
  Future<void> initialize() {
    _ready = _doInitialize();
    return _ready!;
  }

  Future<void> _doInitialize() async {
    _responsePort = ReceivePort();
    _isolate =
        await Isolate.spawn(collisionIsolateEntry, _responsePort!.sendPort);
    final firstMessage = await _responsePort!.first;
    _commandPort = firstMessage as SendPort;
    _responsePort = ReceivePort();
    _commandPort!.send(_responsePort!.sendPort);
    _responsePort!.listen(_handleResponse);
  }

  void _handleResponse(dynamic message) {
    final bytes = message as Uint8List;
    final data = ByteData.sublistView(bytes);
    final requestId = data.getUint16(0);
    final completer = _pending.remove(requestId);
    completer?.complete(ByteData.sublistView(bytes, 2));
  }

  Future<ByteData> _send(Uint8ListBuffer buf) {
    final id = _allocRequestId();
    final completer = Completer<ByteData>();
    _pending[id] = completer;
    if (_commandPort != null) {
      _doSend(id, buf);
    } else if (_ready != null) {
      _ready!.then((_) => _doSend(id, buf));
    } else {
      _pending.remove(id);
      completer.completeError(
          StateError('Collision worker disposed'), StackTrace.current);
    }
    return completer.future;
  }

  void _doSend(int id, Uint8ListBuffer buf) {
    final out = Uint8ListBuffer();
    out.write(2, () => out.byteData.setUint16(out.offset, id));
    final payload = buf.compact;
    out.ensureCapacity(payload.length);
    out.write(payload.length, () {
      for (var i = 0; i < payload.length; i++) {
        out.byteData.setUint8(out.offset + i, payload[i]);
      }
    });
    _commandPort!.send(out.compact);
  }

  @override
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _responsePort?.close();
    _isolate = null;
    _commandPort = null;
    _responsePort = null;
    _ready = null;
    for (final c in _pending.values) {
      c.completeError(StateError('Collision worker disposed'));
    }
    _pending.clear();
  }

  @override
  int createShape(ColliderShapeType type) {
    final h = _nextHandle++;
    _op(CollisionBatchOp.createShape, () {
      _wi(h);
      _wu(type.index);
    });
    return h;
  }

  @override
  void destroyShape(int handle) =>
      _op(CollisionBatchOp.destroyShape, () => _wi(handle));

  @override
  void setShapeTransform(int handle, double x, double y, double angle) =>
      _op(CollisionBatchOp.setTransform, () {
        _wi(handle);
        _wf(x);
        _wf(y);
        _wf(angle);
      });

  @override
  void setShapeEnabled(int handle, bool enabled) =>
      _op(CollisionBatchOp.setEnabled, () {
        _wi(handle);
        _wb(enabled);
      });

  @override
  void setShapeLayer(int handle, int layer) =>
      _op(CollisionBatchOp.setLayer, () {
        _wi(handle);
        _wi(layer);
      });

  @override
  void setShapeExcludeLayers(int handle, int excludeLayers) =>
      _op(CollisionBatchOp.setExcludeLayers, () {
        _wi(handle);
        _wi(excludeLayers);
      });

  @override
  void setShapeOffset(int handle, double ox, double oy) =>
      _op(CollisionBatchOp.setOffset, () {
        _wi(handle);
        _wf(ox);
        _wf(oy);
      });

  @override
  void setShapeBox(int handle, double halfW, double halfH) =>
      _op(CollisionBatchOp.setBox, () {
        _wi(handle);
        _wf(halfW);
        _wf(halfH);
      });

  @override
  void setShapeCircle(int handle, double radius) =>
      _op(CollisionBatchOp.setCircle, () {
        _wi(handle);
        _wf(radius);
      });

  @override
  void setShapeCapsule(int handle, double halfLen, double radius, int dir) =>
      _op(CollisionBatchOp.setCapsule, () {
        _wi(handle);
        _wf(halfLen);
        _wf(radius);
        _wu(dir);
      });

  @override
  void setShapePolygon(int handle, Float32List vertices) =>
      _op(CollisionBatchOp.setPolygon, () {
        _wi(handle);
        final count = vertices.length ~/ 2;
        _wi(count);
        for (var i = 0; i < vertices.length; i++) {
          _wf(vertices[i]);
        }
      });

  @override
  void setShapeEdge(
          int handle, double x0, double y0, double x1, double y1) =>
      _op(CollisionBatchOp.setEdge, () {
        _wi(handle);
        _wf(x0);
        _wf(y0);
        _wf(x1);
        _wf(y1);
      });

  @override
  void setLayerMask(int layer, int mask) =>
      _op(CollisionBatchOp.setLayerMask, () {
        _wi(layer);
        _wi(mask);
      });

  @override
  void setIgnoreLayerCollision(int layer1, int layer2, bool ignore) =>
      _op(CollisionBatchOp.setIgnoreLayer, () {
        _wi(layer1);
        _wi(layer2);
        _wb(ignore);
      });

  @override
  Future<CollisionDelta> step() async {
    final sentCount = _opCount;
    final sentData = _opsBuffer.compact;

    final response = await _send(
        IsolateCollisionProtocol.writeStepWithBatch(sentCount, sentData));

    // Retain ops that arrived during the await for the next frame
    final asyncGapCount = _opCount - sentCount;
    if (asyncGapCount == 0) {
      _opsBuffer.clear();
      _opCount = 0;
    } else {
      final fullData = _opsBuffer.compact;
      _opsBuffer.clear();
      _opCount = 0;
      final gapBytes = fullData.sublist(sentData.length);
      _opsBuffer.ensureCapacity(gapBytes.length);
      _opsBuffer.write(gapBytes.length, () {
        for (var i = 0; i < gapBytes.length; i++) {
          _opsBuffer.byteData.setUint8(_opsBuffer.offset + i, gapBytes[i]);
        }
      });
      _opCount = asyncGapCount;
    }

    return IsolateCollisionProtocol.readDelta(response);
  }
}
