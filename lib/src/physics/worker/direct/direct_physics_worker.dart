import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/physics/worker/physics_worker.dart';
import 'package:goo2d/src/physics/worker/engine/physics_engine.dart';
import 'package:goo2d/src/physics/worker/direct/direct_body_ops.dart';
import 'package:goo2d/src/physics/worker/direct/direct_collider_ops.dart';
import 'package:goo2d/src/physics/worker/direct/direct_joint_ops.dart';
import 'package:goo2d/src/physics/worker/direct/direct_effector_ops.dart';
import 'package:goo2d/src/physics/worker/direct/direct_query_ops.dart';
import 'package:goo2d/src/physics/worker/direct/direct_global_ops.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';
import 'package:goo2d/src/physics/worker/data/contact_delta.dart';
import 'package:goo2d/src/physics/worker/data/raycast_hit_data.dart';
import 'package:goo2d/src/physics/worker/data/contact_point_data.dart';

/// Physics worker that invokes the engine directly on the main thread.
///
/// `object → invocation`: no serialization, no message passing.
/// All Futures complete synchronously via [Future.value].
class DirectPhysicsWorker implements PhysicsWorker {
  final PhysicsEngine engine = PhysicsEngine();

  @override
  Future<void> initialize() => Future.value();

  @override
  void dispose() {}

  @override
  Future<void> step(double deltaTime) {
    engine.step(deltaTime);
    return Future.value();
  }

  @override
  Future<ContactDelta> stepWithContactDelta(double deltaTime) =>
      Future.value(engine.stepDelta(deltaTime));

