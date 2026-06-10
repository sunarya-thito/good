import 'dart:isolate';
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/rpc/buffer.dart';
import 'package:goo2d/src/physics/worker/engine/physics_engine.dart';
import 'package:goo2d/src/physics/worker/engine/physics_body.dart';
import 'package:goo2d/src/physics/worker/engine/physics_collider.dart';
import 'package:goo2d/src/physics/worker/engine/physics_joint.dart';
import 'package:goo2d/src/physics/worker/engine/physics_effector.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';
import 'package:goo2d/src/physics/worker/data/raycast_hit_data.dart';
import 'package:goo2d/src/physics/worker/data/contact_point_data.dart';
import 'package:goo2d/src/physics/worker/isolate/isolate_protocol.dart';
import 'package:goo2d/src/physics/worker/direct/direct_body_ops.dart';
import 'package:goo2d/src/physics/worker/direct/direct_collider_ops.dart';
import 'package:goo2d/src/physics/worker/direct/direct_joint_ops.dart';
import 'package:goo2d/src/physics/worker/direct/direct_effector_ops.dart';

/// Entry point for the physics isolate.
void isolateEntry(SendPort mainPort) {
  final engine = PhysicsEngine();
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

    final result = _dispatch(engine, payload);

    if (requestId != 0 && result != null) {
      // Send response with request ID prepended
      final out = Uint8ListBuffer();
      out.write(2, () => out.byteData.setUint16(out.offset, requestId));
      final r = result.compact;
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

Uint8ListBuffer? _dispatch(PhysicsEngine engine, ByteData data) {
  final opcode = data.getUint8(0);
  var off = 1;

  double rd() { final v = data.getFloat64(off); off += 8; return v; }
  int ri() { final v = data.getInt32(off); off += 4; return v; }
  bool rb() { final v = data.getUint8(off) != 0; off += 1; return v; }
  Vector2 rv() => Vector2(rd(), rd());
  Object? ro() {
    final type = data.getUint8(off); off += 1;
    switch (type) {
      case 0: return null;
      case 1: final v = data.getFloat64(off); off += 8; return v;
      case 2: final v = data.getInt32(off); off += 4; return v;
      case 3: final v = data.getUint8(off) != 0; off += 1; return v;
      case 4: final v = Vector2(data.getFloat64(off), data.getFloat64(off + 8)); off += 16; return v;
      default: throw ArgumentError('Unknown object type: $type');
    }
  }

  Uint8ListBuffer respDouble(double v) {
    final b = Uint8ListBuffer(8);
    b.write(8, () => b.byteData.setFloat64(b.offset, v));
    return b;
  }
  Uint8ListBuffer respInt(int v) {
    final b = Uint8ListBuffer(4);
    b.write(4, () => b.byteData.setInt32(b.offset, v));
    return b;
  }
  Uint8ListBuffer respBool(bool v) {
    final b = Uint8ListBuffer(1);
    b.write(1, () => b.byteData.setUint8(b.offset, v ? 1 : 0));
    return b;
  }
  Uint8ListBuffer respVec(Vector2 v) {
    final b = Uint8ListBuffer(16);
    b.write(8, () => b.byteData.setFloat64(b.offset, v.x));
    b.write(8, () => b.byteData.setFloat64(b.offset, v.y));
    return b;
  }

  switch (opcode) {
    case Opcode.stepWithBatch:
      {
        final dt = rd();
        final opCount = ri();
        for (var i = 0; i < opCount; i++) {
          final opType = data.getUint8(off); off += 1;
          switch (opType) {
            case BatchOpType.createBody:
              engine.createBodyWithHandle(ri());
            case BatchOpType.destroyBody:
              engine.destroyBody(ri());
            case BatchOpType.setBodyProp:
              final h = ri(); final p = ri(); DirectBodyOps.setProperty(engine, h, p, ro());
            case BatchOpType.createCollider:
              engine.createColliderWithHandle(ri(), ColliderShapeType.values[ri()], ri());
            case BatchOpType.destroyCollider:
              engine.destroyCollider(ri());
            case BatchOpType.setColliderProp:
              final h = ri(); final p = ri(); DirectColliderOps.setProperty(engine, h, p, ro());
            case BatchOpType.createJoint:
              engine.createJointWithHandle(ri(), ri(), ri());
            case BatchOpType.destroyJoint:
              engine.destroyJoint(ri());
            case BatchOpType.setJointProp:
              final h = ri(); final p = ri(); DirectJointOps.setProperty(engine, h, p, ro());
            case BatchOpType.createEffector:
              engine.createEffectorWithHandle(ri(), ri());
            case BatchOpType.destroyEffector:
              engine.destroyEffector(ri());
            case BatchOpType.setEffectorProp:
              final h = ri(); final p = ri(); DirectEffectorOps.setProperty(engine, h, p, ro());
          }
        }
        engine.step(dt);
      }
      return Uint8ListBuffer();

    case Opcode.stepWithContactDelta:
      {
        final dt = rd();
        final opCount = ri();
        for (var i = 0; i < opCount; i++) {
          final opType = data.getUint8(off); off += 1;
          switch (opType) {
            case BatchOpType.createBody:
              engine.createBodyWithHandle(ri());
            case BatchOpType.destroyBody:
              engine.destroyBody(ri());
            case BatchOpType.setBodyProp:
              final h = ri(); final p = ri(); DirectBodyOps.setProperty(engine, h, p, ro());
            case BatchOpType.createCollider:
              engine.createColliderWithHandle(ri(), ColliderShapeType.values[ri()], ri());
            case BatchOpType.destroyCollider:
              engine.destroyCollider(ri());
            case BatchOpType.setColliderProp:
              final h = ri(); final p = ri(); DirectColliderOps.setProperty(engine, h, p, ro());
            case BatchOpType.createJoint:
              engine.createJointWithHandle(ri(), ri(), ri());
            case BatchOpType.destroyJoint:
              engine.destroyJoint(ri());
            case BatchOpType.setJointProp:
              final h = ri(); final p = ri(); DirectJointOps.setProperty(engine, h, p, ro());
            case BatchOpType.createEffector:
              engine.createEffectorWithHandle(ri(), ri());
            case BatchOpType.destroyEffector:
              engine.destroyEffector(ri());
            case BatchOpType.setEffectorProp:
              final h = ri(); final p = ri(); DirectEffectorOps.setProperty(engine, h, p, ro());
          }
        }
        return IsolateProtocol.writeContactDelta(engine.stepDelta(dt));
      }

    case Opcode.step:
      engine.step(rd());
      return Uint8ListBuffer();
    case Opcode.syncTransforms:
      engine.syncTransforms();
      return null;

    case Opcode.getGlobal:
      final prop = ri();
      return _getGlobalProp(engine, prop, respDouble, respInt, respBool, respVec);

    case Opcode.setGlobalVec:
      final prop = ri();
      final v = rv();
      _setGlobalVec(engine, prop, v);
      return null;
    case Opcode.setGlobalDouble:
      final prop = ri();
      final v = rd();
      _setGlobalDouble(engine, prop, v);
      return null;
    case Opcode.setGlobalInt:
      final prop = ri();
      final v = ri();
      _setGlobalInt(engine, prop, v);
      return null;
    case Opcode.setGlobalBool:
      final prop = ri();
      final v = rb();
      _setGlobalBool(engine, prop, v);
      return null;

    case Opcode.createBody:
      return respInt(engine.createBody());
    case Opcode.destroyBody:
      engine.destroyBody(ri());
      return null;

    case Opcode.createCollider:
      final type = ri();
      final bh = ri();
      return respInt(engine.createCollider(ColliderShapeType.values[type], bh));
    case Opcode.destroyCollider:
      engine.destroyCollider(ri());
      return null;

    case Opcode.createJoint:
      final t = ri();
      final bh = ri();
      return respInt(engine.createJoint(t, bh));
    case Opcode.destroyJoint:
      engine.destroyJoint(ri());
      return null;

    case Opcode.createEffector:
      return respInt(engine.createEffector(ri()));
    case Opcode.destroyEffector:
      engine.destroyEffector(ri());
      return null;

    case Opcode.getProp:
      final entity = ri();
      final h = ri();
      final p = ri();
      return _getProp(engine, entity, h, p);

    case Opcode.setProp:
      final entity = ri();
      final h = ri();
      final p = ri();
      final v = _readObject(data, off);
      _setProp(engine, entity, h, p, v.value);
      return null;

    case Opcode.bodyMethod:
      final method = ri();
      final h = ri();
      final body = engine.getBody(h);
      switch (method) {
        case BodyMethodId.addForce:       body.addForce(rv(), ri()); return null;
        case BodyMethodId.addForceAtPos:  body.addForceAtPosition(rv(), rv(), ri()); return null;
        case BodyMethodId.addTorque:      body.addTorque(rd(), ri()); return null;
        case BodyMethodId.addRelForce:    body.addRelativeForce(rv(), ri()); return null;
        case BodyMethodId.movePos:        body.movePosition(rv()); return null;
        case BodyMethodId.moveRot:        body.moveRotation(rd()); return null;
        case BodyMethodId.movePosRot:     body.movePositionAndRotation(rv(), rd()); return null;
        case BodyMethodId.setRot:         body.setRotation(rd()); return null;
        case BodyMethodId.wakeUp:         body.wake(); return null;
        case BodyMethodId.sleep:          body.putToSleep(); return null;
        case BodyMethodId.isAwake:        return respBool(body.isAwake);
        case BodyMethodId.isSleeping:     return respBool(body.isSleeping);
        case BodyMethodId.getPoint:       return respVec(body.getPoint(rv()));
        case BodyMethodId.getRelPoint:    return respVec(body.getRelativePoint(rv()));
        case BodyMethodId.getVector:      return respVec(body.getVector(rv()));
        case BodyMethodId.getRelVector:   return respVec(body.getRelativeVector(rv()));
        case BodyMethodId.getPointVel:    return respVec(body.getPointVelocity(rv()));
        case BodyMethodId.getRelPointVel: return respVec(body.getRelativePointVelocity(rv()));
        case BodyMethodId.closestPoint:   return respVec(engine.closestPoint(rv(), h));
      }
      return null;

    case Opcode.raycast:
      final o = rv(); final d = rv(); final dist = rd(); final lm = ri(); final mind = rd(); final maxd = rd();
      return _writeRaycastResult(engine.raycast(o, d, dist, lm, mind, maxd));
    case Opcode.linecast:
      final s = rv(); final e = rv(); final lm = ri(); final mind = rd(); final maxd = rd();
      return _writeRaycastResult(engine.linecast(s, e, lm, mind, maxd));

    case Opcode.colliderMethod:
      final method = ri();
      final h = ri();
      switch (method) {
        case ColliderMethodId.closestPoint:
          return respVec(engine.closestPoint(rv(), h));
        case ColliderMethodId.distance:
          return respDouble(engine.distanceBetween(h, ri()));
        case ColliderMethodId.isTouching:
          return respBool(engine.isTouching(h, ri()));
        case ColliderMethodId.isTouchingLayers:
          return respBool(engine.isTouchingLayers(h, ri()));
        case ColliderMethodId.generateGeometry:
          engine.getCollider(h).generateGeometry();
          return respBool(true); // Return something to complete the future
      }
      return null;

    case Opcode.overlapCircle:
      final p = rv(); final r = rd(); final lm = ri(); final mind = rd(); final maxd = rd();
      return _writeIntList(engine.overlapCircle(p, r, lm, mind, maxd));
    case Opcode.overlapPoint:
      final p = rv(); final lm = ri(); final mind = rd(); final maxd = rd();
      return _writeIntList(engine.overlapPoint(p, lm, mind, maxd));

    case Opcode.closestPoint:
      final p = rv(); final ch = ri();
      return respVec(engine.closestPoint(p, ch));

    case Opcode.getContacts:
      return _writeContactPoints(engine.getContacts(ri()));
    case Opcode.getContactColliders:
      return _writeIntList(engine.getContactColliders(ri()));
    case Opcode.overlapCollider:
      return _writeIntList(engine.overlapCollider(ri()));

    default:
      return null;
  }
}

// Helpers for global property dispatch (abbreviated for key props)
Uint8ListBuffer? _getGlobalProp(PhysicsEngine e, int prop,
    Uint8ListBuffer Function(double) rd, Uint8ListBuffer Function(int) ri,
    Uint8ListBuffer Function(bool) rb, Uint8ListBuffer Function(Vector2) rv) {
  return switch (prop) {
    GlobalPropId.gravity => rv(e.gravity),
    GlobalPropId.callbacksOnDisable => rb(e.callbacksOnDisable),
    GlobalPropId.bounceThreshold => rd(e.bounceThreshold),
    GlobalPropId.contactThreshold => rd(e.contactThreshold),
    GlobalPropId.baumgarteTOIScale => rd(e.baumgarteTOIScale),
    GlobalPropId.baumgarteScale => rd(e.baumgarteScale),
    GlobalPropId.angularSleepTolerance => rd(e.angularSleepTolerance),
    GlobalPropId.linearSleepTolerance => rd(e.linearSleepTolerance),
    GlobalPropId.defaultContactOffset => rd(e.defaultContactOffset),
    GlobalPropId.maxAngularCorrection => rd(e.maxAngularCorrection),
    GlobalPropId.maxLinearCorrection => rd(e.maxLinearCorrection),
    GlobalPropId.maxRotationSpeed => rd(e.maxRotationSpeed),
    GlobalPropId.maxTranslationSpeed => rd(e.maxTranslationSpeed),
    GlobalPropId.minSubStepFPS => rd(e.minSubStepFPS),
    GlobalPropId.timeToSleep => rd(e.timeToSleep),
    GlobalPropId.positionIterations => ri(e.positionIterations),
    GlobalPropId.velocityIterations => ri(e.velocityIterations),
    GlobalPropId.maxSubStepCount => ri(e.maxSubStepCount),
    GlobalPropId.maxPolygonShapeVertices => ri(e.maxPolygonShapeVertices),
    GlobalPropId.allLayers => ri(e.allLayers),
    GlobalPropId.defaultRaycastLayers => ri(e.defaultRaycastLayers),
    GlobalPropId.ignoreRaycastLayer => ri(e.ignoreRaycastLayer),
    GlobalPropId.simulationLayers => ri(e.simulationLayers),
    GlobalPropId.simulationMode => ri(e.simulationMode),
    GlobalPropId.queriesStartInColliders => rb(e.queriesStartInColliders),
    GlobalPropId.queriesHitTriggers => rb(e.queriesHitTriggers),
    GlobalPropId.reuseCollisionCallbacks => rb(e.reuseCollisionCallbacks),
    GlobalPropId.useSubStepping => rb(e.useSubStepping),
    GlobalPropId.useSubStepContacts => rb(e.useSubStepContacts),
    _ => null,
  };
}

void _setGlobalVec(PhysicsEngine e, int prop, Vector2 v) {
  if (prop == GlobalPropId.gravity) e.gravity = v;
}
void _setGlobalDouble(PhysicsEngine e, int prop, double v) {
  switch (prop) {
    case GlobalPropId.bounceThreshold: e.bounceThreshold = v;
    case GlobalPropId.contactThreshold: e.contactThreshold = v;
    case GlobalPropId.baumgarteTOIScale: e.baumgarteTOIScale = v;
    case GlobalPropId.baumgarteScale: e.baumgarteScale = v;
    case GlobalPropId.angularSleepTolerance: e.angularSleepTolerance = v;
    case GlobalPropId.linearSleepTolerance: e.linearSleepTolerance = v;
    case GlobalPropId.defaultContactOffset: e.defaultContactOffset = v;
    case GlobalPropId.maxAngularCorrection: e.maxAngularCorrection = v;
    case GlobalPropId.maxLinearCorrection: e.maxLinearCorrection = v;
    case GlobalPropId.maxRotationSpeed: e.maxRotationSpeed = v;
    case GlobalPropId.maxTranslationSpeed: e.maxTranslationSpeed = v;
    case GlobalPropId.minSubStepFPS: e.minSubStepFPS = v;
    case GlobalPropId.timeToSleep: e.timeToSleep = v;
  }
}
void _setGlobalInt(PhysicsEngine e, int prop, int v) {
  switch (prop) {
    case GlobalPropId.positionIterations: e.positionIterations = v;
    case GlobalPropId.velocityIterations: e.velocityIterations = v;
    case GlobalPropId.maxSubStepCount: e.maxSubStepCount = v;
    case GlobalPropId.simulationLayers: e.simulationLayers = v;
    case GlobalPropId.simulationMode: e.simulationMode = v;
  }
}
void _setGlobalBool(PhysicsEngine e, int prop, bool v) {
  switch (prop) {
    case GlobalPropId.callbacksOnDisable: e.callbacksOnDisable = v;
    case GlobalPropId.queriesStartInColliders: e.queriesStartInColliders = v;
    case GlobalPropId.queriesHitTriggers: e.queriesHitTriggers = v;
    case GlobalPropId.reuseCollisionCallbacks: e.reuseCollisionCallbacks = v;
    case GlobalPropId.useSubStepping: e.useSubStepping = v;
    case GlobalPropId.useSubStepContacts: e.useSubStepContacts = v;
  }
}

Uint8ListBuffer? _getProp(PhysicsEngine e, int entity, int h, int p) {
  Object? value;
  switch (entity) {
    case EntityType.body:
      final body = e.getBody(h);
      value = _getBodyPropSync(body, p);
    case EntityType.collider:
      final col = e.getCollider(h);
      value = _getColliderPropSync(col, p);
    case EntityType.joint:
      final j = e.getJoint(h);
      value = _getJointPropSync(j, p);
    case EntityType.effector:
      final ef = e.getEffector(h);
      value = _getEffectorPropSync(ef, p);
    default: return null;
  }
  final b = Uint8ListBuffer(32);
  IsolateProtocol.writeObjectTo(b, value);
  return b;
}

void _setProp(PhysicsEngine e, int entity, int h, int p, Object? v) {
  switch (entity) {
    case EntityType.body: DirectBodyOps.setProperty(e, h, p, v);
    case EntityType.collider: DirectColliderOps.setProperty(e, h, p, v);
    case EntityType.joint: DirectJointOps.setProperty(e, h, p, v);
    case EntityType.effector: DirectEffectorOps.setProperty(e, h, p, v);
  }
}

Object? _getBodyPropSync(EngineBody body, int p) {
  return switch (p) {
    BodyProp.position => body.position,
    BodyProp.rotation => body.rotation,
    BodyProp.linearVelocity => body.linearVelocity,
    BodyProp.angularVelocity => body.angularVelocity,
    BodyProp.mass => body.mass,
    BodyProp.simulated => body.simulated,
    BodyProp.bodyType => body.bodyType,
    BodyProp.gravityScale => body.gravityScale,
    _ => null, // Fallback for non-critical props
  };
}

Object? _getColliderPropSync(PhysicsCollider col, int p) {
  return switch (p) {
    ColliderProp.offset => col.offset,
    ColliderProp.isTrigger => col.isTrigger,
    ColliderProp.density => col.density,
    ColliderProp.friction => col.friction,
    ColliderProp.bounciness => col.bounciness,
    _ => null,
  };
}

Object? _getJointPropSync(PhysicsJoint j, int p) {
  return switch (p) {
    JointProp.breakForce => j.breakForce,
    JointProp.breakTorque => j.breakTorque,
    JointProp.anchor => j.anchor,
    JointProp.connectedAnchor => j.connectedAnchor,
    _ => null,
  };
}

Object? _getEffectorPropSync(PhysicsEffector ef, int p) {
  return switch (p) {
    EffectorProp.colliderMask => ef.colliderMask,
    EffectorProp.useColliderMask => ef.useColliderMask,
    _ => null,
  };
}

({Object? value, int length}) _readObject(ByteData d, int off) {
  final type = d.getUint8(off);
  off += 1;
  return switch (type) {
    0 => (value: null, length: 1),
    1 => (value: d.getFloat64(off), length: 9),
    2 => (value: d.getInt32(off), length: 5),
    3 => (value: d.getUint8(off) != 0, length: 2),
    4 => (value: Vector2(d.getFloat64(off), d.getFloat64(off + 8)), length: 17),
    _ => (value: null, length: 1),
  };
}

Uint8ListBuffer _writeRaycastResult(List result) {
  final b = Uint8ListBuffer();
  b.write(4, () => b.byteData.setInt32(b.offset, result.length));
  for (final hit in result) {
    if (hit is! RaycastHitData) continue;
    b.write(8, () => b.byteData.setFloat64(b.offset, hit.point.x));
    b.write(8, () => b.byteData.setFloat64(b.offset, hit.point.y));
    b.write(8, () => b.byteData.setFloat64(b.offset, hit.normal.x));
    b.write(8, () => b.byteData.setFloat64(b.offset, hit.normal.y));
    b.write(8, () => b.byteData.setFloat64(b.offset, hit.centroid.x));
    b.write(8, () => b.byteData.setFloat64(b.offset, hit.centroid.y));
    b.write(8, () => b.byteData.setFloat64(b.offset, hit.distance));
    b.write(8, () => b.byteData.setFloat64(b.offset, hit.fraction));
    b.write(4, () => b.byteData.setInt32(b.offset, hit.colliderHandle));
    b.write(4, () => b.byteData.setInt32(b.offset, hit.bodyHandle));
  }
  return b;
}

Uint8ListBuffer _writeIntList(List<int> list) {
  final b = Uint8ListBuffer();
  b.write(4, () => b.byteData.setInt32(b.offset, list.length));
  for (final v in list) {
    b.write(4, () => b.byteData.setInt32(b.offset, v));
  }
  return b;
}

Uint8ListBuffer _writeContactPoints(List result) {
  final contacts = result.cast<ContactPointData>();
  final b = Uint8ListBuffer(4 + contacts.length * 80);
  b.write(4, () => b.byteData.setInt32(b.offset, contacts.length));
  for (final c in contacts) {
    b.write(80, () {
      final o = b.offset;
      b.byteData.setFloat64(o,      c.point.x);
      b.byteData.setFloat64(o + 8,  c.point.y);
      b.byteData.setFloat64(o + 16, c.normal.x);
      b.byteData.setFloat64(o + 24, c.normal.y);
      b.byteData.setFloat64(o + 32, c.relativeVelocity.x);
      b.byteData.setFloat64(o + 40, c.relativeVelocity.y);
      b.byteData.setFloat64(o + 48, c.separation);
      b.byteData.setFloat64(o + 56, c.normalImpulse);
      b.byteData.setFloat64(o + 64, c.tangentImpulse);
      b.byteData.setInt32(o + 72,   c.colliderHandle);
      b.byteData.setInt32(o + 76,   c.otherColliderHandle);
    });
  }
  return b;
}
