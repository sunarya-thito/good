import 'package:vector_math/vector_math_64.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';
import 'package:goo2d/src/physics/worker/data/contact_delta.dart';
import 'package:goo2d/src/physics/worker/data/raycast_hit_data.dart';
import 'package:goo2d/src/physics/worker/data/contact_point_data.dart';

/// Abstract interface for physics execution strategies.
///
/// Two implementations exist:
/// - [DirectPhysicsWorker]: `object → invocation` (no serialization).
/// - [IsolatePhysicsWorker]: `object → binary → isolate → binary → invocation`.
abstract class PhysicsWorker {
  Future<void> initialize();
  void dispose();
  Future<void> step(double deltaTime);
  Future<ContactDelta> stepWithContactDelta(double deltaTime);

  // ===================== Global Settings =====================
  Future<void> setGravity(Vector2 value);
  Future<Vector2> getGravity();
  Future<void> setCallbacksOnDisable(bool value);
  Future<bool> getCallbacksOnDisable();
  Future<void> setBounceThreshold(double value);
  Future<double> getBounceThreshold();
  Future<void> setContactThreshold(double value);
  Future<double> getContactThreshold();
  Future<void> setBaumgarteTOIScale(double value);
  Future<double> getBaumgarteTOIScale();
  Future<void> setBaumgarteScale(double value);
  Future<double> getBaumgarteScale();
  Future<void> setAngularSleepTolerance(double value);
  Future<double> getAngularSleepTolerance();
  Future<void> setLinearSleepTolerance(double value);
  Future<double> getLinearSleepTolerance();
  Future<void> setDefaultContactOffset(double value);
  Future<double> getDefaultContactOffset();
  Future<void> setMaxAngularCorrection(double value);
  Future<double> getMaxAngularCorrection();
  Future<void> setMaxLinearCorrection(double value);
  Future<double> getMaxLinearCorrection();
  Future<void> setMaxRotationSpeed(double value);
  Future<double> getMaxRotationSpeed();
  Future<void> setMaxTranslationSpeed(double value);
  Future<double> getMaxTranslationSpeed();
  Future<void> setMinSubStepFPS(double value);
  Future<double> getMinSubStepFPS();
  Future<void> setTimeToSleep(double value);
  Future<double> getTimeToSleep();
  Future<void> setPositionIterations(int value);
  Future<int> getPositionIterations();
  Future<void> setVelocityIterations(int value);
  Future<int> getVelocityIterations();
  Future<void> setMaxSubStepCount(int value);
  Future<int> getMaxSubStepCount();
  Future<int> getMaxPolygonShapeVertices();
  Future<int> getAllLayers();
  Future<int> getDefaultRaycastLayers();
  Future<int> getIgnoreRaycastLayer();
  Future<void> setSimulationLayers(int value);
  Future<int> getSimulationLayers();
  Future<void> setSimulationMode(int value);
  Future<int> getSimulationMode();
  Future<void> setQueriesStartInColliders(bool value);
  Future<bool> getQueriesStartInColliders();
  Future<void> setQueriesHitTriggers(bool value);
  Future<bool> getQueriesHitTriggers();
  Future<void> setReuseCollisionCallbacks(bool value);
  Future<bool> getReuseCollisionCallbacks();
  Future<void> setUseSubStepping(bool value);
  Future<bool> getUseSubStepping();
  Future<void> setUseSubStepContacts(bool value);
  Future<bool> getUseSubStepContacts();

  // ===================== Layer Collision =====================
  Future<bool> getIgnoreLayerCollision(int layer1, int layer2);
  Future<void> setIgnoreLayerCollision(int layer1, int layer2, bool ignore);
  Future<int> getLayerCollisionMask(int layer);
  Future<void> setLayerCollisionMask(int layer, int mask);
  Future<void> ignoreCollision(int colliderA, int colliderB, bool ignore);
  Future<bool> getIgnoreCollision(int colliderA, int colliderB);

