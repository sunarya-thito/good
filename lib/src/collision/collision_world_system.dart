import 'dart:typed_data';
import 'package:goo2d/goo2d.dart';
import 'package:goo2d/src/collision/collision_system.dart';
import 'package:goo2d/src/collision/worker/collision_delta.dart';
import 'package:goo2d/src/collision/worker/collision_worker.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';

/// An ECS [WorldSystem] that bridges [CollisionSystem] to entities carrying
/// [ColliderData] and [TransformData] (no [RigidbodyData] required).
///
/// On each fixed tick this system:
/// 1. Creates/destroys collision shapes to match living entities.
/// 2. Pushes entity transforms into the collision worker.
/// 3. Steps the worker and dispatches overlap events.
///
/// Add to a [WorldController] to enable ECS collision:
/// ```dart
/// world.addSystem(CollisionWorldSystem());
/// ```
///
/// Overlap events are dispatched per-paradigm to avoid Dart covariant-generic
/// collisions (since `Entity` and `Collider` both extend `PhysicsBody`, a
/// `<PhysicsBody>` broadcast would incorrectly reach `<Entity>` and `<Collider>`
/// listeners at runtime):
/// - ECS–ECS: [PhysicsOverlap<Entity>] via [WorldController.broadcastEventAsync]
/// - EC–EC: [PhysicsOverlap<Collider>] via [GameObject.dispatchTo] + world broadcast
/// - Cross-paradigm: [PhysicsOverlap<PhysicsBody>] via [GameObject.dispatchTo] only
class CollisionWorldSystem extends WorldSystem with FixedTickable {
  late final ColliderData _cold = define(ColliderData.new);
  late final TransformData _td  = define(TransformData.new);

  // resolved lazily on first fixed tick (gameObject is null at onAttach time)
  CollisionSystem? _cs;

  // entity slot → collider handle; used to detect removed entities
  final Map<int, int> _trackedEntities = {};

  // collider handle → Entity reverse lookup (open-addressing hash, no Map)
  Int32List _lookupHandles = Int32List(64)..fillRange(0, 64, -1);
  List<Entity?> _lookupEntities = List.filled(64, null);
  int _lookupCap = 64;
  int _lookupMask = 63;
  int _lookupCount = 0;

  @override
  void onAttach() => CollisionSystem.registerEcsWorld(this);

  @override
  void onDetach() => CollisionSystem.unregisterEcsWorld();

  @override
  Future<void> onFixedUpdate(double dt) async {
    final cs = CollisionSystem.maybeInstance;
    if (cs == null) return;
    _syncEntityRegistrations(cs.worker);
    _buildReverseLookup();
    _syncTransforms(cs.worker);
    final delta = await cs.worker.step();
    if (CollisionSystem.maybeInstance == null) return;
    await _dispatchAll(delta);
  }

  // ── Entity registration ──────────────────────────────────────────────────

  void _syncEntityRegistrations(CollisionWorker w) {
    final currentSlots = <int>{};

    (world.query()..withAll(_cold)).withEntity().forEach((r) {
      final s = r.entity.index;
      currentSlots.add(s);
      if (_cold.colliderHandle.getSlot(s) >= 0) {
        _trackedEntities.putIfAbsent(s, () => _cold.colliderHandle.getSlot(s));
        return;
      }
      final st = _cold.shapeType.getSlot(s);
      final handle = w.createShape(st);
      _cold.colliderHandle.setSlot(s, handle);
      _trackedEntities[s] = handle;
      w.setShapeOffset(handle, _cold.offsetX.getSlot(s), _cold.offsetY.getSlot(s));
      _applyShapeGeometry(w, handle, s);
    });

    final deadSlots = _trackedEntities.keys
        .where((s) => !currentSlots.contains(s))
        .toList(growable: false);
    for (final s in deadSlots) {
      w.destroyShape(_trackedEntities.remove(s)!);
    }
  }

  void _applyShapeGeometry(CollisionWorker w, int handle, int s) {
    final st = _cold.shapeType.getSlot(s);
    if (st == ColliderShapeType.circle) {
      w.setShapeCircle(handle, _cold.radius.getSlot(s));
    } else if (st == ColliderShapeType.box) {
      w.setShapeBox(handle, _cold.width.getSlot(s) / 2, _cold.height.getSlot(s) / 2);
    }
  }

  // ── Reverse lookup (open-addressing hash, rebuilt each tick) ─────────────

  static int _lHash(int h, int mask) => (h * 0x9E3779B9) & mask;

  void _buildReverseLookup() {
    _lookupHandles.fillRange(0, _lookupCap, -1);
    for (var i = 0; i < _lookupCap; i++) { _lookupEntities[i] = null; }
    _lookupCount = 0;

    (world.query()..withAll(_cold)).withEntity().forEach((r) {
      final handle = _cold.colliderHandle.getSlot(r.entity.index);
      if (handle < 0) return;
      _lookupInsert(handle, r.entity);
    });
  }

  void _lookupInsert(int handle, Entity entity) {
    if (_lookupCount >= _lookupCap * 3 ~/ 4) _growLookup();
    var bucket = _lHash(handle, _lookupMask);
    while (_lookupHandles[bucket] != -1) {
      bucket = (bucket + 1) & _lookupMask;
    }
    _lookupHandles[bucket] = handle;
    _lookupEntities[bucket] = entity;
    _lookupCount++;
  }

