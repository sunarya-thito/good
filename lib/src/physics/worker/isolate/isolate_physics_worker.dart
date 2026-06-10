import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/physics/worker/physics_worker.dart';
import 'package:goo2d/src/physics/worker/isolate/isolate_entry.dart';
import 'package:goo2d/src/physics/worker/isolate/isolate_protocol.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';
import 'package:goo2d/src/physics/worker/data/contact_delta.dart';
import 'package:goo2d/src/physics/worker/data/raycast_hit_data.dart';
import 'package:goo2d/src/physics/worker/data/contact_point_data.dart';
import 'package:goo2d/src/rpc/buffer.dart';

/// Physics worker that runs the engine on a separate isolate.
///
/// Mutation methods (create/destroy/setProperty) are synchronous — they
/// accumulate into pending lists/maps. `step()` flushes everything as a single
/// `stepWithBatch` message, guaranteed to arrive before engine.step() runs in
/// the isolate, eliminating the initialization race.
class IsolatePhysicsWorker implements PhysicsWorker {
  Isolate? _isolate;
  SendPort? _commandPort;
  ReceivePort? _responsePort;
  Future<void>? _ready;

  int _nextRequestId = 0;
  final Map<int, Completer<ByteData>> _pending = {};

  // Handle allocation — main thread owns IDs.
  int _nextHandle = 1;
  int _allocHandle() => _nextHandle++;

  // Ordered ops accumulated this frame
  Uint8ListBuffer _opsBuffer = Uint8ListBuffer();
  int _opCount = 0;

  void _op(int opType, void Function() write) {
    _opsBuffer.write(1, () => _opsBuffer.byteData.setUint8(_opsBuffer.offset, opType));
    write();
    _opCount++;
  }

  void _wi(int v) => _opsBuffer.write(4, () => _opsBuffer.byteData.setInt32(_opsBuffer.offset, v));
  void _wo(Object? v) => IsolateProtocol.writeObjectTo(_opsBuffer, v);

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
    _isolate = await Isolate.spawn(isolateEntry, _responsePort!.sendPort);
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
      completer.completeError(StateError('Physics worker disposed'), StackTrace.current);
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

  void _sendFireAndForget(Uint8ListBuffer buf) {
    if (_commandPort != null) {
      _doFireAndForget(buf);
    } else if (_ready != null) {
      _ready!.then((_) => _doFireAndForget(buf));
    }
  }

  void _doFireAndForget(Uint8ListBuffer buf) {
    final out = Uint8ListBuffer();
    out.write(2, () => out.byteData.setUint16(out.offset, 0));
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
  }

  @override
  Future<void> step(double deltaTime) async {
    final sentCount = _opCount;
    final sentData = _opsBuffer.compact;

    await _send(IsolateProtocol.writeStepWithBatchOrdered(deltaTime, sentCount, sentData));

    // Ops that fired during the await must survive into the next frame.
    final asyncGapCount = _opCount - sentCount;
    if (asyncGapCount == 0) {
      _opsBuffer.clear();
      _opCount = 0;
    } else {
      final fullData = _opsBuffer.compact;
      _opsBuffer.clear();
      _opCount = 0;
      final gapBytes = fullData.sublist(sentData.length);
      _opsBuffer.write(gapBytes.length, () {
        for (var i = 0; i < gapBytes.length; i++) {
          _opsBuffer.byteData.setUint8(_opsBuffer.offset + i, gapBytes[i]);
        }
      });
      _opCount = asyncGapCount;
    }
  }

