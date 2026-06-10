import 'dart:typed_data';
import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/rpc/buffer.dart';
import 'package:goo2d/src/physics/worker/data/contact_delta.dart';
import 'package:goo2d/src/physics/worker/data/raycast_hit_data.dart';
import 'package:goo2d/src/physics/worker/data/contact_point_data.dart';

/// Opcode categories for the binary protocol.
class Opcode {
  static const int step = 0;
  static const int getGlobal = 1;
  static const int setGlobalVec = 2;
  static const int setGlobalDouble = 3;
  static const int setGlobalInt = 4;
  static const int setGlobalBool = 5;
  static const int layerOp = 6;
  static const int layerIgnore = 7;
  static const int layerSetMask = 8;
  static const int colliderIgnore = 9;
  static const int colliderGetIgnore = 10;
  static const int createBody = 11;
  static const int destroyBody = 12;
  static const int getProp = 13;
  static const int setProp = 14;
  static const int bodyMethod = 15;
  static const int createCollider = 16;
  static const int destroyCollider = 17;
  static const int colliderMethod = 18;
  static const int createJoint = 19;
  static const int destroyJoint = 20;
  static const int createEffector = 21;
  static const int destroyEffector = 22;
  static const int raycast = 23;
  static const int linecast = 24;
  static const int boxCast = 25;
  static const int circleCast = 26;
  static const int capsuleCast = 27;
  static const int overlapCircle = 28;
  static const int overlapBox = 29;
  static const int overlapPoint = 30;
  static const int closestPoint = 31;
  static const int getContacts = 32;
  static const int getContactColliders = 33;
  static const int overlapCollider = 34;
  static const int syncTransforms = 35;
  static const int stepWithBatch = 36;
  static const int stepWithContactDelta = 37;
}

class GlobalPropId {
  static const int gravity = 0, callbacksOnDisable = 1, bounceThreshold = 2;
  static const int contactThreshold = 3, baumgarteTOIScale = 4, baumgarteScale = 5;
  static const int angularSleepTolerance = 6, linearSleepTolerance = 7;
  static const int defaultContactOffset = 8, maxAngularCorrection = 9;
  static const int maxLinearCorrection = 10, maxRotationSpeed = 11;
  static const int maxTranslationSpeed = 12, minSubStepFPS = 13, timeToSleep = 14;
  static const int positionIterations = 15, velocityIterations = 16;
  static const int maxSubStepCount = 17, maxPolygonShapeVertices = 18;
  static const int allLayers = 19, defaultRaycastLayers = 20, ignoreRaycastLayer = 21;
  static const int simulationLayers = 22, simulationMode = 23;
  static const int queriesStartInColliders = 24, queriesHitTriggers = 25;
  static const int reuseCollisionCallbacks = 26, useSubStepping = 27;
  static const int useSubStepContacts = 28;
}

class LayerOpId { static const int getIgnore = 0, getMask = 1; }

class BatchOpType {
  static const int createBody      = 0;
  static const int destroyBody     = 1;
  static const int setBodyProp     = 2;
  static const int createCollider  = 3;
  static const int destroyCollider = 4;
  static const int setColliderProp = 5;
  static const int createJoint     = 6;
  static const int destroyJoint    = 7;
  static const int setJointProp    = 8;
  static const int createEffector  = 9;
  static const int destroyEffector = 10;
  static const int setEffectorProp = 11;
}

class EntityType { static const int body = 0, collider = 1, joint = 2, effector = 3; }

class BodyMethodId {
  static const int addForce = 0, addForceAtPos = 1, addTorque = 2, addRelForce = 3;
  static const int movePos = 4, moveRot = 5, movePosRot = 6, setRot = 7;
  static const int wakeUp = 8, sleep = 9, isAwake = 10, isSleeping = 11;
  static const int getPoint = 12, getRelPoint = 13, getVector = 14, getRelVector = 15;
  static const int getPointVel = 16, getRelPointVel = 17, closestPoint = 18;
}

class ColliderMethodId {
  static const int closestPoint = 0, distance = 1, isTouching = 2, isTouchingLayers = 3, generateGeometry = 4;
}

/// Binary protocol for isolate communication: `object → binary`.
class IsolateProtocol {
  IsolateProtocol._();

  // ===================== Writers =====================
  static Uint8ListBuffer _buf(int opcode) {
    final b = Uint8ListBuffer(64);
    b.write(1, () => b.byteData.setUint8(b.offset, opcode));
    return b;
  }