  // ===================== Global Settings =====================
  @override
  Future<void> setGravity(Vector2 v) => DirectGlobalOps.setGravity(engine, v);
  @override
  Future<Vector2> getGravity() => DirectGlobalOps.getGravity(engine);
  @override
  Future<void> setCallbacksOnDisable(bool v) => DirectGlobalOps.setCallbacksOnDisable(engine, v);
  @override
  Future<bool> getCallbacksOnDisable() => DirectGlobalOps.getCallbacksOnDisable(engine);
  @override
  Future<void> setBounceThreshold(double v) => DirectGlobalOps.setBounceThreshold(engine, v);
  @override
  Future<double> getBounceThreshold() => DirectGlobalOps.getBounceThreshold(engine);
  @override
  Future<void> setContactThreshold(double v) => DirectGlobalOps.setContactThreshold(engine, v);
  @override
  Future<double> getContactThreshold() => DirectGlobalOps.getContactThreshold(engine);
  @override
  Future<void> setBaumgarteTOIScale(double v) => DirectGlobalOps.setBaumgarteTOIScale(engine, v);
  @override
  Future<double> getBaumgarteTOIScale() => DirectGlobalOps.getBaumgarteTOIScale(engine);
  @override
  Future<void> setBaumgarteScale(double v) => DirectGlobalOps.setBaumgarteScale(engine, v);
  @override
  Future<double> getBaumgarteScale() => DirectGlobalOps.getBaumgarteScale(engine);
  @override
  Future<void> setAngularSleepTolerance(double v) => DirectGlobalOps.setAngularSleepTolerance(engine, v);
  @override
  Future<double> getAngularSleepTolerance() => DirectGlobalOps.getAngularSleepTolerance(engine);
  @override
  Future<void> setLinearSleepTolerance(double v) => DirectGlobalOps.setLinearSleepTolerance(engine, v);
  @override
  Future<double> getLinearSleepTolerance() => DirectGlobalOps.getLinearSleepTolerance(engine);
  @override
  Future<void> setDefaultContactOffset(double v) => DirectGlobalOps.setDefaultContactOffset(engine, v);
  @override
  Future<double> getDefaultContactOffset() => DirectGlobalOps.getDefaultContactOffset(engine);
  @override
  Future<void> setMaxAngularCorrection(double v) => DirectGlobalOps.setMaxAngularCorrection(engine, v);
  @override
  Future<double> getMaxAngularCorrection() => DirectGlobalOps.getMaxAngularCorrection(engine);
  @override
  Future<void> setMaxLinearCorrection(double v) => DirectGlobalOps.setMaxLinearCorrection(engine, v);
  @override
  Future<double> getMaxLinearCorrection() => DirectGlobalOps.getMaxLinearCorrection(engine);
  @override
  Future<void> setMaxRotationSpeed(double v) => DirectGlobalOps.setMaxRotationSpeed(engine, v);
  @override
  Future<double> getMaxRotationSpeed() => DirectGlobalOps.getMaxRotationSpeed(engine);
  @override
  Future<void> setMaxTranslationSpeed(double v) => DirectGlobalOps.setMaxTranslationSpeed(engine, v);
  @override
  Future<double> getMaxTranslationSpeed() => DirectGlobalOps.getMaxTranslationSpeed(engine);
  @override
  Future<void> setMinSubStepFPS(double v) => DirectGlobalOps.setMinSubStepFPS(engine, v);
  @override
  Future<double> getMinSubStepFPS() => DirectGlobalOps.getMinSubStepFPS(engine);
  @override
  Future<void> setTimeToSleep(double v) => DirectGlobalOps.setTimeToSleep(engine, v);
  @override
  Future<double> getTimeToSleep() => DirectGlobalOps.getTimeToSleep(engine);
  @override
  Future<void> setPositionIterations(int v) => DirectGlobalOps.setPositionIterations(engine, v);
  @override
  Future<int> getPositionIterations() => DirectGlobalOps.getPositionIterations(engine);
  @override
  Future<void> setVelocityIterations(int v) => DirectGlobalOps.setVelocityIterations(engine, v);
  @override
  Future<int> getVelocityIterations() => DirectGlobalOps.getVelocityIterations(engine);
  @override
  Future<void> setMaxSubStepCount(int v) => DirectGlobalOps.setMaxSubStepCount(engine, v);
  @override
  Future<int> getMaxSubStepCount() => DirectGlobalOps.getMaxSubStepCount(engine);
  @override
  Future<int> getMaxPolygonShapeVertices() => DirectGlobalOps.getMaxPolygonShapeVertices(engine);
  @override
  Future<int> getAllLayers() => DirectGlobalOps.getAllLayers(engine);
  @override
  Future<int> getDefaultRaycastLayers() => DirectGlobalOps.getDefaultRaycastLayers(engine);
  @override
  Future<int> getIgnoreRaycastLayer() => DirectGlobalOps.getIgnoreRaycastLayer(engine);
  @override
  Future<void> setSimulationLayers(int v) => DirectGlobalOps.setSimulationLayers(engine, v);
  @override
  Future<int> getSimulationLayers() => DirectGlobalOps.getSimulationLayers(engine);
  @override
  Future<void> setSimulationMode(int v) => DirectGlobalOps.setSimulationMode(engine, v);
  @override
  Future<int> getSimulationMode() => DirectGlobalOps.getSimulationMode(engine);
  @override
  Future<void> setQueriesStartInColliders(bool v) => DirectGlobalOps.setQueriesStartInColliders(engine, v);
  @override
  Future<bool> getQueriesStartInColliders() => DirectGlobalOps.getQueriesStartInColliders(engine);
  @override
  Future<void> setQueriesHitTriggers(bool v) => DirectGlobalOps.setQueriesHitTriggers(engine, v);
  @override
  Future<bool> getQueriesHitTriggers() => DirectGlobalOps.getQueriesHitTriggers(engine);
  @override
  Future<void> setReuseCollisionCallbacks(bool v) => DirectGlobalOps.setReuseCollisionCallbacks(engine, v);
  @override
  Future<bool> getReuseCollisionCallbacks() => DirectGlobalOps.getReuseCollisionCallbacks(engine);
  @override
  Future<void> setUseSubStepping(bool v) => DirectGlobalOps.setUseSubStepping(engine, v);
  @override
  Future<bool> getUseSubStepping() => DirectGlobalOps.getUseSubStepping(engine);
  @override
  Future<void> setUseSubStepContacts(bool v) => DirectGlobalOps.setUseSubStepContacts(engine, v);
  @override
  Future<bool> getUseSubStepContacts() => DirectGlobalOps.getUseSubStepContacts(engine);