  Entity? _lookupFind(int handle) {
    var bucket = _lHash(handle, _lookupMask);
    while (true) {
      final h = _lookupHandles[bucket];
      if (h == -1) return null;
      if (h == handle) return _lookupEntities[bucket];
      bucket = (bucket + 1) & _lookupMask;
    }
  }

  void _growLookup() {
    final newCap = _lookupCap * 2;
    final newMask = newCap - 1;
    final newHandles = Int32List(newCap)..fillRange(0, newCap, -1);
    final newEntities = List<Entity?>.filled(newCap, null);
    for (var i = 0; i < _lookupCap; i++) {
      final h = _lookupHandles[i];
      if (h == -1) continue;
      var bucket = _lHash(h, newMask);
      while (newHandles[bucket] != -1) { bucket = (bucket + 1) & newMask; }
      newHandles[bucket] = h;
      newEntities[bucket] = _lookupEntities[i];
    }
    _lookupCap = newCap;
    _lookupMask = newMask;
    _lookupHandles = newHandles;
    _lookupEntities = newEntities;
  }

  // ── Transform sync ───────────────────────────────────────────────────────

  void _syncTransforms(CollisionWorker w) {
    (world.query()..withAll(_cold, _td)).withEntity().forEach((r) {
      final s = r.entity.index;
      final handle = _cold.colliderHandle.getSlot(s);
      if (handle < 0) return;
      w.setShapeTransform(
          handle, _td.x.getSlot(s), _td.y.getSlot(s), _td.angle.getSlot(s));
    });
  }

  // ── Event dispatch ────────────────────────────────────────────────────────

  Future<void> _dispatchAll(CollisionDelta delta) async {
    await _dispatchPairs(delta.enterPairs, isEnter: true, isExit: false);
    await _dispatchPairs(delta.stayPairs,  isEnter: false, isExit: false);
    await _dispatchPairs(delta.exitPairs,  isEnter: false, isExit: true);
  }

  Future<void> _dispatchPairs(
      Int32List pairs, {required bool isEnter, required bool isExit}) async {
    final n = pairs.length ~/ 2;
    for (var i = 0; i < n; i++) {
      final hA = pairs[i * 2], hB = pairs[i * 2 + 1];
      final cA = CollisionSystem.getCollider(hA);
      final cB = CollisionSystem.getCollider(hB);
      final eA = _lookupFind(hA);
      final eB = _lookupFind(hB);

      if (isExit) {
        if (cA != null && cB != null && cA.isAttached && cB.isAttached) {
          await OverlapExitEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB))
              .dispatchTo(cA.gameObject);
          await OverlapExitEvent(PhysicsOverlap<Collider>(trigger: cB, other: cA))
              .dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
              OverlapExitEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB)));
        } else if (eA != null && eB != null) {
          await world.broadcastEventAsync(
              OverlapExitEvent(PhysicsOverlap<Entity>(trigger: eA, other: eB)));
        } else if (cA != null && eB != null && cA.isAttached) {
          await OverlapExitEvent(PhysicsOverlap<PhysicsBody>(trigger: cA, other: eB))
              .dispatchTo(cA.gameObject);
        } else if (eA != null && cB != null && cB.isAttached) {
          await OverlapExitEvent(PhysicsOverlap<PhysicsBody>(trigger: cB, other: eA))
              .dispatchTo(cB.gameObject);
        }
      } else if (isEnter) {
        if (cA != null && cB != null && cA.isAttached && cB.isAttached) {
          await OverlapEnterEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB))
              .dispatchTo(cA.gameObject);
          await OverlapEnterEvent(PhysicsOverlap<Collider>(trigger: cB, other: cA))
              .dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
              OverlapEnterEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB)));
        } else if (eA != null && eB != null) {
          await world.broadcastEventAsync(
              OverlapEnterEvent(PhysicsOverlap<Entity>(trigger: eA, other: eB)));
        } else if (cA != null && eB != null && cA.isAttached) {
          await OverlapEnterEvent(PhysicsOverlap<PhysicsBody>(trigger: cA, other: eB))
              .dispatchTo(cA.gameObject);
        } else if (eA != null && cB != null && cB.isAttached) {
          await OverlapEnterEvent(PhysicsOverlap<PhysicsBody>(trigger: cB, other: eA))
              .dispatchTo(cB.gameObject);
        }
      } else {
        if (cA != null && cB != null && cA.isAttached && cB.isAttached) {
          await OverlapStayEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB))
              .dispatchTo(cA.gameObject);
          await OverlapStayEvent(PhysicsOverlap<Collider>(trigger: cB, other: cA))
              .dispatchTo(cB.gameObject);
          await world.broadcastEventAsync(
              OverlapStayEvent(PhysicsOverlap<Collider>(trigger: cA, other: cB)));
        } else if (eA != null && eB != null) {
          await world.broadcastEventAsync(
              OverlapStayEvent(PhysicsOverlap<Entity>(trigger: eA, other: eB)));
        } else if (cA != null && eB != null && cA.isAttached) {
          await OverlapStayEvent(PhysicsOverlap<PhysicsBody>(trigger: cA, other: eB))
              .dispatchTo(cA.gameObject);
        } else if (eA != null && cB != null && cB.isAttached) {
          await OverlapStayEvent(PhysicsOverlap<PhysicsBody>(trigger: cB, other: eA))
              .dispatchTo(cB.gameObject);
        }
      }
    }
  }
}