  // ===================== Body Operations =====================
  int createBody();
  void destroyBody(int handle);
  // Property access uses generic get/set by property index
  Future<Object?> getBodyProperty(int handle, int property);
  void setBodyProperty(int handle, int property, Object? value);
  // Methods
  Future<void> bodyAddForce(int handle, Vector2 force, int mode);
  Future<void> bodyAddForceAtPosition(int handle, Vector2 force, Vector2 position, int mode);
  Future<void> bodyAddTorque(int handle, double torque, int mode);
  Future<void> bodyAddRelativeForce(int handle, Vector2 force, int mode);
  Future<void> bodyMovePosition(int handle, Vector2 position);
  Future<void> bodyMoveRotation(int handle, double angle);
  Future<void> bodyMovePositionAndRotation(int handle, Vector2 position, double angle);
  Future<void> bodySetRotation(int handle, double angle);
  Future<void> bodyWakeUp(int handle);
  Future<void> bodySleep(int handle);
  Future<bool> bodyIsAwake(int handle);
  Future<bool> bodyIsSleeping(int handle);
  Future<Vector2> bodyGetPoint(int handle, Vector2 worldPoint);
  Future<Vector2> bodyGetRelativePoint(int handle, Vector2 localPoint);
  Future<Vector2> bodyGetVector(int handle, Vector2 worldVector);
  Future<Vector2> bodyGetRelativeVector(int handle, Vector2 localVector);
  Future<Vector2> bodyGetPointVelocity(int handle, Vector2 worldPoint);
  Future<Vector2> bodyGetRelativePointVelocity(int handle, Vector2 localPoint);
  Future<Vector2> bodyClosestPoint(int handle, Vector2 position);

  // ===================== Collider Operations =====================
  int createCollider(ColliderShapeType type, int bodyHandle);
  void destroyCollider(int handle);
  Future<Object?> getColliderProperty(int handle, int property);
  void setColliderProperty(int handle, int property, Object? value);
  Future<Vector2> colliderClosestPoint(int handle, Vector2 position);
  Future<double> colliderDistance(int handleA, int handleB);
  Future<bool> colliderIsTouching(int handleA, int handleB);
  Future<bool> colliderIsTouchingLayers(int handle, int layerMask);
  Future<void> colliderGenerateGeometry(int handle);

  // ===================== Joint Operations =====================
  int createJoint(int type, int bodyHandleA);
  void destroyJoint(int handle);
  Future<Object?> getJointProperty(int handle, int property);
  void setJointProperty(int handle, int property, Object? value);

  // ===================== Effector Operations =====================
  int createEffector(int type);
  void destroyEffector(int handle);
  Future<Object?> getEffectorProperty(int handle, int property);
  void setEffectorProperty(int handle, int property, Object? value);

  // ===================== Queries =====================
  Future<List<RaycastHitData>> raycast(Vector2 origin, Vector2 direction, double distance, int layerMask, double minDepth, double maxDepth);
  Future<List<RaycastHitData>> linecast(Vector2 start, Vector2 end, int layerMask, double minDepth, double maxDepth);
  Future<List<RaycastHitData>> boxCast(Vector2 origin, Vector2 size, double angle, Vector2 direction, double distance, int layerMask, double minDepth, double maxDepth);
  Future<List<RaycastHitData>> circleCast(Vector2 origin, double radius, Vector2 direction, double distance, int layerMask, double minDepth, double maxDepth);
  Future<List<RaycastHitData>> capsuleCast(Vector2 origin, Vector2 size, int capsuleDirection, double angle, Vector2 direction, double distance, int layerMask, double minDepth, double maxDepth);
  Future<List<int>> overlapCircle(Vector2 point, double radius, int layerMask, double minDepth, double maxDepth);
  Future<List<int>> overlapBox(Vector2 point, Vector2 size, double angle, int layerMask, double minDepth, double maxDepth);
  Future<List<int>> overlapPoint(Vector2 point, int layerMask, double minDepth, double maxDepth);
  Future<Vector2> closestPoint(Vector2 position, int colliderHandle);
  Future<List<ContactPointData>> getContacts(int colliderHandle);
  Future<List<int>> getContactColliders(int colliderHandle);
  Future<List<int>> overlapCollider(int colliderHandle);
  Future<void> syncTransforms();
}
