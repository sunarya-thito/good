import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:meta/meta.dart';
import 'package:goo2d/src/collision/collision_system.dart';
import 'package:goo2d/src/collision/worker/collision_worker.dart';
import 'package:goo2d/src/physics/worker/physics_worker.dart';
import 'package:goo2d/src/physics/worker/direct/direct_collider_ops.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';
import 'package:goo2d/goo2d.dart';

/// Base class for all 2D collider types.
///
/// A [Collider] defines the physical shape used for collision detection. It must be on the same
/// [GameObject] as a [Rigidbody] — attaching a collider without one throws a [StateError].
///
/// When [isTrigger] is false (the default) the collider produces a solid contact that the physics
/// engine resolves. When [isTrigger] is true, the shape overlaps other colliders without generating
/// a contact force; use [PhysicsContactListener] to receive the enter/stay/exit events.
///
/// Surface feel is controlled by [friction] and [bounciness], which the engine combines with the
/// touching collider's values according to [frictionCombine] and [bounceCombine].
///
/// Do not instantiate this class directly — use [BoxCollider], [CircleCollider], [CapsuleCollider],
/// [EdgeCollider], [PolygonCollider], or [CompositeCollider].
///
/// See also:
/// * [Rigidbody] for the component that drives movement.
/// * [PhysicsContactListener] to receive collision and trigger callbacks.
abstract class Collider extends Behavior implements PhysicsBody {
  late int _handle;
  static int _nextBoundsHandle = -1;

  /// True when this collider has no physics/collision shape (bounds-tracking only).
  @protected
  bool get hasBoundsOnly => isAttached && _handle < 0;

  /// The internal physics handle for this collider.
  int get handle {
    assert(isAttached, 'Collider must be attached to a GameObject before accessing handle.');
    return _handle;
  }

  @override
  int get colliderHandle => handle;

  /// The shape type of this collider.
  ColliderShapeType get shapeType;

  @protected
  PhysicsWorker get worker => game.getSystem<PhysicsSystem>()!.worker;

  @override
  void internalAttach(GameObject gameObject) {
    super.internalAttach(gameObject);
    final cs = game.getSystem<CollisionSystem>();
    if (cs != null) {
      _handle = cs.worker.createShape(shapeType);
      cs.registerCollider(_handle, this);
      _syncToCollisionWorker(cs.worker);
    } else {
      final rb = gameObject.tryGetComponent<Rigidbody>();
      if (rb != null) {
        _handle = worker.createCollider(shapeType, rb.handle);
        PhysicsSystem.registerCollider(_handle, this);
        syncAllProperties();
      } else {
        // Bounds-only mode: no physics simulation; registered for worldBounds/screen detection.
        _handle = _nextBoundsHandle--;
        final ps = game.getSystem<PhysicsSystem>();
        if (ps != null) PhysicsSystem.registerCollider(_handle, this);
      }
    }
  }

  @override
  void internalDetach() {
    final cs = game.getSystem<CollisionSystem>();
    if (cs != null) {
      cs.unregisterCollider(_handle);
      cs.worker.destroyShape(_handle);
    } else {
      PhysicsSystem.unregisterCollider(_handle, this);
      if (_handle >= 0) {
        game.getSystem<PhysicsSystem>()?.worker.destroyCollider(_handle);
      }
    }
    super.internalDetach();
  }

  @override
  set enabled(bool value) {
    super.enabled = value;
    if (!isAttached) return;
    final cs = game.getSystem<CollisionSystem>();
    if (cs != null) {
      cs.worker.setShapeEnabled(_handle, value);
    } else if (!hasBoundsOnly) {
      worker.setColliderProperty(_handle, ColliderProp.enabled, value);
    }
  }

  @protected
  void _syncToCollisionWorker(CollisionWorker w) {
    w.setShapeOffset(_handle, _offset.x, _offset.y);
    w.setShapeLayer(_handle, gameObject.layer);
    w.setShapeExcludeLayers(_handle, _excludeLayers);
    w.setShapeEnabled(_handle, enabled);
    syncCollisionGeometry(w);
  }

  @protected
  void syncCollisionGeometry(CollisionWorker w) {}