  static void _writeDouble(Uint8ListBuffer b, double v) =>
      b.write(8, () => b.byteData.setFloat64(b.offset, v));
  static void _writeInt(Uint8ListBuffer b, int v) =>
      b.write(4, () => b.byteData.setInt32(b.offset, v));
  static void _writeBool(Uint8ListBuffer b, bool v) =>
      b.write(1, () => b.byteData.setUint8(b.offset, v ? 1 : 0));
  static void _writeVec(Uint8ListBuffer b, Vector2 v) {
    _writeDouble(b, v.x);
    _writeDouble(b, v.y);
  }

  static Uint8ListBuffer writeStep(double dt) { final b = _buf(Opcode.step); _writeDouble(b, dt); return b; }
  static Uint8ListBuffer writeGetGlobal(int prop) { final b = _buf(Opcode.getGlobal); _writeInt(b, prop); return b; }
  static Uint8ListBuffer writeSetGlobal(int prop, Vector2 v) { final b = _buf(Opcode.setGlobalVec); _writeInt(b, prop); _writeVec(b, v); return b; }
  static Uint8ListBuffer writeSetGlobalDouble(int prop, double v) { final b = _buf(Opcode.setGlobalDouble); _writeInt(b, prop); _writeDouble(b, v); return b; }
  static Uint8ListBuffer writeSetGlobalInt(int prop, int v) { final b = _buf(Opcode.setGlobalInt); _writeInt(b, prop); _writeInt(b, v); return b; }
  static Uint8ListBuffer writeSetGlobalBool(int prop, bool v) { final b = _buf(Opcode.setGlobalBool); _writeInt(b, prop); _writeBool(b, v); return b; }

  static Uint8ListBuffer writeLayerOp(int op, int l1, int l2) { final b = _buf(Opcode.layerOp); _writeInt(b, op); _writeInt(b, l1); _writeInt(b, l2); return b; }
  static Uint8ListBuffer writeLayerIgnore(int l1, int l2, bool v) { final b = _buf(Opcode.layerIgnore); _writeInt(b, l1); _writeInt(b, l2); _writeBool(b, v); return b; }
  static Uint8ListBuffer writeLayerSetMask(int l, int m) { final b = _buf(Opcode.layerSetMask); _writeInt(b, l); _writeInt(b, m); return b; }
  static Uint8ListBuffer writeColliderIgnore(int a, int bh, bool v) { final b = _buf(Opcode.colliderIgnore); _writeInt(b, a); _writeInt(b, bh); _writeBool(b, v); return b; }
  static Uint8ListBuffer writeColliderGetIgnore(int a, int bh) { final b = _buf(Opcode.colliderGetIgnore); _writeInt(b, a); _writeInt(b, bh); return b; }

  static Uint8ListBuffer writeCreateBody() => _buf(Opcode.createBody);
  static Uint8ListBuffer writeDestroyBody(int h) { final b = _buf(Opcode.destroyBody); _writeInt(b, h); return b; }
  static Uint8ListBuffer writeGetProp(int entity, int h, int p) { final b = _buf(Opcode.getProp); _writeInt(b, entity); _writeInt(b, h); _writeInt(b, p); return b; }

  static Uint8ListBuffer writeSetProp(int entity, int h, int p, Object? v) {
    final b = _buf(Opcode.setProp);
    _writeInt(b, entity); _writeInt(b, h); _writeInt(b, p);
    _writeObject(b, v);
    return b;
  }

  /// Public version for use by the isolate entry point.
  static void writeObjectTo(Uint8ListBuffer b, Object? v) => _writeObject(b, v);

  static void _writeObject(Uint8ListBuffer b, Object? v) {
    if (v == null) { b.write(1, () => b.byteData.setUint8(b.offset, 0)); return; }
    if (v is double) { b.write(1, () => b.byteData.setUint8(b.offset, 1)); _writeDouble(b, v); return; }
    if (v is int) { b.write(1, () => b.byteData.setUint8(b.offset, 2)); _writeInt(b, v); return; }
    if (v is bool) { b.write(1, () => b.byteData.setUint8(b.offset, 3)); _writeBool(b, v); return; }
    if (v is Vector2) { b.write(1, () => b.byteData.setUint8(b.offset, 4)); _writeVec(b, v); return; }
    if (v is List<Vector2>) {
      b.write(1, () => b.byteData.setUint8(b.offset, 5));
      _writeInt(b, v.length);
      for (final vec in v) { _writeVec(b, vec); }
      return;
    }
    throw ArgumentError('Unsupported object type: ${v.runtimeType}');
  }

