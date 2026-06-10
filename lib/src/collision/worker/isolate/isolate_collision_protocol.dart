import 'dart:typed_data';
import 'package:goo2d/src/collision/worker/collision_delta.dart';
import 'package:goo2d/src/rpc/buffer.dart';

/// Op-codes for the ordered batch carried in a [stepWithBatch] message.
abstract class CollisionBatchOp {
  static const createShape = 0x01;
  static const destroyShape = 0x02;
  static const setTransform = 0x03;
  static const setEnabled = 0x04;
  static const setLayer = 0x05;
  static const setExcludeLayers = 0x06;
  static const setOffset = 0x07;
  static const setBox = 0x08;
  static const setCircle = 0x09;
  static const setCapsule = 0x0A;
  static const setPolygon = 0x0B;
  static const setEdge = 0x0C;
  static const setLayerMask = 0x0D;
  static const setIgnoreLayer = 0x0E;
}

/// Top-level message op-codes.
abstract class CollisionOpcode {
  static const stepWithBatch = 0x01;
}

class IsolateCollisionProtocol {
  static Uint8ListBuffer writeStepWithBatch(
      int opCount, Uint8List opsData) {
    final buf = Uint8ListBuffer(1 + 4 + opsData.length);
    buf.write(1, () => buf.byteData.setUint8(buf.offset, CollisionOpcode.stepWithBatch));
    buf.write(4, () => buf.byteData.setInt32(buf.offset, opCount));
    buf.ensureCapacity(opsData.length);
    buf.write(opsData.length, () {
      for (var i = 0; i < opsData.length; i++) {
        buf.byteData.setUint8(buf.offset + i, opsData[i]);
      }
    });
    return buf;
  }

  static CollisionDelta readDelta(ByteData data) {
    var off = 0;
    final enterCount = data.getInt32(off); off += 4;
    final stayCount = data.getInt32(off); off += 4;
    final exitCount = data.getInt32(off); off += 4;

    final enter = Int32List(enterCount * 2);
    for (var i = 0; i < enterCount * 2; i++) {
      enter[i] = data.getInt32(off); off += 4;
    }
    final stay = Int32List(stayCount * 2);
    for (var i = 0; i < stayCount * 2; i++) {
      stay[i] = data.getInt32(off); off += 4;
    }
    final exit = Int32List(exitCount * 2);
    for (var i = 0; i < exitCount * 2; i++) {
      exit[i] = data.getInt32(off); off += 4;
    }

    return CollisionDelta(enterPairs: enter, stayPairs: stay, exitPairs: exit);
  }

  static Uint8ListBuffer writeDelta(CollisionDelta delta) {
    final ec = delta.enterPairs.length ~/ 2;
    final sc = delta.stayPairs.length ~/ 2;
    final xc = delta.exitPairs.length ~/ 2;
    final total = 12 + (ec + sc + xc) * 2 * 4;
    final buf = Uint8ListBuffer(total);
    buf.write(4, () => buf.byteData.setInt32(buf.offset, ec));
    buf.write(4, () => buf.byteData.setInt32(buf.offset, sc));
    buf.write(4, () => buf.byteData.setInt32(buf.offset, xc));
    void writePairs(Int32List pairs) {
      for (var i = 0; i < pairs.length; i++) {
        buf.write(4, () => buf.byteData.setInt32(buf.offset, pairs[i]));
      }
    }
    writePairs(delta.enterPairs);
    writePairs(delta.stayPairs);
    writePairs(delta.exitPairs);
    return buf;
  }
}