  // ===================== Layer Collision =====================
  @override
  Future<bool> getIgnoreLayerCollision(int l1, int l2) => DirectGlobalOps.getIgnoreLayerCollision(engine, l1, l2);
  @override
  Future<void> setIgnoreLayerCollision(int l1, int l2, bool v) => DirectGlobalOps.setIgnoreLayerCollision(engine, l1, l2, v);
  @override
  Future<int> getLayerCollisionMask(int l) => DirectGlobalOps.getLayerCollisionMask(engine, l);
  @override
  Future<void> setLayerCollisionMask(int l, int m) => DirectGlobalOps.setLayerCollisionMask(engine, l, m);
  @override
  Future<void> ignoreCollision(int a, int b, bool v) => DirectGlobalOps.ignoreCollision(engine, a, b, v);
  @override
  Future<bool> getIgnoreCollision(int a, int b) => DirectGlobalOps.getIgnoreCollision(engine, a, b);

  // ===================== Body =====================
  @override
  int createBody() => engine.createBody();
  @override
  void destroyBody(int h) => engine.destroyBody(h);
  @override
  Future<Object?> getBodyProperty(int h, int p) => DirectBodyOps.getProperty(engine, h, p);
  @override
  void setBodyProperty(int h, int p, Object? v) { DirectBodyOps.setProperty(engine, h, p, v); }
  @override
  Future<void> bodyAddForce(int h, Vector2 f, int m) => DirectBodyOps.addForce(engine, h, f, m);
  @override
  Future<void> bodyAddForceAtPosition(int h, Vector2 f, Vector2 p, int m) => DirectBodyOps.addForceAtPosition(engine, h, f, p, m);
  @override
  Future<void> bodyAddTorque(int h, double t, int m) => DirectBodyOps.addTorque(engine, h, t, m);
  @override
  Future<void> bodyAddRelativeForce(int h, Vector2 f, int m) => DirectBodyOps.addRelativeForce(engine, h, f, m);
  @override
  Future<void> bodyMovePosition(int h, Vector2 p) => DirectBodyOps.movePosition(engine, h, p);
  @override
  Future<void> bodyMoveRotation(int h, double a) => DirectBodyOps.moveRotation(engine, h, a);
  @override
  Future<void> bodyMovePositionAndRotation(int h, Vector2 p, double a) => DirectBodyOps.movePositionAndRotation(engine, h, p, a);
  @override
  Future<void> bodySetRotation(int h, double a) => DirectBodyOps.setRotation(engine, h, a);
  @override
  Future<void> bodyWakeUp(int h) => DirectBodyOps.wakeUp(engine, h);
  @override
  Future<void> bodySleep(int h) => DirectBodyOps.sleep(engine, h);
  @override
  Future<bool> bodyIsAwake(int h) => DirectBodyOps.isAwake(engine, h);
  @override
  Future<bool> bodyIsSleeping(int h) => DirectBodyOps.isSleeping(engine, h);
  @override
  Future<Vector2> bodyGetPoint(int h, Vector2 p) => DirectBodyOps.getPoint(engine, h, p);
  @override
  Future<Vector2> bodyGetRelativePoint(int h, Vector2 p) => DirectBodyOps.getRelativePoint(engine, h, p);
  @override
  Future<Vector2> bodyGetVector(int h, Vector2 v) => DirectBodyOps.getVector(engine, h, v);
  @override
  Future<Vector2> bodyGetRelativeVector(int h, Vector2 v) => DirectBodyOps.getRelativeVector(engine, h, v);
  @override
  Future<Vector2> bodyGetPointVelocity(int h, Vector2 p) => DirectBodyOps.getPointVelocity(engine, h, p);
  @override
  Future<Vector2> bodyGetRelativePointVelocity(int h, Vector2 p) => DirectBodyOps.getRelativePointVelocity(engine, h, p);
  @override
  Future<Vector2> bodyClosestPoint(int h, Vector2 p) => DirectBodyOps.closestPoint(engine, h, p);