  // Body methods
  static Uint8ListBuffer writeBodyMethod(int method, int h, Vector2 v, int mode) { final b = _buf(Opcode.bodyMethod); _writeInt(b, method); _writeInt(b, h); _writeVec(b, v); _writeInt(b, mode); return b; }
  static Uint8ListBuffer writeBodyMethodVV(int method, int h, Vector2 v1, Vector2 v2, int mode) { final b = _buf(Opcode.bodyMethod); _writeInt(b, method); _writeInt(b, h); _writeVec(b, v1); _writeVec(b, v2); _writeInt(b, mode); return b; }
  static Uint8ListBuffer writeBodyMethodDI(int method, int h, double d, int i) { final b = _buf(Opcode.bodyMethod); _writeInt(b, method); _writeInt(b, h); _writeDouble(b, d); _writeInt(b, i); return b; }
  static Uint8ListBuffer writeBodyMethodV(int method, int h, Vector2 v) { final b = _buf(Opcode.bodyMethod); _writeInt(b, method); _writeInt(b, h); _writeVec(b, v); return b; }
  static Uint8ListBuffer writeBodyMethodD(int method, int h, double d) { final b = _buf(Opcode.bodyMethod); _writeInt(b, method); _writeInt(b, h); _writeDouble(b, d); return b; }
  static Uint8ListBuffer writeBodyMethodVD(int method, int h, Vector2 v, double d) { final b = _buf(Opcode.bodyMethod); _writeInt(b, method); _writeInt(b, h); _writeVec(b, v); _writeDouble(b, d); return b; }
  static Uint8ListBuffer writeBodyMethodVoid(int method, int h) { final b = _buf(Opcode.bodyMethod); _writeInt(b, method); _writeInt(b, h); return b; }

  // Collider
  static Uint8ListBuffer writeCreateCollider(int type, int bh) { final b = _buf(Opcode.createCollider); _writeInt(b, type); _writeInt(b, bh); return b; }
  static Uint8ListBuffer writeDestroyCollider(int h) { final b = _buf(Opcode.destroyCollider); _writeInt(b, h); return b; }
  static Uint8ListBuffer writeColliderMethodV(int method, int h, Vector2 v) { final b = _buf(Opcode.colliderMethod); _writeInt(b, method); _writeInt(b, h); _writeVec(b, v); return b; }
  static Uint8ListBuffer writeColliderMethodII(int method, int a, int bh) { final b = _buf(Opcode.colliderMethod); _writeInt(b, method); _writeInt(b, a); _writeInt(b, bh); return b; }
  static Uint8ListBuffer writeColliderMethodI(int method, int h) { final b = _buf(Opcode.colliderMethod); _writeInt(b, method); _writeInt(b, h); return b; }

  // Joint / Effector
  static Uint8ListBuffer writeCreateJoint(int t, int bh) { final b = _buf(Opcode.createJoint); _writeInt(b, t); _writeInt(b, bh); return b; }
  static Uint8ListBuffer writeDestroyJoint(int h) { final b = _buf(Opcode.destroyJoint); _writeInt(b, h); return b; }
  static Uint8ListBuffer writeCreateEffector(int t) { final b = _buf(Opcode.createEffector); _writeInt(b, t); return b; }
  static Uint8ListBuffer writeDestroyEffector(int h) { final b = _buf(Opcode.destroyEffector); _writeInt(b, h); return b; }