  @protected
  void syncAllProperties() {
    if (hasBoundsOnly) return;
    worker.setColliderProperty(_handle, ColliderProp.enabled, enabled);
    worker.setColliderProperty(_handle, ColliderProp.offset, _offset.clone());
    worker.setColliderProperty(_handle, ColliderProp.isTrigger, _isTrigger);
    worker.setColliderProperty(_handle, ColliderProp.density, _density);
    worker.setColliderProperty(_handle, ColliderProp.friction, _friction);
    worker.setColliderProperty(_handle, ColliderProp.bounciness, _bounciness);
    worker.setColliderProperty(_handle, ColliderProp.frictionCombine, _frictionCombine.index);
    worker.setColliderProperty(_handle, ColliderProp.bounceCombine, _bounceCombine.index);
    worker.setColliderProperty(_handle, ColliderProp.compositeOperation, _compositeOperation.index);
    worker.setColliderProperty(_handle, ColliderProp.compositeOrder, _compositeOrder);
    worker.setColliderProperty(_handle, ColliderProp.usedByEffector, _usedByEffector);
    worker.setColliderProperty(_handle, ColliderProp.excludeLayers, _excludeLayers);
    worker.setColliderProperty(_handle, ColliderProp.includeLayers, _includeLayers);
    worker.setColliderProperty(_handle, ColliderProp.callbackLayers, _callbackLayers);
    worker.setColliderProperty(_handle, ColliderProp.contactCaptureLayers, _contactCaptureLayers);
    worker.setColliderProperty(_handle, ColliderProp.forceReceiveLayers, _forceReceiveLayers);
    worker.setColliderProperty(_handle, ColliderProp.forceSendLayers, _forceSendLayers);
    worker.setColliderProperty(_handle, ColliderProp.layerOverridePriority, _layerOverridePriority);
  }

  // --- Configuration Properties (Sync) ---

  /// Local-space offset of the collider shape from the [ObjectTransform] origin. Default `Vector2.zero()`.
  Vector2 get offset => _offset;
  Vector2 _offset = Vector2.zero();
  set offset(Vector2 value) {
    _offset.setFrom(value);
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(_handle, ColliderProp.offset, value.clone());
  }

  /// When true, this collider acts as a sensor: other colliders pass through it without generating
  /// contact forces, but [PhysicsContactListener.onOverlapEnter] / [onOverlapExit] events are still fired.
  /// Default false.
  bool get isTrigger => _isTrigger;
  bool _isTrigger = false;
  set isTrigger(bool value) {
    _isTrigger = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(_handle, ColliderProp.isTrigger, value);
  }

  /// Mass per unit area, used to compute [Rigidbody.mass] when [Rigidbody.useAutoMass] is true.
  /// Default 1.0.
  double get density => _density;
  double _density = 1.0;
  set density(double value) {
    _density = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(_handle, ColliderProp.density, value);
  }

  /// Surface friction coefficient. Range 0.0 (frictionless) to 1.0 (rough). Default 0.4.
  ///
  /// Combined with the touching collider's friction using [frictionCombine].
  double get friction => _friction;
  double _friction = 0.4;
  set friction(double value) {
    _friction = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(_handle, ColliderProp.friction, value);
  }

  /// How much kinetic energy is retained after a bounce. Range 0.0 (no bounce) to 1.0 (perfectly elastic). Default 0.0.
  ///
  /// Combined with the touching collider's bounciness using [bounceCombine].
  double get bounciness => _bounciness;
  double _bounciness = 0.0;
  set bounciness(double value) {
    _bounciness = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(_handle, ColliderProp.bounciness, value);
  }

  /// How [friction] from two touching colliders is combined into a single value. Default `average`.
  PhysicsMaterialCombine get frictionCombine => _frictionCombine;
  PhysicsMaterialCombine _frictionCombine = PhysicsMaterialCombine.average;
  set frictionCombine(PhysicsMaterialCombine value) {
    _frictionCombine = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(_handle, ColliderProp.frictionCombine, value.index);
  }

  /// How [bounciness] from two touching colliders is combined into a single value. Default `average`.
  PhysicsMaterialCombine get bounceCombine => _bounceCombine;
  PhysicsMaterialCombine _bounceCombine = PhysicsMaterialCombine.average;
  set bounceCombine(PhysicsMaterialCombine value) {
    _bounceCombine = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(_handle, ColliderProp.bounceCombine, value.index);
  }

  /// How this collider contributes to a parent [CompositeCollider]. Default `none`.
  CompositeOperation get compositeOperation => _compositeOperation;
  CompositeOperation _compositeOperation = CompositeOperation.none;
  set compositeOperation(CompositeOperation value) {
    _compositeOperation = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(_handle, ColliderProp.compositeOperation, value.index);
  }

  /// Processing priority when multiple colliders merge into a [CompositeCollider]. Lower numbers run first.
  int get compositeOrder => _compositeOrder;
  int _compositeOrder = 0;
  set compositeOrder(int value) {
    _compositeOrder = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(_handle, ColliderProp.compositeOrder, value);
  }

