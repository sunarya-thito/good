import 'package:meta/meta.dart';
import 'package:goo2d/src/physics/worker/physics_worker.dart';
import 'package:goo2d/src/physics/worker/direct/direct_body_ops.dart';
import 'package:goo2d/goo2d.dart';

/// Gives a [GameObject] mass, velocity, and forces so it participates in the physics simulation.
///
/// Add a [Rigidbody] to an object to let the physics engine move it. The object must also have
/// at least one [Collider] on the same [GameObject] to interact with other bodies.
///
/// The three body types behave differently:
/// - [RigidbodyType.dynamic]: fully simulated — gravity, forces, and collisions affect it.
/// - [RigidbodyType.kinematic]: moves only through explicit calls to [movePosition] / [moveRotation];
///   the physics simulation does not apply forces or gravity.
/// - [RigidbodyType.static]: never moves; used for immovable scenery.
///
/// ```dart
/// class Rock extends StatefulGameWidget {
///   const Rock({super.key});
///   @override
///   GameState createState() => RockState();
/// }
///
/// class RockState extends GameState<Rock> {
///   @override
///   void initState() {
///     super.initState();
///     addComponent(
///       ObjectTransform()..position = Vector2(0, 5),
///       Rigidbody()..gravityScale = 1.0,
///       BoxCollider()..size = Vector2(1, 1),
///     );
///   }
/// }
/// ```
///
/// See also:
/// * [Collider], which defines the shape used for collision detection.
/// * [PhysicsContactListener], for receiving collision and trigger callbacks.
class Rigidbody extends Component {
  late int _handle;

  /// The internal physics handle for this rigidbody.
  int get handle {
    assert(isAttached, 'Rigidbody must be attached to a GameObject before accessing handle.');
    return _handle;
  }

  @protected
  PhysicsWorker get worker => game.getSystem<PhysicsSystem>()!.worker;

  @override
  void internalAttach(GameObject gameObject) {
    super.internalAttach(gameObject);
    _handle = worker.createBody();
    _syncAllProperties();
    PhysicsSystem.registerRigidbody(_handle, this);
  }

  @override
  void internalDetach() {
    PhysicsSystem.unregisterRigidbody(_handle, this);
    worker.destroyBody(_handle);
    super.internalDetach();
  }

  void _syncAllProperties() {
    final transform = gameObject.tryGetComponent<ObjectTransform>();
    if (transform != null) {
      worker.setBodyProperty(_handle, BodyProp.position, transform.position.clone());
      worker.setBodyProperty(_handle, BodyProp.rotation, transform.angle);
    }
    worker.setBodyProperty(_handle, BodyProp.bodyType, _bodyType.index);
    worker.setBodyProperty(_handle, BodyProp.interpolation, _interpolation.index);
    worker.setBodyProperty(_handle, BodyProp.linearDamping, _linearDamping);
    worker.setBodyProperty(_handle, BodyProp.angularDamping, _angularDamping);
    worker.setBodyProperty(_handle, BodyProp.gravityScale, _gravityScale);
    worker.setBodyProperty(_handle, BodyProp.mass, _mass);
    worker.setBodyProperty(_handle, BodyProp.inertia, _inertia);
    worker.setBodyProperty(_handle, BodyProp.freezeRotation, _freezeRotation);
    worker.setBodyProperty(_handle, BodyProp.simulated, _simulated);
    worker.setBodyProperty(_handle, BodyProp.useAutoMass, _useAutoMass);
    worker.setBodyProperty(_handle, BodyProp.useFullKinematicContacts, _useFullKinematicContacts);
    worker.setBodyProperty(_handle, BodyProp.constraints, _constraints);
    worker.setBodyProperty(_handle, BodyProp.collisionDetectionMode, _collisionDetectionMode.index);
    worker.setBodyProperty(_handle, BodyProp.sleepMode, _sleepMode.index);
    worker.setBodyProperty(_handle, BodyProp.excludeLayers, _excludeLayers);
    worker.setBodyProperty(_handle, BodyProp.includeLayers, _includeLayers);
    worker.setBodyProperty(_handle, BodyProp.centerOfMass, _centerOfMass.clone());
  }