  // Queries
  static Uint8ListBuffer writeRaycast(Vector2 o, Vector2 d, double dist, int lm, double mind, double maxd) { final b = _buf(Opcode.raycast); _writeVec(b, o); _writeVec(b, d); _writeDouble(b, dist); _writeInt(b, lm); _writeDouble(b, mind); _writeDouble(b, maxd); return b; }
  static Uint8ListBuffer writeLinecast(Vector2 s, Vector2 e, int lm, double mind, double maxd) { final b = _buf(Opcode.linecast); _writeVec(b, s); _writeVec(b, e); _writeInt(b, lm); _writeDouble(b, mind); _writeDouble(b, maxd); return b; }
  static Uint8ListBuffer writeBoxCast(Vector2 o, Vector2 sz, double a, Vector2 d, double dist, int lm, double mind, double maxd) { final b = _buf(Opcode.boxCast); _writeVec(b, o); _writeVec(b, sz); _writeDouble(b, a); _writeVec(b, d); _writeDouble(b, dist); _writeInt(b, lm); _writeDouble(b, mind); _writeDouble(b, maxd); return b; }
  static Uint8ListBuffer writeCircleCast(Vector2 o, double r, Vector2 d, double dist, int lm, double mind, double maxd) { final b = _buf(Opcode.circleCast); _writeVec(b, o); _writeDouble(b, r); _writeVec(b, d); _writeDouble(b, dist); _writeInt(b, lm); _writeDouble(b, mind); _writeDouble(b, maxd); return b; }
  static Uint8ListBuffer writeCapsuleCast(Vector2 o, Vector2 sz, int cd, double a, Vector2 d, double dist, int lm, double mind, double maxd) { final b = _buf(Opcode.capsuleCast); _writeVec(b, o); _writeVec(b, sz); _writeInt(b, cd); _writeDouble(b, a); _writeVec(b, d); _writeDouble(b, dist); _writeInt(b, lm); _writeDouble(b, mind); _writeDouble(b, maxd); return b; }
  static Uint8ListBuffer writeOverlapCircle(Vector2 p, double r, int lm, double mind, double maxd) { final b = _buf(Opcode.overlapCircle); _writeVec(b, p); _writeDouble(b, r); _writeInt(b, lm); _writeDouble(b, mind); _writeDouble(b, maxd); return b; }
  static Uint8ListBuffer writeOverlapBox(Vector2 p, Vector2 sz, double a, int lm, double mind, double maxd) { final b = _buf(Opcode.overlapBox); _writeVec(b, p); _writeVec(b, sz); _writeDouble(b, a); _writeInt(b, lm); _writeDouble(b, mind); _writeDouble(b, maxd); return b; }
  static Uint8ListBuffer writeOverlapPoint(Vector2 p, int lm, double mind, double maxd) { final b = _buf(Opcode.overlapPoint); _writeVec(b, p); _writeInt(b, lm); _writeDouble(b, mind); _writeDouble(b, maxd); return b; }
  static Uint8ListBuffer writeClosestPoint(Vector2 p, int ch) { final b = _buf(Opcode.closestPoint); _writeVec(b, p); _writeInt(b, ch); return b; }
  static Uint8ListBuffer writeGetContacts(int h) { final b = _buf(Opcode.getContacts); _writeInt(b, h); return b; }
  static Uint8ListBuffer writeGetContactColliders(int h) { final b = _buf(Opcode.getContactColliders); _writeInt(b, h); return b; }
  static Uint8ListBuffer writeOverlapCollider(int h) { final b = _buf(Opcode.overlapCollider); _writeInt(b, h); return b; }
  static Uint8ListBuffer writeSyncTransforms() => _buf(Opcode.syncTransforms);

  static Uint8ListBuffer writeStepWithContactDeltaBatch(
      double dt, int opCount, Uint8List opsData) {
    final b = _buf(Opcode.stepWithContactDelta);
    _writeDouble(b, dt);
    _writeInt(b, opCount);
    b.ensureCapacity(opsData.length);
    b.write(opsData.length, () {
      for (var i = 0; i < opsData.length; i++) {
        b.byteData.setUint8(b.offset + i, opsData[i]);
      }
    });
    return b;
  }

  /// Serializes a full ordered-op batch + step into one message.
  ///
  /// Format:
  ///   [1] opcode=stepWithBatch
  ///   [8] dt
  ///   [4] opCount
  ///   for each op: [1] BatchOpType  [variable] args  (see BatchOpType)
  static Uint8ListBuffer writeStepWithBatchOrdered(
      double dt, int opCount, Uint8List opsData) {
    final b = _buf(Opcode.stepWithBatch);
    _writeDouble(b, dt);
    _writeInt(b, opCount);
    b.ensureCapacity(opsData.length);
    b.write(opsData.length, () {
      for (var i = 0; i < opsData.length; i++) {
        b.byteData.setUint8(b.offset + i, opsData[i]);
      }
    });
    return b;
  }

  // ===================== Readers =====================
  static double readDouble(ByteData d) => d.getFloat64(0);
  static int readInt(ByteData d) => d.getInt32(0);
  static bool readBool(ByteData d) => d.getUint8(0) != 0;
  static Vector2 readVector2(ByteData d) => Vector2(d.getFloat64(0), d.getFloat64(8));

  static Object? readObject(ByteData d) {
    final type = d.getUint8(0);
    return switch (type) {
      0 => null,
      1 => d.getFloat64(1),
      2 => d.getInt32(1),
      3 => d.getUint8(1) != 0,
      4 => Vector2(d.getFloat64(1), d.getFloat64(9)),
      5 => () {
        final len = d.getInt32(1);
        final list = <Vector2>[];
        for (var i = 0; i < len; i++) {
          list.add(Vector2(d.getFloat64(5 + i * 16), d.getFloat64(13 + i * 16)));
        }
        return list;
      }(),
      _ => throw ArgumentError('Unknown object type tag: $type'),
    };
  }