  @override
  Future<ContactDelta> stepWithContactDelta(double deltaTime) async {
    final sentCount = _opCount;
    final sentData = _opsBuffer.compact;

    final response = await _send(
      IsolateProtocol.writeStepWithContactDeltaBatch(deltaTime, sentCount, sentData),
    );

    final asyncGapCount = _opCount - sentCount;
    if (asyncGapCount == 0) {
      _opsBuffer.clear();
      _opCount = 0;
    } else {
      final fullData = _opsBuffer.compact;
      _opsBuffer.clear();
      _opCount = 0;
      final gapBytes = fullData.sublist(sentData.length);
      _opsBuffer.write(gapBytes.length, () {
        for (var i = 0; i < gapBytes.length; i++) {
          _opsBuffer.byteData.setUint8(_opsBuffer.offset + i, gapBytes[i]);
        }
      });
      _opCount = asyncGapCount;
    }

    return IsolateProtocol.readContactDelta(response);
  }

  // ===================== Body (synchronous — queue into batch) =====================
  @override
  int createBody() {
    final h = _allocHandle();
    _op(BatchOpType.createBody, () => _wi(h));
    return h;
  }

  @override
  void destroyBody(int h) =>
      _op(BatchOpType.destroyBody, () => _wi(h));

  @override
  void setBodyProperty(int h, int p, Object? v) =>
      _op(BatchOpType.setBodyProp, () { _wi(h); _wi(p); _wo(v); });

  @override
  Future<Object?> getBodyProperty(int h, int p) async =>
      IsolateProtocol.readObject(await _send(IsolateProtocol.writeGetProp(EntityType.body, h, p)));

  // ===================== Collider (synchronous — queue into batch) =====================
  @override
  int createCollider(ColliderShapeType t, int bh) {
    final h = _allocHandle();
    _op(BatchOpType.createCollider, () { _wi(h); _wi(t.index); _wi(bh); });
    return h;
  }

  @override
  void destroyCollider(int h) =>
      _op(BatchOpType.destroyCollider, () => _wi(h));

  @override
  void setColliderProperty(int h, int p, Object? v) =>
      _op(BatchOpType.setColliderProp, () { _wi(h); _wi(p); _wo(v); });

  @override
  Future<Object?> getColliderProperty(int h, int p) async =>
      IsolateProtocol.readObject(await _send(IsolateProtocol.writeGetProp(EntityType.collider, h, p)));

  // ===================== Joint (synchronous — queue into batch) =====================
  @override
  int createJoint(int t, int bh) {
    final h = _allocHandle();
    _op(BatchOpType.createJoint, () { _wi(h); _wi(t); _wi(bh); });
    return h;
  }

  @override
  void destroyJoint(int h) =>
      _op(BatchOpType.destroyJoint, () => _wi(h));

  @override
  void setJointProperty(int h, int p, Object? v) =>
      _op(BatchOpType.setJointProp, () { _wi(h); _wi(p); _wo(v); });

  @override
  Future<Object?> getJointProperty(int h, int p) async =>
      IsolateProtocol.readObject(await _send(IsolateProtocol.writeGetProp(EntityType.joint, h, p)));

  // ===================== Effector (synchronous — queue into batch) =====================
  @override
  int createEffector(int t) {
    final h = _allocHandle();
    _op(BatchOpType.createEffector, () { _wi(h); _wi(t); });
    return h;
  }

  @override
  void destroyEffector(int h) =>
      _op(BatchOpType.destroyEffector, () => _wi(h));

  @override
  void setEffectorProperty(int h, int p, Object? v) =>
      _op(BatchOpType.setEffectorProp, () { _wi(h); _wi(p); _wo(v); });

  @override
  Future<Object?> getEffectorProperty(int h, int p) async =>
      IsolateProtocol.readObject(await _send(IsolateProtocol.writeGetProp(EntityType.effector, h, p)));