  // --- Configuration Properties ---

  /// Controls which simulation rules apply to this body.
  ///
  /// - `dynamic`: fully simulated — gravity, forces, and contacts all affect it.
  /// - `kinematic`: moves only via [movePosition] / [moveRotation]; the engine ignores forces and gravity.
  /// - `static`: never moves; used for immovable scenery. Default `dynamic`.
  RigidbodyType get bodyType => _bodyType;
  RigidbodyType _bodyType = RigidbodyType.dynamic;
  set bodyType(RigidbodyType value) {
    _bodyType = value;
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.bodyType, value.index);
  }

  /// Smooths the rendered position between physics steps.
  ///
  /// `none` renders at the exact physics position; `interpolate` blends from
  /// the previous step; `extrapolate` predicts ahead. Default `none`.
  RigidbodyInterpolation get interpolation => _interpolation;
  RigidbodyInterpolation _interpolation = RigidbodyInterpolation.none;
  set interpolation(RigidbodyInterpolation value) {
    _interpolation = value;
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.interpolation, value.index);
  }

  /// Linear drag applied to velocity each physics step. 0 = no drag. Default 0.
  double get linearDamping => _linearDamping;
  double _linearDamping = 0;
  set linearDamping(double value) {
    _linearDamping = value;
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.linearDamping, value);
  }

  /// Angular drag applied to angular velocity each physics step. Default 0.05.
  double get angularDamping => _angularDamping;
  double _angularDamping = 0.05;
  set angularDamping(double value) {
    _angularDamping = value;
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.angularDamping, value);
  }

  /// Multiplier for world gravity on this body. 0 = weightless, 1 = normal, negative = reversed. Default 1.0.
  double get gravityScale => _gravityScale;
  double _gravityScale = 1.0;
  set gravityScale(double value) {
    _gravityScale = value;
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.gravityScale, value);
  }

  /// Mass of this body in kilograms. Ignored when [useAutoMass] is true. Default 1.0.
  double get mass => _mass;
  double _mass = 1.0;
  set mass(double value) {
    _mass = value;
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.mass, value);
  }

  /// Rotational inertia (moment of inertia) in kg·m². 0 lets the simulation derive it from attached colliders.
  double get inertia => _inertia;
  double _inertia = 0;
  set inertia(double value) {
    _inertia = value;
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.inertia, value);
  }

  /// When true, the physics simulation never rotates this body. Useful for characters that must stay upright.
  bool get freezeRotation => _freezeRotation;
  bool _freezeRotation = false;
  set freezeRotation(bool value) {
    _freezeRotation = value;
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.freezeRotation, value);
  }

  /// When false, removes the body from the simulation without destroying it. Default true.
  bool get simulated => _simulated;
  bool _simulated = true;
  set simulated(bool value) {
    _simulated = value;
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.simulated, value);
  }

  /// When true, [mass] is calculated automatically from the area and [Collider.density] of attached colliders.
  bool get useAutoMass => _useAutoMass;
  bool _useAutoMass = false;
  set useAutoMass(bool value) {
    _useAutoMass = value;
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.useAutoMass, value);
  }

  /// When true, kinematic bodies generate contacts with all body types, not just dynamic ones.
  bool get useFullKinematicContacts => _useFullKinematicContacts;
  bool _useFullKinematicContacts = false;
  set useFullKinematicContacts(bool value) {
    _useFullKinematicContacts = value;
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.useFullKinematicContacts, value);
  }

  /// Bitfield that freezes specific position or rotation axes. See `RigidbodyConstraints`.
  int get constraints => _constraints;
  int _constraints = 0;
  set constraints(int value) {
    _constraints = value;
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.constraints, value);
  }

  /// How collisions are detected as this body moves.
  ///
  /// `discrete` only checks the final position each step; `continuous` sweeps the path
  /// and catches fast-moving bodies that might tunnel through thin colliders.
  CollisionDetectionMode get collisionDetectionMode => _collisionDetectionMode;
  CollisionDetectionMode _collisionDetectionMode = CollisionDetectionMode.discrete;
  set collisionDetectionMode(CollisionDetectionMode value) {
    _collisionDetectionMode = value;
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.collisionDetectionMode, value.index);
  }

  /// Controls whether this body starts awake or asleep when first added to the simulation.
  RigidbodySleepMode get sleepMode => _sleepMode;
  RigidbodySleepMode _sleepMode = RigidbodySleepMode.startAwake;
  set sleepMode(RigidbodySleepMode value) {
    _sleepMode = value;
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.sleepMode, value.index);
  }

  /// Layer bitmask of layers this body will never collide with, overriding the global layer matrix.
  int get excludeLayers => _excludeLayers;
  int _excludeLayers = 0;
  set excludeLayers(int value) {
    _excludeLayers = value;
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.excludeLayers, value);
  }

  /// Layer bitmask of layers this body will always collide with, overriding the global layer matrix.
  int get includeLayers => _includeLayers;
  int _includeLayers = 0;
  set includeLayers(int value) {
    _includeLayers = value;
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.includeLayers, value);
  }

  /// Local-space offset of the center of mass from the object origin. Default `Vector2.zero()`.
  Vector2 get centerOfMass => _centerOfMass;
  Vector2 _centerOfMass = Vector2.zero();
  set centerOfMass(Vector2 value) {
    _centerOfMass.setFrom(value);
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.centerOfMass, value.clone());
  }

  // --- Simulated State Properties (Async reads, sync writes) ---

  /// Current linear velocity in world units per second.
  ///
  /// Reading is asynchronous because the value lives in the physics worker.
  /// Writing is fire-and-forget — the change takes effect on the next physics step.
  Future<Vector2> get linearVelocity async => (await worker.getBodyProperty(_handle, BodyProp.linearVelocity)) as Vector2;
  set linearVelocity(Vector2 value) {
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.linearVelocity, value);
  }

  /// Current angular velocity in radians per second.
  Future<double> get angularVelocity async => (await worker.getBodyProperty(_handle, BodyProp.angularVelocity)) as double;
  set angularVelocity(double value) {
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.angularVelocity, value);
  }

  /// Physics-simulated world position.
  ///
  /// This may lag one step behind [ObjectTransform.position] when interpolation is enabled.
  /// Use [movePosition] to reposition a kinematic body smoothly.
  Future<Vector2> get position async => (await worker.getBodyProperty(_handle, BodyProp.position)) as Vector2;
  set position(Vector2 value) {
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.position, value);
  }

  /// Physics-simulated rotation in radians.
  Future<double> get rotation async => (await worker.getBodyProperty(_handle, BodyProp.rotation)) as double;
  set rotation(double value) {
    if (isAttached) worker.setBodyProperty(_handle, BodyProp.rotation, value);
  }

  /// Total force currently applied to this body (N).
  Future<Vector2> get totalForce async => (await worker.getBodyProperty(_handle, BodyProp.totalForce)) as Vector2;

  /// Total torque currently applied to this body (N·m).
  Future<double> get totalTorque async => (await worker.getBodyProperty(_handle, BodyProp.totalTorque)) as double;

  /// World-space position of the center of mass.
  Future<Vector2> get worldCenterOfMass async => (await worker.getBodyProperty(_handle, BodyProp.worldCenterOfMass)) as Vector2;

  /// X component of [linearVelocity].
  Future<double> get linearVelocityX async => (await linearVelocity).x;

  /// Y component of [linearVelocity].
  Future<double> get linearVelocityY async => (await linearVelocity).y;

  // --- Local/Computed Properties ---

  /// Number of [Collider] components currently on the same [GameObject].
  int get attachedColliderCount => gameObject.getComponents<Collider>().length;

  /// World-space transform matrix from the sibling [ObjectTransform].
  Matrix4 get worldMatrix => gameObject.getComponent<ObjectTransform>().worldMatrix;

  /// Alias for [worldMatrix].
  Matrix4 get localToWorldMatrix => worldMatrix;

  /// A [PhysicsMaterial] applied to all colliders on this body at once.
  ///
  /// Setting this overwrites the material on every attached [Collider].
  PhysicsMaterial? _sharedMaterial;
  PhysicsMaterial? get sharedMaterial => _sharedMaterial;
  set sharedMaterial(PhysicsMaterial? value) {
    _sharedMaterial = value;
    if (value == null || !isAttached) return;
    for (final c in gameObject.getComponents<Collider>()) {
      c.sharedMaterial = value;
    }
  }

  // --- Methods ---

  /// Casts all attached colliders in [direction] and returns hits up to [distance] world units away.
  Future<List<RaycastHit>> cast(Vector2 direction, double distance, [int layerMask = Physics.defaultRaycastLayers]) async {
    final results = await worker.raycast(await position, direction, distance, layerMask, -double.infinity, double.infinity);
    return results.map((d) => RaycastHit.fromData(d)).whereType<RaycastHit>().toList();
  }

  /// Returns the minimum separation distance between this body and [collider].
  Future<double> distance(Collider collider) async => worker.colliderDistance(_handle, collider.handle);

  /// Returns all [Collider] components on the same [GameObject].
  List<Collider> getAttachedColliders() => gameObject.getComponents<Collider>().toList();

  /// Fills [shapeGroup] with physics shapes from all attached colliders.
  int getShapes(PhysicsShapeGroup shapeGroup, [int shapeIndex = 0, int shapeCount = 0]) {
    var total = 0;
    for (final c in gameObject.getComponents<Collider>()) {
      total += c.getShapes(shapeGroup);
    }
    return total;
  }

  /// Returns all colliders that currently overlap this body.
  Future<List<Collider>> overlap(int layerMask, double minDepth, double maxDepth) async {
    final handles = <int>{};
    for (final c in gameObject.getComponents<Collider>()) {
      handles.addAll(await worker.overlapCollider(c.handle));
    }
    return handles.map((h) => PhysicsSystem.getCollider(h)).whereType<Collider>().toList();
  }

  /// Returns true if [point] lies inside any attached collider.
  Future<bool> overlapPoint(Vector2 point) async => worker.colliderIsTouchingLayers(_handle, ~0);

  /// Moves this body by [displacement] without applying velocity or forces directly.
  Future<void> slide(Vector2 displacement) async => movePosition(await position + displacement);

  /// Applies [force] (N) to the center of mass using [mode] to control how it is accumulated.
  Future<void> addForce(Vector2 force, ForceMode mode) async => worker.bodyAddForce(_handle, force, mode.index);

  /// Applies [force] (N) at a specific world [position], which may also produce torque.
  Future<void> addForceAtPosition(Vector2 force, Vector2 position, ForceMode mode) async => worker.bodyAddForceAtPosition(_handle, force, position, mode.index);

  /// Applies a force along the X axis only. See [addForce].
  Future<void> addForceX(double force, ForceMode mode) => addForce(Vector2(force, 0), mode);

  /// Applies a force along the Y axis only. See [addForce].
  Future<void> addForceY(double force, ForceMode mode) => addForce(Vector2(0, force), mode);

  /// Applies a torque (N·m) around the Z axis.
  Future<void> addTorque(double torque, ForceMode mode) async => worker.bodyAddTorque(_handle, torque, mode.index);

  /// Applies [relativeForce] in this body's local coordinate space.
  Future<void> addRelativeForce(Vector2 relativeForce, ForceMode mode) async => worker.bodyAddRelativeForce(_handle, relativeForce, mode.index);

  /// Applies a local-space force along the local X axis only.
  Future<void> addRelativeForceX(double force, ForceMode mode) => addRelativeForce(Vector2(force, 0), mode);

  /// Applies a local-space force along the local Y axis only.
  Future<void> addRelativeForceY(double force, ForceMode mode) => addRelativeForce(Vector2(0, force), mode);

  /// Moves a kinematic body to [position] in a physics-aware way that generates contacts along the path.
  Future<void> movePosition(Vector2 position) async => worker.bodyMovePosition(_handle, position);

  /// Moves a kinematic body to [position] and [angle] (radians) atomically.
  Future<void> movePositionAndRotation(Vector2 position, double angle) async => worker.bodyMovePositionAndRotation(_handle, position, angle);

  /// Rotates a kinematic body to [angle] (radians) in a physics-aware way.
  Future<void> moveRotation(double angle) async => worker.bodyMoveRotation(_handle, angle);

  /// Teleports the body's rotation to [angle] (radians) without generating contacts.
  Future<void> setRotation(double angle) async => worker.bodySetRotation(_handle, angle);

  /// Wakes this body so the simulation processes it next step.
  Future<void> wakeUp() async => worker.bodyWakeUp(_handle);

  /// Puts this body to sleep, pausing simulation until it is disturbed.
  Future<void> sleep() async => worker.bodySleep(_handle);

  /// Returns true if this body is currently awake.
  Future<bool> isAwake() async => worker.bodyIsAwake(_handle);

  /// Returns true if this body is currently sleeping.
  Future<bool> isSleeping() async => worker.bodyIsSleeping(_handle);

  /// Converts a world-space [point] to this body's local space.
  Future<Vector2> getPoint(Vector2 point) async => worker.bodyGetPoint(_handle, point);

  /// Converts a local-space [relativePoint] to world space.
  Future<Vector2> getRelativePoint(Vector2 relativePoint) async => worker.bodyGetRelativePoint(_handle, relativePoint);

  /// Rotates a world-space [vector] into this body's local space (no translation).
  Future<Vector2> getVector(Vector2 vector) async => worker.bodyGetVector(_handle, vector);

  /// Rotates a local-space [relativeVector] to world space (no translation).
  Future<Vector2> getRelativeVector(Vector2 relativeVector) async => worker.bodyGetRelativeVector(_handle, relativeVector);

  /// Returns the velocity of a world-space [point] on this body, accounting for angular velocity.
  Future<Vector2> getPointVelocity(Vector2 point) async => worker.bodyGetPointVelocity(_handle, point);

  /// Returns the velocity of a local-space [relativePoint] on this body.
  Future<Vector2> getRelativePointVelocity(Vector2 relativePoint) async => worker.bodyGetRelativePointVelocity(_handle, relativePoint);

  /// Returns the point on this body's surface closest to [position].
  Future<Vector2> closestPoint(Vector2 position) async => worker.bodyClosestPoint(_handle, position);

  /// Returns true if this body is currently touching [collider].
  Future<bool> isTouching(Collider collider) async => worker.colliderIsTouching(_handle, collider.handle);

  /// Returns true if this body is touching any collider on the given [layerMask].
  Future<bool> isTouchingLayers(int layerMask) async => worker.colliderIsTouchingLayers(_handle, layerMask);

  /// Returns all current contact points for this body.
  Future<List<ContactPoint>> getContacts() async {
    final data = await worker.getContacts(_handle);
    return data.map((d) => ContactPoint.fromData(d)).whereType<ContactPoint>().toList();
  }

  /// Returns all colliders currently in contact with this body.
  Future<List<Collider>> getContactColliders() async {
    final handles = await worker.getContactColliders(_handle);
    return handles.map((h) => PhysicsSystem.getCollider(h)).whereType<Collider>().toList();
  }
}