  /// When true, an effector component on this object can apply forces through this collider. Default false.
  bool get usedByEffector => _usedByEffector;
  bool _usedByEffector = false;
  set usedByEffector(bool value) {
    _usedByEffector = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(_handle, ColliderProp.usedByEffector, value);
  }

  /// Layer bitmask of layers this collider will never collide with, overriding the global layer matrix.
  int get excludeLayers => _excludeLayers;
  int _excludeLayers = 0;
  set excludeLayers(int value) {
    _excludeLayers = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(_handle, ColliderProp.excludeLayers, value);
  }

  /// Layer bitmask of layers this collider will always collide with, overriding the global layer matrix.
  int get includeLayers => _includeLayers;
  int _includeLayers = 0;
  set includeLayers(int value) {
    _includeLayers = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(_handle, ColliderProp.includeLayers, value);
  }

  /// Layer bitmask of layers that trigger collision callbacks on this collider. Default all layers (`~0`).
  int get callbackLayers => _callbackLayers;
  int _callbackLayers = ~0;
  set callbackLayers(int value) {
    _callbackLayers = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(_handle, ColliderProp.callbackLayers, value);
  }

  /// Layer bitmask of layers for which this collider captures [ContactPoint] data. Default all layers (`~0`).
  int get contactCaptureLayers => _contactCaptureLayers;
  int _contactCaptureLayers = ~0;
  set contactCaptureLayers(int value) {
    _contactCaptureLayers = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(_handle, ColliderProp.contactCaptureLayers, value);
  }

  /// Layer bitmask of layers from which this collider can receive effector forces. Default all layers (`~0`).
  int get forceReceiveLayers => _forceReceiveLayers;
  int _forceReceiveLayers = ~0;
  set forceReceiveLayers(int value) {
    _forceReceiveLayers = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(_handle, ColliderProp.forceReceiveLayers, value);
  }

  /// Layer bitmask of layers to which this collider can send effector forces. Default all layers (`~0`).
  int get forceSendLayers => _forceSendLayers;
  int _forceSendLayers = ~0;
  set forceSendLayers(int value) {
    _forceSendLayers = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(_handle, ColliderProp.forceSendLayers, value);
  }

  /// Priority used when resolving conflicting layer override settings. Higher value wins.
  int get layerOverridePriority => _layerOverridePriority;
  int _layerOverridePriority = 0;
  set layerOverridePriority(int value) {
    _layerOverridePriority = value;
    if (isAttached && !hasBoundsOnly) worker.setColliderProperty(_handle, ColliderProp.layerOverridePriority, value);
  }

  // --- Read-Only / Computed Properties ---

  /// Current error state reported by the physics engine for this collider.
  Future<ColliderErrorState> get errorState async => (await worker.getColliderProperty(_handle, ColliderProp.errorState)) as ColliderErrorState;

  /// Number of physics shapes this collider currently contributes.
  Future<int> get shapeCount async => (await worker.getColliderProperty(_handle, ColliderProp.shapeCount)) as int;

  /// Whether this collider can be merged into a [CompositeCollider].
  Future<bool> get compositeCapable async => (await worker.getColliderProperty(_handle, ColliderProp.compositeCapable)) as bool;

  /// World-space axis-aligned bounding box that encloses this collider's shape.
  ui.Rect get bounds {
    final t = gameObject.getComponent<ObjectTransform>();
    final pos = t.position;
    final wm = t.worldMatrix;
    final angle = math.atan2(wm.entry(1, 0), wm.entry(0, 0));
    return computeShapeBounds(Vector2(pos.x + _offset.x, pos.y + _offset.y), angle);
  }

  @protected
  ui.Rect computeShapeBounds(Vector2 center, double angle) =>
      ui.Rect.fromCenter(center: ui.Offset(center.x, center.y), width: 0, height: 0);

  /// Alias for [bounds] used by screen visibility tracking.
  ui.Rect get worldBounds => bounds;

  /// Internal screen state — whether this collider overlapped the screen last frame.
  bool wasOverlappingScreen = false;

  /// Internal screen state — whether this collider was fully inside the screen last frame.
  bool wasFullyInsideScreen = false;

  /// World-space transform matrix for this collider's physics shapes.
  Matrix4 get localToWorldMatrix => gameObject.getComponent<ObjectTransform>().worldMatrix;

  /// The [Rigidbody] on the same [GameObject] as this collider.
  Rigidbody get attachedRigidbody => gameObject.getComponent<Rigidbody>();

  /// The [CompositeCollider] on this [GameObject], if one exists.
  CompositeCollider? get composite => gameObject.getComponent<CompositeCollider>();

  /// Effective layer bitmask for contact decisions, derived from [callbackLayers], [excludeLayers], and [includeLayers].
  int get contactMask => _callbackLayers & ~_excludeLayers | _includeLayers;