  // ===================== Global Settings =====================
  @override
  Future<void> setGravity(Vector2 v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobal(GlobalPropId.gravity, v));
  @override
  Future<Vector2> getGravity() async => IsolateProtocol.readVector2(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.gravity)));
  @override
  Future<void> setCallbacksOnDisable(bool v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalBool(GlobalPropId.callbacksOnDisable, v));
  @override
  Future<bool> getCallbacksOnDisable() async => IsolateProtocol.readBool(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.callbacksOnDisable)));
  @override
  Future<void> setBounceThreshold(double v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalDouble(GlobalPropId.bounceThreshold, v));
  @override
  Future<double> getBounceThreshold() async => IsolateProtocol.readDouble(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.bounceThreshold)));
  @override
  Future<void> setContactThreshold(double v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalDouble(GlobalPropId.contactThreshold, v));
  @override
  Future<double> getContactThreshold() async => IsolateProtocol.readDouble(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.contactThreshold)));
  @override
  Future<void> setBaumgarteTOIScale(double v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalDouble(GlobalPropId.baumgarteTOIScale, v));
  @override
  Future<double> getBaumgarteTOIScale() async => IsolateProtocol.readDouble(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.baumgarteTOIScale)));
  @override
  Future<void> setBaumgarteScale(double v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalDouble(GlobalPropId.baumgarteScale, v));
  @override
  Future<double> getBaumgarteScale() async => IsolateProtocol.readDouble(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.baumgarteScale)));
  @override
  Future<void> setAngularSleepTolerance(double v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalDouble(GlobalPropId.angularSleepTolerance, v));
  @override
  Future<double> getAngularSleepTolerance() async => IsolateProtocol.readDouble(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.angularSleepTolerance)));
  @override
  Future<void> setLinearSleepTolerance(double v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalDouble(GlobalPropId.linearSleepTolerance, v));
  @override
  Future<double> getLinearSleepTolerance() async => IsolateProtocol.readDouble(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.linearSleepTolerance)));
  @override
  Future<void> setDefaultContactOffset(double v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalDouble(GlobalPropId.defaultContactOffset, v));
  @override
  Future<double> getDefaultContactOffset() async => IsolateProtocol.readDouble(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.defaultContactOffset)));
  @override
  Future<void> setMaxAngularCorrection(double v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalDouble(GlobalPropId.maxAngularCorrection, v));
  @override
  Future<double> getMaxAngularCorrection() async => IsolateProtocol.readDouble(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.maxAngularCorrection)));
  @override
  Future<void> setMaxLinearCorrection(double v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalDouble(GlobalPropId.maxLinearCorrection, v));
  @override
  Future<double> getMaxLinearCorrection() async => IsolateProtocol.readDouble(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.maxLinearCorrection)));
  @override
  Future<void> setMaxRotationSpeed(double v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalDouble(GlobalPropId.maxRotationSpeed, v));
  @override
  Future<double> getMaxRotationSpeed() async => IsolateProtocol.readDouble(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.maxRotationSpeed)));
  @override
  Future<void> setMaxTranslationSpeed(double v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalDouble(GlobalPropId.maxTranslationSpeed, v));
  @override
  Future<double> getMaxTranslationSpeed() async => IsolateProtocol.readDouble(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.maxTranslationSpeed)));
  @override
  Future<void> setMinSubStepFPS(double v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalDouble(GlobalPropId.minSubStepFPS, v));
  @override
  Future<double> getMinSubStepFPS() async => IsolateProtocol.readDouble(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.minSubStepFPS)));
  @override
  Future<void> setTimeToSleep(double v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalDouble(GlobalPropId.timeToSleep, v));
  @override
  Future<double> getTimeToSleep() async => IsolateProtocol.readDouble(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.timeToSleep)));
  @override
  Future<void> setPositionIterations(int v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalInt(GlobalPropId.positionIterations, v));
  @override
  Future<int> getPositionIterations() async => IsolateProtocol.readInt(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.positionIterations)));
  @override
  Future<void> setVelocityIterations(int v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalInt(GlobalPropId.velocityIterations, v));
  @override
  Future<int> getVelocityIterations() async => IsolateProtocol.readInt(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.velocityIterations)));
  @override
  Future<void> setMaxSubStepCount(int v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalInt(GlobalPropId.maxSubStepCount, v));
  @override
  Future<int> getMaxSubStepCount() async => IsolateProtocol.readInt(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.maxSubStepCount)));
  @override
  Future<int> getMaxPolygonShapeVertices() async => IsolateProtocol.readInt(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.maxPolygonShapeVertices)));
  @override
  Future<int> getAllLayers() async => IsolateProtocol.readInt(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.allLayers)));
  @override
  Future<int> getDefaultRaycastLayers() async => IsolateProtocol.readInt(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.defaultRaycastLayers)));
  @override
  Future<int> getIgnoreRaycastLayer() async => IsolateProtocol.readInt(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.ignoreRaycastLayer)));
  @override
  Future<void> setSimulationLayers(int v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalInt(GlobalPropId.simulationLayers, v));
  @override
  Future<int> getSimulationLayers() async => IsolateProtocol.readInt(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.simulationLayers)));
  @override
  Future<void> setSimulationMode(int v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalInt(GlobalPropId.simulationMode, v));
  @override
  Future<int> getSimulationMode() async => IsolateProtocol.readInt(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.simulationMode)));
  @override
  Future<void> setQueriesStartInColliders(bool v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalBool(GlobalPropId.queriesStartInColliders, v));
  @override
  Future<bool> getQueriesStartInColliders() async => IsolateProtocol.readBool(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.queriesStartInColliders)));
  @override
  Future<void> setQueriesHitTriggers(bool v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalBool(GlobalPropId.queriesHitTriggers, v));
  @override
  Future<bool> getQueriesHitTriggers() async => IsolateProtocol.readBool(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.queriesHitTriggers)));
  @override
  Future<void> setReuseCollisionCallbacks(bool v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalBool(GlobalPropId.reuseCollisionCallbacks, v));
  @override
  Future<bool> getReuseCollisionCallbacks() async => IsolateProtocol.readBool(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.reuseCollisionCallbacks)));
  @override
  Future<void> setUseSubStepping(bool v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalBool(GlobalPropId.useSubStepping, v));
  @override
  Future<bool> getUseSubStepping() async => IsolateProtocol.readBool(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.useSubStepping)));
  @override
  Future<void> setUseSubStepContacts(bool v) async => _sendFireAndForget(IsolateProtocol.writeSetGlobalBool(GlobalPropId.useSubStepContacts, v));
  @override
  Future<bool> getUseSubStepContacts() async => IsolateProtocol.readBool(await _send(IsolateProtocol.writeGetGlobal(GlobalPropId.useSubStepContacts)));

  // ===================== Layer Collision =====================
  @override
  Future<bool> getIgnoreLayerCollision(int l1, int l2) async => IsolateProtocol.readBool(await _send(IsolateProtocol.writeLayerOp(LayerOpId.getIgnore, l1, l2)));
  @override
  Future<void> setIgnoreLayerCollision(int l1, int l2, bool v) async => _sendFireAndForget(IsolateProtocol.writeLayerIgnore(l1, l2, v));
  @override
  Future<int> getLayerCollisionMask(int l) async => IsolateProtocol.readInt(await _send(IsolateProtocol.writeLayerOp(LayerOpId.getMask, l, 0)));
  @override
  Future<void> setLayerCollisionMask(int l, int m) async => _sendFireAndForget(IsolateProtocol.writeLayerSetMask(l, m));
  @override
  Future<void> ignoreCollision(int a, int b, bool v) async => _sendFireAndForget(IsolateProtocol.writeColliderIgnore(a, b, v));
  @override
  Future<bool> getIgnoreCollision(int a, int b) async => IsolateProtocol.readBool(await _send(IsolateProtocol.writeColliderGetIgnore(a, b)));

  // ===================== Body methods (fire-and-forget — gameplay only) =====================
  @override
  Future<void> bodyAddForce(int h, Vector2 f, int m) async => _sendFireAndForget(IsolateProtocol.writeBodyMethod(BodyMethodId.addForce, h, f, m));
  @override
  Future<void> bodyAddForceAtPosition(int h, Vector2 f, Vector2 p, int m) async => _sendFireAndForget(IsolateProtocol.writeBodyMethodVV(BodyMethodId.addForceAtPos, h, f, p, m));
  @override
  Future<void> bodyAddTorque(int h, double t, int m) async => _sendFireAndForget(IsolateProtocol.writeBodyMethodDI(BodyMethodId.addTorque, h, t, m));
  @override
  Future<void> bodyAddRelativeForce(int h, Vector2 f, int m) async => _sendFireAndForget(IsolateProtocol.writeBodyMethod(BodyMethodId.addRelForce, h, f, m));
  @override
  Future<void> bodyMovePosition(int h, Vector2 p) async => _sendFireAndForget(IsolateProtocol.writeBodyMethodV(BodyMethodId.movePos, h, p));
  @override
  Future<void> bodyMoveRotation(int h, double a) async => _sendFireAndForget(IsolateProtocol.writeBodyMethodD(BodyMethodId.moveRot, h, a));
  @override
  Future<void> bodyMovePositionAndRotation(int h, Vector2 p, double a) async => _sendFireAndForget(IsolateProtocol.writeBodyMethodVD(BodyMethodId.movePosRot, h, p, a));
  @override
  Future<void> bodySetRotation(int h, double a) async => _sendFireAndForget(IsolateProtocol.writeBodyMethodD(BodyMethodId.setRot, h, a));
  @override
  Future<void> bodyWakeUp(int h) async => _sendFireAndForget(IsolateProtocol.writeBodyMethodVoid(BodyMethodId.wakeUp, h));
  @override
  Future<void> bodySleep(int h) async => _sendFireAndForget(IsolateProtocol.writeBodyMethodVoid(BodyMethodId.sleep, h));
  @override
  Future<bool> bodyIsAwake(int h) async => IsolateProtocol.readBool(await _send(IsolateProtocol.writeBodyMethodVoid(BodyMethodId.isAwake, h)));
  @override
  Future<bool> bodyIsSleeping(int h) async => IsolateProtocol.readBool(await _send(IsolateProtocol.writeBodyMethodVoid(BodyMethodId.isSleeping, h)));
  @override
  Future<Vector2> bodyGetPoint(int h, Vector2 p) async => IsolateProtocol.readVector2(await _send(IsolateProtocol.writeBodyMethodV(BodyMethodId.getPoint, h, p)));
  @override
  Future<Vector2> bodyGetRelativePoint(int h, Vector2 p) async => IsolateProtocol.readVector2(await _send(IsolateProtocol.writeBodyMethodV(BodyMethodId.getRelPoint, h, p)));
  @override
  Future<Vector2> bodyGetVector(int h, Vector2 v) async => IsolateProtocol.readVector2(await _send(IsolateProtocol.writeBodyMethodV(BodyMethodId.getVector, h, v)));
  @override
  Future<Vector2> bodyGetRelativeVector(int h, Vector2 v) async => IsolateProtocol.readVector2(await _send(IsolateProtocol.writeBodyMethodV(BodyMethodId.getRelVector, h, v)));
  @override
  Future<Vector2> bodyGetPointVelocity(int h, Vector2 p) async => IsolateProtocol.readVector2(await _send(IsolateProtocol.writeBodyMethodV(BodyMethodId.getPointVel, h, p)));
  @override
  Future<Vector2> bodyGetRelativePointVelocity(int h, Vector2 p) async => IsolateProtocol.readVector2(await _send(IsolateProtocol.writeBodyMethodV(BodyMethodId.getRelPointVel, h, p)));
  @override
  Future<Vector2> bodyClosestPoint(int h, Vector2 p) async => IsolateProtocol.readVector2(await _send(IsolateProtocol.writeBodyMethodV(BodyMethodId.closestPoint, h, p)));

  // ===================== Collider methods =====================
  @override
  Future<Vector2> colliderClosestPoint(int h, Vector2 p) async => IsolateProtocol.readVector2(await _send(IsolateProtocol.writeColliderMethodV(ColliderMethodId.closestPoint, h, p)));
  @override
  Future<double> colliderDistance(int a, int b) async => IsolateProtocol.readDouble(await _send(IsolateProtocol.writeColliderMethodII(ColliderMethodId.distance, a, b)));
  @override
  Future<bool> colliderIsTouching(int a, int b) async => IsolateProtocol.readBool(await _send(IsolateProtocol.writeColliderMethodII(ColliderMethodId.isTouching, a, b)));
  @override
  Future<bool> colliderIsTouchingLayers(int h, int l) async => IsolateProtocol.readBool(await _send(IsolateProtocol.writeColliderMethodII(ColliderMethodId.isTouchingLayers, h, l)));
  @override
  Future<void> colliderGenerateGeometry(int h) async => await _send(IsolateProtocol.writeColliderMethodI(ColliderMethodId.generateGeometry, h));

  // ===================== Queries =====================
  @override
  Future<List<RaycastHitData>> raycast(Vector2 o, Vector2 d, double dist, int lm, double mind, double maxd) async =>
      IsolateProtocol.readRaycastHits(await _send(IsolateProtocol.writeRaycast(o, d, dist, lm, mind, maxd)));
  @override
  Future<List<RaycastHitData>> linecast(Vector2 s, Vector2 e, int lm, double mind, double maxd) async =>
      IsolateProtocol.readRaycastHits(await _send(IsolateProtocol.writeLinecast(s, e, lm, mind, maxd)));
  @override
  Future<List<RaycastHitData>> boxCast(Vector2 o, Vector2 sz, double a, Vector2 d, double dist, int lm, double mind, double maxd) async =>
      IsolateProtocol.readRaycastHits(await _send(IsolateProtocol.writeBoxCast(o, sz, a, d, dist, lm, mind, maxd)));
  @override
  Future<List<RaycastHitData>> circleCast(Vector2 o, double r, Vector2 d, double dist, int lm, double mind, double maxd) async =>
      IsolateProtocol.readRaycastHits(await _send(IsolateProtocol.writeCircleCast(o, r, d, dist, lm, mind, maxd)));
  @override
  Future<List<RaycastHitData>> capsuleCast(Vector2 o, Vector2 sz, int cd, double a, Vector2 d, double dist, int lm, double mind, double maxd) async =>
      IsolateProtocol.readRaycastHits(await _send(IsolateProtocol.writeCapsuleCast(o, sz, cd, a, d, dist, lm, mind, maxd)));
  @override
  Future<List<int>> overlapCircle(Vector2 p, double r, int lm, double mind, double maxd) async =>
      IsolateProtocol.readIntList(await _send(IsolateProtocol.writeOverlapCircle(p, r, lm, mind, maxd)));
  @override
  Future<List<int>> overlapBox(Vector2 p, Vector2 sz, double a, int lm, double mind, double maxd) async =>
      IsolateProtocol.readIntList(await _send(IsolateProtocol.writeOverlapBox(p, sz, a, lm, mind, maxd)));
  @override
  Future<List<int>> overlapPoint(Vector2 p, int lm, double mind, double maxd) async =>
      IsolateProtocol.readIntList(await _send(IsolateProtocol.writeOverlapPoint(p, lm, mind, maxd)));
  @override
  Future<Vector2> closestPoint(Vector2 p, int ch) async =>
      IsolateProtocol.readVector2(await _send(IsolateProtocol.writeClosestPoint(p, ch)));
  @override
  Future<List<ContactPointData>> getContacts(int h) async =>
      IsolateProtocol.readContactPoints(await _send(IsolateProtocol.writeGetContacts(h)));
  @override
  Future<List<int>> getContactColliders(int h) async =>
      IsolateProtocol.readIntList(await _send(IsolateProtocol.writeGetContactColliders(h)));
  @override
  Future<List<int>> overlapCollider(int h) async =>
      IsolateProtocol.readIntList(await _send(IsolateProtocol.writeOverlapCollider(h)));
  @override
  Future<void> syncTransforms() async => _sendFireAndForget(IsolateProtocol.writeSyncTransforms());
}