  // ===================== Collider =====================
  @override
  int createCollider(ColliderShapeType t, int bh) => engine.createCollider(t, bh);
  @override
  void destroyCollider(int h) => engine.destroyCollider(h);
  @override
  Future<Object?> getColliderProperty(int h, int p) => DirectColliderOps.getProperty(engine, h, p);
  @override
  void setColliderProperty(int h, int p, Object? v) { DirectColliderOps.setProperty(engine, h, p, v); }
  @override
  Future<Vector2> colliderClosestPoint(int h, Vector2 p) => DirectColliderOps.closestPoint(engine, h, p);
  @override
  Future<double> colliderDistance(int a, int b) => DirectColliderOps.distance(engine, a, b);
  @override
  Future<bool> colliderIsTouching(int a, int b) => DirectColliderOps.isTouching(engine, a, b);
  @override
  Future<bool> colliderIsTouchingLayers(int h, int l) => DirectColliderOps.isTouchingLayers(engine, h, l);
  @override
  Future<void> colliderGenerateGeometry(int h) => DirectColliderOps.generateGeometry(engine, h);

  // ===================== Joint =====================
  @override
  int createJoint(int t, int bh) => engine.createJoint(t, bh);
  @override
  void destroyJoint(int h) => engine.destroyJoint(h);
  @override
  Future<Object?> getJointProperty(int h, int p) => DirectJointOps.getProperty(engine, h, p);
  @override
  void setJointProperty(int h, int p, Object? v) { DirectJointOps.setProperty(engine, h, p, v); }

  // ===================== Effector =====================
  @override
  int createEffector(int t) => engine.createEffector(t);
  @override
  void destroyEffector(int h) => engine.destroyEffector(h);
  @override
  Future<Object?> getEffectorProperty(int h, int p) => DirectEffectorOps.getProperty(engine, h, p);
  @override
  void setEffectorProperty(int h, int p, Object? v) { DirectEffectorOps.setProperty(engine, h, p, v); }

  // ===================== Queries =====================
  @override
  Future<List<RaycastHitData>> raycast(Vector2 o, Vector2 d, double dist, int lm, double mind, double maxd) => DirectQueryOps.raycast(engine, o, d, dist, lm, mind, maxd);
  @override
  Future<List<RaycastHitData>> linecast(Vector2 s, Vector2 e, int lm, double mind, double maxd) => DirectQueryOps.linecast(engine, s, e, lm, mind, maxd);
  @override
  Future<List<RaycastHitData>> boxCast(Vector2 o, Vector2 sz, double a, Vector2 d, double dist, int lm, double mind, double maxd) => DirectQueryOps.boxCast(engine, o, sz, a, d, dist, lm, mind, maxd);
  @override
  Future<List<RaycastHitData>> circleCast(Vector2 o, double r, Vector2 d, double dist, int lm, double mind, double maxd) => DirectQueryOps.circleCast(engine, o, r, d, dist, lm, mind, maxd);
  @override
  Future<List<RaycastHitData>> capsuleCast(Vector2 o, Vector2 sz, int cd, double a, Vector2 d, double dist, int lm, double mind, double maxd) => DirectQueryOps.capsuleCast(engine, o, sz, cd, a, d, dist, lm, mind, maxd);
  @override
  Future<List<int>> overlapCircle(Vector2 p, double r, int lm, double mind, double maxd) => DirectQueryOps.overlapCircle(engine, p, r, lm, mind, maxd);
  @override
  Future<List<int>> overlapBox(Vector2 p, Vector2 sz, double a, int lm, double mind, double maxd) => DirectQueryOps.overlapBox(engine, p, sz, a, lm, mind, maxd);
  @override
  Future<List<int>> overlapPoint(Vector2 p, int lm, double mind, double maxd) => DirectQueryOps.overlapPoint(engine, p, lm, mind, maxd);
  @override
  Future<Vector2> closestPoint(Vector2 p, int ch) => DirectQueryOps.closestPoint(engine, p, ch);
  @override
  Future<List<ContactPointData>> getContacts(int h) => DirectQueryOps.getContacts(engine, h);
  @override
  Future<List<int>> getContactColliders(int h) => DirectQueryOps.getContactColliders(engine, h);
  @override
  Future<List<int>> overlapCollider(int h) => DirectQueryOps.overlapCollider(engine, h);
  @override
  Future<void> syncTransforms() { engine.syncTransforms(); return Future.value(); }
}