  // --- Methods ---

  /// Returns true if this collider and [collider] are on layers that can ever contact each other.
  bool canContact(Collider collider) => (contactMask & (1 << collider.gameObject.layer)) != 0;

  /// Returns the point on the perimeter of this collider closest to [position] in world space.
  Future<Vector2> closestPoint(Vector2 position) => worker.colliderClosestPoint(_handle, position);

  /// Returns the minimum separation distance between this collider and [collider].
  Future<double> distance(Collider collider) => worker.colliderDistance(_handle, collider._handle);

  /// Returns true if this collider is currently touching [collider].
  Future<bool> isTouching(Collider collider) => worker.colliderIsTouching(_handle, collider._handle);

  /// Returns true if this collider is touching any collider on [layerMask].
  Future<bool> isTouchingLayers(int layerMask) => worker.colliderIsTouchingLayers(_handle, layerMask);

  /// Check if a collider overlaps a point in space.
  Future<bool> overlapPoint(Vector2 point) async => (await worker.overlapPoint(point, 1 << gameObject.layer, 0, 0)).contains(_handle);

  /// Synchronous point-in-shape test in the object's local coordinate space.
  ///
  /// Used by the render hit-test system. The [position] is already transformed
  /// into local game-unit space by [GameRenderObject.hitTest] before this is
  /// called. Each Collider subclass overrides this with its own geometry test.
  bool containsPoint(ui.Offset position) => false;

  PhysicsMaterial? _sharedMaterial;

  /// A [PhysicsMaterial] that sets [friction], [bounciness], [frictionCombine], and [bounceCombine] all at once.
  PhysicsMaterial? get sharedMaterial => _sharedMaterial;
  set sharedMaterial(PhysicsMaterial? value) {
    _sharedMaterial = value;
    if (value == null) return;
    friction = value.friction;
    bounciness = value.bounciness;
    frictionCombine = value.frictionCombine;
    bounceCombine = value.bounceCombine;
  }

  /// Casts this collider's shape in [direction] and returns all hits up to [distance] world units away.
  Future<List<RaycastHit>> cast(Vector2 direction, [double distance = double.infinity, bool ignoreSiblingColliders = true]) async {
    final transform = gameObject.getComponent<ObjectTransform>();
    return Physics.boxCastAll(transform.position, Vector2(1, 1), transform.angle, direction, distance, ~0, -double.infinity, double.infinity);
  }

  /// Returns null — the engine has no Mesh asset class yet; this is a stub.
  Object? createMesh(bool useDelaunayMesh, double extrusionAmount) => null;

  /// Returns all colliders currently touching this collider.
  Future<List<Collider>> getContactColliders() async {
    final handles = await worker.getContactColliders(_handle);
    return handles.map((h) => PhysicsSystem.getCollider(h)).whereType<Collider>().toList();
  }

  /// Fills [shapeGroup] with the physics shapes for this collider. Returns the number of shapes added.
  int getShapes(PhysicsShapeGroup shapeGroup, [int shapeIndex = 0, int shapeCount = 0]) => 0;

  /// Returns a hash of the current physics shapes, useful for change detection.
  int getShapeHash() {
    final group = PhysicsShapeGroup();
    final count = getShapes(group);
    if (count == 0) return 0;
    var hash = count;
    for (var i = 0; i < count; i++) {
      final s = group.getShape(i);
      hash = hash ^ (s.shapeType.index * 397) ^ (s.radius * 1000).toInt() ^ (s.vertexCount * 31);
    }
    return hash;
  }

  /// Returns all current contact points involving this collider.
  Future<List<ContactPoint>> getContacts() async {
    final data = await worker.getContacts(_handle);
    return data.map((d) => ContactPoint.fromData(d)).whereType<ContactPoint>().toList();
  }

  /// Returns the world-space bounding box for a specific physics shape by index.
  ui.Rect getShapeBounds(int shapeIndex) => bounds;

  /// Fires a ray from this collider's position in [direction], returning all hits.
  Future<List<RaycastHit>> raycast(Vector2 direction, [double distance = double.infinity, int layerMask = ~0, double minDepth = -double.infinity, double maxDepth = double.infinity]) async {
    final pos = gameObject.getComponent<ObjectTransform>().position;
    return Physics.raycastAll(Vector2(pos.x, pos.y), direction, distance, layerMask, minDepth, maxDepth);
  }

  /// Returns all colliders currently overlapping this collider.
  Future<List<Collider>> overlap() async {
    final handles = await worker.overlapCollider(_handle);
    return handles.map((h) => PhysicsSystem.getCollider(h)).whereType<Collider>().toList();
  }
}