  static List<int> readIntList(ByteData d) {
    final len = d.getInt32(0);
    return [for (var i = 0; i < len; i++) d.getInt32(4 + i * 4)];
  }

  static List<RaycastHitData> readRaycastHits(ByteData d) {
    final len = d.getInt32(0);
    final list = <RaycastHitData>[];
    var off = 4;
    for (var i = 0; i < len; i++) {
      list.add(RaycastHitData(
        point: Vector2(d.getFloat64(off), d.getFloat64(off + 8)),
        normal: Vector2(d.getFloat64(off + 16), d.getFloat64(off + 24)),
        centroid: Vector2(d.getFloat64(off + 32), d.getFloat64(off + 40)),
        distance: d.getFloat64(off + 48),
        fraction: d.getFloat64(off + 56),
        colliderHandle: d.getInt32(off + 64),
        bodyHandle: d.getInt32(off + 68),
      ));
      off += 72;
    }
    return list;
  }

  // Header: 8 × Int32 (array lengths), then raw bytes for each array.
  static Uint8ListBuffer writeContactDelta(ContactDelta d) {
    void writeI32List(Uint8ListBuffer b, Int32List list) {
      b.ensureCapacity(list.length * 4);
      b.write(list.length * 4, () {
        for (var i = 0; i < list.length; i++) {
          b.byteData.setInt32(b.offset + i * 4, list[i]);
        }
      });
    }

    void writeF32List(Uint8ListBuffer b, Float32List list) {
      b.ensureCapacity(list.length * 4);
      b.write(list.length * 4, () {
        for (var i = 0; i < list.length; i++) {
          b.byteData.setFloat32(b.offset + i * 4, list[i]);
        }
      });
    }

    final b = Uint8ListBuffer(32);
    _writeInt(b, d.enterContacts.length);
    _writeInt(b, d.stayContacts.length);
    _writeInt(b, d.exitContacts.length);
    _writeInt(b, d.enterTriggers.length);
    _writeInt(b, d.stayTriggers.length);
    _writeInt(b, d.exitTriggers.length);
    _writeInt(b, d.contactPoints.length);
    _writeInt(b, d.contactPointCounts.length);
    writeI32List(b, d.enterContacts);
    writeI32List(b, d.stayContacts);
    writeI32List(b, d.exitContacts);
    writeI32List(b, d.enterTriggers);
    writeI32List(b, d.stayTriggers);
    writeI32List(b, d.exitTriggers);
    writeF32List(b, d.contactPoints);
    writeI32List(b, d.contactPointCounts);
    return b;
  }

  static ContactDelta readContactDelta(ByteData d) {
    var off = 0;
    int ri() { final v = d.getInt32(off); off += 4; return v; }

    final ecLen = ri(); final scLen = ri(); final xcLen = ri();
    final etLen = ri(); final stLen = ri(); final xtLen = ri();
    final ptLen = ri(); final pcLen = ri();

    Int32List readI32(int len) {
      final list = Int32List(len);
      for (var i = 0; i < len; i++) { list[i] = d.getInt32(off); off += 4; }
      return list;
    }

    Float32List readF32(int len) {
      final list = Float32List(len);
      for (var i = 0; i < len; i++) { list[i] = d.getFloat32(off); off += 4; }
      return list;
    }

    return ContactDelta(
      enterContacts: readI32(ecLen),
      stayContacts: readI32(scLen),
      exitContacts: readI32(xcLen),
      enterTriggers: readI32(etLen),
      stayTriggers: readI32(stLen),
      exitTriggers: readI32(xtLen),
      contactPoints: readF32(ptLen),
      contactPointCounts: readI32(pcLen),
    );
  }

  static List<ContactPointData> readContactPoints(ByteData d) {
    final len = d.getInt32(0);
    final list = <ContactPointData>[];
    var off = 4;
    for (var i = 0; i < len; i++) {
      list.add(ContactPointData(
        point: Vector2(d.getFloat64(off), d.getFloat64(off + 8)),
        normal: Vector2(d.getFloat64(off + 16), d.getFloat64(off + 24)),
        relativeVelocity: Vector2(d.getFloat64(off + 32), d.getFloat64(off + 40)),
        separation: d.getFloat64(off + 48),
        normalImpulse: d.getFloat64(off + 56),
        tangentImpulse: d.getFloat64(off + 64),
        colliderHandle: d.getInt32(off + 72),
        otherColliderHandle: d.getInt32(off + 76),
      ));
      off += 80;
    }
    return list;
  }
}
